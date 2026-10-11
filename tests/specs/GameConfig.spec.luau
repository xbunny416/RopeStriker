-- Referential integrity of the content catalogues and Bible constants.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local loader = t.loader()
	local GameConfig = loader:require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")

	describe("Bible constants", function()
		it("matches §2 and §3.2", function()
			expect(GameConfig.Rhythm.ToleranceSeconds).toBe(0.15)
			expect(GameConfig.Rhythm.ComboStep).toBe(0.1)
			expect(GameConfig.Rhythm.ComboCap).toBe(2.5)
			expect(GameConfig.Boots[GameConfig.Starter.Boots].StaminaCapacity).toBe(100)
			expect(GameConfig.Combat.StrengthExponent).toBe(0.65)
			expect(GameConfig.Combat.MaxValidationDistance).toBe(16)
			expect(GameConfig.Rewards.ContributionThreshold).toBe(0.05)
			expect(GameConfig.Rebirth.RequiredEra).toBe(4)
			expect(GameConfig.Rebirth.RequiredStrength).toBe(1000000)
			expect(GameConfig.Rebirth.MultiplierBase).toBe(1.5)
			expect(GameConfig.UI.BossBarRange).toBe(60)
		end)
		it("defines both attacks per §2.1", function()
			local lash = GameConfig.Combat.Attacks.GroundLash
			expect(lash.Multiplier).toBe(1)
			expect(lash.Shape.Kind).toBe("Cone")
			expect(lash.Shape.Range).toBe(14)
			expect(lash.Shape.AngleDegrees).toBe(45)
			expect(lash.Duration).toBe(0.35)
			local sweep = GameConfig.Combat.Attacks.AerialSweep
			expect(sweep.Multiplier).toBe(0.75)
			expect(sweep.Shape.Kind).toBe("Circle")
			expect(sweep.Shape.Range).toBe(12)
			expect(sweep.Duration).toBe(0.45)
		end)
		it("has the Colosseum mob roster", function()
			local counts = {}
			for _, spawner in GameConfig.Spawners do
				counts[spawner.MobId] = (counts[spawner.MobId] or 0) + 1
			end
			expect(counts.RomanLegionary).toBe(4)
			expect(counts.CenturionElite).toBe(2)
			expect(counts.GladiatorPrimus).toBe(1)
			expect(GameConfig.Mobs.RomanLegionary.MaxHealth).toBe(250)
			expect(GameConfig.Mobs.RomanLegionary.RespawnSeconds).toBe(8)
			expect(GameConfig.Mobs.CenturionElite.MaxHealth).toBe(1200)
			expect(GameConfig.Mobs.CenturionElite.RespawnSeconds).toBe(20)
			expect(GameConfig.Mobs.GladiatorPrimus.MaxHealth).toBe(10000)
			expect(GameConfig.Mobs.GladiatorPrimus.RespawnSeconds).toBe(60)
			for _, mob in GameConfig.Mobs do
				for _, attack in mob.Attacks do
					expect(attack.TelegraphSeconds).toBe(0.8)
				end
			end
		end)
		it("keeps the Colosseum at 200x200 studs with 20-stud walls", function()
			expect(GameConfig.World.ColosseumRadius * 2).toBe(200)
			expect(GameConfig.World.ColosseumWallHeight).toBe(20)
		end)
	end)

	describe("References", function()
		it("ids match their keys", function()
			for _, catalogue in
				{ GameConfig.Ropes, GameConfig.Boots, GameConfig.Pets, GameConfig.Eggs, GameConfig.Mobs }
			do
				for key, entry in catalogue do
					expect(entry.Id).toBe(key)
				end
			end
			for key, entry in GameConfig.Titles do
				expect(entry.Id).toBe(key)
			end
			for key, entry in GameConfig.SkillTree do
				expect(entry.Id).toBe(key)
			end
			for key, entry in GameConfig.Portals do
				expect(entry.Id).toBe(key)
			end
		end)
		it("starter items exist and are free", function()
			expect(GameConfig.Ropes[GameConfig.Starter.Rope].Price).toBe(0)
			expect(GameConfig.Boots[GameConfig.Starter.Boots].Price).toBe(0)
			expect(GameConfig.Titles[GameConfig.Starter.Title] ~= nil).toBe(true)
		end)
		it("spawners, eggs and drops reference real content", function()
			for _, spawner in GameConfig.Spawners do
				expect(GameConfig.Mobs[spawner.MobId] ~= nil).toBe(true)
			end
			for _, egg in GameConfig.Eggs do
				for petId, weight in egg.Weights do
					expect(GameConfig.Pets[petId] ~= nil).toBe(true)
					expect(weight > 0).toBe(true)
				end
			end
			for _, mob in GameConfig.Mobs do
				for _, drop in mob.Drops.Bonus do
					local catalogue = if drop.Kind == "Pet" then GameConfig.Pets else GameConfig.Titles
					expect(catalogue[drop.Id] ~= nil).toBe(true)
					expect(drop.Chance > 0 and drop.Chance <= 1).toBe(true)
				end
			end
			for _, titleId in GameConfig.Rebirth.MilestoneTitles do
				expect(GameConfig.Titles[titleId] ~= nil).toBe(true)
			end
		end)
		it("skill requirements point at existing nodes", function()
			for _, node in GameConfig.SkillTree do
				for _, requirement in node.Requires do
					local target = GameConfig.SkillTree[requirement.Id]
					expect(target ~= nil).toBe(true)
					expect(requirement.Level <= target.MaxLevel).toBe(true)
				end
			end
		end)
		it("portals chain era to era and stay reachable without rebirths up to Era 4", function()
			for _, portal in GameConfig.Portals do
				expect(portal.ToEra).toBe(portal.FromEra + 1)
				expect(GameConfig.Eras[portal.ToEra] ~= nil).toBe(true)
				if portal.ToEra <= GameConfig.Rebirth.RequiredEra then
					expect(portal.RequiredRebirths).toBe(0)
					expect(portal.RequiredStrength < GameConfig.Rebirth.RequiredStrength).toBe(true)
				end
				expect(portal.Position.X).toBe(GameConfig.Eras[portal.ToEra].SectorMinX)
			end
		end)
		it("era sectors are contiguous along X", function()
			for index = 2, #GameConfig.Eras do
				expect(GameConfig.Eras[index].SectorMinX).toBe(GameConfig.Eras[index - 1].SectorMaxX)
				expect(GameConfig.Eras[index].Index).toBe(index)
			end
		end)
	end)

	describe("Immutability", function()
		it("is deep-frozen", function()
			expect(table.isfrozen(GameConfig)).toBe(true)
			expect(table.isfrozen(GameConfig.Ropes.HempCord)).toBe(true)
			expect(table.isfrozen(GameConfig.DefaultPlayerData.Stats)).toBe(true)
			expect(function()
				(GameConfig.Ropes :: any).HempCord = nil
			end).toThrow()
		end)
	end)
end
