--!strict
--[[
	Guard
	-----
	Runtime validation for untrusted values (anything arriving through a RemoteEvent
	or RemoteFunction). Every helper returns the validated value, or nil when the
	value is malformed, so call sites read as:

	    local direction = Guard.Direction(rawDirection)
	    if not direction then return end

	NaN, +/-inf, wrong types, oversized strings/arrays and sparse arrays are all
	rejected. Nothing here ever errors on hostile input.
]]

local Guard = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

Guard.IsFinite = isFinite

-- A finite number, optionally clamped to an inclusive [min, max] range.
function Guard.Number(value: unknown, min: number?, max: number?): number?
	if type(value) ~= "number" or not isFinite(value) then
		return nil
	end
	if min ~= nil and value < min then
		return nil
	end
	if max ~= nil and value > max then
		return nil
	end
	return value
end

-- A finite whole number inside an inclusive range.
function Guard.Integer(value: unknown, min: number?, max: number?): number?
	local number = Guard.Number(value, min, max)
	if number == nil or number % 1 ~= 0 then
		return nil
	end
	return number
end

-- A non-empty, valid UTF-8 string no longer than maxLength bytes.
function Guard.String(value: unknown, maxLength: number): string?
	if type(value) ~= "string" then
		return nil
	end
	if #value == 0 or #value > maxLength then
		return nil
	end
	if utf8.len(value) == nil then
		return nil
	end
	return value
end

-- A string that is one of the allowed options.
function Guard.OneOf(value: unknown, options: { string }): string?
	if type(value) ~= "string" then
		return nil
	end
	if table.find(options, value) == nil then
		return nil
	end
	return value
end

-- A string that is a key of the given lookup table (e.g. a config catalogue).
function Guard.Key(value: unknown, lookup: { [string]: any }): string?
	if type(value) ~= "string" or #value == 0 or #value > 64 then
		return nil
	end
	if lookup[value] == nil then
		return nil
	end
	return value
end

-- A finite Vector3, optionally bounded in magnitude.
function Guard.Vector3(value: unknown, maxMagnitude: number?): Vector3?
	if typeof(value) ~= "Vector3" then
		return nil
	end
	local vector = value :: Vector3
	if not (isFinite(vector.X) and isFinite(vector.Y) and isFinite(vector.Z)) then
		return nil
	end
	if maxMagnitude ~= nil and vector.Magnitude > maxMagnitude then
		return nil
	end
	return vector
end

-- A usable direction: finite, non-degenerate. Returned normalised.
function Guard.Direction(value: unknown): Vector3?
	local vector = Guard.Vector3(value, 1e4)
	if vector == nil or vector.Magnitude < 1e-3 then
		return nil
	end
	return vector.Unit
end

-- A dense array (keys 1..n, no holes, no extra keys) with at most maxLength items.
function Guard.Array(value: unknown, maxLength: number): { unknown }?
	if type(value) ~= "table" then
		return nil
	end
	local source = value :: { [unknown]: unknown }
	local length = #source
	if length > maxLength then
		return nil
	end
	local count = 0
	for key in source do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
			return nil
		end
		count += 1
	end
	if count ~= length then
		return nil
	end
	local result: { unknown } = table.create(length)
	for index = 1, length do
		result[index] = source[index]
	end
	return result
end

-- A dense array of unique whole numbers inside [min, max].
function Guard.IntegerList(value: unknown, maxLength: number, min: number, max: number): { number }?
	local array = Guard.Array(value, maxLength)
	if array == nil then
		return nil
	end
	local result: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, item in array do
		local integer = Guard.Integer(item, min, max)
		if integer == nil then
			return nil
		end
		if not seen[integer] then
			seen[integer] = true
			table.insert(result, integer)
		end
	end
	return result
end

function Guard.Boolean(value: unknown): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value
end

return Guard
