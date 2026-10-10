--!strict
--[[
	RopeController
	==============
	Everything the player does with the rope, on the client.

	Rhythm jump detector (Bible §2.1)
	  * Input: ContextActionService binds Space / ButtonA (jump) and Mouse1 / ButtonR2
	    (action) above the default controls; UserInputService.JumpRequest catches the
	    mobile jump button; Humanoid.StateChanged(Jumping) is a last-resort fallback.
	    The on-screen Action Button calls RopeController.PerformAction().
	  * The press is time-stamped on the synchronised server clock and judged instantly:
	    within 0.15s of a beat = on-beat (+0.1x combo, green burst).
	  * Landing is detected with a downward raycast every frame (not Humanoid states,
	    which lag): when the feet are back within LANDED_GAP of the ground while falling,
	    the landing time is taken. A press that missed the beat can still be saved by an
	    on-beat landing; otherwise the combo resets to 1.0x.
	  * ReportBounce(pressTime, landTime) is sent at landing; the server re-judges it
	    and BounceResult reconciles the locally predicted combo.

	Combo visualizer: a BillboardGui on the torso with a ring shrinking onto a target
	ring every beat, a green burst on hits, and a tier-coloured combo counter.

	Rope rendering (every character): the Beam between HandleL/HandleR is re-curved
	every frame - orbiting the body on the beat in Training, whipping forward for Ground
	Lash, spinning outward for Aerial Sweep - and handle/tip Trails shift colour with the
	owner's combo tier (White -> Blue -> Gold -> Red). Rope_Whoosh rises +1 semitone per
	tier.

	Combat: SWING performs Ground Lash on the ground or Aerial Sweep in the air, predicts
	hits locally for instant feedback and sends RequestAttack for server validation.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Rhythm = require(Source.Shared.Rhythm)
local Signal = require(Source.Shared.Signal)
local Spatial = require(Source.Shared.Spatial)
local Tags = require(Source.Shared.Tags)
local Trove = require(Source.Shared.Trove)
local Zones = require(Source.Shared.Zones)
local Remotes = require(Source.Network.Remotes)

local Modules = script.Parent.Parent.Modules
local BeamCurve = require(Modules.BeamCurve)
local ClientState = require(Modules.ClientState)
local ProceduralPose = require(Modules.ProceduralPose)
local SoundPlayer = require(Modules.SoundPlayer)

type AttackKind = GameConfig.AttackKind
type PlayerMode = GameConfig.PlayerMode
type Judgement = Rhythm.Judgement
type BounceResult = Remotes.BounceResult

type PendingBounce = {
	PressTime: number, -- synchronised server clock
	PressClock: number, -- os.clock(), for local timeouts
	PressJudgement: Judgement?,
	LeftGround: boolean,
}

type RopeView = {
	Character: Model,
	Owner: Player?,
	Joints: ProceduralPose.Joints,
	TierIndex: number,
	TrailsOn: boolean,
}

type RingParts = {
	Gui: BillboardGui,
	Approach: Frame,
	ApproachStroke: UIStroke,
	TargetStroke: UIStroke,
	Burst: Frame,
	BurstStroke: UIStroke,
	Combo: TextLabel,
	ComboScale: UIScale,
	Judge: TextLabel,
}

local ACTION_JUMP = "ChronoRopeJump"
local ACTION_SWING = "ChronoRopeSwing"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value

local GROUNDED_GAP = 0.35 -- may start a rope jump when the feet are this close to ground
local TAKEOFF_GAP = 0.6 -- the jump counts as started once the feet are this high
local LANDED_GAP = 0.25 -- landing: back within this distance while not rising
local TAKEOFF_TIMEOUT = 0.45 -- pressed but never left the ground: discard
local RING_TARGET_SCALE = 0.42
local ROPE_CULL_DISTANCE = 180
local BEZIER_APEX_FACTOR = 0.75 -- apex of a symmetric cubic sits at 3/4 of the control offset
local SPARK_MIN_TIER = 3 -- Gold

local RhythmConfig = GameConfig.Rhythm
local Palette = GameConfig.UI.Palette

local GROUND_LASH: AttackKind = "GroundLash"
local AERIAL_SWEEP: AttackKind = "AerialSweep"
local GroundLashData = GameConfig.Combat.Attacks[GROUND_LASH]
local AerialSweepData = GameConfig.Combat.Attacks[AERIAL_SWEEP]

local ATTACK_DURATION: { [string]: number } = {
	GroundLash = GroundLashData.Duration,
	AerialSweep = AerialSweepData.Duration,
}

local RopeController = {}

RopeController.ModeChanged = Signal.new() :: Signal.Signal<PlayerMode>
RopeController.BounceJudged = Signal.new() :: Signal.Signal<Judgement, number>
RopeController.BounceConfirmed = Signal.new() :: Signal.Signal<BounceResult>
RopeController.AttackPerformed = Signal.new() :: Signal.Signal<AttackKind>
RopeController.EngagedChanged = Signal.new() :: Signal.Signal<boolean>

local player = Players.LocalPlayer

local humanoid: Humanoid? = nil
local rootPart: BasePart? = nil
local characterTrove = Trove.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local mode: PlayerMode = "Training"
local pending: PendingBounce? = nil
local predictedCombo = RhythmConfig.ComboStart
local engaged = false
local engagedUntil = 0

local lastAttackClock = -math.huge
local attackCooldown = 0
local localAttack: AttackKind? = nil
local localAttackAt = 0

local tracks: { [string]: AnimationTrack? } = {}
local ropeViews: { [Model]: RopeView } = {}
local ring: RingParts? = nil

---------------------------------------------------------------------------------------
-- Ground sensing (raycasts)
---------------------------------------------------------------------------------------

-- Distance between the feet and the ground directly below (0 when standing).
local function groundGap(): number?
	local hum = humanoid
	local root = rootPart
	if hum == nil or root == nil then
		return nil
	end
	local legHeight = if hum.RigType == Enum.HumanoidRigType.R6 then 2 else hum.HipHeight
	local standHeight = legHeight + root.Size.Y / 2
	local result = workspace:Raycast(root.Position, Vector3.new(0, -(standHeight + 6), 0), rayParams)
	if result == nil then
		return math.huge
	end
	return (root.Position.Y - result.Position.Y) - standHeight
end

local function isGrounded(): boolean
	local gap = groundGap()
	return gap ~= nil and gap <= GROUNDED_GAP
end

---------------------------------------------------------------------------------------
-- Animation tracks (used when GameConfig.Animations ids are set)
---------------------------------------------------------------------------------------

local function loadTracks(hum: Humanoid)
	table.clear(tracks)
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator == nil then
		return
	end
	local function load(key: string, id: string, looped: boolean, priority: Enum.AnimationPriority)
		if id == "" then
			return
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local track = animator:LoadAnimation(animation)
		track.Looped = looped
		track.Priority = priority
		tracks[key] = track
	end
	load("JumpRopeLoop", GameConfig.Animations.JumpRopeLoop, true, Enum.AnimationPriority.Action)
	load("GroundLash", GameConfig.Animations.GroundLashAttack, false, Enum.AnimationPriority.Action2)
	load("AerialSweep", GameConfig.Animations.AirSweepAttack, false, Enum.AnimationPriority.Action2)
end

local function playJumpRopeLoop(play: boolean)
	local track = tracks.JumpRopeLoop
	if track == nil then
		return
	end
	if play and not track.IsPlaying then
		track:Play(0.15)
		if track.Length > 0 then
			-- One arm-orbit cycle per beat, phase-locked to the shared clock.
			track:AdjustSpeed(track.Length / RhythmConfig.BeatInterval)
			track.TimePosition = Rhythm.Phase(workspace:GetServerTimeNow()) * track.Length
		end
	elseif not play and track.IsPlaying then
		track:Stop(0.2)
	end
end

---------------------------------------------------------------------------------------
-- Combo visualizer (rhythm prompt ring)
---------------------------------------------------------------------------------------

local function ringFrame(
	parent: Instance,
	name: string,
	scale: number,
	color: Color3,
	thickness: number
): (Frame, UIStroke)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(scale, scale)
	frame.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = frame
	frame.Parent = parent
	return frame, stroke
end

local function ringLabel(parent: Instance, name: string, positionY: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, positionY)
	label.Size = UDim2.fromScale(1.2, height)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = parent
	return label
end

local function buildRing(adornee: BasePart)
	local existing = ring
	if existing then
		existing.Gui:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RhythmPrompt"
	gui.Adornee = adornee
	gui.Size = UDim2.fromScale(5, 5)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Enabled = false

	local _, targetStroke = ringFrame(gui, "TargetRing", RING_TARGET_SCALE, Color3.new(1, 1, 1), 3)
	local approach, approachStroke = ringFrame(gui, "ApproachRing", 1, RhythmConfig.ComboTiers[1].Color, 4)
	local burst, burstStroke = ringFrame(gui, "Burst", RING_TARGET_SCALE, Palette.Good, 6)
	burstStroke.Transparency = 1

	local combo = ringLabel(gui, "Combo", 0.06, 0.2)
	local comboScale = Instance.new("UIScale")
	comboScale.Parent = combo
	local judge = ringLabel(gui, "Judge", 0.95, 0.14)

	gui.Parent = player:WaitForChild("PlayerGui")
	ring = {
		Gui = gui,
		Approach = approach,
		ApproachStroke = approachStroke,
		TargetStroke = targetStroke,
		Burst = burst,
		BurstStroke = burstStroke,
		Combo = combo,
		ComboScale = comboScale,
		Judge = judge,
	}
end

local function showJudgement(judgement: Judgement, combo: number)
	local parts = ring
	if parts == nil then
		return
	end
	local tierColor = Rhythm.TierColor(combo)
	parts.Combo.Text = `x{string.format("%.1f", combo)}`
	parts.Combo.TextColor3 = tierColor

	if judgement.OnBeat then
		parts.Judge.Text = if math.abs(judgement.Offset) <= 0.05 then "PERFECT!" else "ON BEAT!"
		parts.Judge.TextColor3 = Palette.Good
		parts.Burst.Size = UDim2.fromScale(RING_TARGET_SCALE, RING_TARGET_SCALE)
		parts.BurstStroke.Transparency = 0
		local info = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(parts.Burst, info, { Size = UDim2.fromScale(1.15, 1.15) }):Play()
		TweenService:Create(parts.BurstStroke, info, { Transparency = 1 }):Play()
		parts.ComboScale.Scale = 1.35
		TweenService:Create(parts.ComboScale, TweenInfo.new(0.2), { Scale = 1 }):Play()
		SoundPlayer.Play("RhythmHit", nil, Rhythm.WhooshPitch(combo))
	else
		parts.Judge.Text = "MISS"
		parts.Judge.TextColor3 = Palette.Bad
	end
end

local function updateRing(serverNow: number)
	local parts = ring
	if parts == nil then
		return
	end
	parts.Gui.Enabled = engaged
	if not engaged then
		return
	end
	local remaining = Rhythm.TimeUntilNextBeat(serverNow) / RhythmConfig.BeatInterval
	local scale = RING_TARGET_SCALE + (1 - RING_TARGET_SCALE) * remaining
	parts.Approach.Size = UDim2.fromScale(scale, scale)
	parts.ApproachStroke.Color = Rhythm.TierColor(predictedCombo)
	parts.ApproachStroke.Transparency = 0.15 + 0.6 * remaining
	-- The target ring glows green while the window is open.
	local open = Rhythm.IsOnBeat(serverNow)
	parts.TargetStroke.Color = if open then Palette.Good else Color3.new(1, 1, 1)
	if parts.Combo.Text == "" then
		parts.Combo.Text = `x{string.format("%.1f", predictedCombo)}`
	end
end

---------------------------------------------------------------------------------------
-- Training stance & rope jumps
---------------------------------------------------------------------------------------

local function setEngaged(value: boolean)
	if value then
		engagedUntil = os.clock() + RhythmConfig.EngagedTimeout
	end
	if engaged == value then
		return
	end
	engaged = value
	if not value then
		predictedCombo = RhythmConfig.ComboStart
		local parts = ring
		if parts then
			parts.Combo.Text = ""
			parts.Judge.Text = ""
		end
	end
	playJumpRopeLoop(value)
	RopeController.EngagedChanged:Fire(value)
end

local function beginBounce(pressTime: number, performJump: boolean)
	local hum = humanoid
	if hum == nil then
		return
	end
	if performJump then
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	local judgement = Rhythm.Judge(pressTime)
	local bounce: PendingBounce = {
		PressTime = pressTime,
		PressClock = os.clock(),
		PressJudgement = if judgement.OnBeat then judgement else nil,
		LeftGround = false,
	}
	pending = bounce
	setEngaged(true)

	if judgement.OnBeat then
		predictedCombo = Rhythm.NextCombo(predictedCombo, true)
		showJudgement(judgement, predictedCombo)
		RopeController.BounceJudged:Fire(judgement, predictedCombo)
	end
	SoundPlayer.Play("RopeWhoosh", rootPart, Rhythm.WhooshPitch(predictedCombo))
end

local function performRopeJump()
	local hum = humanoid
	if hum == nil or rootPart == nil or hum.Health <= 0 or pending ~= nil then
		return
	end
	local state = hum:GetState()
	if state == Enum.HumanoidStateType.Seated or state == Enum.HumanoidStateType.Dead then
		return
	end
	if not isGrounded() then
		return
	end
	beginBounce(workspace:GetServerTimeNow(), true)
end

-- Per-frame bounce tracking: takeoff, then raycast landing detection.
local function updateBounce()
	local bounce = pending
	local root = rootPart
	if bounce == nil or root == nil then
		return
	end
	local gap = groundGap()
	if gap == nil then
		pending = nil
		return
	end
	local elapsed = os.clock() - bounce.PressClock

	if not bounce.LeftGround then
		if gap >= TAKEOFF_GAP then
			bounce.LeftGround = true
		elseif elapsed > TAKEOFF_TIMEOUT then
			pending = nil -- the jump never happened (ceiling, seat, stun...)
		end
		return
	end

	if gap <= LANDED_GAP and root.AssemblyLinearVelocity.Y <= 1 then
		local landTime = workspace:GetServerTimeNow()
		pending = nil
		local judgement = bounce.PressJudgement
		if judgement == nil then
			-- The press missed; an on-beat landing still counts (Bible §2.1).
			local landJudgement = Rhythm.Judge(bounce.PressTime, landTime)
			predictedCombo = Rhythm.NextCombo(predictedCombo, landJudgement.OnBeat)
			showJudgement(landJudgement, predictedCombo)
			RopeController.BounceJudged:Fire(landJudgement, predictedCombo)
		end
		Remotes.ReportBounce:FireServer(bounce.PressTime, landTime)
	elseif elapsed > GameConfig.Training.MaxAirtime then
		pending = nil
	end
end

---------------------------------------------------------------------------------------
-- Combat
---------------------------------------------------------------------------------------

local function predictTargets(attack: GameConfig.AttackData, origin: Vector3, direction: Vector3): { number }
	local targets: { number } = {}
	local halfAngle = math.rad(attack.Shape.AngleDegrees / 2)
	for _, instance in CollectionService:GetTagged(Tags.ChronoMob) do
		if not instance:IsA("Model") or instance:GetAttribute("State") == "Dead" then
			continue
		end
		local mobId = instance:GetAttribute("MobId")
		local radius = instance:GetAttribute("HitRadius")
		if type(mobId) ~= "number" then
			continue
		end
		local hitRadius = if type(radius) == "number" then radius else 2
		local position = instance:GetPivot().Position
		local inside = if attack.Shape.Kind == "Circle"
			then Spatial.InRadius(origin, position, attack.Shape.Range, hitRadius, GameConfig.Combat.HeightTolerance)
			else Spatial.InCone(
				origin,
				direction,
				position,
				attack.Shape.Range,
				halfAngle,
				hitRadius,
				GameConfig.Combat.HeightTolerance
			)
		if inside then
			table.insert(targets, mobId)
			if #targets >= GameConfig.Combat.MaxTargetsPerAttack then
				break
			end
		end
	end
	return targets
end

local function performAttack()
	local hum = humanoid
	local root = rootPart
	if hum == nil or root == nil or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - lastAttackClock < attackCooldown then
		return
	end

	local kind: AttackKind = if isGrounded() then "GroundLash" else "AerialSweep"
	local attack = GameConfig.Combat.Attacks[kind]
	lastAttackClock = now
	attackCooldown = attack.Cooldown
	localAttack = kind
	localAttackAt = workspace:GetServerTimeNow()

	local direction = Spatial.FlatUnit(root.CFrame.LookVector)
	local targets = predictTargets(attack, root.Position, direction)
	Remotes.RequestAttack:FireServer(kind, direction, targets)

	local track = tracks[kind]
	if track then
		track:Play(0.05)
	end
	SoundPlayer.Play("RopeWhoosh", root, Rhythm.WhooshPitch(predictedCombo) * 0.9)
	RopeController.AttackPerformed:Fire(kind)
end

-- JUMP in Training, SWING in Combat (on-screen Action Button, ButtonR2).
function RopeController.PerformAction()
	if mode == "Combat" then
		performAttack()
	else
		performRopeJump()
	end
end

function RopeController.GetMode(): PlayerMode
	return mode
end

function RopeController.GetCombo(): number
	return predictedCombo
end

function RopeController.IsEngaged(): boolean
	return engaged
end

---------------------------------------------------------------------------------------
-- Rope rendering for every character
---------------------------------------------------------------------------------------

local function ropeStateOf(view: RopeView, serverNow: number): (string, number)
	if view.Owner == player then
		local attack = localAttack
		if attack and serverNow - localAttackAt < ATTACK_DURATION[attack] then
			return attack, localAttackAt
		end
		return if engaged then "Training" else "Idle", 0
	end
	local state = view.Character:GetAttribute("RopeState")
	local stateAt = view.Character:GetAttribute("RopeStateAt")
	local name = if type(state) == "string" then state else "Idle"
	local at = if type(stateAt) == "number" then stateAt else 0
	local duration = ATTACK_DURATION[name]
	if duration and serverNow - at >= duration then
		return "Idle", at
	end
	return name, at
end

local function comboOf(view: RopeView): number
	if view.Owner == player then
		return predictedCombo
	end
	local owner = view.Owner
	local combo = if owner then owner:GetAttribute("RhythmCombo") else nil
	return if type(combo) == "number" then combo else RhythmConfig.ComboStart
end

local function updateRope(view: RopeView, serverNow: number, cameraPosition: Vector3)
	local model = view.Character:FindFirstChild("ChronoRope")
	local root = view.Character:FindFirstChild("HumanoidRootPart")
	if model == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	if (root.Position - cameraPosition).Magnitude > ROPE_CULL_DISTANCE then
		return
	end
	local beam = model:FindFirstChild("RopeBeam")
	local handleR = model:FindFirstChild("HandleR")
	if beam == nil or not beam:IsA("Beam") or handleR == nil or not handleR:IsA("BasePart") then
		return
	end
	local attachment0 = beam.Attachment0
	local attachment1 = beam.Attachment1
	if attachment0 == nil or attachment1 == nil then
		return
	end

	local frame = root.CFrame
	local p0 = attachment0.WorldPosition
	local p3 = attachment1.WorldPosition
	local state, stateAt = ropeStateOf(view, serverNow)
	local elapsed = serverNow - stateAt

	local direction: Vector3
	local reach: number
	local active = true
	if state == "GroundLash" then
		local t = math.clamp(elapsed / ATTACK_DURATION.GroundLash, 0, 1)
		-- Swing from up-and-back over the head to forward-and-down: a downward whip.
		local swing = math.rad(130 - 165 * (1 - (1 - t) ^ 3))
		direction = frame.LookVector * math.cos(swing) + frame.UpVector * math.sin(swing)
		local range = GroundLashData.Shape.Range
		reach = math.max(1.5, range * math.sin(math.pi * math.min(1, t * 1.1)))
	elseif state == "AerialSweep" then
		local t = math.clamp(elapsed / ATTACK_DURATION.AerialSweep, 0, 1)
		local yaw = ProceduralPose.AirSweepYaw(t)
		direction = (frame * CFrame.Angles(0, yaw, 0)).RightVector
		local range = AerialSweepData.Shape.Range
		reach = math.max(2, range * math.sin(math.pi * math.min(1, t * 1.05)))
	elseif state == "Training" then
		local angle = Rhythm.RopeAngle(serverNow)
		direction = -frame.UpVector * math.cos(angle) + -frame.LookVector * math.sin(angle)
		reach = 3.3
	else
		direction = (-frame.UpVector + frame.LookVector * 0.35).Unit
		reach = 1.6
		active = false
	end

	local offset = direction * (reach / BEZIER_APEX_FACTOR)
	local p1 = p0 + offset
	local p2 = p3 + offset
	BeamCurve.Apply(beam, attachment0, attachment1, p0, p1, p2, p3)

	-- Rope-tip trail follows the apex of the curve.
	local tipA = handleR:FindFirstChild("TipA")
	local tipB = handleR:FindFirstChild("TipB")
	if tipA and tipA:IsA("Attachment") and tipB and tipB:IsA("Attachment") then
		local apex = BeamCurve.Point(p0, p1, p2, p3, 0.5)
		local span = p3 - p0
		local tangent = if span.Magnitude > 1e-3 then span.Unit * 0.35 else Vector3.xAxis * 0.35
		tipA.Position = handleR.CFrame:PointToObjectSpace(apex - tangent)
		tipB.Position = handleR.CFrame:PointToObjectSpace(apex + tangent)
	end

	-- Trails: on while the rope is moving, coloured by the owner's combo tier; the
	-- high-tension sparks join in from the Gold tier upwards.
	local tierIndex = Rhythm.TierIndex(comboOf(view))
	if active ~= view.TrailsOn or tierIndex ~= view.TierIndex then
		view.TrailsOn = active
		view.TierIndex = tierIndex
		local color = ColorSequence.new(RhythmConfig.ComboTiers[tierIndex].Color)
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Trail") then
				descendant.Enabled = active
				descendant.Color = color
			elseif descendant:IsA("ParticleEmitter") and descendant.Name == "TensionSparks" then
				descendant.Enabled = active and tierIndex >= SPARK_MIN_TIER
				descendant.Color = color
				descendant.Rate = 25 * tierIndex
			end
		end
	end
end

local function applyPose(view: RopeView, serverNow: number)
	local state, stateAt = ropeStateOf(view, serverNow)
	local animations = GameConfig.Animations
	if state == "Training" and animations.JumpRopeLoop == "" then
		ProceduralPose.JumpRope(view.Joints, Rhythm.RopeAngle(serverNow))
	elseif state == "GroundLash" and animations.GroundLashAttack == "" then
		ProceduralPose.GroundLash(view.Joints, (serverNow - stateAt) / ATTACK_DURATION.GroundLash)
	elseif state == "AerialSweep" and animations.AirSweepAttack == "" then
		ProceduralPose.AirSweep(view.Joints, (serverNow - stateAt) / ATTACK_DURATION.AerialSweep)
	end
end

local function trackRope(model: Model, owner: Player?)
	ropeViews[model] = {
		Character = model,
		Owner = owner,
		Joints = ProceduralPose.FindJoints(model),
		TierIndex = 0,
		TrailsOn = true, -- forces the first colour/enable pass
	}
	-- Joints are created by the avatar loader after CharacterAdded; refresh once loaded.
	task.delay(1, function()
		local view = ropeViews[model]
		if view then
			view.Joints = ProceduralPose.FindJoints(model)
		end
	end)
	model.AncestryChanged:Connect(function()
		if model.Parent == nil then
			ropeViews[model] = nil
		end
	end)
end

local function watchPlayer(other: Player)
	if other.Character then
		trackRope(other.Character, other)
	end
	other.CharacterAdded:Connect(function(model: Model)
		trackRope(model, other)
	end)
end

---------------------------------------------------------------------------------------
-- Local character
---------------------------------------------------------------------------------------

local function onCharacterAdded(model: Model)
	characterTrove:Clean()
	pending = nil
	setEngaged(false)

	local hum = model:WaitForChild("Humanoid", 10)
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if player.Character ~= model then
		return -- respawned while we were waiting
	end
	if hum == nil or root == nil or not hum:IsA("Humanoid") or not root:IsA("BasePart") then
		return
	end
	humanoid = hum
	rootPart = root
	rayParams.FilterDescendantsInstances = { model }
	loadTracks(hum)

	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	buildRing(if torso and torso:IsA("BasePart") then torso else root)

	characterTrove:Connect(hum.StateChanged, function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		-- Fallback: any jump in Training mode is a bounce, however it was triggered.
		if new == Enum.HumanoidStateType.Jumping and mode == "Training" and pending == nil then
			beginBounce(workspace:GetServerTimeNow(), false)
		end
	end)
	characterTrove:Connect(hum.Died, function()
		pending = nil
		setEngaged(false)
	end)
end

local function updateMode()
	local root = rootPart
	if root == nil then
		return
	end
	local current: PlayerMode = Zones.ModeAt(root.Position)
	if current ~= mode then
		mode = current
		pending = nil
		setEngaged(false)
		RopeController.ModeChanged:Fire(current)
	end
end

---------------------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------------------

local function onJumpAction(_: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if mode ~= "Training" then
		return Enum.ContextActionResult.Pass -- regular jumping in combat zones
	end
	if state == Enum.UserInputState.Begin then
		performRopeJump()
	end
	return Enum.ContextActionResult.Sink
end

local function onSwingAction(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if mode == "Combat" then
		performAttack()
		return Enum.ContextActionResult.Sink
	end
	if input.KeyCode == Enum.KeyCode.ButtonR2 then
		performRopeJump()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass -- left click stays free for the camera/UI in Training
end

---------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------

function RopeController.Init()
	Remotes.BounceResult.OnClientEvent:Connect(function(result: BounceResult)
		if type(result) ~= "table" or type(result.Combo) ~= "number" then
			return
		end
		-- Server combo is authoritative. If a newer press was already judged on-beat
		-- locally, keep that bounce's prediction on top of the confirmed value.
		local bounce = pending
		if bounce and bounce.PressJudgement then
			predictedCombo = Rhythm.NextCombo(result.Combo, true)
		else
			predictedCombo = result.Combo
		end
		RopeController.BounceConfirmed:Fire(result)
	end)

	Remotes.AttackFx.OnClientEvent:Connect(
		function(userId: number, _kind: string, _direction: Vector3, hitPosition: Vector3?)
			if userId == player.UserId then
				return
			end
			local other = Players:GetPlayerByUserId(userId)
			local otherCharacter = other and other.Character
			local otherRoot = otherCharacter and otherCharacter:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				SoundPlayer.Play("RopeWhoosh", otherRoot, 1, 0.7)
			end
			if typeof(hitPosition) == "Vector3" then
				SoundPlayer.PlayAt("WhipCrack", hitPosition)
			end
		end
	)
end

function RopeController.Start()
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	ContextActionService:BindActionAtPriority(
		ACTION_JUMP,
		onJumpAction,
		false,
		ACTION_PRIORITY,
		Enum.KeyCode.Space,
		Enum.KeyCode.ButtonA
	)
	ContextActionService:BindActionAtPriority(
		ACTION_SWING,
		onSwingAction,
		false,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
	UserInputService.JumpRequest:Connect(function()
		if mode == "Training" then
			performRopeJump() -- mobile jump button
		end
	end)

	RunService.Heartbeat:Connect(function()
		updateMode()
		updateBounce()
		if engaged and pending == nil and os.clock() > engagedUntil then
			setEngaged(false)
		end
	end)

	RunService.PreSimulation:Connect(function()
		local serverNow = workspace:GetServerTimeNow()
		for _, view in ropeViews do
			applyPose(view, serverNow)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local serverNow = workspace:GetServerTimeNow()
		local camera = workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		for _, view in ropeViews do
			updateRope(view, serverNow, cameraPosition)
		end
		updateRing(serverNow)
	end)

	ClientState.Changed:Connect(function(key: string)
		if key == "RhythmCombo" and pending == nil and not engaged then
			predictedCombo = ClientState.Combo()
		end
	end)
end

return RopeController
