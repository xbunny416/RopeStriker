--!strict
--[[
	RebirthService
	--------------
	Temporal Paradox (Bible §2.2) and the Rebirth Paradox Skill Tree.

	  Cost:     reach Era 4 (unlock the Neon Future rift) + 1,000,000 TotalStrength.
	  Resets:   unbanked KP, TotalStrength, ropes and boots (back to the starters).
	  Retains:  unlocked portals, every pet, cosmetics, Rebirth Tokens, skill levels.
	  Rewards:  RebirthCount + 1 => base stats x1.5 compounding, +Rebirth Tokens to spend
	            in the skill tree, milestone titles.

	The mutation itself lives in DataService.Rebirth / PlayerDataOps.Rebirth so it is a
	single atomic step; this service is the request front door and the follow-up FX.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Guard = require(Source.Shared.Guard)
local Remotes = require(Source.Network.Remotes)

local DataService = require(script.Parent.DataService)
local TrainingService = require(script.Parent.TrainingService)

local Modules = script.Parent.Parent.Modules
local PlayerDataOps = require(Modules.PlayerDataOps)
local RateLimiter = require(Modules.RateLimiter)
local Security = require(Modules.Security)

local REBIRTH_COOLDOWN = 3

local RebirthService = {}

local lastRebirth: { [Player]: number } = {}
local requestLimiter = RateLimiter.new(
	GameConfig.Security.RateLimits.Request.Capacity,
	GameConfig.Security.RateLimits.Request.RefillPerSecond
)

local function onRequestRebirth(player: Player): (boolean, string)
	if not requestLimiter:Allow(player) then
		return false, "Slow down a little!"
	end
	local now = os.clock()
	if now - (lastRebirth[player] or -math.huge) < REBIRTH_COOLDOWN then
		return false, "The timeline is still stabilising..."
	end

	local success, message = DataService.Rebirth(player)
	if not success then
		return false, message
	end
	lastRebirth[player] = now

	local data = DataService.GetData(player)
	local count = if data then data.RebirthCount else 0
	TrainingService.ResetCombo(player)
	Remotes.RebirthComplete:FireClient(player, count)
	return true, message
end

local function onUnlockSkill(player: Player, rawNodeId: unknown): (boolean, string)
	if not requestLimiter:Allow(player) then
		return false, "Slow down a little!"
	end
	local nodeId = Guard.Key(rawNodeId, GameConfig.SkillTree)
	if nodeId == nil then
		Security.Strike(player, "UnlockSkill malformed", 2)
		return false, "Unknown skill."
	end
	local ok, message = false, "Your data is still loading."
	DataService.Mutate(player, { "SkillLevels", "RebirthTokens", "EquippedPets" }, function(data)
		ok, message = PlayerDataOps.UnlockSkill(data, nodeId)
	end)
	return ok, message
end

function RebirthService.Init()
	Remotes.RequestRebirth.OnServerInvoke = onRequestRebirth
	Remotes.UnlockSkill.OnServerInvoke = onUnlockSkill
end

function RebirthService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastRebirth[player] = nil
		requestLimiter:Reset(player)
	end)
end

return RebirthService
