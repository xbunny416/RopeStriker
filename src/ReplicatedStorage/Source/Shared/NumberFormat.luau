--!strict
--[[
	NumberFormat
	------------
	Human-friendly number rendering for HUD/UI text.

	    Abbreviate(950)        --> "950"
	    Abbreviate(1.25)       --> "1.25"
	    Abbreviate(15320)      --> "15.32K"
	    Abbreviate(999999)     --> "1M"
	    Abbreviate(2.5e12)     --> "2.5T"
	    Commas(1234567)        --> "1,234,567"
	    Multiplier(2.5)        --> "x2.5"
]]

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZeros(text: string): string
	if string.find(text, ".", 1, true) == nil then
		return text
	end
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

function NumberFormat.Abbreviate(value: number, decimals: number?): string
	if value ~= value then
		return "0"
	end
	if value == math.huge then
		return "inf"
	end
	if value == -math.huge then
		return "-inf"
	end

	local places = decimals or 2
	local sign = if value < 0 then "-" else ""
	local magnitude = math.abs(value)

	if magnitude < 1000 then
		return sign .. trimZeros(string.format(`%.{places}f`, magnitude))
	end

	local tier = math.floor(math.log10(magnitude) / 3)
	if tier >= #SUFFIXES then
		return sign .. string.format("%.2e", magnitude)
	end

	local scaled = magnitude / 10 ^ (tier * 3)
	local text = string.format(`%.{places}f`, scaled)
	-- Rounding can push e.g. 999.996K to "1000.00"; promote to the next suffix.
	if (tonumber(text) or 0) >= 1000 and tier + 1 < #SUFFIXES then
		tier += 1
		scaled = magnitude / 10 ^ (tier * 3)
		text = string.format(`%.{places}f`, scaled)
	end

	return sign .. trimZeros(text) .. SUFFIXES[tier + 1]
end

function NumberFormat.Commas(value: number): string
	if value ~= value or math.abs(value) == math.huge then
		return NumberFormat.Abbreviate(value)
	end
	local sign = if value < 0 then "-" else ""
	local whole = string.format("%.0f", math.floor(math.abs(value)))
	local formatted = string.reverse((string.gsub(string.reverse(whole), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return sign .. formatted
end

function NumberFormat.Multiplier(value: number): string
	return "x" .. trimZeros(string.format("%.2f", value))
end

function NumberFormat.Percent(fraction: number): string
	return trimZeros(string.format("%.1f", fraction * 100)) .. "%"
end

function NumberFormat.Seconds(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	local minutes = seconds // 60
	local remainder = seconds % 60
	if minutes > 0 then
		return string.format("%d:%02d", minutes, remainder)
	end
	return `{remainder}s`
end

return NumberFormat
