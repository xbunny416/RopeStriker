-- Shared-health ledger (§2.1 5% rule) and the mob state machine (§6).

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local loader = t.loader()
	local GameConfig = loader:require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
	local DamageLedger = loader:require("src/ServerScriptService/Source/Modules/DamageLedger.luau")
	local MobBrain = loader:require("src/ServerScriptService/Source/Modules/MobBrain.luau")

	local function unitMultipliers(_userId: number): (number, number)
		return 1, 1
	end

	describe("DamageLedger", function()
		it("never credits overkill", function()
			local ledger = DamageLedger.new(250)
			expect(ledger:Record(1, 200, 250)).toBe(200)
			expect(ledger:Record(2, 999, 50)).toBe(50)
			expect(ledger:Total()).toBe(250)
			expect(ledger:Record(3, 10, 0)).toBe(0)
		end)

		it("pays >= 5% contributors by share and skips the rest", function()
			local ledger = DamageLedger.new(10000)
			ledger:Record(101, 6000, 10000)
			ledger:Record(102, 3600, 4000)
			ledger:Record(103, 400, 400) -- exactly 4%: below the threshold
			local payouts = ledger:ComputePayouts(1200, unitMultipliers)
			expect(#payouts).toBe(3)
			expect(payouts[1].UserId).toBe(101)
			expect(payouts[1].Shards).toBe(720)
			expect(payouts[2].Shards).toBe(432)
			expect(payouts[3].Eligible).toBe(false)
			expect(payouts[3].Shards).toBe(0)
		end)

		it("applies each contributor's own rebirth and skill multipliers", function()
			local ledger = DamageLedger.new(1000)
			ledger:Record(1, 500, 1000)
			ledger:Record(2, 500, 500)
			local payouts = ledger:ComputePayouts(100, function(userId: number): (number, number)
				if userId == 1 then
					return 2.25, 1
				end
				return 1, 1.2
			end)
			local byUser = {}
			for _, payout in payouts do
				byUser[payout.UserId] = payout.Shards
			end
			expect(byUser[1]).toBe(113) -- 100 * 0.5 * 2.25 = 112.5 -> 113
			expect(byUser[2]).toBe(60)
		end)

		it("resets between lives", function()
			local ledger = DamageLedger.new(100)
			ledger:Record(1, 30, 100)
			expect(ledger:ContributorCount()).toBe(1)
			ledger:Reset()
			expect(ledger:ContributorCount()).toBe(0)
			expect(ledger:DamageBy(1)).toBe(0)
		end)
	end)

	describe("MobBrain", function()
		local legionary = GameConfig.Mobs.RomanLegionary

		local function perceive(now: number, hasTarget: boolean, distance: number, home: number?)
			return {
				Now = now,
				HasTarget = hasTarget,
				TargetDistance = distance,
				DistanceFromHome = home or 0,
				Roll = 0.5,
			}
		end

		it("runs Idle -> Chase -> Telegraph -> Attack -> Chase", function()
			local brain = MobBrain.new(legionary, 0)
			expect(brain.State).toBe("Idle")

			local decision = MobBrain.Step(brain, perceive(0.1, true, 20))
			expect(decision.State).toBe("Chase")
			expect(decision.Action).toBe("Chase")

			decision = MobBrain.Step(brain, perceive(0.2, true, legionary.AttackRange - 1))
			expect(decision.State).toBe("Telegraph")
			expect(decision.Action).toBe("BeginTelegraph")
			expect(decision.Attack.Id).toBe("ShieldSlash")

			decision = MobBrain.Step(brain, perceive(0.5, true, 1))
			expect(decision.State).toBe("Telegraph")
			expect(decision.Action).toBe("Hold")

			decision = MobBrain.Step(brain, perceive(1.0, true, 1)) -- 0.8s after wind-up
			expect(decision.State).toBe("Attack")
			expect(decision.Action).toBe("Strike")

			decision = MobBrain.Step(brain, perceive(1.6, true, 1)) -- recovery 0.5s elapsed
			expect(decision.State).toBe("Chase")
			expect(brain.NextAttackAt).toBeNear(1.6 + legionary.AttackCooldown)
		end)

		it("holds in range until the cooldown is over", function()
			local brain = MobBrain.new(legionary, 0)
			brain.State = "Chase"
			brain.NextAttackAt = 5
			local decision = MobBrain.Step(brain, perceive(1, true, 1))
			expect(decision.State).toBe("Chase")
			expect(decision.Action).toBe("Hold")
			decision = MobBrain.Step(brain, perceive(5, true, 1))
			expect(decision.State).toBe("Telegraph")
		end)

		it("leashes back home and goes idle there", function()
			local brain = MobBrain.new(legionary, 0)
			MobBrain.Step(brain, perceive(0.1, true, 30))
			local decision = MobBrain.Step(brain, perceive(0.2, true, 30, legionary.LeashRange + 1))
			expect(decision.State).toBe("Return")
			expect(decision.Action).toBe("GoHome")
			decision = MobBrain.Step(brain, perceive(0.3, true, 30, legionary.LeashRange * 0.9))
			expect(decision.State).toBe("Return") -- hysteresis: no immediate re-chase
			decision = MobBrain.Step(brain, perceive(5, false, math.huge, 2))
			expect(decision.State).toBe("Idle")
			expect(decision.Action).toBe("Arrived")
		end)

		it("heals after staying out of combat", function()
			local brain = MobBrain.new(legionary, 0)
			MobBrain.NoteCombat(brain, 10)
			expect(MobBrain.ShouldReset(brain, 10 + legionary.ResetAfterIdleSeconds - 1, 100)).toBe(false)
			expect(MobBrain.ShouldReset(brain, 10 + legionary.ResetAfterIdleSeconds, 100)).toBe(true)
			expect(MobBrain.ShouldReset(brain, 100, legionary.MaxHealth)).toBe(false)
			brain.State = "Chase"
			expect(MobBrain.ShouldReset(brain, 100, 100)).toBe(false)
		end)

		it("stays dead", function()
			local brain = MobBrain.new(legionary, 0)
			MobBrain.Kill(brain, 1)
			local decision = MobBrain.Step(brain, perceive(2, true, 1))
			expect(decision.State).toBe("Dead")
			expect(decision.Action).toBe("None")
		end)

		it("picks boss attacks by weight", function()
			local primus = GameConfig.Mobs.GladiatorPrimus
			expect(MobBrain.ChooseAttack(primus, 0).Id).toBe("PrimusCleave")
			expect(MobBrain.ChooseAttack(primus, 0.66).Id).toBe("PrimusCleave")
			expect(MobBrain.ChooseAttack(primus, 0.67).Id).toBe("ArenaSlam")
			expect(MobBrain.ChooseAttack(primus, 0.99).Id).toBe("ArenaSlam")
		end)
	end)
end
