--!strict
--[[
	Telegraph
	---------
	Client-side ground warning for mob attacks (Bible §4.3 "Telegraph Decal"): a red
	projected cone or circle on the floor that fills up over the 0.8s wind-up, then
	flashes on impact. Built from flat Neon WedgeParts (cone slices) and cylinders, so
	no texture assets are needed and it works on every surface the arena has.

	Geometry: each cone slice is an isosceles triangle (apex at the mob) split into two
	right triangles along its altitude; each right triangle is one WedgePart laid flat
	(its thickness axis pointing up).
]]

export type Decal = {
	SetProgress: (self: Decal, progress: number) -> (),
	Flash: (self: Decal) -> (),
	Destroy: (self: Decal) -> (),
}

local OUTLINE_COLOR = Color3.fromRGB(255, 70, 60)
local FILL_COLOR = Color3.fromRGB(255, 30, 30)
local THICKNESS = 0.12
local MAX_SLICE_DEGREES = 15

local Telegraph = {}

local function flatPart(kind: "Cylinder" | "Wedge", parent: Instance, transparency: number, color: Color3): BasePart
	local part: BasePart
	if kind == "Wedge" then
		part = Instance.new("WedgePart")
	else
		local cylinder = Instance.new("Part")
		cylinder.Shape = Enum.PartType.Cylinder
		part = cylinder
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.Parent = parent
	return part
end

-- Places two wedges as the isosceles triangle apex -> apex + u*h +/- v*b.
local function placeTriangle(
	left: BasePart,
	right: BasePart,
	apex: Vector3,
	u: Vector3,
	v: Vector3,
	height: number,
	halfBase: number
)
	if height < 0.02 or halfBase < 0.02 then
		left.Transparency = 1
		right.Transparency = 1
		return
	end
	local foot = apex + u * height
	local normal = u:Cross(v).Unit
	left.Size = Vector3.new(THICKNESS, height, halfBase)
	left.CFrame = CFrame.fromMatrix(foot - u * (height / 2) + v * (halfBase / 2), normal, -u)
	right.Size = Vector3.new(THICKNESS, height, halfBase)
	right.CFrame = CFrame.fromMatrix(foot - u * (height / 2) - v * (halfBase / 2), -normal, -u)
end

local function disc(part: BasePart, center: Vector3, radius: number)
	if radius < 0.02 then
		part.Transparency = 1
		return
	end
	part.Size = Vector3.new(THICKNESS, radius * 2, radius * 2)
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.pi / 2)
end

--[[
	kind       "Cone" | "Circle"
	origin     ground point under the mob
	direction  horizontal facing locked at wind-up start
	range      cone length / circle radius
	angle      cone full spread in degrees
]]
function Telegraph.Create(
	parent: Instance,
	kind: string,
	origin: Vector3,
	direction: Vector3,
	range: number,
	angle: number
): Decal
	local folder = Instance.new("Folder")
	folder.Name = "Telegraph"
	folder.Parent = parent

	local base = origin + Vector3.new(0, 0.1, 0)
	local fillBase = origin + Vector3.new(0, 0.16, 0)
	local outlines: { BasePart } = {}
	local fills: { BasePart } = {}

	local flat = Vector3.new(direction.X, 0, direction.Z)
	local forward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)

	local slices: { { U: Vector3, V: Vector3 } } = {}
	local sliceAngle = 0

	if kind == "Circle" then
		local outline = flatPart("Cylinder", folder, 0.65, OUTLINE_COLOR)
		disc(outline, base, range)
		local fill = flatPart("Cylinder", folder, 0.35, FILL_COLOR)
		disc(fill, fillBase, 0)
		table.insert(outlines, outline)
		table.insert(fills, fill)
	else
		local spread = math.rad(math.clamp(angle, 1, 359))
		local count = math.max(2, math.ceil(math.deg(spread) / MAX_SLICE_DEGREES))
		sliceAngle = spread / count
		for index = 0, count - 1 do
			local center = -spread / 2 + sliceAngle * (index + 0.5)
			local u = CFrame.Angles(0, center, 0):VectorToWorldSpace(forward)
			local v = u:Cross(Vector3.yAxis).Unit
			table.insert(slices, { U = u, V = v })
			local outlineLeft = flatPart("Wedge", folder, 0.65, OUTLINE_COLOR)
			local outlineRight = flatPart("Wedge", folder, 0.65, OUTLINE_COLOR)
			placeTriangle(
				outlineLeft,
				outlineRight,
				base,
				u,
				v,
				range * math.cos(sliceAngle / 2),
				range * math.sin(sliceAngle / 2)
			)
			table.insert(outlines, outlineLeft)
			table.insert(outlines, outlineRight)
			local fillLeft = flatPart("Wedge", folder, 0.35, FILL_COLOR)
			local fillRight = flatPart("Wedge", folder, 0.35, FILL_COLOR)
			placeTriangle(fillLeft, fillRight, fillBase, u, v, 0, 0)
			table.insert(fills, fillLeft)
			table.insert(fills, fillRight)
		end
	end

	local decal: Decal = {
		SetProgress = function(_: Decal, progress: number)
			local p = math.clamp(progress, 0, 1)
			if kind == "Circle" then
				local fill = fills[1]
				fill.Transparency = 0.35
				disc(fill, fillBase, range * p)
				return
			end
			for index, slice in slices do
				local left = fills[index * 2 - 1]
				local right = fills[index * 2]
				left.Transparency = 0.35
				right.Transparency = 0.35
				placeTriangle(
					left,
					right,
					fillBase,
					slice.U,
					slice.V,
					range * p * math.cos(sliceAngle / 2),
					range * p * math.sin(sliceAngle / 2)
				)
			end
		end,

		Flash = function(_: Decal)
			for _, part in outlines do
				part.Transparency = 0.1
				part.Color = Color3.fromRGB(255, 240, 220)
			end
		end,

		Destroy = function(_: Decal)
			folder:Destroy()
		end,
	}
	return decal
end

return Telegraph
