-- Bible §2.1 rhythm window, combo rules and §4.3/§4.4 tiers.

return function(t)
	local describe, it, expect = t.describe, t.it, t.expect
	local loader = t.loader()
	local GameConfig = loader:require("src/ReplicatedStorage/Source/Configuration/GameConfig.luau")
	local Rhythm = loader:require("src/ReplicatedStorage/Source/Shared/Rhythm.luau")

	local interval = GameConfig.Rhythm.BeatInterval
	local tolerance = GameConfig.Rhythm.ToleranceSeconds
	-- A realistic synchronised server clock value (Unix seconds).
	local epochBeat = math.floor(1.79e9 / interval) * interval

	describe("Beat clock", function()
		it("uses a 0.15s tolerance", function()
			expect(tolerance).toBe(0.15)
		end)
		it("finds the nearest beat at realistic clock magnitudes", function()
			expect(Rhythm.Offset(epochBeat + 0.1)).toBeNear(0.1, 1e-5)
			expect(Rhythm.Offset(epochBeat - 0.1)).toBeNear(-0.1, 1e-5)
			expect(Rhythm.Offset(epochBeat + interval * 0.5 - 0.01)).toBeNear(interval * 0.5 - 0.01, 1e-5)
		end)
		it("reports phase and time to the next beat consistently", function()
			local t0 = epochBeat + interval * 0.25
			expect(Rhythm.Phase(t0)).toBeNear(0.25, 1e-5)
			expect(Rhythm.TimeUntilNextBeat(t0)).toBeNear(interval * 0.75, 1e-5)
		end)
		it("treats the window edges inclusively", function()
			expect(Rhythm.IsOnBeat(epochBeat + 0.15)).toBe(true)
			expect(Rhythm.IsOnBeat(epochBeat - 0.15)).toBe(true)
			expect(Rhythm.IsOnBeat(epochBeat + 0.151)).toBe(false)
		end)
	end)

	describe("Judge", function()
		it("accepts an on-beat press", function()
			local judgement = Rhythm.Judge(epochBeat + 0.05, epochBeat + 0.6)
			expect(judgement.OnBeat).toBe(true)
			expect(judgement.Source).toBe("Press")
		end)
		it("accepts an on-beat landing when the press missed", function()
			local press = epochBeat + 0.3
			local land = epochBeat + interval - 0.1
			local judgement = Rhythm.Judge(press, land)
			expect(judgement.OnBeat).toBe(true)
			expect(judgement.Source).toBe("Land")
		end)
		it("misses when neither press nor landing is in the window", function()
			local judgement = Rhythm.Judge(epochBeat + 0.3, epochBeat + 0.3 + 0.2)
			expect(judgement.OnBeat).toBe(false)
			expect(judgement.Source).toBe("None")
		end)
		it("can judge a press alone (client instant feedback)", function()
			expect(Rhythm.Judge(epochBeat + 0.02).OnBeat).toBe(true)
			expect(Rhythm.Judge(epochBeat + 0.3).OnBeat).toBe(false)
		end)
	end)

	describe("Combo", function()
		it("rises +0.1x per on-beat bounce and caps at exactly 2.5x", function()
			local combo = GameConfig.Rhythm.ComboStart
			expect(combo).toBe(1)
			for _ = 1, 15 do
				combo = Rhythm.NextCombo(combo, true)
			end
			expect(combo).toBe(2.5)
			combo = Rhythm.NextCombo(combo, true)
			expect(combo).toBe(2.5)
		end)
		it("never drifts with floating point", function()
			local combo = 1
			for step = 1, 7 do
				combo = Rhythm.NextCombo(combo, true)
				expect(combo).toBe(math.round((1 + step * 0.1) * 1000) / 1000)
			end
		end)
		it("resets to 1.0x on a miss", function()
			expect(Rhythm.NextCombo(2.3, false)).toBe(1)
		end)
	end)

	describe("Tiers", function()
		it("maps combos to White, Blue, Gold, Red", function()
			expect(Rhythm.TierIndex(1)).toBe(1)
			expect(Rhythm.TierIndex(1.4)).toBe(1)
			expect(Rhythm.TierIndex(1.5)).toBe(2)
			expect(Rhythm.TierIndex(2.0)).toBe(3)
			expect(Rhythm.TierIndex(2.4)).toBe(3)
			expect(Rhythm.TierIndex(2.5)).toBe(4)
		end)
		it("raises Rope_Whoosh by one semitone per tier", function()
			expect(Rhythm.WhooshPitch(1)).toBe(1)
			expect(Rhythm.WhooshPitch(1.5)).toBeNear(2 ^ (1 / 12))
			expect(Rhythm.WhooshPitch(2.5)).toBeNear(2 ^ (3 / 12))
		end)
	end)

	describe("Rope orbit", function()
		it("passes under the feet shortly after each beat", function()
			local underFeet = epochBeat + GameConfig.Rhythm.RopeUnderFeetPhase * interval
			local angle = Rhythm.RopeAngle(underFeet)
			expect(math.min(angle, math.pi * 2 - angle)).toBeNear(0, 1e-3)
		end)
	end)
end
