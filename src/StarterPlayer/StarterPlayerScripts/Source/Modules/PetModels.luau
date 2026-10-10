--!strict
--[[
	PetModels
	---------
	Client-side builders for the Zone 1 chibi pets (Bible §4.1: Mini Centurion, Baby War
	Mammoth, Golden Eagle). Each greybox is a handful of anchored blocks (far below the
	500-triangle budget); a Blender export placed at
	ReplicatedStorage.Assets.Pets.<Visual.Template> replaces it automatically.

	All parts are anchored, non-colliding and non-queryable: pets are purely cosmetic and
	are moved with PivotTo by PetController.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

type PetData = GameConfig.PetData

local PetModels = {}

local function piece(
	model: Model,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	wedge: boolean?
): BasePart
	local part: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = offset
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	return part
end

local function eyes(model: Model, z: number, y: number, spacing: number)
	local black = Color3.fromRGB(24, 24, 28)
	piece(model, "EyeLeft", Vector3.new(0.16, 0.22, 0.05), CFrame.new(-spacing, y, z), black)
	piece(model, "EyeRight", Vector3.new(0.16, 0.22, 0.05), CFrame.new(spacing, y, z), black)
end

local function centurion(model: Model, pet: PetData): BasePart
	local visual = pet.Visual
	local body = piece(model, "Body", Vector3.new(1.1, 0.9, 0.8), CFrame.new(0, 0, 0), visual.PrimaryColor)
	piece(model, "Head", Vector3.new(1.2, 1.1, 1.05), CFrame.new(0, 0.95, 0), visual.SecondaryColor)
	piece(model, "Helmet", Vector3.new(1.3, 0.45, 1.15), CFrame.new(0, 1.55, 0), visual.AccentColor)
	piece(model, "Crest", Vector3.new(0.22, 0.5, 1.0), CFrame.new(0, 1.95, 0), visual.PrimaryColor)
	piece(model, "Shield", Vector3.new(0.18, 0.9, 0.75), CFrame.new(-0.7, 0, -0.1), visual.PrimaryColor)
	piece(model, "ShieldBoss", Vector3.new(0.2, 0.25, 0.25), CFrame.new(-0.8, 0, -0.1), visual.AccentColor)
	eyes(model, -0.54, 0.95, 0.25)
	return body
end

local function mammoth(model: Model, pet: PetData): BasePart
	local visual = pet.Visual
	local body = piece(model, "Body", Vector3.new(1.4, 1.1, 1.7), CFrame.new(0, 0.1, 0.1), visual.PrimaryColor)
	piece(model, "Blanket", Vector3.new(1.5, 0.3, 1.0), CFrame.new(0, 0.7, 0.15), visual.AccentColor)
	piece(model, "Head", Vector3.new(1.1, 1.0, 0.9), CFrame.new(0, 0.35, -1.05), visual.PrimaryColor)
	piece(model, "Trunk", Vector3.new(0.3, 0.9, 0.3), CFrame.new(0, -0.3, -1.5), visual.PrimaryColor)
	piece(model, "EarLeft", Vector3.new(0.12, 0.7, 0.6), CFrame.new(-0.62, 0.4, -0.95), visual.PrimaryColor)
	piece(model, "EarRight", Vector3.new(0.12, 0.7, 0.6), CFrame.new(0.62, 0.4, -0.95), visual.PrimaryColor)
	piece(
		model,
		"TuskLeft",
		Vector3.new(0.14, 0.18, 0.55),
		CFrame.new(-0.32, -0.15, -1.55),
		visual.SecondaryColor,
		true
	)
	piece(
		model,
		"TuskRight",
		Vector3.new(0.14, 0.18, 0.55),
		CFrame.new(0.32, -0.15, -1.55),
		visual.SecondaryColor,
		true
	)
	for _, x in { -0.45, 0.45 } do
		for _, z in { -0.5, 0.65 } do
			piece(model, "Leg", Vector3.new(0.35, 0.5, 0.35), CFrame.new(x, -0.65, z), visual.PrimaryColor)
		end
	end
	eyes(model, -1.51, 0.5, 0.25)
	return body
end

local function eagle(model: Model, pet: PetData): BasePart
	local visual = pet.Visual
	local body = piece(model, "Body", Vector3.new(0.9, 0.9, 1.1), CFrame.new(0, 0, 0), visual.PrimaryColor)
	piece(model, "Head", Vector3.new(0.75, 0.75, 0.75), CFrame.new(0, 0.7, -0.35), visual.SecondaryColor)
	piece(
		model,
		"Beak",
		Vector3.new(0.25, 0.25, 0.4),
		CFrame.new(0, 0.6, -0.9) * CFrame.Angles(0, math.pi, 0),
		visual.AccentColor,
		true
	)
	piece(model, "WingLeft", Vector3.new(1.3, 0.12, 0.7), CFrame.new(-1.05, 0.15, 0.05), visual.PrimaryColor)
	piece(model, "WingRight", Vector3.new(1.3, 0.12, 0.7), CFrame.new(1.05, 0.15, 0.05), visual.PrimaryColor)
	piece(model, "Tail", Vector3.new(0.6, 0.12, 0.6), CFrame.new(0, -0.1, 0.75), visual.SecondaryColor)
	eyes(model, -0.73, 0.78, 0.18)
	return body
end

local function fromTemplate(pet: PetData): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local pets = assets and assets:FindFirstChild("Pets")
	local template = pets and pets:FindFirstChild(pet.Visual.Template or pet.Id)
	if template and template:IsA("Model") and template.PrimaryPart then
		local clone = template:Clone()
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
			end
		end
		return clone
	end
	return nil
end

-- Builds an unparented pet model whose PrimaryPart is "Body".
function PetModels.Build(petId: string): Model?
	local pet = GameConfig.Pets[petId]
	if pet == nil then
		return nil
	end
	local template = fromTemplate(pet)
	if template then
		template.Name = pet.Id
		return template
	end

	local model = Instance.new("Model")
	model.Name = pet.Id
	local archetype = pet.Visual.Archetype
	local body: BasePart
	if archetype == "Mammoth" then
		body = mammoth(model, pet)
	elseif archetype == "Eagle" then
		body = eagle(model, pet)
	else
		body = centurion(model, pet)
	end
	model.PrimaryPart = body
	return model
end

-- Flying pets hover higher and flap; walkers bob.
function PetModels.IsFlying(petId: string): boolean
	local pet = GameConfig.Pets[petId]
	return pet ~= nil and pet.Visual.Archetype == "Eagle"
end

return PetModels
