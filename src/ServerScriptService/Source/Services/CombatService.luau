--!strict
--[[
	CombatService
	=============
	Validates and resolves rope attacks (Bible §2.1 damage, §6 anti-exploit).

	RequestAttack(attack, direction, targetIds) is a *claim* from the client's local hit
	prediction. The server trusts none of it:

	  1. Rate limit and strict payload validation (known attack kind, finite direction,
	     a short list of unique integer ids).
	  2. Cooldowns: an attack is rejected if it arrives before the previous attack's
	     cooldown elapsed (with a small jitter allowance).
	  3. Air vs ground: Aerial Sweep requires the server to have seen the player
	     airborne within a short grace window; Ground Lash requires recent ground contact.
	  4. Facing: the claimed aim must roughly match the character's actual facing.
	  5. Per target: the mob must exist, be alive, be within 16 studs (edge distance)
	     and inside the attack volume (Ground Lash 14-stud 45-degree cone, Aerial Sweep
	     12-stud radial shockwave) plus a latency tolerance.

	DMG = ((TotalStrength ^ 0.65) + RopeBaseDamage) * PetMultiplierSum
	      * (1.0 Ground Lash | 0.75 Aerial Sweep) * (1 + Paradox Edge bonus)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Formulas = require(Source.Shared.Formulas)
local Guard = require(Source.Shared.Guard)
local Spatial = require(Source.Shared.Spatial)
local Remotes = require(Source.Network.Remotes)

local DataService = require(script.Parent.DataService)
local MobService = require(script.Parent.MobService)

local Modules = script.Parent.Parent.Modules
local GroundTracker = require(Modules.GroundTracker)
local RateLimiter = require(Modules.RateLimiter)
local Security = require(Modules.Security)

type AttackKind = GameConfig.AttackKind
type HitReport = Remotes.HitReport

local ATTACK_KINDS = { "GroundLash", "AerialSweep" }
local MAX_FACING_ANGLE = math.rad(80)
local MAX_MOB_ID = 2 ^ 31

local CombatConfig = GameConfig.Combat

local CombatService = {}

local lastAttack: { [Player]: { At: number, Cooldown: number } } = {}
local attackLimiter = RateLimiter.new(
	GameConfig.Security.RateLimits.RequestAttack.Capacity,
	GameConfig.Security.RateLimits.RequestAttack.RefillPerSecond
)

local function inAttackVolume(
	attack: GameConfig.AttackData,
	origin: Vector3,
	direction: Vector3,
	targetPosition: Vector3,
	targetRadius: number
): boolean
	local reach = CombatConfig.MaxValidationDistance
	if attack.Shape.Kind == "Circle" then
		return Spatial.InRadius(origin, targetPosition, reach, targetRadius, CombatConfig.HeightTolerance)
	end
	local halfAngle = math.rad(attack.Shape.AngleDegrees / 2 + CombatConfig.AngleToleranceDegrees)
	return Spatial.InCone(
		origin,
		direction,
		targetPosition,
		reach,
		halfAngle,
		targetRadius,
		CombatConfig.HeightTolerance
	)
end

local function onRequestAttack(player: Player, rawKind: unknown, rawDirection: unknown, rawTargets: unknown)
	if not attackLimiter:Allow(player) then
		Security.Strike(player, "RequestAttack rate limit")
		return
	end

	-- 1. Payload validation.
	local kindName = Guard.OneOf(rawKind, ATTACK_KINDS)
	local direction = Guard.Direction(rawDirection)
	local targetIds = Guard.IntegerList(rawTargets, CombatConfig.MaxTargetsPerAttack, 1, MAX_MOB_ID)
	if kindName == nil or direction == nil or targetIds == nil then
		Security.Strike(player, "RequestAttack malformed payload", 2)
		return
	end
	local kind: AttackKind = if kindName == "AerialSweep" then "AerialSweep" else "GroundLash"
	local attack = CombatConfig.Attacks[kind]

	local data = DataService.GetData(player)
	local character = player.Character
	if data == nil or character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return
	end

	-- 2. Cooldown (server clock; a little early is tolerated for network jitter).
	local now = os.clock()
	local previous = lastAttack[player]
	if previous and now - previous.At < previous.Cooldown * CombatConfig.CooldownTolerance then
		Security.Strike(player, "attack cooldown bypass", 0.5)
		return
	end

	-- 3. Air vs ground.
	GroundTracker.SampleNow(player)
	if attack.RequiresAirborne then
		if not GroundTracker.WasAirborneWithin(player, CombatConfig.AirborneGraceSeconds) then
			return
		end
	elseif not GroundTracker.WasGroundedWithin(player, CombatConfig.AirborneGraceSeconds) then
		return
	end

	-- 4. Facing: the aim must roughly match where the character actually faces.
	local flatAim = Spatial.FlatUnit(direction, root.CFrame.LookVector)
	local facing = Spatial.FlatUnit(root.CFrame.LookVector)
	if attack.Shape.Kind == "Cone" and math.acos(math.clamp(flatAim:Dot(facing), -1, 1)) > MAX_FACING_ANGLE then
		Security.Strike(player, "attack aim does not match facing", 0.5)
		return
	end

	lastAttack[player] = { At = now, Cooldown = attack.Cooldown }

	character:SetAttribute("RopeState", kind)
	character:SetAttribute("RopeStateAt", workspace:GetServerTimeNow())

	-- 5. Per-target validation + damage.
	local damage = Formulas.AttackDamage(data, kind)
	local origin = root.Position
	local hits: { HitReport } = {}
	for _, mobId in targetIds do
		local mob = MobService.GetMob(mobId)
		if mob == nil then
			continue
		end
		local mobPosition = MobService.GetPosition(mob)
		local edgeDistance = (mobPosition - origin).Magnitude - mob.Data.HitRadius
		if edgeDistance > CombatConfig.MaxValidationDistance then
			Security.Strike(player, `target {edgeDistance} studs away`, 0.25)
			continue
		end
		if not inAttackVolume(attack, origin, flatAim, mobPosition, mob.Data.HitRadius) then
			continue
		end
		local _, killed = MobService.ApplyDamage(mobId, player, damage)
		table.insert(hits, {
			MobId = mobId,
			Damage = damage,
			Killed = killed,
			Position = mobPosition,
		})
	end

	if #hits > 0 then
		Remotes.CombatFeedback:FireClient(player, hits)
	end
	-- Cosmetic broadcast: other clients play the swing, whoosh and (on a hit) the
	-- spatial whip crack where the rope landed.
	Remotes.AttackFx:FireAllClients(player.UserId, kind, flatAim, if #hits > 0 then hits[1].Position else nil)
end

function CombatService.Init()
	Remotes.RequestAttack.OnServerEvent:Connect(onRequestAttack)
end

function CombatService.Start()
	GroundTracker.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		lastAttack[player] = nil
		attackLimiter:Reset(player)
	end)
end

return CombatService
