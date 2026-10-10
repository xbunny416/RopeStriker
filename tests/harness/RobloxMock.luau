--[[
	RobloxMock
	----------
	Just enough of the Roblox engine surface to run the real server services under Lune:
	signals, instances with attributes/children, players with characters, a flat-ground
	workspace with a controllable synchronised clock, a manually stepped Heartbeat, a
	controllable os.clock, fake remotes that record traffic and an in-memory
	ProfileService.

	Known Lune quirk: CFrame.lookAt in Lune 0.10 mirrors the Z axis of the look vector.
	Tests build orientations with CFrame.Angles instead; game code is unaffected.
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Mock = {}

---------------------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------------------

function Mock.signal()
	local handlers = {}
	local signal = {}
	function signal:Connect(fn)
		local connection = { Connected = true }
		function connection:Disconnect()
			connection.Connected = false
		end
		table.insert(handlers, { Fn = fn, Connection = connection })
		return connection
	end
	function signal:Once(fn)
		local connection
		connection = signal:Connect(function(...)
			connection:Disconnect()
			fn(...)
		end)
		return connection
	end
	function signal:Fire(...)
		for _, handler in table.clone(handlers) do
			if handler.Connection.Connected then
				handler.Fn(...)
			end
		end
	end
	function signal:Count(): number
		local count = 0
		for _, handler in handlers do
			if handler.Connection.Connected then
				count += 1
			end
		end
		return count
	end
	return signal
end

---------------------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------------------

local BASE_CLASSES = {
	Part = { "BasePart", "PVInstance" },
	WedgePart = { "BasePart", "PVInstance" },
	Model = { "PVInstance" },
	NumberValue = { "ValueBase" },
	IntValue = { "ValueBase" },
}

function Mock.instance(className: string, props: { [string]: any }?)
	local state: { [string]: any } = { ClassName = className, Name = className }
	local children = {}
	local attributes = {}
	local attributeSignals = {}
	local methods = {}
	local object = {}

	function methods:IsA(name: string): boolean
		if name == className or name == "Instance" then
			return true
		end
		for _, base in BASE_CLASSES[className] or {} do
			if base == name then
				return true
			end
		end
		return false
	end
	function methods:GetChildren()
		return table.clone(children)
	end
	function methods:FindFirstChild(name: string)
		for _, child in children do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	methods.WaitForChild = methods.FindFirstChild
	function methods:FindFirstChildOfClass(name: string)
		for _, child in children do
			if child.ClassName == name then
				return child
			end
		end
		return nil
	end
	function methods:GetDescendants()
		local result = {}
		for _, child in children do
			table.insert(result, child)
			for _, descendant in child:GetDescendants() do
				table.insert(result, descendant)
			end
		end
		return result
	end
	function methods:Destroy()
		object.Parent = nil
	end
	function methods:SetAttribute(name: string, value: any)
		local previous = attributes[name]
		attributes[name] = value
		if previous ~= value and attributeSignals[name] then
			attributeSignals[name]:Fire()
		end
	end
	function methods:GetAttribute(name: string): any
		return attributes[name]
	end
	function methods:GetAttributes()
		return table.clone(attributes)
	end
	function methods:GetAttributeChangedSignal(name: string)
		attributeSignals[name] = attributeSignals[name] or Mock.signal()
		return attributeSignals[name]
	end
	function methods:__addChild(child)
		table.insert(children, child)
	end
	function methods:__removeChild(child)
		local index = table.find(children, child)
		if index then
			table.remove(children, index)
		end
	end
	function methods:GetPivot()
		local cframe = state.CFrame
		if cframe then
			return cframe
		end
		local primary = state.PrimaryPart
		return if primary then primary.CFrame else CFrame.new()
	end

	setmetatable(object, {
		__index = function(_, key)
			local method = methods[key]
			if method then
				return method
			end
			local value = state[key]
			if value ~= nil then
				return value
			end
			return object:FindFirstChild(key)
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local previous = state.Parent
				if previous and previous.__removeChild then
					previous:__removeChild(object)
				end
				state.Parent = value
				if value and value.__addChild then
					value:__addChild(object)
				end
				return
			end
			if key == "CFrame" then
				state.Position = value.Position
			elseif key == "Position" and state.CFrame then
				state.CFrame = CFrame.new(value) * (state.CFrame - state.CFrame.Position)
			end
			state[key] = value
		end,
		__tostring = function()
			return state.Name
		end,
	})

	for key, value in props or {} do
		object[key] = value
	end
	return object
end

---------------------------------------------------------------------------------------
-- Players & characters
---------------------------------------------------------------------------------------

function Mock.character(position: Vector3)
	local model = Mock.instance("Model", { Name = "Character" })
	local humanoid = Mock.instance("Humanoid", {
		Health = 100,
		MaxHealth = 100,
		HipHeight = 2,
		RigType = Enum.HumanoidRigType.R15,
		MoveDirection = Vector3.zero,
	})
	humanoid.Parent = model
	local root = Mock.instance("Part", {
		Name = "HumanoidRootPart",
		Size = Vector3.new(2, 2, 1),
		CFrame = CFrame.new(position),
		AssemblyLinearVelocity = Vector3.zero,
	})
	root.Parent = model
	model.PrimaryPart = root
	return model, humanoid, root
end

function Mock.players()
	local service = Mock.instance("Players")
	service.PlayerAdded = Mock.signal()
	service.PlayerRemoving = Mock.signal()
	local list = {}

	function service:GetPlayers()
		return table.clone(list)
	end
	function service:GetPlayerByUserId(userId: number)
		for _, player in list do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end
	function service:__join(userId: number, name: string)
		local player = Mock.instance("Player", { Name = name, UserId = userId })
		player.CharacterAdded = Mock.signal()
		player.Kicked = nil
		function player:Kick(message: string?)
			player.Kicked = message or ""
		end
		function player:HasAppearanceLoaded(): boolean
			return true
		end
		player.Parent = service
		table.insert(list, player)
		service.PlayerAdded:Fire(player)
		return player
	end
	function service:__leave(player)
		local index = table.find(list, player)
		if index then
			table.remove(list, index)
		end
		service.PlayerRemoving:Fire(player)
		player.Parent = nil
	end
	return service
end

-- Puts a fresh character into the world for `player` at `position` (feet on y = 0).
function Mock.spawnCharacter(player, position: Vector3)
	local model, humanoid, root = Mock.character(position)
	player.Character = model
	player.CharacterAdded:Fire(model)
	return model, humanoid, root
end

---------------------------------------------------------------------------------------
-- Engine services
---------------------------------------------------------------------------------------

-- Flat ground at y = 0 everywhere; controllable synchronised clock.
function Mock.workspace()
	local service = Mock.instance("Workspace")
	service.ServerTime = 1.79e9
	function service:GetServerTimeNow(): number
		return service.ServerTime
	end
	function service:Raycast(origin: Vector3, direction: Vector3, _params: any)
		if direction.Y >= 0 then
			return nil
		end
		if origin.Y + direction.Y > 0 then
			return nil
		end
		return {
			Position = Vector3.new(origin.X, 0, origin.Z),
			Normal = Vector3.yAxis,
			Distance = origin.Y,
		}
	end
	return service
end

function Mock.runService()
	local service = Mock.instance("RunService")
	service.Heartbeat = Mock.signal()
	service.RenderStepped = Mock.signal()
	service.PreSimulation = Mock.signal()
	function service:IsServer(): boolean
		return true
	end
	function service:IsClient(): boolean
		return false
	end
	function service:IsStudio(): boolean
		return true
	end
	return service
end

function Mock.collectionService()
	local service = Mock.instance("CollectionService")
	local signals = {}
	function service:GetTagged(_tag: string)
		return {}
	end
	function service:HasTag(_instance: any, _tag: string): boolean
		return false
	end
	function service:GetInstanceAddedSignal(tag: string)
		signals[tag] = signals[tag] or Mock.signal()
		return signals[tag]
	end
	function service:GetInstanceRemovedSignal(tag: string)
		return service:GetInstanceAddedSignal(`{tag}:removed`)
	end
	return service
end

-- os replacement with a controllable clock (other functions pass through).
function Mock.os()
	local clock = { Now = 1000 }
	local fake = setmetatable({
		clock = function(): number
			return clock.Now
		end,
		time = function(): number
			return 1790000000
		end,
	}, { __index = os })
	return fake, clock
end

function Mock.raycastParams()
	return {
		new = function()
			return { FilterType = nil, FilterDescendantsInstances = {}, IgnoreWater = false }
		end,
	}
end

---------------------------------------------------------------------------------------
-- Networking & persistence
---------------------------------------------------------------------------------------

function Mock.remote()
	local remote = { OnServerEvent = Mock.signal(), OnClientEvent = Mock.signal(), Fired = {} }
	function remote:FireClient(player, ...)
		table.insert(remote.Fired, { Player = player, Args = table.pack(...) })
	end
	function remote:FireAllClients(...)
		table.insert(remote.Fired, { Player = "*", Args = table.pack(...) })
	end
	function remote:Last()
		return remote.Fired[#remote.Fired]
	end
	return remote
end

-- A Remotes module stand-in exposing every name from Network/Definitions.
function Mock.remotes(definitions)
	local remotes = {}
	for _, definition in definitions do
		remotes[definition.Name] = Mock.remote()
	end
	return remotes
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function reconcile(target, template)
	for key, value in template do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(target[key]) == "table" and type(value) == "table" then
			reconcile(target[key], value)
		end
	end
end

-- In-memory ProfileService with session release semantics.
function Mock.profileService()
	local service = { Saved = {}, FailNextLoad = false, Loaded = {} }
	function service.GetProfileStore(_name: string, template)
		local store = {}
		function store:LoadProfileAsync(key: string)
			if service.FailNextLoad then
				service.FailNextLoad = false
				return nil
			end
			local profile = {
				Data = deepCopy(service.Saved[key] or template),
				UserIds = {},
				Active = true,
				ReleaseListeners = {},
			}
			function profile:IsActive(): boolean
				return profile.Active
			end
			function profile:Reconcile()
				reconcile(profile.Data, template)
			end
			function profile:AddUserId(userId: number)
				table.insert(profile.UserIds, userId)
			end
			function profile:ListenToRelease(listener)
				table.insert(profile.ReleaseListeners, listener)
			end
			function profile:Release()
				if not profile.Active then
					return
				end
				profile.Active = false
				service.Saved[key] = deepCopy(profile.Data)
				for _, listener in profile.ReleaseListeners do
					listener()
				end
			end
			service.Loaded[key] = profile
			return profile
		end
		return store
	end
	return service
end

return Mock
