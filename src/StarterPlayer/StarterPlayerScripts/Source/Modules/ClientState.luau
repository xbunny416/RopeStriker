--!strict
--[[
	ClientState
	-----------
	The client's read-only mirror of its own profile.

	  * Full snapshot: StateSnapshot (pushed on load) or GetSnapshot (pulled, retried) -
	    whichever arrives first, so there is no race with the server's load timing.
	  * Tables (pets, owned items, portals, skills, stats): StatePatch.
	  * Scalars (KP, Strength, Shards, ...) and derived stats (StaminaCapacity,
	    PetMultiplier, RhythmCombo, Mode, Era): Player attributes.

	Changed fires with the key that changed ("*" after a full snapshot).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Signal = require(Source.Shared.Signal)
local Remotes = require(Source.Network.Remotes)

type PlayerData = GameConfig.PlayerData

local SCALAR_KEYS = {
	"UnbankedKP",
	"TotalStrength",
	"Shards",
	"RebirthCount",
	"RebirthTokens",
	"HighestEra",
	"EquippedRope",
	"EquippedBoots",
	"EquippedTitle",
}

local DERIVED_ATTRIBUTES = {
	"StaminaCapacity",
	"PetMultiplier",
	"EquippedPetIds",
	"RhythmCombo",
	"Mode",
	"Era",
}

local SNAPSHOT_RETRIES = 60

local ClientState = {}

ClientState.Loaded = Signal.new() :: Signal.Signal<PlayerData>
ClientState.Changed = Signal.new() :: Signal.Signal<string>

local player = Players.LocalPlayer
local data: PlayerData? = nil

local function overlayAttributes(target: PlayerData)
	for _, key in SCALAR_KEYS do
		local value = player:GetAttribute(key)
		if value ~= nil then
			(target :: any)[key] = value
		end
	end
end

local function applySnapshot(snapshot: unknown)
	if type(snapshot) ~= "table" then
		return
	end
	local first = data == nil
	local incoming = snapshot :: any
	overlayAttributes(incoming)
	data = incoming
	if first then
		ClientState.Loaded:Fire(incoming)
	end
	ClientState.Changed:Fire("*")
end

local function applyPatch(patch: unknown)
	local current = data
	if current == nil or type(patch) ~= "table" then
		return
	end
	for key, value in patch :: { [string]: any } do
		(current :: any)[key] = value
		ClientState.Changed:Fire(key)
	end
end

function ClientState.Get(): PlayerData?
	return data
end

function ClientState.IsLoaded(): boolean
	return data ~= nil
end

-- Yields until the first snapshot arrived.
function ClientState.WaitForData(): PlayerData
	local current = data
	if current then
		return current
	end
	return ClientState.Loaded:Wait()
end

function ClientState.Attribute(name: string): any
	return player:GetAttribute(name)
end

function ClientState.Number(name: string, default: number): number
	local value = player:GetAttribute(name)
	return if type(value) == "number" then value else default
end

function ClientState.Combo(): number
	return ClientState.Number("RhythmCombo", GameConfig.Rhythm.ComboStart)
end

function ClientState.Capacity(): number
	return ClientState.Number("StaminaCapacity", GameConfig.Training.BaseStaminaCapacity)
end

function ClientState.Start()
	Remotes.StateSnapshot.OnClientEvent:Connect(applySnapshot)
	Remotes.StatePatch.OnClientEvent:Connect(applyPatch)

	for _, key in SCALAR_KEYS do
		player:GetAttributeChangedSignal(key):Connect(function()
			local current = data
			if current then
				(current :: any)[key] = player:GetAttribute(key)
			end
			ClientState.Changed:Fire(key)
		end)
	end
	for _, name in DERIVED_ATTRIBUTES do
		player:GetAttributeChangedSignal(name):Connect(function()
			ClientState.Changed:Fire(name)
		end)
	end

	task.spawn(function()
		for _ = 1, SNAPSHOT_RETRIES do
			if data ~= nil then
				return
			end
			local ok, snapshot = pcall(function()
				return Remotes.GetSnapshot:InvokeServer()
			end)
			if ok and type(snapshot) == "table" then
				if data == nil then
					applySnapshot(snapshot)
				end
				return
			end
			task.wait(1)
		end
		warn("[ClientState] profile snapshot never arrived")
	end)
end

return ClientState
