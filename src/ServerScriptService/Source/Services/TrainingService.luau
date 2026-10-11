--!strict
--[[
	TrainingService
	===============
	Server authority for Training Mode (Bible §2.1).

	Bounce pipeline (client RopeController -> ReportBounce(pressTime, landTime)):
	  1. Rate limit + payload validation (finite numbers only).
	  2. Timing plausibility on the synchronised clock: landing not in the future, not
	     stale, airtime physically possible, bounces cannot overlap.
	  3. Physical evidence: GroundTracker must have witnessed a takeoff (jump credit),
	     so firing the remote without actually jumping earns nothing.
	  4. Zone: training only outside combat zones.
	  5. Re-judge the timestamps against the shared beat clock (press OR landing within
	     0.15s of a beat), update the authoritative combo (+0.1x, cap 2.5x, miss resets),
	     award KP_gain = BaseRopeKP * BootMultiplier * PetMultiplierSum * Combo (* rebirth
	     & skill multipliers) up to Stamina Capacity, and report the result back.

	Banking: the Epoch Obelisk's ProximityPrompt, or stepping onto its glowing pedestal,
	converts all unbanked KP into TotalStrength (DataService.BankPower).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Formulas = require(Source.Shared.Formulas)
local Guard = require(Source.Shared.Guard)
local Rhythm = require(Source.Shared.Rhythm)
local Spatial = require(Source.Shared.Spatial)
local Tags = require(Source.Shared.Tags)
local Zones = require(Source.Shared.Zones)
local Remotes = require(Source.Network.Remotes)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local Modules = script.Parent.Parent.Modules
local GroundTracker = require(Modules.GroundTracker)
local RateLimiter = require(Modules.RateLimiter)
local Security = require(Modules.Security)

type BounceResult = Remotes.BounceResult

type TrainingState = {
	Combo: number,
	LastLandTime: number, -- server time of the last accepted landing
	Engaged: boolean,
	EngagedUntil: number,
	LastBankAt: number,
	OnPedestal: boolean,
}

local TICK_INTERVAL = 0.2
local PEDESTAL_HEIGHT_RANGE = 7

local Training = GameConfig.Training
local RhythmConfig = GameConfig.Rhythm

local TrainingService = {}

local states: { [Player]: TrainingState } = {}
local bounceLimiter = RateLimiter.new(
	GameConfig.Security.RateLimits.ReportBounce.Capacity,
	GameConfig.Security.RateLimits.ReportBounce.RefillPerSecond
)

local function getState(player: Player): TrainingState
	local state = states[player]
	if state == nil then
		local created: TrainingState = {
			Combo = RhythmConfig.ComboStart,
			LastLandTime = -math.huge,
			Engaged = false,
			EngagedUntil = 0,
			LastBankAt = -math.huge,
			OnPedestal = false,
		}
		states[player] = created
		return created
	end
	return state
end

local function getRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if character == nil then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return root, humanoid
end

local function setCombo(player: Player, state: TrainingState, combo: number)
	state.Combo = combo
	player:SetAttribute("RhythmCombo", combo)
end

-- Character attribute other clients read to animate this player's rope.
local function setRopeState(player: Player, ropeState: string)
	local character = player.Character
	if character then
		character:SetAttribute("RopeState", ropeState)
		character:SetAttribute("RopeStateAt", workspace:GetServerTimeNow())
	end
end

local function respond(player: Player, result: BounceResult)
	Remotes.BounceResult:FireClient(player, result)
end

local function reject(player: Player, state: TrainingState, reason: string)
	respond(player, {
		Accepted = false,
		OnBeat = false,
		Combo = state.Combo,
		Gained = 0,
		Capped = false,
		Reason = reason,
	})
end

---------------------------------------------------------------------------------------
-- Bounces
---------------------------------------------------------------------------------------

local function onReportBounce(player: Player, rawPress: unknown, rawLand: unknown)
	if not bounceLimiter:Allow(player) then
		Security.Strike(player, "ReportBounce rate limit")
		return
	end
	local pressTime = Guard.Number(rawPress)
	local landTime = Guard.Number(rawLand)
	if pressTime == nil or landTime == nil then
		Security.Strike(player, "ReportBounce malformed payload", 2)
		return
	end

	local data = DataService.GetData(player)
	local root = getRoot(player)
	if data == nil or root == nil then
		return
	end
	local state = getState(player)

	-- 2. Timing plausibility on the synchronised server clock.
	local now = workspace:GetServerTimeNow()
	local airtime = landTime - pressTime
	if airtime < Training.MinAirtime or airtime > Training.MaxAirtime then
		Security.Strike(player, `impossible airtime {airtime}`)
		reject(player, state, "Timing")
		return
	end
	if landTime > now + Training.MaxFutureSkew or now - landTime > Training.MaxReportAge then
		reject(player, state, "Stale")
		return
	end
	if pressTime < state.LastLandTime - 0.05 then
		Security.Strike(player, "overlapping bounces")
		reject(player, state, "Timing")
		return
	end
	-- Spacing is judged on the reported (synchronised) timestamps, not on arrival times,
	-- so network jitter bunching two honest reports together cannot reject one.
	if landTime - state.LastLandTime < Training.MinBounceInterval then
		reject(player, state, "TooFast")
		return
	end

	-- 3. Zone: no training inside the Colosseum.
	if Zones.ModeAt(root.Position) ~= "Training" then
		reject(player, state, "Zone")
		return
	end

	-- 4. The server must have seen the jump happen.
	GroundTracker.SampleNow(player)
	if not GroundTracker.ConsumeJumpCredit(player) then
		Security.Strike(player, "bounce without witnessed takeoff", 0.5)
		reject(player, state, "Unverified")
		return
	end

	-- 5. Authoritative judgement + reward.
	state.LastLandTime = landTime
	state.Engaged = true
	state.EngagedUntil = os.clock() + RhythmConfig.EngagedTimeout

	local judgement = Rhythm.Judge(pressTime, landTime)
	local combo = Rhythm.NextCombo(state.Combo, judgement.OnBeat)
	setCombo(player, state, combo)

	local gain = Formulas.KPPerBounce(data, combo)
	local added, capped = DataService.AddKP(player, gain)
	DataService.RecordBounce(player, judgement.OnBeat, combo)
	setRopeState(player, "Training")

	if combo >= RhythmConfig.ComboCap and DataService.GrantTitle(player, "RhythmMaster") then
		DataService.Notify(player, "Title", "Title unlocked: Rhythm Master!")
	end

	respond(player, {
		Accepted = true,
		OnBeat = judgement.OnBeat,
		Combo = combo,
		Gained = added,
		Capped = capped,
		Reason = nil,
	})
end

---------------------------------------------------------------------------------------
-- Banking
---------------------------------------------------------------------------------------

local function bank(player: Player, fromPrompt: boolean)
	local state = getState(player)
	local now = os.clock()
	if now - state.LastBankAt < Training.BankCooldown then
		return
	end
	local root = getRoot(player)
	if root == nil then
		return
	end
	if WorldService.DistanceToNearestObelisk(root.Position) > Training.ObeliskValidationDistance then
		Security.Strike(player, "banking far from an obelisk")
		return
	end
	state.LastBankAt = now

	local amount = DataService.BankPower(player)
	if amount > 0 then
		local data = DataService.GetData(player)
		Remotes.Banked:FireClient(player, amount, if data then data.TotalStrength else 0)
	elseif fromPrompt then
		DataService.Notify(player, "Info", "Nothing to bank yet - jump rope on the beat to build Kinetic Power!")
	end
end

local function connectObelisk(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("ProximityPrompt") and descendant.Name == "BankPrompt" then
			descendant.Triggered:Connect(function(player: Player)
				bank(player, true)
			end)
		end
	end
end

local function isOnPedestal(position: Vector3, pedestals: { BasePart }): boolean
	for _, pedestal in pedestals do
		-- Pedestals are cylinders lying on their X axis: diameter = Size.Y.
		local radius = pedestal.Size.Y / 2
		local top = pedestal.Position.Y + pedestal.Size.X / 2
		local height = position.Y - top
		if height >= -1 and height <= PEDESTAL_HEIGHT_RANGE then
			if Spatial.HorizontalDistance(position, pedestal.Position) <= radius + 0.5 then
				return true
			end
		end
	end
	return false
end

local function tick()
	local pedestals = WorldService.GetPedestals()
	local clock = os.clock()
	for _, player in Players:GetPlayers() do
		local state = states[player]
		if state == nil then
			continue
		end

		if state.Engaged and clock > state.EngagedUntil then
			-- Stopped bouncing: the stance drops and the rhythm streak is lost.
			state.Engaged = false
			setCombo(player, state, RhythmConfig.ComboStart)
			setRopeState(player, "Idle")
		end

		local root = getRoot(player)
		local onPedestal = root ~= nil and isOnPedestal(root.Position, pedestals)
		if onPedestal and not state.OnPedestal then
			bank(player, false) -- stepping onto the glowing pedestal banks automatically
		end
		state.OnPedestal = onPedestal
	end
end

---------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------

function TrainingService.GetCombo(player: Player): number
	local state = states[player]
	return if state then state.Combo else RhythmConfig.ComboStart
end

function TrainingService.ResetCombo(player: Player)
	local state = getState(player)
	state.Engaged = false
	setCombo(player, state, RhythmConfig.ComboStart)
end

function TrainingService.Init()
	Remotes.ReportBounce.OnServerEvent:Connect(onReportBounce)
end

function TrainingService.Start()
	GroundTracker.Start()

	for _, obelisk in CollectionService:GetTagged(Tags.EpochObelisk) do
		connectObelisk(obelisk)
	end
	CollectionService:GetInstanceAddedSignal(Tags.EpochObelisk):Connect(connectObelisk)

	local function onCharacter(player: Player)
		local state = getState(player)
		state.Engaged = false
		state.LastLandTime = -math.huge
		setCombo(player, state, RhythmConfig.ComboStart)
		setRopeState(player, "Idle")
	end
	local function onPlayer(player: Player)
		getState(player)
		player:SetAttribute("RhythmCombo", RhythmConfig.ComboStart)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		if player.Character then
			onCharacter(player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
		bounceLimiter:Reset(player)
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator >= TICK_INTERVAL then
			accumulator = 0
			tick()
		end
	end)
end

return TrainingService
