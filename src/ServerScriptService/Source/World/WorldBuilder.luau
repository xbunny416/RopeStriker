--!strict
--[[
	WorldBuilder
	============
	Procedurally assembles the shippable greybox of the open world (Bible §3) so the
	place is fully playable straight out of `rojo build`:

	  * Era 1 - Ancient Rome: the Training Piazza (Epoch Obelisk + glowing pedestal,
	    Blacksmith, Chrono-Egg Incubator with 3 eggs, Rebirth Portal arch) and the Grand
	    Colosseum (200x200 circular arena, 20-stud stone walls, 3 spectator tiers,
	    central dais, 4 Legionary + 2 Centurion + 1 Primus spawners).
	  * Eras 2-4: themed plazas with their own obelisk.
	  * Chronal Rifts: particle-ring portals in the sector walls, each with a collision
	    barrier that clients open locally once the server confirms the unlock.

	Art direction: low-poly flat-shaded geometry using only SmoothPlastic, Neon and
	Pebble (ForceField for rift barriers), few parts per prop and no textures, which
	keeps draw calls and memory low on mobile. Everything interactive is found through
	CollectionService tags (see Shared/Tags), so the greybox can be swapped piece by
	piece for Blender FBX assets without touching gameplay code.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)
local NumberFormat = require(ReplicatedStorage.Source.Shared.NumberFormat)
local Tags = require(ReplicatedStorage.Source.Shared.Tags)

type EraData = GameConfig.EraData

local World = GameConfig.World

local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local PEBBLE = Enum.Material.Pebble

local MARBLE = Color3.fromRGB(236, 230, 216)
local STONE = Color3.fromRGB(214, 200, 172)
local STONE_DARK = Color3.fromRGB(176, 160, 134)
local SAND = Color3.fromRGB(226, 202, 152)
local GOLD = Color3.fromRGB(240, 196, 64)
local GOLD_GLOW = Color3.fromRGB(255, 208, 92)
local TERRACOTTA = Color3.fromRGB(196, 98, 66)
local WOOD = Color3.fromRGB(122, 84, 52)
local IRON = Color3.fromRGB(78, 80, 88)
local EMBER = Color3.fromRGB(255, 122, 44)
local PARADOX = Color3.fromRGB(170, 96, 255)
local BLOSSOM = Color3.fromRGB(255, 183, 213)
local BRICK = Color3.fromRGB(150, 74, 56)

local RIFT_HALF_WIDTH = 14
local RIFT_HEIGHT = 28
local BOUNDARY_HEIGHT = 60
local BOUNDARY_THICKNESS = 6

local WorldBuilder = {}

---------------------------------------------------------------------------------------
-- Primitive helpers
---------------------------------------------------------------------------------------

local function newModel(parent: Instance, name: string): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

local function style(part: BasePart, color: Color3, material: Enum.Material?)
	part.Anchored = true
	part.Color = color
	part.Material = material or SMOOTH
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	style(part, color, material)
	part.Parent = parent
	return part
end

-- Vertical cylinder centred on `cframe`.
local function cylinder(
	parent: Instance,
	name: string,
	diameter: number,
	height: number,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = cframe * CFrame.Angles(0, 0, math.pi / 2)
	style(part, color, material)
	part.Parent = parent
	return part
end

-- Flat disc whose top surface sits at `topY`.
local function disc(
	parent: Instance,
	name: string,
	center: Vector3,
	topY: number,
	diameter: number,
	height: number,
	color: Color3,
	material: Enum.Material?
): Part
	return cylinder(parent, name, diameter, height, CFrame.new(center.X, topY - height / 2, center.Z), color, material)
end

local function ball(
	parent: Instance,
	name: string,
	diameter: number,
	position: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = CFrame.new(position)
	style(part, color, material)
	part.Parent = parent
	return part
end

local function decor(part: BasePart): BasePart
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function pointLight(parent: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
end

local function particles(parent: Instance, color: Color3, rate: number, speed: NumberRange, lifetime: NumberRange)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Speed = speed
	emitter.Lifetime = lifetime
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = parent
end

local function attachment(parent: BasePart, name: string, offset: Vector3): Attachment
	local point = Instance.new("Attachment")
	point.Name = name
	point.Position = offset
	point.Parent = parent
	return point
end

local function prompt(
	parent: Instance,
	name: string,
	actionText: string,
	objectText: string,
	holdDuration: number,
	distance: number
): ProximityPrompt
	local proximity = Instance.new("ProximityPrompt")
	proximity.Name = name
	proximity.ActionText = actionText
	proximity.ObjectText = objectText
	proximity.HoldDuration = holdDuration
	proximity.MaxActivationDistance = distance
	proximity.RequiresLineOfSight = false
	proximity.KeyboardKeyCode = Enum.KeyCode.E
	proximity.GamepadKeyCode = Enum.KeyCode.ButtonX
	proximity.Parent = parent
	return proximity
end

local function sign(part: BasePart, text: string, textColor: Color3, background: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = background
	label.TextColor3 = textColor
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

-- Position on a horizontal circle around `center`.
local function onCircle(center: Vector3, radius: number, angle: number, y: number): Vector3
	return Vector3.new(center.X + math.cos(angle) * radius, y, center.Z + math.sin(angle) * radius)
end

-- CFrame at `position` whose -Z (front) faces `target` on the horizontal plane.
local function facing(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

---------------------------------------------------------------------------------------
-- Interactables
---------------------------------------------------------------------------------------

local function buildObelisk(parent: Instance, position: Vector3, eraIndex: number, accent: Color3): Model
	local obelisk = newModel(parent, "EpochObelisk")
	local y = position.Y

	local pedestal = disc(obelisk, "Pedestal", position, y + 1.4, World.ObeliskPedestalRadius * 2, 1.2, GOLD_GLOW, NEON)
	pedestal.Transparency = 0.25
	pedestal:AddTag(Tags.ObeliskPedestal)

	local base =
		block(obelisk, "Base", Vector3.new(8, 3, 8), CFrame.new(position + Vector3.new(0, 2.9, 0)), MARBLE, PEBBLE)
	local shaft = block(obelisk, "Shaft", Vector3.new(4, 22, 4), CFrame.new(position + Vector3.new(0, 15.4, 0)), GOLD)
	shaft.Reflectance = 0.15
	for _, height in { 9, 16, 23 } do
		decor(
			block(
				obelisk,
				"GlyphBand",
				Vector3.new(4.3, 0.5, 4.3),
				CFrame.new(position + Vector3.new(0, height, 0)),
				accent,
				NEON
			)
		)
	end
	local capstone = block(
		obelisk,
		"Capstone",
		Vector3.new(3, 3, 3),
		CFrame.new(position + Vector3.new(0, 28, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		GOLD_GLOW,
		NEON
	)
	decor(capstone)
	pointLight(capstone, GOLD_GLOW, 2, 28)
	particles(capstone, GOLD_GLOW, 6, NumberRange.new(1, 3), NumberRange.new(1, 2))

	local promptPoint = attachment(base, "PromptAttachment", Vector3.new(0, 1, 0))
	prompt(
		promptPoint,
		"BankPrompt",
		"Bank Kinetic Power",
		"Epoch Obelisk",
		0,
		GameConfig.Training.ObeliskPromptDistance
	)

	obelisk.PrimaryPart = shaft
	obelisk:SetAttribute("Era", eraIndex)
	obelisk:AddTag(Tags.EpochObelisk)
	return obelisk
end

local function buildBlacksmith(parent: Instance)
	local smith = newModel(parent, "Blacksmith")
	local origin = facing(World.BlacksmithPosition, World.ObeliskPosition)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	block(smith, "Floor", Vector3.new(24, 1, 18), at(0, 0.5, 0), STONE_DARK, PEBBLE)
	block(smith, "BackWall", Vector3.new(24, 12, 1.5), at(0, 6.5, 8.25), STONE, PEBBLE)
	block(smith, "LeftWall", Vector3.new(1.5, 12, 18), at(-11.25, 6.5, 0), STONE, PEBBLE)
	block(smith, "RightWall", Vector3.new(1.5, 12, 18), at(11.25, 6.5, 0), STONE, PEBBLE)
	block(smith, "Roof", Vector3.new(26, 1, 20), at(0, 13, 0), TERRACOTTA)
	block(smith, "RoofRidge", Vector3.new(26, 1.2, 4), at(0, 14, 2), TERRACOTTA)

	block(smith, "Forge", Vector3.new(5, 4, 4), at(-7, 3, 5), IRON, PEBBLE)
	local embers = decor(block(smith, "Embers", Vector3.new(3, 1, 2.5), at(-7, 4.6, 4.6), EMBER, NEON))
	pointLight(embers, EMBER, 3, 18)
	particles(embers, EMBER, 12, NumberRange.new(2, 5), NumberRange.new(0.5, 1.2))

	block(smith, "AnvilBase", Vector3.new(3, 1.6, 1.6), at(2, 1.8, -1), IRON)
	local anvil = block(smith, "Anvil", Vector3.new(4, 0.8, 2), at(2, 3, -1), IRON)

	-- Rope rack with the three Zone 1 ropes on display.
	block(smith, "RackBeam", Vector3.new(10, 0.6, 0.6), at(5, 9, 7), WOOD)
	for index, rope in { GameConfig.Ropes.HempCord, GameConfig.Ropes.LeatherStrap, GameConfig.Ropes.BronzeChain } do
		local x = 1.5 + (index - 1) * 3.5
		decor(cylinder(smith, "DisplayRope", rope.Visual.Width * 3, 5, at(x, 6.4, 7), rope.Visual.Color))
	end

	local signBoard = block(smith, "Sign", Vector3.new(12, 2.4, 0.5), at(0, 15.5, -8.5), WOOD)
	sign(signBoard, "BLACKSMITH", GOLD_GLOW, WOOD)

	local shopPrompt = prompt(anvil, "ShopPrompt", "Open Blacksmith", "Ropes & Boots", 0, 12)
	shopPrompt:SetAttribute("OpensPanel", "Shop")
	shopPrompt:AddTag(Tags.PanelPrompt)
end

local function buildIncubator(parent: Instance)
	local incubator = newModel(parent, "ChronoEggIncubator")
	local origin = facing(World.IncubatorPosition, World.ObeliskPosition)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	block(incubator, "Floor", Vector3.new(30, 1, 16), at(0, 0.5, 0), MARBLE, PEBBLE)
	for _, corner in { Vector2.new(-14, -7), Vector2.new(14, -7), Vector2.new(-14, 7), Vector2.new(14, 7) } do
		block(incubator, "Post", Vector3.new(1.2, 12, 1.2), at(corner.X, 7, corner.Y), MARBLE)
	end
	block(incubator, "Canopy", Vector3.new(32, 1, 18), at(0, 13.5, 0), PARADOX)
	local signBoard = block(incubator, "Sign", Vector3.new(16, 2.4, 0.5), at(0, 15.5, -8.6), MARBLE)
	sign(signBoard, "CHRONO-EGG INCUBATOR", PARADOX, MARBLE)

	local eggs = {}
	for _, egg in GameConfig.Eggs do
		table.insert(eggs, egg)
	end
	table.sort(eggs, function(a: GameConfig.EggData, b: GameConfig.EggData): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)

	for index, egg in eggs do
		local x = (index - 2) * 9
		local eggModel = newModel(incubator, egg.Id)
		local pedestal = cylinder(eggModel, "Pedestal", 5, 3, at(x, 2, 0), STONE, PEBBLE)
		decor(cylinder(eggModel, "Glow", 5.6, 0.3, at(x, 3.55, 0), egg.Color, NEON))
		local shell = decor(ball(eggModel, "Shell", 3.6, at(x, 5.9, 0).Position, egg.Color))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.25, 1)
		mesh.Parent = shell
		particles(shell, egg.Color, 3, NumberRange.new(0.5, 1.5), NumberRange.new(1, 2))

		local hatch = prompt(
			pedestal,
			"HatchPrompt",
			`Hatch ({NumberFormat.Abbreviate(egg.Price)} Shards)`,
			egg.DisplayName,
			0.35,
			10
		)
		hatch.UIOffset = Vector2.new(0, 40)
		eggModel.PrimaryPart = pedestal
		eggModel:SetAttribute("EggId", egg.Id)
		eggModel:AddTag(Tags.ChronoEgg)
	end
end

local function buildRebirthArch(parent: Instance)
	local arch = newModel(parent, "RebirthPortalArch")
	local origin = facing(World.RebirthArchPosition, World.ObeliskPosition)
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	local steps = block(arch, "Steps", Vector3.new(30, 1, 10), at(0, 0.5, 0), MARBLE, PEBBLE)
	block(arch, "PillarLeft", Vector3.new(4, 22, 4), at(-11, 12, 0), MARBLE)
	block(arch, "PillarRight", Vector3.new(4, 22, 4), at(11, 12, 0), MARBLE)
	block(arch, "Lintel", Vector3.new(28, 4, 5), at(0, 25, 0), MARBLE)
	decor(block(arch, "LintelGlyph", Vector3.new(20, 1, 5.2), at(0, 25, 0), PARADOX, NEON))

	local portal = Instance.new("Part")
	portal.Name = "ParadoxField"
	portal.Shape = Enum.PartType.Cylinder
	portal.Size = Vector3.new(0.6, 18, 18)
	portal.CFrame = at(0, 12, 0) * CFrame.Angles(0, math.pi / 2, 0)
	style(portal, PARADOX, NEON)
	portal.Transparency = 0.35
	decor(portal)
	portal.Parent = arch
	pointLight(portal, PARADOX, 2, 30)
	particles(portal, PARADOX, 18, NumberRange.new(1, 4), NumberRange.new(1, 2.5))

	local promptPoint = attachment(steps, "PromptAttachment", Vector3.new(0, 3, -3))
	local rebirthPrompt = prompt(promptPoint, "RebirthPrompt", "Temporal Paradox", "Rebirth Portal", 0, 14)
	rebirthPrompt:SetAttribute("OpensPanel", "Rebirth")
	rebirthPrompt:AddTag(Tags.PanelPrompt)
end

---------------------------------------------------------------------------------------
-- Era 1: Training Piazza + Grand Colosseum
---------------------------------------------------------------------------------------

local function buildGround(parent: Instance, era: EraData)
	local width = era.SectorMaxX - era.SectorMinX
	local depth = era.SectorMaxZ - era.SectorMinZ
	local center =
		Vector3.new((era.SectorMinX + era.SectorMaxX) / 2, World.GroundY - 2, (era.SectorMinZ + era.SectorMaxZ) / 2)
	block(parent, "Ground", Vector3.new(width, 4, depth), CFrame.new(center), era.Theme.Ground)

	-- Visible low border plus a tall invisible wall along the sector's Z edges.
	for _, edgeZ in { era.SectorMinZ, era.SectorMaxZ } do
		local inward = if edgeZ < 0 then 3 else -3
		block(
			parent,
			"Border",
			Vector3.new(width, 6, 6),
			CFrame.new(center.X, 3, edgeZ + inward),
			era.Theme.Trim,
			PEBBLE
		)
		local barrier =
			block(parent, "InvisibleWall", Vector3.new(width, 160, 4), CFrame.new(center.X, 80, edgeZ), era.Theme.Trim)
		barrier.Transparency = 1
		barrier.CanQuery = false
		barrier.CastShadow = false
	end
end

local function road(parent: Instance, from: Vector3, to: Vector3, width: number, color: Color3)
	local offset = to - from
	local length = offset.Magnitude
	local middle = (from + to) / 2
	block(
		parent,
		"Road",
		Vector3.new(width, 0.6, length),
		CFrame.lookAt(Vector3.new(middle.X, 0, middle.Z), Vector3.new(to.X, 0, to.Z)),
		color,
		PEBBLE
	)
end

local function buildPiazza(parent: Instance, era: EraData)
	local piazza = newModel(parent, "TrainingPiazza")
	local center = World.PiazzaCenter

	disc(piazza, "PlazaFloor", center, 0.4, World.PiazzaRadius * 2, 1, era.Theme.Path, PEBBLE)
	disc(piazza, "PlazaInlay", center, 0.5, 46, 1, MARBLE)
	decor(disc(piazza, "InlayRing", center, 0.46, 48, 0.2, era.Theme.Accent, NEON))

	-- Twelve columns frame the plaza, offset so the roads stay clear.
	for index = 0, 11 do
		local angle = index * (math.pi * 2 / 12) + math.pi / 12
		local base = onCircle(center, World.PiazzaRadius - 6, angle, 0)
		cylinder(piazza, "Column", 3, 14, CFrame.new(base + Vector3.new(0, 7.4, 0)), MARBLE)
		block(piazza, "Capital", Vector3.new(4.4, 1.2, 4.4), CFrame.new(base + Vector3.new(0, 15, 0)), MARBLE)
	end

	buildObelisk(piazza, World.ObeliskPosition, era.Index, era.Theme.Accent)
	buildBlacksmith(piazza)
	buildIncubator(piazza)
	buildRebirthArch(piazza)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(World.SpawnPosition.X, 0.5, World.SpawnPosition.Z)
	style(spawn, MARBLE)
	spawn.Neutral = true
	spawn.Duration = 4
	spawn.Parent = piazza
	decor(disc(piazza, "SpawnGlow", World.SpawnPosition, 0.98, 11, 0.1, era.Theme.Accent, NEON))
end

local function buildColosseum(parent: Instance)
	local arena = newModel(parent, "GrandColosseum")
	local center = World.ColosseumCenter
	local radius = World.ColosseumRadius
	local wallHeight = World.ColosseumWallHeight
	local thickness = World.ColosseumWallThickness

	disc(arena, "ArenaFloor", center, 0.45, radius * 2 + 2, 1, SAND)

	local segments = 40
	local step = math.pi * 2 / segments
	local gateAngle = -math.pi / 2 -- the gate faces -Z, towards the Training Piazza
	for index = 0, segments - 1 do
		local angle = (index + 0.5) * step
		local delta = math.abs(((angle - gateAngle + math.pi) % (math.pi * 2)) - math.pi)
		if delta < step then
			continue
		end

		local wallRadius = radius + thickness / 2
		local wallLength = 2 * (radius + thickness) * math.tan(step / 2) + 0.4
		local wallFrame = facing(onCircle(center, wallRadius, angle, wallHeight / 2), center)
		block(arena, "Wall", Vector3.new(wallLength, wallHeight, thickness), wallFrame, STONE, PEBBLE)
		block(
			arena,
			"WallCap",
			Vector3.new(wallLength, 1.2, thickness + 1),
			wallFrame * CFrame.new(0, wallHeight / 2 + 0.6, 0),
			MARBLE
		)

		-- Spectator tiers rise in three steps behind the wall.
		for tier = 1, 3 do
			local tierRadius = radius + thickness + (tier - 0.5) * 5
			local tierHeight = wallHeight + 1 + tier * 3
			local tierLength = 2 * (tierRadius + 2.5) * math.tan(step / 2) + 0.4
			block(
				arena,
				"SpectatorTier",
				Vector3.new(tierLength, tierHeight, 5),
				facing(onCircle(center, tierRadius, angle, tierHeight / 2), center),
				if tier % 2 == 0 then STONE_DARK else STONE,
				PEBBLE
			)
		end
	end

	-- Gate: pillars on both edges of the opening and a lintel above it.
	local gateRadius = radius + thickness / 2
	for _, side in { -1, 1 } do
		block(
			arena,
			"GatePillar",
			Vector3.new(5, wallHeight + 8, thickness + 2),
			facing(onCircle(center, gateRadius, gateAngle + side * step, (wallHeight + 8) / 2), center),
			MARBLE
		)
	end
	local gateChord = 2 * gateRadius * math.sin(step)
	block(
		arena,
		"GateLintel",
		Vector3.new(gateChord + 5, 4, thickness + 2),
		facing(onCircle(center, gateRadius, gateAngle, wallHeight + 6), center),
		MARBLE
	)
	local gateSign = block(
		arena,
		"GateSign",
		Vector3.new(gateChord - 2, 3, 0.5),
		facing(onCircle(center, gateRadius + thickness / 2 + 1.3, gateAngle, wallHeight + 6), center)
			* CFrame.Angles(0, math.pi, 0),
		STONE_DARK
	)
	sign(gateSign, "THE GRAND COLOSSEUM", GOLD_GLOW, STONE_DARK)

	-- Central dais for Gladiator Primus.
	local daisTop = 0.45 + World.DaisHeight
	disc(arena, "CentralDais", center, daisTop, World.DaisRadius * 2, World.DaisHeight + 0.5, MARBLE, PEBBLE)
	decor(disc(arena, "DaisRim", center, 0.62, World.DaisRadius * 2 + 1.2, 0.3, Color3.fromRGB(220, 50, 50), NEON))
	for index = 0, 3 do
		local angle = math.pi / 4 + index * math.pi / 2
		local base = onCircle(center, World.DaisRadius - 2, angle, daisTop)
		cylinder(arena, "BrazierStand", 1.4, 4, CFrame.new(base + Vector3.new(0, 2, 0)), IRON)
		block(arena, "BrazierBowl", Vector3.new(2.6, 1.2, 2.6), CFrame.new(base + Vector3.new(0, 4.4, 0)), IRON)
		local flame = decor(ball(arena, "BrazierFlame", 1.8, base + Vector3.new(0, 5.4, 0), EMBER, NEON))
		pointLight(flame, EMBER, 2, 20)
		particles(flame, EMBER, 10, NumberRange.new(2, 4), NumberRange.new(0.4, 0.9))
	end

	-- Spawners: invisible tagged markers + a faint sigil on the sand.
	for _, spawner in GameConfig.Spawners do
		local position = center + spawner.Offset
		local onDais = spawner.Offset.Magnitude <= World.DaisRadius
		local floorY = if onDais then daisTop else 0.45
		local marker = block(
			arena,
			`Spawner_{spawner.Id}`,
			Vector3.new(2, 0.2, 2),
			CFrame.new(position.X, floorY + 0.1, position.Z),
			Color3.new(1, 1, 1)
		)
		marker.Transparency = 1
		decor(marker)
		marker:SetAttribute("SpawnerId", spawner.Id)
		marker:SetAttribute("MobId", spawner.MobId)
		marker:AddTag(Tags.MobSpawner)
		local sigil =
			decor(disc(arena, "SpawnSigil", position, floorY + 0.06, 7, 0.1, Color3.fromRGB(200, 60, 50), NEON))
		sigil.Transparency = 0.75
	end
end

---------------------------------------------------------------------------------------
-- Eras 2-4
---------------------------------------------------------------------------------------

local function buildJapanLandmarks(parent: Instance, era: EraData)
	local center = era.Center
	for _, offsetX in { -44, 44 } do
		local x = center.X + offsetX
		for _, z in { -12, 12 } do
			cylinder(parent, "ToriiPillar", 2, 18, CFrame.new(x, 9, center.Z + z), era.Theme.Accent)
		end
		block(parent, "ToriiKasagi", Vector3.new(3, 1.6, 31), CFrame.new(x, 18.4, center.Z), Color3.fromRGB(40, 36, 36))
		block(parent, "ToriiNuki", Vector3.new(1.6, 1.2, 27), CFrame.new(x, 14.5, center.Z), era.Theme.Accent)
	end
	for index = 0, 5 do
		local angle = index * math.pi / 3 + math.pi / 6
		local base = onCircle(center, 72, angle, 0)
		cylinder(parent, "BlossomTrunk", 1.6, 9, CFrame.new(base + Vector3.new(0, 4.5, 0)), WOOD)
		decor(ball(parent, "BlossomCanopy", 11, base + Vector3.new(0, 11, 0), BLOSSOM))
		decor(ball(parent, "BlossomCanopy", 7, base + Vector3.new(2.5, 14, 1.5), era.Theme.Trim))
	end
end

local function buildSteamLandmarks(parent: Instance, era: EraData)
	local center = era.Center
	for index = 0, 3 do
		local angle = index * math.pi / 2 + math.pi / 4
		local base = onCircle(center, 70, angle, 0)
		block(parent, "Chimney", Vector3.new(6, 32, 6), CFrame.new(base + Vector3.new(0, 16, 0)), BRICK, PEBBLE)
		local top = decor(
			block(parent, "ChimneyMouth", Vector3.new(6.6, 1, 6.6), CFrame.new(base + Vector3.new(0, 32.5, 0)), IRON)
		)
		particles(top, Color3.fromRGB(120, 116, 112), 8, NumberRange.new(3, 6), NumberRange.new(2, 4))
	end
	for _, offsetZ in { -40, 40 } do
		local gear = Instance.new("Part")
		gear.Name = "Gear"
		gear.Shape = Enum.PartType.Cylinder
		gear.Size = Vector3.new(2, 18, 18)
		gear.CFrame = CFrame.new(center.X, 10, center.Z + offsetZ) * CFrame.Angles(0, math.pi / 2, 0)
		style(gear, era.Theme.Accent)
		gear.Parent = parent
		block(parent, "GearHub", Vector3.new(4, 4, 3), CFrame.new(center.X, 10, center.Z + offsetZ), IRON)
	end
end

local function buildNeonLandmarks(parent: Instance, era: EraData)
	local center = era.Center
	for index = 0, 7 do
		local angle = index * math.pi / 4
		local base = onCircle(center, 58, angle, 0)
		local color = if index % 2 == 0 then era.Theme.Accent else era.Theme.Trim
		block(parent, "Pylon", Vector3.new(2, 26, 2), CFrame.new(base + Vector3.new(0, 13, 0)), color, NEON)
	end
	for index, height in { 22, 30 } do
		decor(disc(parent, "HoloRing", center, height, 26 + index * 10, 0.5, era.Theme.Accent, NEON)).Transparency = 0.5
	end
end

local function buildEraSector(parent: Instance, era: EraData)
	local sector = newModel(parent, `Era{era.Index}_{era.Id}`)
	buildGround(sector, era)
	disc(sector, "Plaza", era.Center, 0.4, 120, 1, era.Theme.Path, PEBBLE)
	buildObelisk(sector, era.Center, era.Index, era.Theme.Accent)

	local westRoadStart = Vector3.new(era.SectorMinX + 4, 0, 0)
	road(sector, westRoadStart, Vector3.new(era.Center.X - 56, 0, 0), 20, era.Theme.Path)
	if era.Index < #GameConfig.Eras then
		road(sector, Vector3.new(era.Center.X + 56, 0, 0), Vector3.new(era.SectorMaxX - 4, 0, 0), 20, era.Theme.Path)
	end

	if era.Id == "FeudalJapan" then
		buildJapanLandmarks(sector, era)
	elseif era.Id == "SteamAge" then
		buildSteamLandmarks(sector, era)
	elseif era.Id == "NeonFuture" then
		buildNeonLandmarks(sector, era)
	end
end

---------------------------------------------------------------------------------------
-- Chronal Rifts & world bounds
---------------------------------------------------------------------------------------

local function buildRift(parent: Instance, portal: GameConfig.PortalData)
	local rift = newModel(parent, portal.Id)
	local destination = GameConfig.Eras[portal.ToEra]
	local x = portal.Position.X
	local from = GameConfig.Eras[portal.FromEra]
	local minZ = math.min(from.SectorMinZ, destination.SectorMinZ)
	local maxZ = math.max(from.SectorMaxZ, destination.SectorMaxZ)

	-- Sector wall with an opening for the rift.
	local leftLength = -RIFT_HALF_WIDTH - minZ
	local rightLength = maxZ - RIFT_HALF_WIDTH
	block(
		rift,
		"SectorWall",
		Vector3.new(BOUNDARY_THICKNESS, BOUNDARY_HEIGHT, leftLength),
		CFrame.new(x, BOUNDARY_HEIGHT / 2, minZ + leftLength / 2),
		STONE_DARK,
		PEBBLE
	)
	block(
		rift,
		"SectorWall",
		Vector3.new(BOUNDARY_THICKNESS, BOUNDARY_HEIGHT, rightLength),
		CFrame.new(x, BOUNDARY_HEIGHT / 2, RIFT_HALF_WIDTH + rightLength / 2),
		STONE_DARK,
		PEBBLE
	)
	block(
		rift,
		"RiftLintel",
		Vector3.new(BOUNDARY_THICKNESS, BOUNDARY_HEIGHT - RIFT_HEIGHT, RIFT_HALF_WIDTH * 2),
		CFrame.new(x, RIFT_HEIGHT + (BOUNDARY_HEIGHT - RIFT_HEIGHT) / 2, 0),
		STONE_DARK,
		PEBBLE
	)

	-- Particle ring.
	local ringCenter = Vector3.new(x, RIFT_HEIGHT / 2, 0)
	local ringRadius = RIFT_HALF_WIDTH + 0.5
	local ringSegments = 20
	for index = 0, ringSegments - 1 do
		local angle = index * math.pi * 2 / ringSegments
		local position = ringCenter + Vector3.new(0, math.sin(angle) * ringRadius, math.cos(angle) * ringRadius)
		local tangent = Vector3.new(0, math.cos(angle), -math.sin(angle))
		decor(
			block(
				rift,
				"RingSegment",
				Vector3.new(2.4, 2.2, 5),
				CFrame.lookAt(position, position + tangent, Vector3.xAxis),
				destination.Theme.Accent,
				NEON
			)
		)
	end

	-- The gate itself: solid for everyone until the client opens it locally.
	local barrier = block(
		rift,
		"RiftBarrier",
		Vector3.new(2, RIFT_HEIGHT, RIFT_HALF_WIDTH * 2),
		CFrame.new(ringCenter),
		destination.Theme.Accent,
		Enum.Material.ForceField
	)
	barrier.CanQuery = false
	barrier.CastShadow = false
	particles(barrier, destination.Theme.Accent, 25, NumberRange.new(0.5, 2), NumberRange.new(1, 2))
	attachment(barrier, "LabelAttachment", Vector3.new(0, RIFT_HEIGHT / 2 + 4, 0))
	barrier:SetAttribute("PortalId", portal.Id)
	barrier:SetAttribute("ToEra", portal.ToEra)
	barrier:SetAttribute("RequiredStrength", portal.RequiredStrength)
	barrier:SetAttribute("RequiredRebirths", portal.RequiredRebirths)
	barrier:AddTag(Tags.ChronalRiftGate)
end

local function buildWorldEnds(parent: Instance)
	local first = GameConfig.Eras[1]
	local last = GameConfig.Eras[#GameConfig.Eras]
	for _, info in { { X = first.SectorMinX, Era = first }, { X = last.SectorMaxX, Era = last } } do
		local depth = info.Era.SectorMaxZ - info.Era.SectorMinZ
		local midZ = (info.Era.SectorMinZ + info.Era.SectorMaxZ) / 2
		block(
			parent,
			"WorldEnd",
			Vector3.new(6, BOUNDARY_HEIGHT, depth),
			CFrame.new(info.X, BOUNDARY_HEIGHT / 2, midZ),
			STONE_DARK,
			PEBBLE
		)
	end
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

function WorldBuilder.Build(parent: Instance): Model
	local world = Instance.new("Model")
	world.Name = "ChronoWorld"

	local rome = GameConfig.Eras[1]
	local romeSector = newModel(world, `Era1_{rome.Id}`)
	buildGround(romeSector, rome)
	buildPiazza(romeSector, rome)
	buildColosseum(romeSector)
	road(
		romeSector,
		Vector3.new(0, 0, World.PiazzaRadius - 4),
		Vector3.new(0, 0, World.ColosseumCenter.Z - World.ColosseumRadius - World.ColosseumWallThickness),
		20,
		rome.Theme.Path
	)
	road(
		romeSector,
		Vector3.new(World.PiazzaRadius - 4, 0, 0),
		Vector3.new(rome.SectorMaxX - 4, 0, 0),
		20,
		rome.Theme.Path
	)

	for index = 2, #GameConfig.Eras do
		buildEraSector(world, GameConfig.Eras[index])
	end

	local rifts = newModel(world, "ChronalRifts")
	for _, portal in GameConfig.Portals do
		buildRift(rifts, portal)
	end
	buildWorldEnds(world)

	-- Parent once at the end: a single replication burst instead of thousands.
	world.Parent = parent
	return world
end

local function ensureEffect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local effect = Instance.new(className :: any)
	effect.Name = name
	effect.Parent = Lighting
	return effect
end

-- Stylised, mobile-friendly lighting. Set Lighting attribute ManualLighting=true to opt out.
function WorldBuilder.ApplyLighting()
	if Lighting:GetAttribute("ManualLighting") == true then
		return
	end
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(86, 82, 96)
	Lighting.OutdoorAmbient = Color3.fromRGB(138, 132, 150)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	local atmosphere = ensureEffect("Atmosphere", "ChronoAtmosphere") :: Atmosphere
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(199, 186, 170)
	atmosphere.Decay = Color3.fromRGB(106, 112, 125)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 1.2

	local bloom = ensureEffect("BloomEffect", "ChronoBloom") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 28
	bloom.Threshold = 1.4

	local grade = ensureEffect("ColorCorrectionEffect", "ChronoGrade") :: ColorCorrectionEffect
	grade.Saturation = 0.12
	grade.Contrast = 0.06
	grade.TintColor = Color3.fromRGB(255, 250, 242)
end

return WorldBuilder
