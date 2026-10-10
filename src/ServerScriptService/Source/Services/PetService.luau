--!strict
--[[
	PetService
	----------
	Chrono-Egg Incubator and pet management.

	  * Hatching is driven by the egg ProximityPrompts on the server (the prompt itself
	    proves proximity; we re-check distance anyway). Price is paid in Shards, the pet
	    is rolled from the egg's weight table (boosted for rarer pets by Chrono Luck),
	    granted and auto-equipped when a slot is free.
	  * Pets are retained through rebirth. PetMultiplierSum (sum of equipped pet
	    multipliers, minimum 1x) feeds both the KP and damage formulas.
	  * Equipped pet catalogue ids are mirrored to the Player attribute "EquippedPetIds"
	    (DataService) so every client can render followers (PetController).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Formulas = require(Source.Shared.Formulas)
local Guard = require(Source.Shared.Guard)
local Tags = require(Source.Shared.Tags)
local Remotes = require(Source.Network.Remotes)

local DataService = require(script.Parent.DataService)

local Modules = script.Parent.Parent.Modules
local PlayerDataOps = require(Modules.PlayerDataOps)
local RateLimiter = require(Modules.RateLimiter)
local Security = require(Modules.Security)

type PetRecord = GameConfig.PetRecord

local HATCH_COOLDOWN = 0.6
local HATCH_DISTANCE = 16

local PetService = {}

local random = Random.new()
local lastHatch: { [Player]: number } = {}
local requestLimiter = RateLimiter.new(
	GameConfig.Security.RateLimits.Request.Capacity,
	GameConfig.Security.RateLimits.Request.RefillPerSecond
)

-- Rolls a pet id for an egg, honouring the player's Chrono Luck.
function PetService.RollPet(eggId: string, skillLevels: { [string]: number }, roll: number?): string?
	local egg = GameConfig.Eggs[eggId]
	if egg == nil then
		return nil
	end
	local luck = Formulas.SkillBonus(skillLevels, "EggLuck")
	return Formulas.PickWeighted(Formulas.EggWeights(egg, luck), roll or random:NextNumber())
end

local function hatch(player: Player, eggModel: Model)
	local eggId = eggModel:GetAttribute("EggId")
	if type(eggId) ~= "string" then
		return
	end
	local egg = GameConfig.Eggs[eggId]
	if egg == nil then
		return
	end

	local now = os.clock()
	if now - (lastHatch[player] or -math.huge) < HATCH_COOLDOWN then
		return
	end
	lastHatch[player] = now

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end
	if (root.Position - eggModel:GetPivot().Position).Magnitude > HATCH_DISTANCE then
		Security.Strike(player, "hatching far from the incubator")
		return
	end

	local data = DataService.GetData(player)
	if data == nil then
		return
	end
	if not PlayerDataOps.HasInventoryRoom(data) then
		DataService.Notify(player, "Error", "Your pet inventory is full.")
		return
	end
	if data.Shards < egg.Price then
		DataService.Notify(player, "Error", `You need {egg.Price - data.Shards} more Shards.`)
		return
	end

	local petId = PetService.RollPet(eggId, data.SkillLevels)
	if petId == nil then
		return
	end

	local record: PetRecord? = nil
	DataService.Mutate(player, { "Shards", "Pets", "EquippedPets", "NextPetUid", "Stats" }, function(mutable)
		-- Re-check inside the atomic section: nothing can change between check and spend.
		if not PlayerDataOps.HasInventoryRoom(mutable) or not PlayerDataOps.SpendShards(mutable, egg.Price) then
			return
		end
		record = PlayerDataOps.GrantPet(mutable, petId, os.time())
		if record then
			mutable.Stats.EggsHatched += 1
		end
	end)

	if record then
		Remotes.HatchResult:FireClient(player, eggId, record)
	end
end

local function connectEgg(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local eggModel = instance
	for _, descendant in eggModel:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "HatchPrompt" then
			descendant.Triggered:Connect(function(player: Player)
				hatch(player, eggModel)
			end)
		end
	end
end

function PetService.Init()
	Remotes.SetPetEquipped.OnServerInvoke = function(
		player: Player,
		rawUid: unknown,
		rawEquipped: unknown
	): (boolean, string)
		if not requestLimiter:Allow(player) then
			return false, "Slow down a little!"
		end
		local equipped = Guard.Boolean(rawEquipped)
		if rawUid == "*best" then
			local done = DataService.Mutate(player, { "EquippedPets" }, function(data)
				PlayerDataOps.EquipBestPets(data)
			end)
			return done, if done then "Equipped your best pets." else "Your data is still loading."
		end
		local uid = Guard.String(rawUid, 16)
		if uid == nil or equipped == nil then
			Security.Strike(player, "SetPetEquipped malformed", 2)
			return false, "Invalid request."
		end
		local ok, message = false, "Your data is still loading."
		DataService.Mutate(player, { "EquippedPets" }, function(data)
			ok, message = PlayerDataOps.SetPetEquipped(data, uid, equipped)
		end)
		return ok, message
	end
end

function PetService.Start()
	for _, egg in CollectionService:GetTagged(Tags.ChronoEgg) do
		connectEgg(egg)
	end
	CollectionService:GetInstanceAddedSignal(Tags.ChronoEgg):Connect(connectEgg)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastHatch[player] = nil
		requestLimiter:Reset(player)
	end)
end

return PetService
