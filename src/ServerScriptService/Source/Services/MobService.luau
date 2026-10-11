--!strict
--[[
	MobService
	==========
	Server-side world mobs for the Grand Colosseum (Bible §3.2 + §6).

	  * Spawners: 4x Roman Legionary (8s respawn, 250 HP), 2x Centurion Elite (20s,
	    1,200 HP), 1x Gladiator Primus on the central dais (60s, 10,000 HP).
	  * AI: every 0.1s each mob perceives the arena and steps its MobBrain state machine
	    (Idle, Chase, Telegraph, Attack, Return). Telegraphs lock the attack area at
	    wind-up start, publish it through model attributes (clients draw the red ground
	    decal for 0.8s) and the strike hits whoever is still inside the locked area.
	  * Shared health: one HP pool per mob, damage credited per player in a DamageLedger
	    (overkill never credited). On death every player with >= 5% of max HP dealt is
	    paid BaseMobShards * share * RebirthMultiplier and rolls the bonus drop table.

	Health is authoritative here; the Humanoid only provides locomotion. Mob physics is
	owned by the server so clients cannot teleport, fling or freeze mobs.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Formulas = require(Source.Shared.Formulas)
local Signal = require(Source.Shared.Signal)
local Spatial = require(Source.Shared.Spatial)
local Tags = require(Source.Shared.Tags)
local Zones = require(Source.Shared.Zones)
local Remotes = require(Source.Network.Remotes)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

local Modules = script.Parent.Parent.Modules
local DamageLedger = require(Modules.DamageLedger)
local MobBrain = require(Modules.MobBrain)
local MobFactory = require(script.Parent.Parent.World.MobFactory)

type MobData = GameConfig.MobData
type MobAttackData = GameConfig.MobAttackData
type SpawnerData = GameConfig.SpawnerData
type RewardReport = Remotes.RewardReport

export type MobRecord = {
	Id: number,
	Data: MobData,
	Spawner: SpawnerData,
	Home: Vector3,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Health: number,
	Alive: boolean,
	Ledger: DamageLedger.Ledger,
	Brain: MobBrain.Brain,
	Target: Player?,
	LastAttacker: Player?,
	LastAttackerAt: number,
	LastMoveTarget: Vector3?,
	LastMoveAt: number,
	LockedOrigin: Vector3?,
	LockedDirection: Vector3?,
	TelegraphTrack: AnimationTrack?,
}

local AI_INTERVAL = 0.1
local CORPSE_SECONDS = 1.6
local MOVE_REFRESH_DISTANCE = 2
local MOVE_REFRESH_SECONDS = 0.5
local PLAYER_RADIUS = 1.5
local STRIKE_HEIGHT_TOLERANCE = 8
local AGGRO_MEMORY_SECONDS = 6
-- Players at the gate (just outside the wall line) can still be targeted, so nobody
-- can chip at mobs from a spot where the mobs cannot fight back.
local ARENA_TARGET_PADDING = 12
local FALL_LIMIT_Y = -40

local MobService = {}

MobService.MobDied = Signal.new() :: Signal.Signal<MobRecord, { DamageLedger.Payout }>

local mobs: { [number]: MobRecord } = {}
local nextMobId = 0
local mobFolder: Folder? = nil
local random = Random.new()

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function livingRoot(player: Player): (BasePart?, Humanoid?)
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

local function moveTo(record: MobRecord, position: Vector3, now: number)
	local last = record.LastMoveTarget
	if
		last ~= nil
		and (last - position).Magnitude < MOVE_REFRESH_DISTANCE
		and now - record.LastMoveAt < MOVE_REFRESH_SECONDS
	then
		return
	end
	record.LastMoveTarget = position
	record.LastMoveAt = now
	record.Humanoid:MoveTo(position)
end

local function hold(record: MobRecord)
	if record.LastMoveTarget ~= nil then
		record.LastMoveTarget = nil
		record.Humanoid:MoveTo(record.Root.Position)
	end
end

local function face(record: MobRecord, position: Vector3)
	local root = record.Root
	local direction = Spatial.FlatUnit(position - root.Position, root.CFrame.LookVector)
	if root.CFrame.LookVector:Dot(direction) < 0.94 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	end
end

-- Nearest valid player in the arena, with sticky aggro on the current target and
-- on whoever hit the mob recently.
local function findTarget(record: MobRecord): (Player?, Vector3?)
	local data = record.Data
	local position = record.Root.Position
	local now = os.clock()
	local bestPlayer: Player? = nil
	local bestPosition: Vector3? = nil
	local bestScore = math.huge

	for _, player in Players:GetPlayers() do
		local root = livingRoot(player)
		if root == nil then
			continue
		end
		local targetPosition = root.Position
		if not Zones.IsInColosseum(targetPosition, ARENA_TARGET_PADDING) then
			continue
		end
		if Spatial.HorizontalDistance(targetPosition, record.Home) > data.LeashRange + data.AttackRange then
			continue
		end
		local recentAttacker = player == record.LastAttacker and now - record.LastAttackerAt < AGGRO_MEMORY_SECONDS
		local range = if recentAttacker then data.AggroRange * 1.5 else data.AggroRange
		local distance = Spatial.HorizontalDistance(position, targetPosition)
		if distance > range then
			continue
		end
		local score = distance
		if player == record.Target then
			score -= 6
		end
		if recentAttacker then
			score -= 10
		end
		if score < bestScore then
			bestScore = score
			bestPlayer = player
			bestPosition = targetPosition
		end
	end
	return bestPlayer, bestPosition
end

local function floorBelow(record: MobRecord): number
	return record.Root.Position.Y - (record.Humanoid.HipHeight + record.Root.Size.Y / 2)
end

local function playTelegraphAnimation(record: MobRecord)
	local animationId = GameConfig.Animations.MobTelegraphSlash
	if animationId == "" then
		return -- clients animate the procedural WeaponShoulder instead
	end
	local track = record.TelegraphTrack
	if track == nil then
		local animator = record.Humanoid:FindFirstChildOfClass("Animator")
		if animator == nil then
			return
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local loaded = animator:LoadAnimation(animation)
		record.TelegraphTrack = loaded
		track = loaded
	end
	if track then
		track:Play(0.1)
	end
end

---------------------------------------------------------------------------------------
-- Attacks
---------------------------------------------------------------------------------------

local function beginTelegraph(record: MobRecord, attack: MobAttackData, targetPosition: Vector3)
	local root = record.Root
	hold(record)
	record.Humanoid.WalkSpeed = 0
	record.Humanoid.AutoRotate = false

	local origin = root.Position
	local direction = Spatial.FlatUnit(targetPosition - origin, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(origin, origin + direction)

	-- Lock the impact area now: dodging during the 0.8s wind-up is the counterplay.
	local groundOrigin = Vector3.new(origin.X, floorBelow(record), origin.Z)
	record.LockedOrigin = groundOrigin
	record.LockedDirection = direction

	local serverNow = workspace:GetServerTimeNow()
	local model = record.Model
	model:SetAttribute("AttackId", attack.Id)
	model:SetAttribute("AttackName", attack.DisplayName)
	model:SetAttribute("TelegraphShape", attack.Shape.Kind)
	model:SetAttribute("TelegraphRange", attack.Shape.Range)
	model:SetAttribute("TelegraphAngle", attack.Shape.AngleDegrees)
	model:SetAttribute("TelegraphOrigin", groundOrigin)
	model:SetAttribute("TelegraphDirection", direction)
	model:SetAttribute("TelegraphEnd", serverNow + attack.TelegraphSeconds)
	model:SetAttribute("TelegraphStart", serverNow) -- written last: clients key off it
	playTelegraphAnimation(record)
end

local function strike(record: MobRecord, attack: MobAttackData)
	local origin = record.LockedOrigin
	local direction = record.LockedDirection
	if origin == nil or direction == nil then
		return
	end
	local shape = attack.Shape
	local halfAngle = math.rad(shape.AngleDegrees / 2)
	local strikeOrigin = origin + Vector3.new(0, 3, 0) -- roughly torso height

	for _, player in Players:GetPlayers() do
		local root, humanoid = livingRoot(player)
		if root == nil or humanoid == nil then
			continue
		end
		local hit = if shape.Kind == "Circle"
			then Spatial.InRadius(strikeOrigin, root.Position, shape.Range, PLAYER_RADIUS, STRIKE_HEIGHT_TOLERANCE)
			else Spatial.InCone(
				strikeOrigin,
				direction,
				root.Position,
				shape.Range,
				halfAngle,
				PLAYER_RADIUS,
				STRIKE_HEIGHT_TOLERANCE
			)
		if hit then
			humanoid:TakeDamage(attack.Damage) -- respects spawn ForceFields
		end
	end

	record.Model:SetAttribute("LastStrikeAt", workspace:GetServerTimeNow())
	record.LockedOrigin = nil
	record.LockedDirection = nil
end

---------------------------------------------------------------------------------------
-- Rewards & death
---------------------------------------------------------------------------------------

local function rewardPlayer(player: Player, record: MobRecord, payout: DamageLedger.Payout)
	local data = record.Data
	DataService.AddShards(player, payout.Shards)
	DataService.Mutate(player, { "Stats" }, function(playerData)
		playerData.Stats.MobsDefeated += 1
		if data.IsBoss then
			playerData.Stats.BossesDefeated += 1
		end
	end)

	local drops: { { Kind: GameConfig.DropKind, Id: string } } = {}
	for _, entry in data.Drops.Bonus do
		if random:NextNumber() >= entry.Chance then
			continue
		end
		if entry.Kind == "Pet" then
			if DataService.GrantPet(player, entry.Id) then
				table.insert(drops, { Kind = entry.Kind, Id = entry.Id })
			end
		elseif entry.Kind == "Title" then
			if DataService.GrantTitle(player, entry.Id) then
				table.insert(drops, { Kind = entry.Kind, Id = entry.Id })
			end
		end
	end

	local report: RewardReport = {
		MobId = data.Id,
		MobName = data.DisplayName,
		Shards = payout.Shards,
		Contribution = payout.Fraction,
		Drops = drops,
	}
	Remotes.MobReward:FireClient(player, report)
end

local spawnMob: (spawner: SpawnerData, home: Vector3) -> ()

local function kill(record: MobRecord)
	record.Alive = false
	MobBrain.Kill(record.Brain, os.clock())
	hold(record)
	record.Humanoid.WalkSpeed = 0
	record.Model:SetAttribute("Health", 0)
	record.Model:SetAttribute("State", "Dead")

	local data = record.Data
	local payouts = record.Ledger:ComputePayouts(data.Drops.BaseShards, function(userId: number): (number, number)
		local player = Players:GetPlayerByUserId(userId)
		local playerData = if player then DataService.GetData(player) else nil
		if playerData == nil then
			return 1, 1
		end
		return Formulas.RebirthMultiplier(playerData.RebirthCount),
			1 + Formulas.SkillBonus(playerData.SkillLevels, "Shards")
	end)

	for _, payout in payouts do
		local player = Players:GetPlayerByUserId(payout.UserId)
		if player and payout.Eligible and payout.Shards > 0 then
			rewardPlayer(player, record, payout)
		end
	end
	MobService.MobDied:Fire(record, payouts)

	local spawner = record.Spawner
	local home = record.Home
	task.delay(CORPSE_SECONDS, function()
		mobs[record.Id] = nil
		record.Model:Destroy()
	end)
	task.delay(data.RespawnSeconds, function()
		spawnMob(spawner, home)
	end)
end

---------------------------------------------------------------------------------------
-- Spawning & AI
---------------------------------------------------------------------------------------

spawnMob = function(spawner: SpawnerData, home: Vector3)
	local data = GameConfig.Mobs[spawner.MobId]
	local folder = mobFolder
	if data == nil or folder == nil then
		warn(`[MobService] cannot spawn {spawner.MobId} at {spawner.Id}`)
		return
	end

	nextMobId += 1
	local id = nextMobId
	local model = MobFactory.Build(data, home)
	model.Name = `{data.Id}_{id}`
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart

	model:SetAttribute("MobId", id)
	model:SetAttribute("MobType", data.Id)
	model:SetAttribute("DisplayName", data.DisplayName)
	model:SetAttribute("MaxHealth", data.MaxHealth)
	model:SetAttribute("Health", data.MaxHealth)
	model:SetAttribute("IsBoss", data.IsBoss)
	model:SetAttribute("HitRadius", data.HitRadius)
	model:SetAttribute("State", "Idle")
	model:AddTag(Tags.ChronoMob)
	model.Parent = folder

	-- Server-owned physics: exploiters cannot move or freeze mobs.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local now = os.clock()
	mobs[id] = {
		Id = id,
		Data = data,
		Spawner = spawner,
		Home = home,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Health = data.MaxHealth,
		Alive = true,
		Ledger = DamageLedger.new(data.MaxHealth),
		Brain = MobBrain.new(data, now),
		Target = nil,
		LastAttacker = nil,
		LastAttackerAt = -math.huge,
		LastMoveTarget = nil,
		LastMoveAt = -math.huge,
		LockedOrigin = nil,
		LockedDirection = nil,
		TelegraphTrack = nil,
	}
end

local function stepMob(record: MobRecord, now: number)
	local data = record.Data
	local root = record.Root
	if root.Position.Y < FALL_LIMIT_Y then
		record.Model:PivotTo(CFrame.new(record.Home + Vector3.new(0, record.Humanoid.HipHeight + root.Size.Y, 0)))
		return
	end

	local target, targetPosition = findTarget(record)
	record.Target = target
	local position = root.Position
	local targetDistance = if targetPosition
		then math.max(0, Spatial.HorizontalDistance(position, targetPosition) - data.HitRadius - PLAYER_RADIUS)
		else math.huge

	local decision = MobBrain.Step(record.Brain, {
		Now = now,
		HasTarget = target ~= nil,
		TargetDistance = targetDistance,
		DistanceFromHome = Spatial.HorizontalDistance(position, record.Home),
		Roll = random:NextNumber(),
	})

	if decision.Changed then
		record.Model:SetAttribute("State", decision.State)
		if decision.State == "Chase" or decision.State == "Return" or decision.State == "Idle" then
			record.Humanoid.WalkSpeed = data.WalkSpeed
			record.Humanoid.AutoRotate = true
		end
	end

	local action = decision.Action
	if action == "Chase" and targetPosition then
		moveTo(record, targetPosition, now)
	elseif action == "Hold" then
		hold(record)
		if decision.State == "Chase" and targetPosition then
			face(record, targetPosition)
		end
	elseif action == "BeginTelegraph" and decision.Attack and targetPosition then
		beginTelegraph(record, decision.Attack, targetPosition)
	elseif action == "Strike" and decision.Attack then
		strike(record, decision.Attack)
	elseif action == "GoHome" then
		moveTo(record, record.Home, now)
	elseif action == "Arrived" then
		hold(record)
	end

	-- Out of combat long enough: heal up and forget contributors.
	if MobBrain.ShouldReset(record.Brain, now, record.Health) then
		record.Health = data.MaxHealth
		record.Ledger:Reset()
		record.Model:SetAttribute("Health", record.Health)
		MobBrain.NoteCombat(record.Brain, now)
	end
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

function MobService.GetMob(mobId: number): MobRecord?
	local record = mobs[mobId]
	if record and record.Alive then
		return record
	end
	return nil
end

function MobService.GetPosition(record: MobRecord): Vector3
	return record.Root.Position
end

--[[
	Applies damage from `attacker` to the shared health pool. Returns
	(creditedDamage, killed). Credited damage excludes overkill.
]]
function MobService.ApplyDamage(mobId: number, attacker: Player, amount: number): (number, boolean)
	local record = mobs[mobId]
	if record == nil or not record.Alive or amount ~= amount or amount <= 0 then
		return 0, false
	end
	local now = os.clock()
	local credited = record.Ledger:Record(attacker.UserId, amount, record.Health)
	record.Health = math.max(0, record.Health - amount)
	record.LastAttacker = attacker
	record.LastAttackerAt = now
	MobBrain.NoteCombat(record.Brain, now)
	record.Model:SetAttribute("Health", record.Health)

	if record.Health <= 0 then
		kill(record)
		return credited, true
	end
	return credited, false
end

function MobService.Init()
	local existing = workspace:FindFirstChild("ChronoMobs")
	if existing and existing:IsA("Folder") then
		mobFolder = existing
	else
		local folder = Instance.new("Folder")
		folder.Name = "ChronoMobs"
		folder.Parent = workspace
		mobFolder = folder
	end
end

function MobService.Start()
	local markers = WorldService.GetSpawnerMarkers()
	for _, spawner in GameConfig.Spawners do
		local marker = markers[spawner.Id]
		local home = if marker
			then marker.Position - Vector3.new(0, marker.Size.Y / 2, 0)
			else GameConfig.World.ColosseumCenter + spawner.Offset + Vector3.new(0, 0.45, 0)
		spawnMob(spawner, home)
	end

	local accumulator = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		accumulator += deltaTime
		if accumulator < AI_INTERVAL then
			return
		end
		accumulator = 0
		local now = os.clock()
		for _, record in mobs do
			if record.Alive then
				local ok, err = pcall(stepMob :: any, record, now)
				if not ok then
					warn(`[MobService] AI error on {record.Model.Name}: {err}`)
				end
			end
		end
	end)
end

return MobService
