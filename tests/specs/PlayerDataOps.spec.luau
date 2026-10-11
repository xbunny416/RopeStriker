-- Profile mutation rules (DataService's atomic operations).

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local loader = t.loader()
	local GameConfig = loader:require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
	local Formulas = loader:require("src/ReplicatedStorage/Source/Shared/Formulas.luau")
	local Ops = loader:require("src/ServerScriptService/Source/Modules/PlayerDataOps.luau")

	local function newData()
		return Ops.NewData(1700000000)
	end

	local function rebirthReady(data)
		data.HighestEra = 4
		data.UnlockedPortals = { RiftToJapan = true, RiftToSteam = true, RiftToNeon = true }
		data.TotalStrength = 1250000
	end

	describe("NewData", function()
		it("deep-copies the frozen template", function()
			local a = newData()
			local b = newData()
			expect(table.isfrozen(a)).toBe(false)
			expect(table.isfrozen(a.Stats)).toBe(false)
			a.OwnedRopes.BronzeChain = true
			expect(b.OwnedRopes.BronzeChain).toBeNil()
			expect(GameConfig.DefaultPlayerData.OwnedRopes.BronzeChain).toBeNil()
			expect(a.FirstJoinUnix).toBe(1700000000)
		end)
	end)

	describe("AddKP / BankPower", function()
		it("stops at Stamina Capacity until banked", function()
			local data = newData()
			local added, capped = Ops.AddKP(data, 60)
			expect(added).toBe(60)
			expect(capped).toBe(false)
			added, capped = Ops.AddKP(data, 60)
			expect(added).toBe(40)
			expect(capped).toBe(true)
			added, capped = Ops.AddKP(data, 5)
			expect(added).toBe(0)
			expect(capped).toBe(true)
			expect(data.UnbankedKP).toBe(100)

			expect(Ops.BankPower(data)).toBe(100)
			expect(data.UnbankedKP).toBe(0)
			expect(data.TotalStrength).toBe(100)
			expect(data.Stats.StrengthBanked).toBe(100)
			expect(Ops.BankPower(data)).toBe(0)
		end)
		it("rejects NaN, infinite and negative amounts", function()
			local data = newData()
			expect((Ops.AddKP(data, 0 / 0))).toBe(0)
			expect((Ops.AddKP(data, -5))).toBe(0)
			expect((Ops.AddKP(data, math.huge))).toBe(0)
			expect(data.UnbankedKP).toBe(0)
		end)
	end)

	describe("Shards", function()
		it("adds whole shards and refuses overspending", function()
			local data = newData()
			expect(Ops.AddShards(data, 12.9)).toBe(12)
			expect(data.Shards).toBe(12)
			expect(Ops.SpendShards(data, 13)).toBe(false)
			expect(Ops.SpendShards(data, 12)).toBe(true)
			expect(data.Shards).toBe(0)
			expect(Ops.SpendShards(data, -1)).toBe(false)
		end)
	end)

	describe("Shop", function()
		it("buys, charges and equips gear", function()
			local data = newData()
			local ok, message = Ops.Purchase(data, "Rope", "LeatherStrap")
			expect(ok).toBe(false)
			expect(message).toContain("Shards")
			data.Shards = 300
			ok = Ops.Purchase(data, "Rope", "LeatherStrap")
			expect(ok).toBe(true)
			expect(data.Shards).toBe(50)
			expect(data.OwnedRopes.LeatherStrap).toBe(true)
			expect(data.EquippedRope).toBe("LeatherStrap")
		end)
		it("re-equips owned gear for free", function()
			local data = newData()
			data.Shards = 1000
			Ops.Purchase(data, "Boots", "LeatherSandals")
			Ops.Equip(data, "Boots", "BareFeet")
			local before = data.Shards
			expect((Ops.Purchase(data, "Boots", "LeatherSandals"))).toBe(true)
			expect(data.Shards).toBe(before)
			expect(data.EquippedBoots).toBe("LeatherSandals")
		end)
		it("refuses titles, unknown items and unowned equips", function()
			local data = newData()
			data.Shards = 1e9
			expect((Ops.Purchase(data, "Title", "Gladiator"))).toBe(false)
			expect((Ops.Purchase(data, "Rope", "Nope"))).toBe(false)
			expect((Ops.Equip(data, "Rope", "BronzeChain"))).toBe(false)
			expect((Ops.Equip(data, "Title", "Gladiator"))).toBe(false)
			Ops.GrantTitle(data, "Gladiator")
			expect((Ops.Equip(data, "Title", "Gladiator"))).toBe(true)
		end)
	end)

	describe("Pets", function()
		it("grants unique uids and auto-equips into free slots", function()
			local data = newData()
			local first = Ops.GrantPet(data, "MiniCenturion", 1)
			local second = Ops.GrantPet(data, "GoldenEagle", 2)
			expect(first.Uid).toBe("P1")
			expect(second.Uid).toBe("P2")
			Ops.GrantPet(data, "BabyWarMammoth", 3)
			Ops.GrantPet(data, "GoldenEagle", 4)
			expect(#data.EquippedPets).toBe(GameConfig.Pet.MaxEquipped)
			expect(table.find(data.EquippedPets, "P4")).toBeNil()
		end)
		it("enforces slot limits, Epoch Resonance adds a slot", function()
			local data = newData()
			for _ = 1, 4 do
				Ops.GrantPet(data, "MiniCenturion", 0)
			end
			local ok, message = Ops.SetPetEquipped(data, "P4", true)
			expect(ok).toBe(false)
			expect(message).toContain("full")
			data.SkillLevels.EpochResonance = 1
			expect((Ops.SetPetEquipped(data, "P4", true))).toBe(true)
			expect(#data.EquippedPets).toBe(4)
			expect((Ops.SetPetEquipped(data, "P1", false))).toBe(true)
			expect(table.find(data.EquippedPets, "P1")).toBeNil()
			expect((Ops.SetPetEquipped(data, "P99", true))).toBe(false)
		end)
		it("caps the inventory", function()
			local data = newData()
			for _ = 1, GameConfig.Pet.MaxInventory do
				Ops.GrantPet(data, "MiniCenturion", 0)
			end
			expect(Ops.GrantPet(data, "GoldenEagle", 0)).toBeNil()
			expect(Ops.PetCount(data)).toBe(GameConfig.Pet.MaxInventory)
		end)
		it("equips the best pets", function()
			local data = newData()
			for _, petId in { "MiniCenturion", "MiniCenturion", "MiniCenturion", "GoldenEagle", "BabyWarMammoth" } do
				Ops.GrantPet(data, petId, 0)
			end
			Ops.EquipBestPets(data)
			local ids = Formulas.EquippedPetIds(data)
			table.sort(ids)
			expect(ids).toEqual({ "BabyWarMammoth", "GoldenEagle", "MiniCenturion" })
		end)
	end)

	describe("Portals", function()
		it("unlock in order and only with enough stored Strength", function()
			local data = newData()
			expect((Ops.UnlockPortal(data, "RiftToSteam"))).toBe(false) -- not reachable yet
			expect((Ops.UnlockPortal(data, "RiftToJapan"))).toBe(false) -- not strong enough
			data.TotalStrength = 10000
			expect((Ops.UnlockPortal(data, "RiftToJapan"))).toBe(true)
			expect(data.HighestEra).toBe(2)
			expect((Ops.UnlockPortal(data, "RiftToSteam"))).toBe(false)
			data.TotalStrength = 600000
			expect((Ops.UnlockPortal(data, "RiftToSteam"))).toBe(true)
			expect((Ops.UnlockPortal(data, "RiftToNeon"))).toBe(true)
			expect(data.HighestEra).toBe(4)
		end)
	end)

	describe("Rebirth (Temporal Paradox)", function()
		it("is refused until Era 4 + 1,000,000 Strength", function()
			local data = newData()
			data.TotalStrength = 5e6
			local ok = Ops.Rebirth(data)
			expect(ok).toBe(false)
			expect(data.RebirthCount).toBe(0)
		end)

		it("resets KP, Strength, ropes and boots", function()
			local data = newData()
			rebirthReady(data)
			data.UnbankedKP = 50
			data.OwnedRopes.BronzeChain = true
			data.EquippedRope = "BronzeChain"
			data.OwnedBoots.HermesWingedGreaves = true
			data.EquippedBoots = "HermesWingedGreaves"
			expect((Ops.Rebirth(data))).toBe(true)
			expect(data.UnbankedKP).toBe(0)
			expect(data.TotalStrength).toBe(0)
			expect(data.OwnedRopes).toEqual({ HempCord = true })
			expect(data.EquippedRope).toBe("HempCord")
			expect(data.OwnedBoots).toEqual({ BareFeet = true })
			expect(data.EquippedBoots).toBe("BareFeet")
		end)

		it("retains portals, pets, cosmetics, tokens and skills", function()
			local data = newData()
			rebirthReady(data)
			Ops.GrantPet(data, "GoldenEagle", 0)
			Ops.GrantTitle(data, "Gladiator")
			data.RebirthTokens = 2
			data.SkillLevels.KineticEcho = 1
			expect((Ops.Rebirth(data))).toBe(true)
			expect(data.UnlockedPortals.RiftToNeon).toBe(true)
			expect(data.HighestEra).toBe(4)
			expect(data.Pets.P1.Id).toBe("GoldenEagle")
			expect(data.EquippedPets).toEqual({ "P1" })
			expect(data.OwnedTitles.Gladiator).toBe(true)
			expect(data.RebirthTokens).toBe(3)
			expect(data.SkillLevels.KineticEcho).toBe(1)
		end)

		it("raises the compound multiplier and grants milestone titles", function()
			local data = newData()
			rebirthReady(data)
			Ops.Rebirth(data)
			expect(data.RebirthCount).toBe(1)
			expect(Formulas.RebirthMultiplier(data.RebirthCount)).toBeNear(1.5)
			expect(data.OwnedTitles.ParadoxWalker).toBe(true)
			-- Portals are retained, so the next rebirth only needs Strength again.
			data.TotalStrength = 1000000
			expect((Ops.Rebirth(data))).toBe(true)
			expect(data.RebirthCount).toBe(2)
		end)
	end)

	describe("Skill tree", function()
		it("checks tokens, prerequisites and max level", function()
			local data = newData()
			local ok, message = Ops.UnlockSkill(data, "KineticEcho")
			expect(ok).toBe(false)
			expect(message).toContain("Tokens")
			data.RebirthTokens = 20
			ok, message = Ops.UnlockSkill(data, "TemporalSatchel")
			expect(ok).toBe(false)
			expect(message).toContain("Kinetic Echo")
			expect((Ops.UnlockSkill(data, "KineticEcho"))).toBe(true)
			expect((Ops.UnlockSkill(data, "TemporalSatchel"))).toBe(true)
			for _ = 2, 5 do
				Ops.UnlockSkill(data, "KineticEcho")
			end
			expect(data.SkillLevels.KineticEcho).toBe(5)
			ok, message = Ops.UnlockSkill(data, "KineticEcho")
			expect(ok).toBe(false)
			expect(message).toContain("maxed")
			expect(data.RebirthTokens).toBe(20 - 6)
			expect((Ops.UnlockSkill(data, "Nope"))).toBe(false)
		end)
	end)

	describe("Sanitize & Migrate", function()
		it("repairs corrupted fields", function()
			local data = newData()
			data.Shards = 0 / 0
			data.TotalStrength = -50
			data.EquippedRope = "GhostRope"
			data.EquippedBoots = "HermesWingedGreaves" -- not owned
			data.HighestEra = 99
			data.SkillLevels.KineticEcho = 42
			data.SkillLevels.Removed = 3
			Ops.GrantPet(data, "MiniCenturion", 0)
			data.EquippedPets = { "P1", "P1", "Missing" }
			data.Pets.P7 = { Uid = "P7", Id = "GoldenEagle", ObtainedUnix = 0 }
			data.NextPetUid = 2
			data.UnbankedKP = 5000
			Ops.Sanitize(data)
			expect(data.Shards).toBe(0)
			expect(data.TotalStrength).toBe(0)
			expect(data.EquippedRope).toBe("HempCord")
			expect(data.EquippedBoots).toBe("BareFeet")
			expect(data.HighestEra).toBe(#GameConfig.Eras)
			expect(data.SkillLevels.KineticEcho).toBe(5)
			expect(data.SkillLevels.Removed).toBeNil()
			expect(data.EquippedPets).toEqual({ "P1" })
			expect(data.NextPetUid).toBe(8)
			expect(data.UnbankedKP).toBe(Formulas.StaminaCapacity(data))
		end)
		it("stamps the current data version", function()
			local data = newData()
			data.DataVersion = 0
			Ops.Migrate(data)
			expect(data.DataVersion).toBe(GameConfig.Data.CurrentVersion)
		end)
	end)
end
