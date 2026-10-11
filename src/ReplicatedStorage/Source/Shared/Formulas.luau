--!strict
--[[
	Formulas
	--------
	The Mathematical Economy & Progression Matrix (Project Bible §2), implemented once
	and shared by server (authoritative) and client (UI previews).

	  KP_gain    = BaseRopeKP * BootMultiplier * PetMultiplierSum * RhythmComboBonus
	               * RebirthMultiplier * (1 + Kinetic Echo bonus)
	  Capacity   = BootStaminaCapacity * RebirthMultiplier * (1 + Temporal Satchel bonus)
	  DMG        = ((TotalStrength ^ 0.65) + RopeBaseDamage) * PetMultiplierSum
	               * AttackMultiplier * (1 + Paradox Edge bonus)
	  Shards     = BaseMobShards * (DamageDealtByPlayer / TotalMobMaxHealth)
	               * RebirthMultiplier * (1 + Shard Siphon bonus)
	  Rebirth    = 1.5 ^ RebirthCount   (+50% compound per rebirth)

	Interpretation notes (documented in docs/GameDesign.md):
	  * "+50% compound base stat multiplier" is applied to the base stats a player
	    accrues: KP per bounce and Stamina Capacity (so bounces-per-bank stays constant
	    across rebirths), plus the Shard payout where the Bible names it explicitly.
	  * PetMultiplierSum is the sum of equipped pet multipliers, floored at 1.0 so a
	    player without pets is not zeroed out.
	  * Damage only scales with rebirths indirectly, through faster strength gain.
]]

local GameConfig = require(script.Parent.Parent.Configuration.GameConfig)

type PlayerData = GameConfig.PlayerData
type AttackKind = GameConfig.AttackKind
type SkillEffect = GameConfig.SkillEffect

local Formulas = {}

---------------------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------------------

function Formulas.RebirthMultiplier(rebirthCount: number): number
	return GameConfig.Rebirth.MultiplierBase ^ math.max(0, rebirthCount)
end

-- Sum of an effect across every skill node of that effect type.
function Formulas.SkillBonus(skillLevels: { [string]: number }, effect: SkillEffect): number
	local bonus = 0
	for nodeId, level in skillLevels do
		local node = GameConfig.SkillTree[nodeId]
		if node and node.Effect == effect then
			bonus += node.PerLevel * math.clamp(level, 0, node.MaxLevel)
		end
	end
	return bonus
end

function Formulas.PetMultiplierSum(petIds: { string }): number
	local sum = 0
	for _, petId in petIds do
		local pet = GameConfig.Pets[petId]
		if pet then
			sum += pet.Multiplier
		end
	end
	return math.max(1, sum)
end

-- Pet catalogue ids for the profile's equipped pet uids (invalid uids are skipped).
function Formulas.EquippedPetIds(data: PlayerData): { string }
	local ids: { string } = {}
	for _, uid in data.EquippedPets do
		local record = data.Pets[uid]
		if record and GameConfig.Pets[record.Id] then
			table.insert(ids, record.Id)
		end
	end
	return ids
end

function Formulas.MaxEquippedPets(data: PlayerData): number
	return GameConfig.Pet.MaxEquipped + math.floor(Formulas.SkillBonus(data.SkillLevels, "PetSlots"))
end

function Formulas.Rope(data: PlayerData): GameConfig.RopeData
	return GameConfig.Ropes[data.EquippedRope] or GameConfig.Ropes[GameConfig.Starter.Rope]
end

function Formulas.Boots(data: PlayerData): GameConfig.BootData
	return GameConfig.Boots[data.EquippedBoots] or GameConfig.Boots[GameConfig.Starter.Boots]
end

---------------------------------------------------------------------------------------
-- Kinetic Power (§2.1)
---------------------------------------------------------------------------------------

export type KPInputs = {
	BaseRopeKP: number,
	BootMultiplier: number,
	PetMultiplierSum: number,
	RhythmComboBonus: number,
	RebirthMultiplier: number,
	SkillMultiplier: number,
}

-- The raw Bible formula with the rebirth/skill extensions; every input is explicit.
function Formulas.KPGain(inputs: KPInputs): number
	return inputs.BaseRopeKP
		* inputs.BootMultiplier
		* inputs.PetMultiplierSum
		* inputs.RhythmComboBonus
		* inputs.RebirthMultiplier
		* inputs.SkillMultiplier
end

function Formulas.KPInputsFor(data: PlayerData, combo: number): KPInputs
	return {
		BaseRopeKP = Formulas.Rope(data).BaseKP,
		BootMultiplier = Formulas.Boots(data).Multiplier,
		PetMultiplierSum = Formulas.PetMultiplierSum(Formulas.EquippedPetIds(data)),
		RhythmComboBonus = combo,
		RebirthMultiplier = Formulas.RebirthMultiplier(data.RebirthCount),
		SkillMultiplier = 1 + Formulas.SkillBonus(data.SkillLevels, "KPGain"),
	}
end

function Formulas.KPPerBounce(data: PlayerData, combo: number): number
	return Formulas.KPGain(Formulas.KPInputsFor(data, combo))
end

function Formulas.StaminaCapacity(data: PlayerData): number
	local base = Formulas.Boots(data).StaminaCapacity
	local rebirth = Formulas.RebirthMultiplier(data.RebirthCount)
	local satchel = 1 + Formulas.SkillBonus(data.SkillLevels, "Capacity")
	return math.floor(base * rebirth * satchel + 0.5)
end

