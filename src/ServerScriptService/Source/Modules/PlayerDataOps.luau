--!strict
--[[
	PlayerDataOps
	-------------
	Pure, synchronous mutation logic over a PlayerData table. DataService wraps every
	call in an atomic section (see DataService.Mutate) and handles replication; this
	module only enforces the rules, which keeps them unit-testable without Roblox.

	Every function either fully applies its change or leaves the data untouched, and
	none of them yield.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)
local Formulas = require(ReplicatedStorage.Source.Shared.Formulas)

type PlayerData = GameConfig.PlayerData
type PetRecord = GameConfig.PetRecord
type ItemCategory = GameConfig.ItemCategory

local Ops = {}

local function isFiniteNonNegative(value: any): boolean
	return type(value) == "number" and value == value and value >= 0 and value ~= math.huge
end

-- Recursive copy of plain data tables (no metatables, no cycles).
function Ops.DeepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[Ops.DeepCopy(key)] = Ops.DeepCopy(child)
	end
	return copy
end

function Ops.NewData(nowUnix: number): PlayerData
	local data: PlayerData = Ops.DeepCopy(GameConfig.DefaultPlayerData)
	data.FirstJoinUnix = nowUnix
	data.LastJoinUnix = nowUnix
	return data
end

---------------------------------------------------------------------------------------
-- Versioning & repair
---------------------------------------------------------------------------------------

-- Ordered migrations: MIGRATIONS[n] upgrades a profile from version n to n + 1.
local MIGRATIONS: { [number]: (data: any) -> () } = {}

function Ops.Migrate(data: PlayerData)
	local version = if type(data.DataVersion) == "number" then data.DataVersion else 1
	while version < GameConfig.Data.CurrentVersion do
		local migrate = MIGRATIONS[version]
		if migrate then
			migrate(data)
		end
		version += 1
	end
	data.DataVersion = GameConfig.Data.CurrentVersion
end

--[[
	Repairs anything a crash, a config change or a bad write could have left behind:
	non-finite numbers, equipped items that are not owned or no longer exist, dangling
	pet references, duplicate equips and over-capacity unbanked KP.
]]
function Ops.Sanitize(data: PlayerData)
	local numericKeys = { "UnbankedKP", "TotalStrength", "Shards", "RebirthCount", "RebirthTokens", "NextPetUid" }
	for _, key in numericKeys do
		local value = (data :: any)[key]
		if not isFiniteNonNegative(value) then
			(data :: any)[key] = 0
		end
	end
	data.RebirthCount = math.floor(data.RebirthCount)
	data.RebirthTokens = math.floor(data.RebirthTokens)
	-- Never hand out a uid that is already taken.
	local nextUid = math.max(1, math.floor(data.NextPetUid))
	for uid in data.Pets do
		local number = tonumber(string.match(uid, "^P(%d+)$"))
		if number and number >= nextUid then
			nextUid = number + 1
		end
	end
	data.NextPetUid = nextUid
	data.HighestEra = math.clamp(math.floor(tonumber(data.HighestEra) or 1), 1, #GameConfig.Eras)

	-- Gear
	data.OwnedRopes[GameConfig.Starter.Rope] = true
	if not (GameConfig.Ropes[data.EquippedRope] and data.OwnedRopes[data.EquippedRope]) then
		data.EquippedRope = GameConfig.Starter.Rope
	end
	data.OwnedBoots[GameConfig.Starter.Boots] = true
	if not (GameConfig.Boots[data.EquippedBoots] and data.OwnedBoots[data.EquippedBoots]) then
		data.EquippedBoots = GameConfig.Starter.Boots
	end
	data.OwnedTitles[GameConfig.Starter.Title] = true
	if not (GameConfig.Titles[data.EquippedTitle] and data.OwnedTitles[data.EquippedTitle]) then
		data.EquippedTitle = GameConfig.Starter.Title
	end

	-- Skill levels
	for nodeId, level in data.SkillLevels do
		local node = GameConfig.SkillTree[nodeId]
		if node == nil or not isFiniteNonNegative(level) then
			data.SkillLevels[nodeId] = nil
		else
			data.SkillLevels[nodeId] = math.clamp(math.floor(level), 0, node.MaxLevel)
		end
	end

	-- Pets: equipped uids must exist, be unique and fit the slot count.
	local maxEquipped = Formulas.MaxEquippedPets(data)
	local seen: { [string]: boolean } = {}
	local cleaned: { string } = {}
	for _, uid in data.EquippedPets do
		local record = data.Pets[uid]
		if record and GameConfig.Pets[record.Id] and not seen[uid] and #cleaned < maxEquipped then
			seen[uid] = true
			table.insert(cleaned, uid)
		end
	end
	data.EquippedPets = cleaned

	-- Portals that no longer exist are dropped; HighestEra follows what is unlocked.
	for portalId in data.UnlockedPortals do
		local portal = GameConfig.Portals[portalId]
		if portal == nil then
			data.UnlockedPortals[portalId] = nil
		else
			data.HighestEra = math.max(data.HighestEra, portal.ToEra)
		end
	end

	-- Capacity can shrink after a balance patch; never leave a profile over the cap.
	data.UnbankedKP = math.min(data.UnbankedKP, Formulas.StaminaCapacity(data))
end

---------------------------------------------------------------------------------------
-- Core economy (Bible §2.1)
---------------------------------------------------------------------------------------

--[[
	Adds kinetic power to the unbanked pool, respecting Stamina Capacity.
	Returns (added, reachedCap). Once the cap is reached, further bounces yield 0 KP
	until the player banks at the Epoch Obelisk.
]]
function Ops.AddKP(data: PlayerData, amount: number): (number, boolean)
	if not isFiniteNonNegative(amount) then
		return 0, data.UnbankedKP >= Formulas.StaminaCapacity(data)
	end
	local accepted, reachedCap = Formulas.ClampToCapacity(data.UnbankedKP, amount, Formulas.StaminaCapacity(data))
	data.UnbankedKP += accepted
	return accepted, reachedCap
end

-- Converts all unbanked KP into permanent TotalStrength. Returns the amount banked.
function Ops.BankPower(data: PlayerData): number
	local amount = data.UnbankedKP
	if amount <= 0 then
		return 0
	end
	data.TotalStrength += amount
	data.UnbankedKP = 0
	data.Stats.StrengthBanked += amount
	return amount
end

function Ops.AddShards(data: PlayerData, amount: number): number
	if not isFiniteNonNegative(amount) then
		return 0
	end
	local whole = math.floor(amount)
	data.Shards += whole
	data.Stats.ShardsEarned += whole
	return whole
end

function Ops.SpendShards(data: PlayerData, amount: number): boolean
	if not isFiniteNonNegative(amount) or data.Shards < amount then
		return false
	end
	data.Shards -= amount
	return true
end

function Ops.RecordBounce(data: PlayerData, onBeat: boolean, combo: number)
	data.Stats.Bounces += 1
	if onBeat then
		data.Stats.OnBeatBounces += 1
	end
	if combo > data.Stats.BestCombo then
		data.Stats.BestCombo = combo
	end
end

---------------------------------------------------------------------------------------
-- Gear, titles & shop
---------------------------------------------------------------------------------------

local function catalogue(category: ItemCategory): { [string]: any }
	if category == "Rope" then
		return GameConfig.Ropes
	elseif category == "Boots" then
		return GameConfig.Boots
	end
	return GameConfig.Titles
end

local function ownedSet(data: PlayerData, category: ItemCategory): { [string]: boolean }
	if category == "Rope" then
		return data.OwnedRopes
	elseif category == "Boots" then
		return data.OwnedBoots
	end
	return data.OwnedTitles
end

function Ops.Owns(data: PlayerData, category: ItemCategory, itemId: string): boolean
	return ownedSet(data, category)[itemId] == true
end

function Ops.Equip(data: PlayerData, category: ItemCategory, itemId: string): (boolean, string)
	if catalogue(category)[itemId] == nil then
		return false, "Unknown item."
	end
	if not Ops.Owns(data, category, itemId) then
		return false, "You don't own that yet."
	end
	if category == "Rope" then
		data.EquippedRope = itemId
	elseif category == "Boots" then
		data.EquippedBoots = itemId
	else
		data.EquippedTitle = itemId
	end
	return true, "Equipped."
end

-- Buys a rope or boots with Shards and equips it. Titles cannot be bought.
function Ops.Purchase(data: PlayerData, category: ItemCategory, itemId: string): (boolean, string)
	if category ~= "Rope" and category ~= "Boots" then
		return false, "That item is not for sale."
	end
	local item = catalogue(category)[itemId]
	if item == nil then
		return false, "Unknown item."
	end
	if Ops.Owns(data, category, itemId) then
		return Ops.Equip(data, category, itemId)
	end
	if item.Era > data.HighestEra then
		return false, `Unlock Era {item.Era} to buy this.`
	end
	if not Ops.SpendShards(data, item.Price) then
		return false, "Not enough Shards."
	end
	ownedSet(data, category)[itemId] = true
	Ops.Equip(data, category, itemId)
	return true, `Purchased {item.DisplayName}!`
end

function Ops.GrantTitle(data: PlayerData, titleId: string): boolean
	if GameConfig.Titles[titleId] == nil or data.OwnedTitles[titleId] then
		return false
	end
	data.OwnedTitles[titleId] = true
	return true
end

---------------------------------------------------------------------------------------
-- Pets
---------------------------------------------------------------------------------------

function Ops.PetCount(data: PlayerData): number
	local count = 0
	for _ in data.Pets do
		count += 1
	end
	return count
end

function Ops.HasInventoryRoom(data: PlayerData): boolean
	return Ops.PetCount(data) < GameConfig.Pet.MaxInventory
end

-- Adds a pet (auto-equipping it when a slot is free). Nil when the inventory is full.
function Ops.GrantPet(data: PlayerData, petId: string, nowUnix: number): PetRecord?
	if GameConfig.Pets[petId] == nil or not Ops.HasInventoryRoom(data) then
		return nil
	end
	local uid = `P{data.NextPetUid}`
	data.NextPetUid += 1
	local record: PetRecord = { Uid = uid, Id = petId, ObtainedUnix = nowUnix }
	data.Pets[uid] = record
	if #data.EquippedPets < Formulas.MaxEquippedPets(data) then
		table.insert(data.EquippedPets, uid)
	end
	return record
end

function Ops.SetPetEquipped(data: PlayerData, uid: string, equipped: boolean): (boolean, string)
	local record = data.Pets[uid]
	if record == nil then
		return false, "Unknown pet."
	end
	local index = table.find(data.EquippedPets, uid)
	if equipped then
		if index then
			return true, "Already equipped."
		end
		if #data.EquippedPets >= Formulas.MaxEquippedPets(data) then
			return false, "All pet slots are full."
		end
		table.insert(data.EquippedPets, uid)
		return true, "Pet equipped."
	end
	if index then
		table.remove(data.EquippedPets, index)
	end
	return true, "Pet unequipped."
end

-- Equips the highest-multiplier pets the player owns.
function Ops.EquipBestPets(data: PlayerData)
	local uids: { string } = {}
	for uid, record in data.Pets do
		if GameConfig.Pets[record.Id] then
			table.insert(uids, uid)
		end
	end
	table.sort(uids, function(a: string, b: string): boolean
		local pa = GameConfig.Pets[data.Pets[a].Id]
		local pb = GameConfig.Pets[data.Pets[b].Id]
		if pa.Multiplier ~= pb.Multiplier then
			return pa.Multiplier > pb.Multiplier
		end
		return a < b
	end)
	local equipped: { string } = {}
	for index = 1, math.min(#uids, Formulas.MaxEquippedPets(data)) do
		equipped[index] = uids[index]
	end
	data.EquippedPets = equipped
end

---------------------------------------------------------------------------------------
-- Portals (§3.1)
---------------------------------------------------------------------------------------

function Ops.UnlockPortal(data: PlayerData, portalId: string): (boolean, string)
	local portal = GameConfig.Portals[portalId]
	if portal == nil then
		return false, "Unknown rift."
	end
	if data.UnlockedPortals[portalId] then
		return true, "Already unlocked."
	end
	if data.HighestEra < portal.FromEra then
		return false, "You cannot reach this rift yet."
	end
	if not Formulas.MeetsPortalRequirement(data, portal) then
		return false, "Requirements not met."
	end
	data.UnlockedPortals[portalId] = true
	data.HighestEra = math.max(data.HighestEra, portal.ToEra)
	return true, `{portal.DisplayName} opened!`
end

---------------------------------------------------------------------------------------
-- Temporal Paradox (§2.2)
---------------------------------------------------------------------------------------

--[[
	Resets: unbanked KP, TotalStrength, owned + equipped ropes, owned + equipped boots.
	Retains: unlocked portals (and so HighestEra), all pets, cosmetics, rebirth tokens
	and skill levels.
	Rewards: +1 RebirthCount (=> +50% compound multiplier), rebirth tokens, milestone titles.
]]
function Ops.Rebirth(data: PlayerData): (boolean, string)
	local check = Formulas.CheckRebirth(data)
	if not check.Allowed then
		return false, check.Reason or "Requirements not met."
	end

	data.RebirthCount += 1
	data.RebirthTokens += GameConfig.Rebirth.TokensPerRebirth
	data.Stats.Rebirths += 1

	data.UnbankedKP = 0
	data.TotalStrength = 0
	data.OwnedRopes = { [GameConfig.Starter.Rope] = true }
	data.EquippedRope = GameConfig.Starter.Rope
	data.OwnedBoots = { [GameConfig.Starter.Boots] = true }
	data.EquippedBoots = GameConfig.Starter.Boots

	local milestone = GameConfig.Rebirth.MilestoneTitles[data.RebirthCount]
	if milestone then
		Ops.GrantTitle(data, milestone)
	end

	return true, `Temporal Paradox #{data.RebirthCount} complete!`
end

function Ops.SkillLevel(data: PlayerData, nodeId: string): number
	return data.SkillLevels[nodeId] or 0
end

function Ops.CanUnlockSkill(data: PlayerData, nodeId: string): (boolean, string)
	local node = GameConfig.SkillTree[nodeId]
	if node == nil then
		return false, "Unknown skill."
	end
	local level = Ops.SkillLevel(data, nodeId)
	if level >= node.MaxLevel then
		return false, "Already maxed."
	end
	for _, requirement in node.Requires do
		if Ops.SkillLevel(data, requirement.Id) < requirement.Level then
			local required = GameConfig.SkillTree[requirement.Id]
			local name = if required then required.DisplayName else requirement.Id
			return false, `Requires {name} level {requirement.Level}.`
		end
	end
	if data.RebirthTokens < node.CostPerLevel then
		return false, "Not enough Rebirth Tokens."
	end
	return true, ""
end

function Ops.UnlockSkill(data: PlayerData, nodeId: string): (boolean, string)
	local allowed, reason = Ops.CanUnlockSkill(data, nodeId)
	if not allowed then
		return false, reason
	end
	local node = GameConfig.SkillTree[nodeId]
	data.RebirthTokens -= node.CostPerLevel
	data.SkillLevels[nodeId] = Ops.SkillLevel(data, nodeId) + 1
	return true, `{node.DisplayName} upgraded to level {data.SkillLevels[nodeId]}.`
end

return Ops
