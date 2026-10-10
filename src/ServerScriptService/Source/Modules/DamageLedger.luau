--!strict
--[[
	DamageLedger
	------------
	Per-life contributor table for a shared-health world mob (Bible §2.1).

	  * Only damage that actually removed health is credited (overkill is ignored), so
	    the sum of all contributions can never exceed the mob's max health.
	  * On death, every contributor that dealt >= 5% of max HP is paid
	        Shards = BaseMobShards * (DamageDealt / MaxHealth) * RebirthMultiplier
	    (times their Shard Siphon bonus). Contributors under 5% receive nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formulas = require(ReplicatedStorage.Source.Shared.Formulas)

export type Payout = {
	UserId: number,
	Damage: number,
	Fraction: number,
	Eligible: boolean,
	Shards: number,
}

export type Ledger = {
	MaxHealth: number,
	Record: (self: Ledger, userId: number, amount: number, healthBefore: number) -> number,
	DamageBy: (self: Ledger, userId: number) -> number,
	Total: (self: Ledger) -> number,
	ContributorCount: (self: Ledger) -> number,
	Reset: (self: Ledger) -> (),
	-- multipliersFor returns (rebirthMultiplier, skillMultiplier) for a contributor.
	ComputePayouts: (
		self: Ledger,
		baseShards: number,
		multipliersFor: (userId: number) -> (number, number)
	) -> { Payout },
}

local DamageLedger = {}

function DamageLedger.new(maxHealth: number): Ledger
	assert(maxHealth > 0, "DamageLedger requires a positive max health")

	local damageByUser: { [number]: number } = {}

	local ledger: Ledger
	ledger = {
		MaxHealth = maxHealth,

		-- Credits min(amount, healthBefore) to the user and returns the credited amount.
		Record = function(_: Ledger, userId: number, amount: number, healthBefore: number): number
			if amount ~= amount or amount <= 0 or healthBefore <= 0 then
				return 0
			end
			local credited = math.min(amount, healthBefore)
			damageByUser[userId] = (damageByUser[userId] or 0) + credited
			return credited
		end,

		DamageBy = function(_: Ledger, userId: number): number
			return damageByUser[userId] or 0
		end,

		Total = function(_: Ledger): number
			local total = 0
			for _, amount in damageByUser do
				total += amount
			end
			return total
		end,

		ContributorCount = function(_: Ledger): number
			local count = 0
			for _ in damageByUser do
				count += 1
			end
			return count
		end,

		Reset = function(_: Ledger)
			table.clear(damageByUser)
		end,

		ComputePayouts = function(
			_: Ledger,
			baseShards: number,
			multipliersFor: (userId: number) -> (number, number)
		): { Payout }
			local payouts: { Payout } = {}
			for userId, damage in damageByUser do
				local fraction = Formulas.ContributionFraction(damage, maxHealth)
				local eligible = Formulas.IsEligibleContributor(damage, maxHealth)
				local shards = 0
				if eligible then
					local rebirthMultiplier, skillMultiplier = multipliersFor(userId)
					shards = Formulas.ShardPayout(baseShards, damage, maxHealth, rebirthMultiplier, skillMultiplier)
				end
				table.insert(payouts, {
					UserId = userId,
					Damage = damage,
					Fraction = fraction,
					Eligible = eligible,
					Shards = shards,
				})
			end
			-- Biggest contributor first (stable for equal damage).
			table.sort(payouts, function(a: Payout, b: Payout): boolean
				if a.Damage ~= b.Damage then
					return a.Damage > b.Damage
				end
				return a.UserId < b.UserId
			end)
			return payouts
		end,
	}

	return ledger
end

return DamageLedger
