--!strict
--[[
	Rhythm
	------
	Deterministic beat clock shared by the client (prompt ring, rope orbit, local
	judgement) and the server (authoritative judgement of reported bounces).

	Beats are anchored to the synchronised server clock (workspace:GetServerTimeNow()),
	at every integer multiple of BeatInterval. Every client and server in the universe
	therefore agrees on when the beat lands without ever exchanging a beat message.

	Bible §2.1: a bounce is on-beat when the jump press OR the landing happens within
	ToleranceSeconds (0.15s) of a beat. On-beat bounces raise the combo by +0.1x up to
	2.5x; a miss resets it to 1.0x.
]]

local GameConfig = require(script.Parent.Parent.Configuration.GameConfig)

local RhythmConfig = GameConfig.Rhythm

-- Server-clock timestamps are Unix seconds (~1.8e9), where a double only resolves
-- ~2.4e-7s. A 1 microsecond allowance keeps the window edges inclusive regardless.
local EDGE_EPSILON = 1e-6

export type JudgementSource = "Press" | "Land" | "None"

export type Judgement = {
	OnBeat: boolean,
	Source: JudgementSource,
	Offset: number, -- signed seconds from the closest beat of the judged event
}

local Rhythm = {}

Rhythm.Interval = RhythmConfig.BeatInterval
Rhythm.Tolerance = RhythmConfig.ToleranceSeconds

-- Index of the beat closest to time t.
function Rhythm.NearestBeatIndex(t: number): number
	return math.floor(t / RhythmConfig.BeatInterval + 0.5)
end

function Rhythm.NearestBeatTime(t: number): number
	return Rhythm.NearestBeatIndex(t) * RhythmConfig.BeatInterval
end

-- Signed distance (seconds) from t to its closest beat; negative = early.
function Rhythm.Offset(t: number): number
	return t - Rhythm.NearestBeatTime(t)
end

-- Fraction [0, 1) of the current beat that has elapsed at time t.
function Rhythm.Phase(t: number): number
	local phase = (t / RhythmConfig.BeatInterval) % 1
	if phase ~= phase then
		return 0
	end
	return phase
end

function Rhythm.TimeUntilNextBeat(t: number): number
	return (1 - Rhythm.Phase(t)) * RhythmConfig.BeatInterval
end

function Rhythm.IsOnBeat(t: number, tolerance: number?): boolean
	return math.abs(Rhythm.Offset(t)) <= (tolerance or RhythmConfig.ToleranceSeconds) + EDGE_EPSILON
end

--[[
	Judge a bounce. `landTime` is optional so the client can award an on-beat press
	instantly and only fall back to the landing check when the press missed.
]]
function Rhythm.Judge(pressTime: number, landTime: number?, tolerance: number?): Judgement
	local window = (tolerance or RhythmConfig.ToleranceSeconds) + EDGE_EPSILON
	local pressOffset = Rhythm.Offset(pressTime)
	if math.abs(pressOffset) <= window then
		return { OnBeat = true, Source = "Press", Offset = pressOffset }
	end
	if landTime ~= nil then
		local landOffset = Rhythm.Offset(landTime)
		if math.abs(landOffset) <= window then
			return { OnBeat = true, Source = "Land", Offset = landOffset }
		end
		if math.abs(landOffset) < math.abs(pressOffset) then
			return { OnBeat = false, Source = "None", Offset = landOffset }
		end
	end
	return { OnBeat = false, Source = "None", Offset = pressOffset }
end

-- Combo after a judged bounce: +ComboStep on-beat (capped), reset on a miss.
-- Rounded to 1e-3 so repeated +0.1 steps never drift (1.0 + 0.1 * 15 == 2.5 exactly).
function Rhythm.NextCombo(current: number, onBeat: boolean): number
	if not onBeat then
		return RhythmConfig.ComboStart
	end
	local raised = math.min(RhythmConfig.ComboCap, current + RhythmConfig.ComboStep)
	return math.round(raised * 1000) / 1000
end

-- Index (1-based) of the visual/audio tier for a combo value.
function Rhythm.TierIndex(combo: number): number
	local tiers = RhythmConfig.ComboTiers
	local index = 1
	for i, tier in tiers do
		if combo + 1e-6 >= tier.MinCombo then
			index = i
		end
	end
	return index
end

function Rhythm.TierColor(combo: number): Color3
	return RhythmConfig.ComboTiers[Rhythm.TierIndex(combo)].Color
end

-- Rope_Whoosh playback speed: +SemitonesPerTier semitones for each tier above the first.
function Rhythm.WhooshPitch(combo: number): number
	local semitones = (Rhythm.TierIndex(combo) - 1) * RhythmConfig.SemitonesPerTier
	return 2 ^ (semitones / 12)
end

--[[
	Rope orbit angle (radians) at time t. 0 means the rope is passing under the feet,
	which happens RopeUnderFeetPhase of a beat after each beat - i.e. while a player who
	pressed on the beat is airborne.
]]
function Rhythm.RopeAngle(t: number): number
	local phase = Rhythm.Phase(t) - RhythmConfig.RopeUnderFeetPhase
	return (phase % 1) * math.pi * 2
end

return Rhythm
