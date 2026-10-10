--!strict
--[[
	EquipmentService
	================
	Rope weapon framework (Bible §4.1) and the Blacksmith shop.

	Rope rig, rebuilt on every spawn / equip change:
	  ChronoRope (Model, parented to the character)
	  ├─ HandleL  (Part, Motor6D "Grip" to LeftHand)   RopeAttachment, TrailTop/TrailBottom, HandleTrail
	  ├─ HandleR  (Part, Motor6D "Grip" to RightHand)  RopeAttachment, TrailTop/TrailBottom, HandleTrail,
	  │                                                TipA/TipB + TipTrail (rope-tip trail),
	  │                                                TipA.TensionSparks (ParticleEmitter)
	  └─ RopeBeam (Beam HandleL.RopeAttachment -> HandleR.RopeAttachment)
	Clients animate the beam curve and the tip attachments every frame (RopeController)
	and recolour the trails by combo tier, so the server only replicates the static rig.

	Optional art: ReplicatedStorage.Assets.Ropes.<Visual.Template> may contain HandleL and
	HandleR parts exported from Blender; they replace the procedural handles.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Guard = require(Source.Shared.Guard)
local Remotes = require(Source.Network.Remotes)

local DataService = require(script.Parent.DataService)

local Modules = script.Parent.Parent.Modules
local PlayerDataOps = require(Modules.PlayerDataOps)
local RateLimiter = require(Modules.RateLimiter)
local Security = require(Modules.Security)

type RopeData = GameConfig.RopeData
type BootData = GameConfig.BootData
type ItemCategory = GameConfig.ItemCategory

local APPEARANCE_TIMEOUT = 6
local SHOP_KEYS = { "Shards", "OwnedRopes", "EquippedRope", "OwnedBoots", "EquippedBoots" }

local EquipmentService = {}

local requestLimiter = RateLimiter.new(
	GameConfig.Security.RateLimits.Request.Capacity,
	GameConfig.Security.RateLimits.Request.RefillPerSecond
)

local function findLimb(character: Model, names: { string }): BasePart?
	for _, name in names do
		local limb = character:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			return limb
		end
	end
	return nil
end

local function attachment(parent: BasePart, name: string, position: Vector3): Attachment
	local point = Instance.new("Attachment")
	point.Name = name
	point.Position = position
	point.Parent = parent
	return point
end

local function makeTrail(parent: BasePart, name: string, from: Attachment, to: Attachment, lifetime: number): Trail
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = from
	trail.Attachment1 = to
	trail.Enabled = false
	trail.FaceCamera = true
	trail.Lifetime = lifetime
	trail.MinLength = 0.05
	trail.LightEmission = 0.8
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.Parent = parent
	return trail
end

local function prepareHandle(handle: BasePart)
	handle.Anchored = false
	handle.CanCollide = false
	handle.CanQuery = false
	handle.CanTouch = false
	handle.Massless = true
	handle.CastShadow = false
end

local function templateHandle(rope: RopeData, name: string): BasePart?
	local templateName = rope.Visual.Template
	if templateName == nil then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local ropes = assets and assets:FindFirstChild("Ropes")
	local template = ropes and ropes:FindFirstChild(templateName)
	local handle = template and template:FindFirstChild(name)
	if handle and handle:IsA("BasePart") then
		return handle:Clone()
	end
	return nil
end

local function buildHandle(model: Model, rope: RopeData, name: string, hand: BasePart): (BasePart, Attachment)
	local handle = templateHandle(rope, name)
	if handle == nil then
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(0.32, 1.05, 0.32)
		part.Color = rope.Visual.HandleColor
		part.Material = rope.Visual.HandleMaterial
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		handle = part
	end
	local grip = handle :: BasePart
	prepareHandle(grip)
	grip.Name = name

	local gripOffset = CFrame.new(0, -hand.Size.Y * 0.5, 0)
	grip.CFrame = hand.CFrame * gripOffset
	local motor = Instance.new("Motor6D")
	motor.Name = "Grip"
	motor.Part0 = hand
	motor.Part1 = grip
	motor.C0 = gripOffset
	motor.Parent = grip

	local half = grip.Size.Y / 2
	local ropeAttachment = attachment(grip, "RopeAttachment", Vector3.new(0, -half, 0))
	local top = attachment(grip, "TrailTop", Vector3.new(0, half, 0))
	local bottom = attachment(grip, "TrailBottom", Vector3.new(0, -half, 0))
	makeTrail(grip, "HandleTrail", top, bottom, 0.18)

	grip.Parent = model
	return grip, ropeAttachment
end

local function buildRope(character: Model, rope: RopeData): Model?
	local leftHand = findLimb(character, { "LeftHand", "Left Arm" })
	local rightHand = findLimb(character, { "RightHand", "Right Arm" })
	if leftHand == nil or rightHand == nil then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "ChronoRope"
	model:SetAttribute("RopeId", rope.Id)

	local _, leftAnchor = buildHandle(model, rope, "HandleL", leftHand)
	local handleR, rightAnchor = buildHandle(model, rope, "HandleR", rightHand)

	local beam = Instance.new("Beam")
	beam.Name = "RopeBeam"
	beam.Attachment0 = leftAnchor
	beam.Attachment1 = rightAnchor
	beam.Width0 = rope.Visual.Width
	beam.Width1 = rope.Visual.Width
	beam.Color = ColorSequence.new(rope.Visual.Color)
	beam.Transparency = NumberSequence.new(0)
	beam.LightEmission = if rope.Visual.Glow then 0.45 else 0
	beam.LightInfluence = if rope.Visual.Glow then 0.4 else 1
	beam.Segments = 24
	beam.FaceCamera = true
	beam.CurveSize0 = 0
	beam.CurveSize1 = 0
	beam.Parent = model

	-- Rope-tip trail: clients move TipA/TipB to the rope's apex every frame.
	local tipA = attachment(handleR, "TipA", Vector3.zero)
	local tipB = attachment(handleR, "TipB", Vector3.zero)
	makeTrail(handleR, "TipTrail", tipA, tipB, 0.26)

	-- High-tension sparks at the tip; clients enable them from the Gold tier upwards.
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "TensionSparks"
	sparks.Enabled = false
	sparks.Rate = 30
	sparks.Lifetime = NumberRange.new(0.15, 0.35)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = tipA

	model.Parent = character
	return model
end

local function bootPiece(
	parent: Model,
	anchor: BasePart,
	size: Vector3,
	offset: CFrame,
	boots: BootData,
	wedge: boolean
)
	local part: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	part.Name = "BootPiece"
	part.Size = size
	part.CFrame = anchor.CFrame * offset
	part.Color = boots.Visual.Color
	part.Material = boots.Visual.Material
	prepareHandle(part)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = anchor
	weld.Part1 = part
	weld.Parent = part
	part.Parent = parent
end

local function buildBoots(character: Model, boots: BootData): Model?
	if not boots.Visual.Visible then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "ChronoBoots"
	model:SetAttribute("BootsId", boots.Id)

	for _, side in { "Left", "Right" } do
		local foot = findLimb(character, { `{side}Foot`, `{side} Leg` })
		if foot == nil then
			continue
		end
		local footSize = foot.Size
		bootPiece(
			model,
			foot,
			Vector3.new(footSize.X + 0.14, 0.2, footSize.Z + 0.14),
			CFrame.new(0, -footSize.Y / 2 + 0.06, 0),
			boots,
			false
		)
		bootPiece(
			model,
			foot,
			Vector3.new(footSize.X + 0.1, 0.14, footSize.Z * 0.45),
			CFrame.new(0, footSize.Y * 0.1, -footSize.Z * 0.15),
			boots,
			false
		)

		local shin = findLimb(character, { `{side}LowerLeg` })
		if boots.Visual.Wings and shin then
			local shinSize = shin.Size
			local outward = if side == "Left" then -1 else 1
			bootPiece(
				model,
				shin,
				Vector3.new(shinSize.X + 0.12, shinSize.Y * 0.7, shinSize.Z + 0.12),
				CFrame.new(0, -shinSize.Y * 0.1, 0),
				boots,
				false
			)
			for index = 0, 1 do
				bootPiece(
					model,
					shin,
					Vector3.new(0.08, 0.45 - index * 0.12, 0.9 - index * 0.25),
					CFrame.new(outward * (shinSize.X / 2 + 0.06), shinSize.Y * (0.15 - index * 0.18), 0.25)
						* CFrame.Angles(0, if outward > 0 then 0 else math.pi, 0),
					boots,
					true
				)
			end
		end
	end

	model.Parent = character
	return model
end

-- (Re)builds the rope and/or boots on the player's current character when they differ
-- from what is equipped (or always, when `force` is set for a fresh character).
function EquipmentService.Refresh(player: Player, force: boolean?)
	local character = player.Character
	local data = DataService.GetData(player)
	if character == nil or data == nil then
		return
	end
	local rope = GameConfig.Ropes[data.EquippedRope] or GameConfig.Ropes[GameConfig.Starter.Rope]
	local boots = GameConfig.Boots[data.EquippedBoots] or GameConfig.Boots[GameConfig.Starter.Boots]

	local currentRope = character:FindFirstChild("ChronoRope")
	if force or currentRope == nil or currentRope:GetAttribute("RopeId") ~= rope.Id then
		if currentRope then
			currentRope:Destroy()
		end
		buildRope(character, rope)
	end

	local currentBoots = character:FindFirstChild("ChronoBoots")
	local bootsId = if currentBoots then currentBoots:GetAttribute("BootsId") else GameConfig.Starter.Boots
	if force or bootsId ~= boots.Id then
		if currentBoots then
			currentBoots:Destroy()
		end
		buildBoots(character, boots)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	-- Wait for the avatar's body scale to settle so the grips line up with the hands.
	if not player:HasAppearanceLoaded() then
		local deadline = os.clock() + APPEARANCE_TIMEOUT
		while not player:HasAppearanceLoaded() and os.clock() < deadline and character.Parent ~= nil do
			task.wait(0.1)
		end
	end
	if player.Character ~= character then
		return
	end
	if DataService.WaitForData(player, 30) == nil or player.Character ~= character then
		return
	end
	EquipmentService.Refresh(player, true)
end

local function handleShopRequest(
	player: Player,
	rawCategory: unknown,
	rawItemId: unknown,
	allowed: { string },
	operation: (
		data: GameConfig.PlayerData,
		category: ItemCategory,
		itemId: string
	) -> (boolean, string),
	keys: { string }
): (boolean, string)
	if not requestLimiter:Allow(player) then
		return false, "Slow down a little!"
	end
	local category = Guard.OneOf(rawCategory, allowed)
	local itemId = Guard.String(rawItemId, 64)
	if category == nil or itemId == nil then
		Security.Strike(player, "shop request malformed", 2)
		return false, "Invalid request."
	end
	local ok, message = false, "Your data is still loading."
	DataService.Mutate(player, keys, function(data)
		ok, message = operation(data, category :: ItemCategory, itemId)
	end)
	return ok, message
end

function EquipmentService.Init()
	Remotes.PurchaseItem.OnServerInvoke = function(
		player: Player,
		rawCategory: unknown,
		rawItemId: unknown
	): (boolean, string)
		return handleShopRequest(player, rawCategory, rawItemId, { "Rope", "Boots" }, PlayerDataOps.Purchase, SHOP_KEYS)
	end
	Remotes.EquipItem.OnServerInvoke = function(
		player: Player,
		rawCategory: unknown,
		rawItemId: unknown
	): (boolean, string)
		return handleShopRequest(
			player,
			rawCategory,
			rawItemId,
			{ "Rope", "Boots", "Title" },
			PlayerDataOps.Equip,
			{ "EquippedRope", "EquippedBoots", "EquippedTitle" }
		)
	end
end

function EquipmentService.Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			onCharacterAdded(player, character)
		end)
		local character = player.Character
		if character then
			task.spawn(onCharacterAdded, player, character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		requestLimiter:Reset(player)
	end)

	DataService.Changed:Connect(function(player: Player, keys: { string })
		if table.find(keys, "EquippedRope") or table.find(keys, "EquippedBoots") then
			EquipmentService.Refresh(player)
		end
	end)
end

return EquipmentService
