--!strict
--[[
	Trove
	-----
	Collects disposable resources (instances, connections, threads, callbacks and
	objects exposing Destroy/Disconnect) and releases them together. Used to scope
	everything that belongs to a character, a mob life, an open UI panel, etc.

	    local trove = Trove.new()
	    trove:Connect(humanoid.Died, onDied)
	    trove:Add(beam)
	    trove:Clean() -- disconnects + destroys everything, newest first
]]

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: RBXScriptSignal, callback: (...any) -> ()) -> RBXScriptConnection,
	Remove: (self: Trove, item: any) -> boolean,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
}

local Trove = {}

-- Calls object:<name>() when the object exposes such a method.
local function callMethod(object: { [string]: any }, name: string): boolean
	local method = object[name]
	if type(method) ~= "function" then
		return false
	end
	local callable: (any) -> () = method :: any
	callable(object)
	return true
end

local function release(item: any)
	local kind = typeof(item)
	if kind == "Instance" then
		(item :: Instance):Destroy()
	elseif kind == "RBXScriptConnection" then
		(item :: RBXScriptConnection):Disconnect()
	elseif kind == "function" then
		(item :: () -> ())()
	elseif kind == "thread" then
		local thread = item :: thread
		if coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	elseif kind == "table" then
		local object = item :: { [string]: any }
		if not callMethod(object, "Destroy") and not callMethod(object, "Disconnect") then
			callMethod(object, "Clean")
		end
	end
end

function Trove.new(): Trove
	local items: { any } = {}
	local cleaning = false

	local trove: Trove
	trove = {
		Add = function<T>(_: Trove, item: T): T
			if cleaning then
				-- Anything added mid-clean is released immediately so nothing leaks.
				release(item)
				return item
			end
			table.insert(items, item)
			return item
		end,

		Connect = function(_: Trove, signal: RBXScriptSignal, callback: (...any) -> ()): RBXScriptConnection
			local connection = signal:Connect(callback)
			trove:Add(connection)
			return connection
		end,

		Remove = function(_: Trove, item: any): boolean
			local index = table.find(items, item)
			if index then
				table.remove(items, index)
				release(item)
				return true
			end
			return false
		end,

		Clean = function(_: Trove)
			if cleaning then
				return
			end
			cleaning = true
			for index = #items, 1, -1 do
				local item = items[index]
				items[index] = nil
				local ok, err = pcall(release :: any, item)
				if not ok then
					warn(`[Trove] failed to release {typeof(item)}: {err}`)
				end
			end
			cleaning = false
		end,

		Destroy = function(_: Trove)
			trove:Clean()
		end,
	}

	return trove
end

return Trove
