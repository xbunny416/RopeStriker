--!strict
--[[
	PortalService
	=============
	Chronal Rifts (Bible §3.1) and zone bookkeeping.

	  * Unlocks: when a player approaches a rift and their *server-stored* TotalStrength
	    and RebirthCount satisfy it, the unlock is persisted (retained through rebirth)
	    and PortalUnlocked tells their client to drop the gate's collision locally.
	    Other players still collide with the gate until they qualify.
	  * Enforcement: client-side gates are a convenience, not a security boundary. Every
	    tick the server checks which era sector each character stands in; anyone inside a
	    sector whose rift they have not unlocked (noclip, teleport exploits) is returned
	    to the hub.
	  * Bookkeeping: Player attributes "Era" and "Mode" ("Training" | "Combat").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Formulas = require(Source.Shared.Formulas)
local NumberFormat = require(Source.Shared.NumberFormat)
local Zones = require(Source.Shared.Zones)
local Remotes = require(Source.Network.Remotes)

local DataService = require(script.Parent.DataService)

local Modules = script.Parent.Parent.Modules
local PlayerDataOps = require(Modules.PlayerDataOps)
local Security = require(Modules.Security)

local TICK_INTERVAL = 0.25
local UNLOCK_DISTANCE = 45
local HINT_COOLDOWN = 8

local PortalService = {}

local lastHint: { [Player]: number } = {}

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function returnToHub(player: Player, root: BasePart)
	local spawn = GameConfig.World.SpawnPosition
	local character = player.Character
	if character then
		character:PivotTo(CFrame.new(spawn + Vector3.new(0, 3, 0)))
	end
	root.AssemblyLinearVelocity = Vector3.zero
	DataService.Notify(player, "Error", "The timeline rejected you. Unlock that Chronal Rift first!")
end

local function tryUnlock(player: Player, data: GameConfig.PlayerData, portal: GameConfig.PortalData)
	if not Formulas.MeetsPortalRequirement(data, portal) then
		local now = os.clock()
		if now - (lastHint[player] or -math.huge) > HINT_COOLDOWN then
			lastHint[player] = now
			local requirement = `{NumberFormat.Abbreviate(portal.RequiredStrength)} Strength`
			if portal.RequiredRebirths > 0 then
				requirement ..= ` and {portal.RequiredRebirths} Rebirths`
			end
			DataService.Notify(player, "Info", `{portal.DisplayName} requires {requirement}.`)
		end
		return
	end
	local unlocked, message = false, ""
	DataService.Mutate(player, { "UnlockedPortals", "HighestEra" }, function(mutable)
		unlocked, message = PlayerDataOps.UnlockPortal(mutable, portal.Id)
	end)
	if unlocked then
		Remotes.PortalUnlocked:FireClient(player, portal.Id)
		DataService.Notify(player, "Portal", message)
	end
end

local function tick()
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		local data = DataService.GetData(player)
		if root == nil or data == nil then
			continue
		end
		local position = root.Position
		local era = Zones.EraAt(position)
		if player:GetAttribute("Era") ~= era then
			player:SetAttribute("Era", era)
		end
		local mode = Zones.ModeAt(position)
		if player:GetAttribute("Mode") ~= mode then
			player:SetAttribute("Mode", mode)
		end

		-- Enforcement: standing in a sector whose rift is still locked.
		local guard = Zones.PortalIntoEra(era)
		if guard and not data.UnlockedPortals[guard.Id] then
			Security.Strike(player, `inside locked era {era}`, 3)
			returnToHub(player, root)
			continue
		end

		-- Unlocks for nearby rifts.
		for _, portal in GameConfig.Portals do
			if data.UnlockedPortals[portal.Id] or data.HighestEra < portal.FromEra then
				continue
			end
			if (portal.Position - position).Magnitude <= UNLOCK_DISTANCE then
				tryUnlock(player, data, portal)
			end
		end
	end
end

function PortalService.Init() end

function PortalService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastHint[player] = nil
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator >= TICK_INTERVAL then
			accumulator = 0
			tick()
		end
	end)
end

return PortalService
