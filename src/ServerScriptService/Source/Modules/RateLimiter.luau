--!strict
--[[
	RateLimiter
	-----------
	Token-bucket limiter keyed by any value (normally a Player). Each key owns a
	bucket holding up to `capacity` tokens that refills at `refillPerSecond`.
	A request spends `cost` tokens (default 1) and is rejected when the bucket
	cannot cover it. Buckets are weak-keyed so departed players are collected even
	if Reset() is never called.

	    local limiter = RateLimiter.new(6, 3) -- burst of 6, sustained 3/s
	    if not limiter:Allow(player) then return end
]]

export type RateLimiter = {
	Allow: (self: RateLimiter, key: any, cost: number?) -> boolean,
	Peek: (self: RateLimiter, key: any) -> number,
	Reset: (self: RateLimiter, key: any) -> (),
}

type Bucket = {
	Tokens: number,
	UpdatedAt: number,
}

local RateLimiter = {}

function RateLimiter.new(capacity: number, refillPerSecond: number, clock: (() -> number)?): RateLimiter
	assert(capacity > 0, "RateLimiter capacity must be positive")
	assert(refillPerSecond >= 0, "RateLimiter refill rate must be non-negative")

	local now: () -> number = clock or os.clock
	local buckets: { [any]: Bucket } = setmetatable({}, { __mode = "k" }) :: any

	local function refill(key: any): Bucket
		local timestamp = now()
		local bucket = buckets[key]
		if bucket == nil then
			bucket = { Tokens = capacity, UpdatedAt = timestamp }
			buckets[key] = bucket
			return bucket
		end
		local elapsed = math.max(0, timestamp - bucket.UpdatedAt)
		bucket.Tokens = math.min(capacity, bucket.Tokens + elapsed * refillPerSecond)
		bucket.UpdatedAt = timestamp
		return bucket
	end

	local limiter: RateLimiter = {
		Allow = function(_: RateLimiter, key: any, cost: number?): boolean
			local price = cost or 1
			local bucket = refill(key)
			if bucket.Tokens + 1e-9 < price then
				return false
			end
			bucket.Tokens -= price
			return true
		end,

		Peek = function(_: RateLimiter, key: any): number
			return refill(key).Tokens
		end,

		Reset = function(_: RateLimiter, key: any)
			buckets[key] = nil
		end,
	}

	return limiter
end

return RateLimiter
