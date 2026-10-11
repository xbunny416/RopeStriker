--!strict
--[[
	Spatial
	-------
	Pure geometry helpers shared by client hit prediction and server validation,
	so both sides agree on exactly what "inside the cone" means.

	All hit volumes are evaluated on the horizontal plane with a separate vertical
	tolerance: rope lashes and mob telegraphs are ground-plane shapes, and players
	jumping a few studs should still be hit/hittable.
]]

local Spatial = {}

function Spatial.Flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Horizontal unit vector, or the fallback when the input is (near) vertical.
function Spatial.FlatUnit(vector: Vector3, fallback: Vector3?): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-4 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function Spatial.HorizontalDistance(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	True when a target sphere (centre `point`, radius `targetRadius`) overlaps the
	horizontal disc of `radius` around `origin`, within `heightTolerance` studs
	vertically.
]]
function Spatial.InRadius(
	origin: Vector3,
	point: Vector3,
	radius: number,
	targetRadius: number?,
	heightTolerance: number?
): boolean
	if math.abs(point.Y - origin.Y) > (heightTolerance or math.huge) then
		return false
	end
	return Spatial.HorizontalDistance(origin, point) <= radius + (targetRadius or 0)
end

--[[
	True when a target sphere overlaps a horizontal cone that starts at `origin`,
	points along `direction` (any vector; it is flattened + normalised), extends
	`length` studs and spans `halfAngle` radians either side of the axis.
	The target's own radius widens the angular check by atan(radius / distance)
	so large mobs are hittable at their edges, not only at their centre.
]]
function Spatial.InCone(
	origin: Vector3,
	direction: Vector3,
	point: Vector3,
	length: number,
	halfAngle: number,
	targetRadius: number?,
	heightTolerance: number?
): boolean
	if math.abs(point.Y - origin.Y) > (heightTolerance or math.huge) then
		return false
	end
	local radius = targetRadius or 0
	local offset = Vector3.new(point.X - origin.X, 0, point.Z - origin.Z)
	local distance = offset.Magnitude
	if distance > length + radius then
		return false
	end
	if distance <= math.max(radius, 1e-3) then
		return true -- target overlaps the apex
	end
	local axis = Spatial.FlatUnit(direction)
	local cosine = math.clamp(offset.Unit:Dot(axis), -1, 1)
	local angle = math.acos(cosine)
	local angularRadius = math.atan2(radius, distance)
	return angle <= halfAngle + angularRadius
end

-- Signed angle (radians) to rotate `from` onto `to` around +Y.
function Spatial.YawBetween(from: Vector3, to: Vector3): number
	local a = Spatial.FlatUnit(from)
	local b = Spatial.FlatUnit(to)
	return math.atan2(a:Cross(b).Y, a:Dot(b))
end

return Spatial
