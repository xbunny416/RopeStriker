--!strict
--[[
	GroundTracker
	-------------
	Server-side observation of every character's grounded/airborne state, sampled at
	15 Hz with downward raycasts. It is the server's independent evidence for:

	  * TrainingService - each reported rope bounce must be backed by a takeoff the
	    server actually saw (jump credits), so remote spam cannot farm KP.
	  * CombatService   - Aerial Sweep requires being airborne and Ground Lash requires
	    being grounded, with a short grace window to absorb replication latency.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Source.Configuration.GameConfig)

type Track = {
	Character: Model?,
	Params: RaycastParams,
	Airborne: boolean,
	LastAirborneAt: number,
	LastGroundedAt: number,
	Credits: number,
}

local SAMPLE_INTERVAL = 1 / 15
local AIRBORNE_GAP = 1.0 -- studs above standing height => airborne
local GROUNDED_GAP = 0.5 -- studs above standing height => grounded (hysteresis)
local PROBE_EXTRA = 8

local GroundTracker = {}

local tracks: { [Player]: Track } = {}
local started = false

-- Distance between the character's feet and the ground below it (0 when standing).
function GroundTracker.GroundGap(character: Model, params: RaycastParams): number?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	local legHeight = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	local standHeight = legHeight + root.Size.Y * 0.5
	local result = workspace:Raycast(root.Position, Vector3.new(0, -(standHeight + PROBE_EXTRA), 0), params)
	if result == nil then
		return math.huge
	end
	return (root.Position.Y - result.Position.Y) - standHeight
end

local function getTrack(player: Player): Track?
	local track = tracks[player]
	local character = player.Character
	if character == nil then
		return track
	end
	if track == nil then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		local created: Track = {
			Character = nil,
			Params = params,
			Airborne = false,
			LastAirborneAt = -math.huge,
			LastGroundedAt = os.clock(),
			Credits = 0,
		}
		tracks[player] = created
		track = created
	end
	local current = track :: Track
	if current.Character ~= character then
		current.Character = character
		current.Params.FilterDescendantsInstances = { character }
		current.Airborne = false
		current.Credits = 0
		current.LastGroundedAt = os.clock()
	end
	return current
end

function GroundTracker.SampleNow(player: Player)
	local track = getTrack(player)
	if track == nil or track.Character == nil then
		return
	end
	local gap = GroundTracker.GroundGap(track.Character, track.Params)
	if gap == nil then
		return
	end
	local now = os.clock()
	if track.Airborne then
		if gap <= GROUNDED_GAP then
			track.Airborne = false
			track.LastGroundedAt = now
		else
			track.LastAirborneAt = now
		end
	else
		if gap >= AIRBORNE_GAP then
			track.Airborne = true
			track.LastAirborneAt = now
			-- A fresh takeoff the server witnessed: one rope bounce may be claimed for it.
			track.Credits = math.min(track.Credits + 1, GameConfig.Training.JumpCreditCap)
		else
			track.LastGroundedAt = now
		end
	end
end

function GroundTracker.IsAirborne(player: Player): boolean
	local track = tracks[player]
	return track ~= nil and track.Airborne
end

function GroundTracker.WasAirborneWithin(player: Player, seconds: number): boolean
	local track = tracks[player]
	if track == nil then
		return false
	end
	return track.Airborne or os.clock() - track.LastAirborneAt <= seconds
end

function GroundTracker.WasGroundedWithin(player: Player, seconds: number): boolean
	local track = tracks[player]
	if track == nil then
		return true -- no evidence either way: do not block grounded actions
	end
	return not track.Airborne or os.clock() - track.LastGroundedAt <= seconds
end

-- Spends one witnessed takeoff. False when the server never saw the player jump.
function GroundTracker.ConsumeJumpCredit(player: Player): boolean
	local track = tracks[player]
	if track == nil or track.Credits <= 0 then
		return false
	end
	track.Credits -= 1
	return true
end

function GroundTracker.Start()
	if started then
		return
	end
	started = true

	local accumulator = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator < SAMPLE_INTERVAL then
			return
		end
		accumulator = 0
		for _, player in Players:GetPlayers() do
			GroundTracker.SampleNow(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		tracks[player] = nil
	end)
end

return GroundTracker
