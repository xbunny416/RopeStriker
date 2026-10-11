--[[
	Loader
	------
	Runs the game's real ModuleScripts under Lune with a minimal Roblox-shaped shim:

	  * `script` / `script.Parent` / `game:GetService("ReplicatedStorage")` resolve to
	    proxy nodes that mirror the Rojo filesystem layout (src/<Service>/...), so
	    instance-path requires like `require(script.Parent.Signal)` work unchanged.
	  * `require(node)` loads the mapped .luau file once per Loader (module cache).
	  * Roblox datatypes (Vector3, CFrame, Color3, Enum, ...) come from @lune/roblox;
	    `task` from @lune/task; `Random` is a deterministic shim.
	  * Services that a test needs (Players, RunService, ...) are injected as mocks via
	    `services`, and individual modules can be replaced with `overrides`.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local Loader = {}

local SERVICE_DIRECTORIES = {
	ReplicatedStorage = "src/ReplicatedStorage",
	ServerScriptService = "src/ServerScriptService",
	StarterPlayer = "src/StarterPlayer",
}

-- Deterministic stand-in for Roblox's Random (xorshift-ish, good enough for tests).
local function makeRandom()
	local Random = {}
	function Random.new(seed: number?)
		local state = math.floor(seed or 1337) % 2147483647
		if state <= 0 then
			state += 2147483646
		end
		local object = {}
		function object:NextNumber(min: number?, max: number?): number
			state = (state * 16807) % 2147483647
			local unit = (state - 1) / 2147483646
			if min and max then
				return min + unit * (max - min)
			end
			return unit
		end
		function object:NextInteger(min: number, max: number): number
			return min + math.floor(object:NextNumber() * (max - min + 1))
		end
		return object
	end
	return Random
end

local function stripExtension(name: string): string
	for _, suffix in { ".server.luau", ".client.luau", ".luau", ".lua" } do
		if string.sub(name, -#suffix) == suffix then
			return string.sub(name, 1, -#suffix - 1)
		end
	end
	return name
end

export type LoaderOptions = {
	root: string,
	services: { [string]: any }?,
	overrides: { [string]: any }?,
	globals: { [string]: any }?,
}

function Loader.new(options: LoaderOptions)
	local root = options.root
	local services = options.services or {}
	local overrides = options.overrides or {}
	local cache: { [string]: any } = {}
	local loading: { [string]: boolean } = {}
	local nodes: { [string]: any } = {}
	local self = {}

	-- Lune's fs functions yield, and yielding is illegal inside metamethods, so the
	-- source tree is indexed up front and node lookups stay pure.
	local entries: { [string]: string } = {}
	local listing: { [string]: { string } } = {}
	local function scan(relative: string)
		entries[relative] = "dir"
		local children = {}
		for _, entry in fs.readDir(root .. "/" .. relative) do
			local child = `{relative}/{entry}`
			table.insert(children, entry)
			if fs.isDir(root .. "/" .. child) then
				scan(child)
			else
				entries[child] = "file"
			end
		end
		listing[relative] = children
	end
	scan("src")

	local makeNode: (path: string, kind: string, name: string, parent: any) -> any
	local loadFile: (path: string) -> any

	local function childOf(node: any, childName: string): any
		local meta = getmetatable(node)
		if meta.kind ~= "dir" then
			return nil
		end
		local base = `{meta.path}/{childName}`
		for _, candidate in { ".luau", ".server.luau", ".client.luau", ".lua" } do
			if entries[base .. candidate] == "file" then
				return makeNode(base .. candidate, "file", childName, node)
			end
		end
		if entries[base] == "dir" then
			return makeNode(base, "dir", childName, node)
		end
		if entries[base .. ".model.json"] == "file" then
			return makeNode(base .. ".model.json", "model", childName, node)
		end
		return nil
	end

	makeNode = function(path: string, kind: string, name: string, parent: any): any
		local existing = nodes[path]
		if existing then
			return existing
		end
		local node = {}
		local meta = { path = path, kind = kind, name = name, parent = parent }
		meta.__index = function(_, key: string): any
			if key == "Parent" then
				return parent
			elseif key == "Name" then
				return name
			elseif key == "FindFirstChild" or key == "WaitForChild" then
				return function(_self: any, childName: string): any
					return childOf(node, childName)
				end
			elseif key == "GetChildren" then
				return function(): { any }
					local children = {}
					if kind == "dir" then
						for _, entry in listing[path] or {} do
							local child = childOf(node, stripExtension(string.gsub(entry, "%.model%.json$", "")))
							if child then
								table.insert(children, child)
							end
						end
					end
					return children
				end
			elseif key == "IsA" then
				return function(_self: any, className: string): boolean
					return (className == "Folder" and kind == "dir") or (className == "ModuleScript" and kind == "file")
				end
			end
			local child = childOf(node, key)
			if child == nil then
				error(`{key} is not a valid member of {path}`, 2)
			end
			return child
		end
		meta.__tostring = function(): string
			return path
		end
		setmetatable(node, meta)
		nodes[path] = node
		return node
	end

	local gameNode = setmetatable({}, {
		__index = function(_, key: string): any
			if key == "GetService" then
				return function(_self: any, serviceName: string): any
					local mocked = services[serviceName]
					if mocked ~= nil then
						return mocked
					end
					local directory = SERVICE_DIRECTORIES[serviceName]
					if directory then
						return makeNode(directory, "dir", serviceName, nil)
					end
					error(`Service {serviceName} is not mocked in this test`, 2)
				end
			end
			error(`game.{key} is not available in tests`, 2)
		end,
	})

	local function customRequire(target: any): any
		if type(target) == "string" then
			return require(target)
		end
		local meta = getmetatable(target)
		if meta == nil or meta.path == nil then
			error("require() expects a module node in tests", 2)
		end
		local path = meta.path
		if meta.kind == "dir" then
			local init = childOf(target, "init")
			if init == nil then
				error(`{path} is a folder without init.luau`, 2)
			end
			path = getmetatable(init).path
		end
		return loadFile(path)
	end

	loadFile = function(path: string): any
		local override = overrides[path]
		if override ~= nil then
			return override
		end
		if cache[path] ~= nil then
			return cache[path]
		end
		if loading[path] then
			error(`circular require of {path}`)
		end
		loading[path] = true

		local parts = string.split(path, "/")
		local fileName = parts[#parts]
		local directory = table.concat(parts, "/", 1, #parts - 1)
		local parentNode = Loader.dirNode(self, directory)
		local scriptNode = makeNode(path, "file", stripExtension(fileName), parentNode)

		local environment = {
			script = scriptNode,
			game = gameNode,
			workspace = services.Workspace,
			require = customRequire,
			task = task,
			Random = makeRandom(),
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			NumberRange = roblox.NumberRange,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			Enum = roblox.Enum,
			Instance = services.__Instance or roblox.Instance,
		}
		for key, value in options.globals or {} do
			environment[key] = value
		end

		local source = fs.readFile(root .. "/" .. path)
		local chunk = luau.load(source, { debugName = path, environment = environment })
		local result = chunk()
		loading[path] = nil
		cache[path] = result
		return result
	end

	function self.require(_: any, path: string): any
		return loadFile(path)
	end

	function self.node(_: any, path: string): any
		return Loader.dirNode(self, path)
	end

	self.__makeNode = makeNode
	return self
end

-- Directory node for a repo-relative path (parents resolved lazily).
function Loader.dirNode(loader: any, path: string): any
	local parts = string.split(path, "/")
	local parent = nil
	local current = ""
	for index, part in parts do
		current = if index == 1 then part else `{current}/{part}`
		parent = loader.__makeNode(current, "dir", part, parent)
	end
	return parent
end

return Loader
