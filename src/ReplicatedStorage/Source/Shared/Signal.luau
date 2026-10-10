--!strict
--[[
	Signal
	------
	A small, strictly-typed observer implementation used for intra-VM events
	(server service <-> service, client controller <-> controller).

	Every handler runs in its own coroutine through `task.spawn`, so a handler that
	yields or errors can never stall or break dispatch for the remaining listeners.

	    local ProfileLoaded: Signal.Signal<Player, PlayerData> = Signal.new()
	    ProfileLoaded:Connect(function(player, data) ... end)
	    ProfileLoaded:Fire(player, data)
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	ConnectionCount: (self: Signal<T...>) -> number,
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	local records: { { Callback: (T...) -> (), Connection: Connection } } = {}

	local function removeConnection(target: Connection)
		for index, record in records do
			if record.Connection == target then
				table.remove(records, index)
				return
			end
		end
	end

	local function connect(callback: (T...) -> (), once: boolean): Connection
		local connection: Connection = {
			Connected = true,
			Disconnect = function(self: Connection)
				if not self.Connected then
					return
				end
				self.Connected = false
				removeConnection(self)
			end,
		}

		local handler: (T...) -> ()
		if once then
			handler = function(...: T...)
				connection:Disconnect()
				callback(...)
			end
		else
			handler = callback
		end

		table.insert(records, { Callback = handler, Connection = connection })
		return connection
	end

	local signal: Signal<T...> = {
		Connect = function(_: Signal<T...>, callback: (T...) -> ()): Connection
			return connect(callback, false)
		end,

		Once = function(_: Signal<T...>, callback: (T...) -> ()): Connection
			return connect(callback, true)
		end,

		Wait = function(_: Signal<T...>): T...
			local thread = coroutine.running()
			connect(function(...: T...)
				task.spawn(thread, ...)
			end, true)
			return coroutine.yield()
		end,

		Fire = function(_: Signal<T...>, ...: T...)
			if #records == 0 then
				return
			end
			-- Snapshot so handlers may connect/disconnect while we dispatch.
			for _, record in table.clone(records) do
				if record.Connection.Connected then
					task.spawn(record.Callback, ...)
				end
			end
		end,

		DisconnectAll = function(_: Signal<T...>)
			for _, record in records do
				record.Connection.Connected = false
			end
			table.clear(records)
		end,

		ConnectionCount = function(_: Signal<T...>): number
			return #records
		end,
	}

	return signal
end

return Signal
