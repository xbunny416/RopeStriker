--!strict
--[[
	MobFactory
	----------
	Builds a mob rig for a MobData entry.

	  1. If ServerStorage.Assets.Mobs.<Visual.Template or Id> exists (an imported Blender
	     FBX rig with a Humanoid + HumanoidRootPart), it is cloned.
	  2. Otherwise a low-poly procedural legionary rig is assembled from a handful of
	     SmoothPlastic blocks, coloured and scaled per mob (Legionary 1x, Centurion 1.3x
	     with crest, Gladiator Primus 2.2x).

	Every rig exposes the same contract to MobService and the client visuals:
	  Humanoid (R15 locomotion via HipHeight), HumanoidRootPart (PrimaryPart),
	  Attachment "Overhead" (health bar anchor) and, on procedural rigs, a Motor6D named
	  "WeaponShoulder" that the client rotates for the Mob_Telegraph_Slash wind-up.
]]

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

type MobData = GameConfig.MobData

local MobFactory = {}

local function visualPart(
	model: Model,
	root: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = root.CFrame * offset
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.CanQuery = true -- clients raycast/aim against mob bodies
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function weld(part0: BasePart, part1: BasePart)
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = part0
	constraint.Part1 = part1
	constraint.Parent = part1
end

local function configureHumanoid(humanoid: Humanoid, data: MobData, hipHeight: number)
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = data.WalkSpeed
	humanoid.AutoRotate = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.MaxHealth = 100
	humanoid.Health = 100
	-- Health lives in MobService (shared pool + contributor ledger); the Humanoid is
	-- only used for locomotion, so it must never die or flail on its own.
	for _, state in
		{
			Enum.HumanoidStateType.Dead,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.Swimming,
			Enum.HumanoidStateType.Seated,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end
	if humanoid:FindFirstChildOfClass("Animator") == nil then
		Instance.new("Animator").Parent = humanoid
	end
end

local function fromTemplate(data: MobData): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	local mobs = assets and assets:FindFirstChild("Mobs")
	local template = mobs and mobs:FindFirstChild(data.Visual.Template or data.Id)
	if template == nil or not template:IsA("Model") then
		return nil
	end
	local clone = template:Clone()
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local root = clone:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		warn(`[MobFactory] template {template.Name} needs a Humanoid and HumanoidRootPart; using procedural rig`)
		clone:Destroy()
		return nil
	end
	configureHumanoid(humanoid, data, humanoid.HipHeight)
	clone.PrimaryPart = root
	if root:FindFirstChild("Overhead") == nil then
		local overhead = Instance.new("Attachment")
		overhead.Name = "Overhead"
		overhead.Position = Vector3.new(0, root.Size.Y / 2 + 3 * data.Visual.Scale, 0)
		overhead.Parent = root
	end
	return clone
end

local function procedural(data: MobData): Model
	local scale = data.Visual.Scale
	local visual = data.Visual
	local model = Instance.new("Model")
	model.Name = data.Id

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * scale
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = false
	root.CanQuery = true
	root.Parent = model

	local function add(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
		local part = visualPart(model, root, name, size * scale, CFrame.new(offset * scale), color, material)
		weld(root, part)
		return part
	end

	local torso = add("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), visual.SkinColor)
	add("Cuirass", Vector3.new(2.2, 1.5, 1.2), Vector3.new(0, 0.2, 0), visual.ArmorColor)
	add("Belt", Vector3.new(2.25, 0.35, 1.25), Vector3.new(0, -0.65, 0), visual.AccentColor)
	add("Skirt", Vector3.new(2.1, 0.7, 1.15), Vector3.new(0, -1.15, 0), visual.ArmorColor)
	add("LegLeft", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, -2, 0), visual.SkinColor)
	add("LegRight", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, -2, 0), visual.SkinColor)
	add("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.65, 0), visual.SkinColor)
	add("Helmet", Vector3.new(1.5, 0.75, 1.5), Vector3.new(0, 2.25, 0), visual.AccentColor)
	if visual.Crest then
		add("Crest", Vector3.new(0.3, 0.8, 1.7), Vector3.new(0, 2.95, 0), visual.ArmorColor)
	end

	-- Shield arm (static).
	add("ArmLeft", Vector3.new(0.8, 2, 0.8), Vector3.new(-1.45, 0, 0), visual.SkinColor)
	add("Shield", Vector3.new(0.35, 2.4, 1.9), Vector3.new(-1.95, -0.2, -0.2), visual.ArmorColor)
	add("ShieldBoss", Vector3.new(0.4, 0.6, 0.6), Vector3.new(-2.15, -0.2, -0.2), visual.AccentColor)

	-- Weapon arm on a Motor6D so clients can animate the telegraph wind-up.
	local arm = visualPart(
		model,
		root,
		"ArmRight",
		Vector3.new(0.8, 2, 0.8) * scale,
		CFrame.new(Vector3.new(1.45, 0, 0) * scale),
		visual.SkinColor
	)
	local shoulder = Instance.new("Motor6D")
	shoulder.Name = "WeaponShoulder"
	shoulder.Part0 = torso
	shoulder.Part1 = arm
	shoulder.C0 = CFrame.new(Vector3.new(1.45, 0.9, 0) * scale)
	shoulder.C1 = CFrame.new(Vector3.new(0, 0.9, 0) * scale)
	shoulder.Parent = torso

	local function armPiece(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material?)
		local part = visualPart(model, arm, name, size * scale, CFrame.new(offset * scale), color, material)
		weld(arm, part)
	end
	armPiece("Hilt", Vector3.new(0.4, 0.4, 0.7), Vector3.new(0, -0.95, -0.25), visual.AccentColor)
	armPiece("Blade", Vector3.new(0.22, 0.5, 2.8), Vector3.new(0, -0.95, -1.9), Color3.fromRGB(214, 218, 226))

	local overhead = Instance.new("Attachment")
	overhead.Name = "Overhead"
	overhead.Position = Vector3.new(0, 3.9, 0) * scale
	overhead.Parent = root

	local humanoid = Instance.new("Humanoid")
	configureHumanoid(humanoid, data, 2 * scale)
	humanoid.Parent = model

	model.PrimaryPart = root
	return model
end

-- Builds (but does not parent) the rig for `data`, standing on `floorPosition`.
function MobFactory.Build(data: MobData, floorPosition: Vector3): Model
	local model = fromTemplate(data) or procedural(data)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	local standHeight = humanoid.HipHeight + root.Size.Y / 2
	model:PivotTo(CFrame.new(floorPosition + Vector3.new(0, standHeight + 0.1, 0)))
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

return MobFactory
