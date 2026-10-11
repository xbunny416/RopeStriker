-- Bible §2 economy: KP gain, capacity, damage, shared-mob payouts, rebirth, eggs.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local loader = t.loader()
	local GameConfig = loader:require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
	local Formulas = loader:require("src/ReplicatedStorage/Source/Shared/Formulas.luau")
	local Ops = loader:require("src/ServerScriptService/Source/Modules/PlayerDataOps.luau")

	local function newData()
		return Ops.NewData(0)
	end

	describe("RebirthMultiplier", function()
		it("compounds +50% per rebirth", function()
			expect(Formulas.RebirthMultiplier(0)).toBe(1)
			expect(Formulas.RebirthMultiplier(1)).toBeNear(1.5)
			expect(Formulas.RebirthMultiplier(2)).toBeNear(2.25)
			expect(Formulas.RebirthMultiplier(3)).toBeNear(3.375)
		end)
		it("never drops below 1 for bad input", function()
			expect(Formulas.RebirthMultiplier(-4)).toBe(1)
		end)
	end)

	describe("PetMultiplierSum", function()
		it("is 1x with no pets", function()
			expect(Formulas.PetMultiplierSum({})).toBe(1)
		end)
		it("sums equipped pet multipliers", function()
			expect(Formulas.PetMultiplierSum({ "MiniCenturion" })).toBeNear(1.2)
			expect(Formulas.PetMultiplierSum({ "GoldenEagle", "GoldenEagle", "GoldenEagle" })).toBeNear(7.5)
			expect(Formulas.PetMultiplierSum({ "MiniCenturion", "BabyWarMammoth" })).toBeNear(2.8)
		end)
		it("ignores unknown pet ids", function()
			expect(Formulas.PetMultiplierSum({ "NotAPet", "MiniCenturion" })).toBeNear(1.2)
		end)
	end)

	describe("KP gain", function()
		it("is the product of every term", function()
			local gain = Formulas.KPGain({
				BaseRopeKP = 4,
				BootMultiplier = 1.5,
				PetMultiplierSum = 2,
				RhythmComboBonus = 2.5,
				RebirthMultiplier = 1.5,
				SkillMultiplier = 1.15,
			})
			expect(gain).toBeNear(4 * 1.5 * 2 * 2.5 * 1.5 * 1.15)
		end)

		it("starts at 1 KP per bounce for a fresh profile", function()
			local data = newData()
			expect(Formulas.KPPerBounce(data, 1)).toBe(1)
			expect(Formulas.KPPerBounce(data, 2.5)).toBeNear(2.5)
		end)

		it("applies rope, boots, pets, combo, rebirth and Kinetic Echo", function()
			local data = newData()
			data.OwnedRopes.LeatherStrap = true
			data.EquippedRope = "LeatherStrap"
			data.OwnedBoots.LeatherSandals = true
			data.EquippedBoots = "LeatherSandals"
			Ops.GrantPet(data, "MiniCenturion", 0)
			data.RebirthCount = 1
			data.SkillLevels.KineticEcho = 2
			-- 4 KP * 1.5 boots * 1.2 pets * 2.0 combo * 1.5 rebirth * 1.3 skill
			expect(Formulas.KPPerBounce(data, 2)).toBeNear(28.08, 1e-9)
		end)
	end)

	describe("Stamina capacity", function()
		it("defaults to 100 (Bible §2.1)", function()
			expect(Formulas.StaminaCapacity(newData())).toBe(100)
		end)
		it("scales with boots, rebirths and Temporal Satchel", function()
			local data = newData()
			data.OwnedBoots.HermesWingedGreaves = true
			data.EquippedBoots = "HermesWingedGreaves"
			expect(Formulas.StaminaCapacity(data)).toBe(15000)
			data.RebirthCount = 1
			expect(Formulas.StaminaCapacity(data)).toBe(22500)
			data.SkillLevels.TemporalSatchel = 2
			expect(Formulas.StaminaCapacity(data)).toBe(36000)
		end)
		it("clamps gains to the remaining room and reports the cap", function()
			local accepted, capped = Formulas.ClampToCapacity(90, 20, 100)
			expect(accepted).toBe(10)
			expect(capped).toBe(true)
			accepted, capped = Formulas.ClampToCapacity(0, 5, 100)
			expect(accepted).toBe(5)
			expect(capped).toBe(false)
			accepted, capped = Formulas.ClampToCapacity(100, 5, 100)
			expect(accepted).toBe(0)
			expect(capped).toBe(true)
		end)
	end)

	describe("Damage", function()
		it("follows ((Strength ^ 0.65) + RopeBaseDamage) * PetMultiplierSum", function()
			expect(Formulas.BaseDamage(0, 10, 1)).toBe(10)
			expect(Formulas.BaseDamage(1000, 10, 1)).toBeNear(1000 ^ 0.65 + 10, 1e-9)
			expect(Formulas.BaseDamage(1e6, 75, 2.5)).toBeNear((1e6 ^ 0.65 + 75) * 2.5, 1e-6)
		end)
		it("makes Aerial Sweep deal 0.75x of Ground Lash", function()
			local data = newData()
			data.TotalStrength = 5000
			local ground = Formulas.AttackDamage(data, "GroundLash")
			local aerial = Formulas.AttackDamage(data, "AerialSweep")
			expect(aerial).toBeNear(ground * 0.75, 1e-9)
		end)
		it("adds Paradox Edge per level", function()
			local data = newData()
			local before = Formulas.AttackDamage(data, "GroundLash")
			data.SkillLevels.ParadoxEdge = 3
			expect(Formulas.AttackDamage(data, "GroundLash")).toBeNear(before * 1.45, 1e-9)
		end)
	end)

	describe("Shared-mob payouts", function()
		local base = GameConfig.Mobs.RomanLegionary.Drops.BaseShards
		local maxHealth = GameConfig.Mobs.RomanLegionary.MaxHealth

		it("requires at least 5% of max health", function()
			expect(Formulas.IsEligibleContributor(maxHealth * 0.05, maxHealth)).toBe(true)
			expect(Formulas.IsEligibleContributor(maxHealth * 0.049, maxHealth)).toBe(false)
			expect(Formulas.ShardPayout(base, maxHealth * 0.049, maxHealth, 1)).toBe(0)
		end)
		it("pays BaseMobShards * share * RebirthMultiplier", function()
			expect(Formulas.ShardPayout(base, maxHealth, maxHealth, 1)).toBe(base)
			expect(Formulas.ShardPayout(1200, 4000, 10000, 1)).toBe(480)
			expect(Formulas.ShardPayout(1200, 4000, 10000, 2.25)).toBe(1080)
			expect(Formulas.ShardPayout(1200, 4000, 10000, 1, 1.5)).toBe(720)
		end)
		it("always pays eligible contributors at least one Shard", function()
			expect(Formulas.ShardPayout(15, 12.5, 250, 1)).toBe(1)
		end)
	end)

	describe("Rebirth requirement", function()
		it("needs Era 4 and 1,000,000 Strength", function()
			local data = newData()
			data.TotalStrength = 2e6
			expect(Formulas.CheckRebirth(data).Allowed).toBe(false)
			data.HighestEra = 4
			data.TotalStrength = 999999
			expect(Formulas.CheckRebirth(data).Allowed).toBe(false)
			data.TotalStrength = 1000000
			expect(Formulas.CheckRebirth(data).Allowed).toBe(true)
		end)
	end)

	describe("Portal requirement", function()
		it("checks stored strength and rebirths", function()
			local data = newData()
			local portal = GameConfig.Portals.RiftToJapan
			expect(Formulas.MeetsPortalRequirement(data, portal)).toBe(false)
			data.TotalStrength = portal.RequiredStrength
			expect(Formulas.MeetsPortalRequirement(data, portal)).toBe(true)
		end)
	end)

	describe("Eggs", function()
		it("returns weights in layout order", function()
			local entries = Formulas.EggWeights(GameConfig.Eggs.BronzeEgg, 0)
			expect(#entries).toBe(3)
			expect(entries[1].PetId).toBe("MiniCenturion")
			expect(entries[3].PetId).toBe("GoldenEagle")
			expect(entries[1].Weight).toBe(80)
		end)
		it("boosts only rarer pets with Chrono Luck", function()
			local entries = Formulas.EggWeights(GameConfig.Eggs.BronzeEgg, 0.5)
			expect(entries[1].Weight).toBe(80)
			expect(entries[2].Weight).toBeNear(27)
			expect(entries[3].Weight).toBeNear(3)
		end)
		it("picks deterministically from a roll", function()
			local entries = Formulas.EggWeights(GameConfig.Eggs.BronzeEgg, 0)
			expect(Formulas.PickWeighted(entries, 0)).toBe("MiniCenturion")
			expect(Formulas.PickWeighted(entries, 0.79)).toBe("MiniCenturion")
			expect(Formulas.PickWeighted(entries, 0.81)).toBe("BabyWarMammoth")
			expect(Formulas.PickWeighted(entries, 0.999)).toBe("GoldenEagle")
		end)
		it("matches the configured odds over many rolls", function()
			local entries = Formulas.EggWeights(GameConfig.Eggs.SilverEgg, 0)
			local counts = {}
			local samples = 20000
			for index = 0, samples - 1 do
				local pet = Formulas.PickWeighted(entries, (index + 0.5) / samples)
				counts[pet] = (counts[pet] or 0) + 1
			end
			expect(counts.MiniCenturion / samples).toBeNear(0.5, 0.001)
			expect(counts.BabyWarMammoth / samples).toBeNear(0.42, 0.001)
			expect(counts.GoldenEagle / samples).toBeNear(0.08, 0.001)
		end)
	end)
end
