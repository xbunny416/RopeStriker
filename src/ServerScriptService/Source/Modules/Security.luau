--!strict
--[[
	Security
	--------
	Central place where services report suspicious client behaviour (malformed remote
	payloads, impossible timings, out-of-range targets). Strikes decay with a sliding
	window; crossing GameConfig.Security.KickStrikeThreshold kicks the player.
	Logging is rate limited so an exploiter cannot flood the server output.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

type Record = {
	Count: number,
	WindowStart: number,
	LastLogAt: number,
}

local LOG_INTERVAL = 5

local Security = {}

local records: { [Player]: Record } = {}

function Security.Strike(player: Player, reason: string, weight: number?)
	local now = os.clock()
	local config = GameConfig.Security
	local existing = records[player]
	local record: Record
	if existing == nil or now - existing.WindowStart > config.StrikeWindowSeconds then
		record = { Count = 0, WindowStart = now, LastLogAt = -math.huge }
		records[player] = record
	else
		record = existing
	end
	record.Count += weight or 1

	if now - record.LastLogAt >= LOG_INTERVAL then
		record.LastLogAt = now
		warn(`[Security] {player.Name} ({player.UserId}): {reason} (strikes {record.Count})`)
	end

	if config.KickStrikeThreshold > 0 and record.Count >= config.KickStrikeThreshold then
		records[player] = nil
		player:Kick("Unusual activity was detected. Please rejoin.")
	end
end

function Security.StrikeCount(player: Player): number
	local record = records[player]
	return if record then record.Count else 0
end

Players.PlayerRemoving:Connect(function(player: Player)
	records[player] = nil
end)

return Security
