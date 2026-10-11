--!strict
--[[
	MobBrain
	--------
	Pure server-side mob state machine (Idle -> Chase -> Telegraph -> Attack), with a
	Return state for leashing and a terminal Dead state.

	    Idle ──target──► Chase ──in range & ready──► Telegraph ──0.8s──► Attack
	      ▲                │ ▲                                              │
	      │           lost/leash └────────── recovered, target valid ───────┘
	      └── home ◄── Return ◄──────────── recovered, no target ──────────┘

	MobService feeds a Perception snapshot every AI tick and executes the returned
	Action against the Roblox instance (MoveTo, telegraph attributes, damage). Keeping
	the decisions engine-free makes them deterministic and unit-testable.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

type MobData = GameConfig.MobData
type MobAttackData = GameConfig.MobAttackData

export type MobState = "Idle" | "Chase" | "Telegraph" | "Attack" | "Return" | "Dead"

export type Action =
	"None" -- keep doing what you were doing
	| "Chase" -- move towards the target
	| "Hold" -- stand still (in range / winding up / recovering)
	| "BeginTelegraph" -- lock the attack area and show the ground warning
	| "Strike" -- apply the locked attack now
	| "GoHome" -- walk back to the spawner
	| "Arrived" -- reached home

export type Perception = {
	Now: number,
	HasTarget: boolean,
	TargetDistance: number, -- horizontal edge-to-edge distance to the target
	DistanceFromHome: number,
	Roll: number, -- [0, 1) random number used for attack selection
}

export type Decision = {
	State: MobState,
	Previous: MobState,
	Changed: boolean,
	Action: Action,
	Attack: MobAttackData?,
}

export type Brain = {
	Data: MobData,
	State: MobState,
	StateSince: number,
	NextAttackAt: number,
	Attack: MobAttackData?,
	LastCombatAt: number,
}

local HOME_ARRIVAL_DISTANCE = 3
local RECHASE_LEASH_FRACTION = 0.8

local MobBrain = {}

function MobBrain.new(data: MobData, now: number): Brain
	return {
		Data = data,
		State = "Idle",
		StateSince = now,
		NextAttackAt = now,
		Attack = nil,
		LastCombatAt = now,
	}
end

-- Weighted attack selection from the mob's attack list.
function MobBrain.ChooseAttack(data: MobData, roll: number): MobAttackData
	local total = 0
	for _, attack in data.Attacks do
		total += math.max(0, attack.Weight)
	end
	if total <= 0 then
		return data.Attacks[1]
	end
	local target = math.clamp(roll, 0, 0.999999) * total
	local cumulative = 0
	for _, attack in data.Attacks do
		cumulative += math.max(0, attack.Weight)
		if target < cumulative then
			return attack
		end
	end
	return data.Attacks[#data.Attacks]
end

local function enter(brain: Brain, state: MobState, now: number)
	brain.State = state
	brain.StateSince = now
end

function MobBrain.Step(brain: Brain, perception: Perception): Decision
	local data = brain.Data
	local now = perception.Now
	local previous: MobState = brain.State
	local action: Action = "None"

	if brain.State == "Dead" then
		action = "None"
	elseif brain.State == "Idle" then
		if perception.HasTarget then
			enter(brain, "Chase", now)
			action = "Chase"
		end
	elseif brain.State == "Chase" then
		if not perception.HasTarget or perception.DistanceFromHome > data.LeashRange then
			enter(brain, "Return", now)
			action = "GoHome"
		elseif perception.TargetDistance <= data.AttackRange and now >= brain.NextAttackAt then
			brain.Attack = MobBrain.ChooseAttack(data, perception.Roll)
			brain.LastCombatAt = now
			enter(brain, "Telegraph", now)
			action = "BeginTelegraph"
		elseif perception.TargetDistance <= data.AttackRange then
			action = "Hold"
		else
			action = "Chase"
		end
	elseif brain.State == "Telegraph" then
		local attack = brain.Attack
		if attack == nil then
			enter(brain, "Chase", now)
			action = "Chase"
		elseif now - brain.StateSince >= attack.TelegraphSeconds then
			brain.LastCombatAt = now
			enter(brain, "Attack", now)
			action = "Strike"
		else
			action = "Hold"
		end
	elseif brain.State == "Attack" then
		local attack = brain.Attack
		local recovery = if attack then attack.RecoverySeconds else 0.5
		if now - brain.StateSince >= recovery then
			brain.NextAttackAt = now + data.AttackCooldown
			brain.Attack = nil
			if perception.HasTarget and perception.DistanceFromHome <= data.LeashRange then
				enter(brain, "Chase", now)
				action = "Chase"
			else
				enter(brain, "Return", now)
				action = "GoHome"
			end
		else
			action = "Hold"
		end
	elseif brain.State == "Return" then
		if perception.HasTarget and perception.DistanceFromHome <= data.LeashRange * RECHASE_LEASH_FRACTION then
			enter(brain, "Chase", now)
			action = "Chase"
		elseif perception.DistanceFromHome <= HOME_ARRIVAL_DISTANCE then
			enter(brain, "Idle", now)
			action = "Arrived"
		else
			action = "GoHome"
		end
	end

	return {
		State = brain.State,
		Previous = previous,
		Changed = brain.State ~= previous,
		Action = action,
		Attack = brain.Attack,
	}
end

-- Any damage taken counts as combat (postpones the idle reset).
function MobBrain.NoteCombat(brain: Brain, now: number)
	brain.LastCombatAt = now
end

-- True when a wounded mob has been out of combat long enough to heal and forget
-- its contributors (prevents chip-damage farming across long gaps).
function MobBrain.ShouldReset(brain: Brain, now: number, health: number): boolean
	if brain.State ~= "Idle" and brain.State ~= "Return" then
		return false
	end
	if health >= brain.Data.MaxHealth then
		return false
	end
	return now - brain.LastCombatAt >= brain.Data.ResetAfterIdleSeconds
end

function MobBrain.Kill(brain: Brain, now: number)
	brain.Attack = nil
	enter(brain, "Dead", now)
end

return MobBrain