--[[
	How much of `gain` fits under the Stamina Capacity. Once the cap is reached,
	bounces yield 0 KP until the player banks at the Epoch Obelisk.
	Returns (accepted, reachedCap).
]]
function Formulas.ClampToCapacity(unbanked: number, gain: number, capacity: number): (number, boolean)
	local room = math.max(0, capacity - unbanked)
	if gain >= room then
		return room, true
	end
	return math.max(0, gain), false
end

---------------------------------------------------------------------------------------
-- Damage (§2.1)
---------------------------------------------------------------------------------------

function Formulas.BaseDamage(totalStrength: number, ropeBaseDamage: number, petMultiplierSum: number): number
	local strengthTerm = math.max(0, totalStrength) ^ GameConfig.Combat.StrengthExponent
	return (strengthTerm + ropeBaseDamage) * petMultiplierSum
end

function Formulas.AttackDamage(data: PlayerData, attack: AttackKind): number
	local attackData = GameConfig.Combat.Attacks[attack]
	local base = Formulas.BaseDamage(
		data.TotalStrength,
		Formulas.Rope(data).BaseDamage,
		Formulas.PetMultiplierSum(Formulas.EquippedPetIds(data))
	)
	local edge = 1 + Formulas.SkillBonus(data.SkillLevels, "Damage")
	return base * attackData.Multiplier * edge
end

---------------------------------------------------------------------------------------
-- Shared-mob rewards (§2.1)
---------------------------------------------------------------------------------------

function Formulas.ContributionFraction(damageDealt: number, maxHealth: number): number
	if maxHealth <= 0 then
		return 0
	end
	return math.clamp(damageDealt / maxHealth, 0, 1)
end

function Formulas.IsEligibleContributor(damageDealt: number, maxHealth: number): boolean
	return Formulas.ContributionFraction(damageDealt, maxHealth) + 1e-9 >= GameConfig.Rewards.ContributionThreshold
end

--[[
	Shards = BaseMobShards * (DamageDealtByPlayer / TotalMobMaxHealth) * RebirthMultiplier
	(* Shard Siphon). Rounded to the nearest whole Shard; eligible contributors always
	receive at least MinimumPayout. Ineligible contributors (< 5%) receive 0.
]]
function Formulas.ShardPayout(
	baseShards: number,
	damageDealt: number,
	maxHealth: number,
	rebirthMultiplier: number,
	skillMultiplier: number?
): number
	if not Formulas.IsEligibleContributor(damageDealt, maxHealth) then
		return 0
	end
	local fraction = Formulas.ContributionFraction(damageDealt, maxHealth)
	local raw = baseShards * fraction * rebirthMultiplier * (skillMultiplier or 1)
	return math.max(GameConfig.Rewards.MinimumPayout, math.floor(raw + 0.5))
end

---------------------------------------------------------------------------------------
-- Rebirth (§2.2) & portals (§3.1)
---------------------------------------------------------------------------------------

export type RebirthCheck = {
	Allowed: boolean,
	Reason: string?,
}

function Formulas.CheckRebirth(data: PlayerData): RebirthCheck
	local rules = GameConfig.Rebirth
	if data.HighestEra < rules.RequiredEra then
		return { Allowed = false, Reason = `Reach Era {rules.RequiredEra} first.` }
	end
	if data.TotalStrength < rules.RequiredStrength then
		return { Allowed = false, Reason = "Not enough Strength." }
	end
	return { Allowed = true, Reason = nil }
end

function Formulas.MeetsPortalRequirement(data: PlayerData, portal: GameConfig.PortalData): boolean
	return data.TotalStrength >= portal.RequiredStrength and data.RebirthCount >= portal.RequiredRebirths
end

---------------------------------------------------------------------------------------
-- Eggs
---------------------------------------------------------------------------------------

--[[
	Hatch weights for an egg after Chrono Luck: weights of every pet rarer than the
	egg's most common pet are multiplied by (1 + luck). Returns a sorted, stable list
	so a given random roll always maps to the same pet.
]]
function Formulas.EggWeights(egg: GameConfig.EggData, luck: number): { { PetId: string, Weight: number } }
	local entries: { { PetId: string, Weight: number } } = {}
	local lowestRarity = math.huge
	for petId in egg.Weights do
		local pet = GameConfig.Pets[petId]
		if pet then
			lowestRarity = math.min(lowestRarity, GameConfig.Pet.RarityOrder[pet.Rarity])
		end
	end
	for petId, weight in egg.Weights do
		local pet = GameConfig.Pets[petId]
		if pet and weight > 0 then
			local boosted = if GameConfig.Pet.RarityOrder[pet.Rarity] > lowestRarity
				then weight * (1 + math.max(0, luck))
				else weight
			table.insert(entries, { PetId = petId, Weight = boosted })
		end
	end
	table.sort(entries, function(a: { PetId: string, Weight: number }, b: { PetId: string, Weight: number }): boolean
		local pa = GameConfig.Pets[a.PetId]
		local pb = GameConfig.Pets[b.PetId]
		if pa.LayoutOrder ~= pb.LayoutOrder then
			return pa.LayoutOrder < pb.LayoutOrder
		end
		return a.PetId < b.PetId
	end)
	return entries
end

-- Picks a pet from weighted entries using a roll in [0, 1).
function Formulas.PickWeighted(entries: { { PetId: string, Weight: number } }, roll: number): string?
	local total = 0
	for _, entry in entries do
		total += entry.Weight
	end
	if total <= 0 then
		return nil
	end
	local target = math.clamp(roll, 0, 0.999999999) * total
	local cumulative = 0
	for _, entry in entries do
		cumulative += entry.Weight
		if target < cumulative then
			return entry.PetId
		end
	end
	return entries[#entries].PetId
end

return Formulas
