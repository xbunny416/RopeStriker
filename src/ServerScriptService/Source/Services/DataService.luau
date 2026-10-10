--!strict
--[[
	DataService
	===========
	Owns every player's persistent profile.

	Persistence  - ProfileService (Packages/ProfileService) provides session locking
	               (a profile can only be active on one server; a second server
	               force-loads it and the first releases + kicks), periodic auto-saving
	               (every ~30s, spread across profiles), saving on release and on
	               server shutdown (BindToClose), and an in-memory mock store in Studio
	               when API access is disabled.

	Atomicity    - Luau runs one coroutine at a time per VM, so a mutation is only at
	               risk of interleaving if it yields between reading and writing data.
	               DataService.Mutate runs each mutator in a dedicated coroutine and
	               raises if it yields, which makes every stat mutation (AddKP,
	               BankPower, AddShards, Rebirth, ...) atomic by construction. Mutations
	               are also refused before a profile has loaded or after it was released,
	               so nothing can be written to a profile this server no longer owns.

	Replication  - Scalars (KP, Strength, Shards, ...) are mirrored to Player attributes
	               (cheap, automatically replicated, also visible to other clients for
	               trails/pets/titles); tables are sent to the owner through StatePatch.
	               The full profile is sent once via StateSnapshot / GetSnapshot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Source = ReplicatedStorage.Source
local GameConfig = require(Source.Configuration.GameConfig)
local Formulas = require(Source.Shared.Formulas)
local Signal = require(Source.Shared.Signal)
local Remotes = require(Source.Network.Remotes)
local ProfileService = require(Source.Packages.ProfileService) :: any

local Modules = script.Parent.Parent.Modules
local PlayerDataOps = require(Modules.PlayerDataOps)
local RateLimiter = require(Modules.RateLimiter)

type PlayerData = GameConfig.PlayerData
type PetRecord = GameConfig.PetRecord

-- Typed facade over the (untyped) ProfileService Profile object.
type Profile = {
	Data: PlayerData,
	IsActive: (self: Profile) -> boolean,
	Release: (self: Profile) -> (),
	Reconcile: (self: Profile) -> (),
	AddUserId: (self: Profile, userId: number) -> (),
	ListenToRelease: (self: Profile, listener: (placeId: number?, jobId: string?) -> ()) -> any,
}

-- Profile fields mirrored to Player attributes.
local SCALAR_KEYS: { [string]: boolean } = {
	UnbankedKP = true,
	TotalStrength = true,
	Shards = true,
	RebirthCount = true,
	RebirthTokens = true,
	HighestEra = true,
	EquippedRope = true,
	EquippedBoots = true,
	EquippedTitle = true,
}

-- Fields whose change alters derived attributes.
local CAPACITY_KEYS: { [string]: boolean } = { EquippedBoots = true, RebirthCount = true, SkillLevels = true }
local PET_KEYS: { [string]: boolean } = { EquippedPets = true, Pets = true, SkillLevels = true }

-- Every key Rebirth can touch (used for its replication pass).
local REBIRTH_KEYS = {
	"RebirthCount",
	"RebirthTokens",
	"UnbankedKP",
	"TotalStrength",
	"OwnedRopes",
	"EquippedRope",
	"OwnedBoots",
	"EquippedBoots",
	"OwnedTitles",
	"Stats",
}

local DataService = {}

DataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player, PlayerData>
DataService.ProfileReleasing = Signal.new() :: Signal.Signal<Player, PlayerData>
DataService.Changed = Signal.new() :: Signal.Signal<Player, { string }>

local profileStore: any = nil
local profiles: { [Player]: Profile } = {}
local sessionStartClock: { [Player]: number } = {}
local loading: { [Player]: boolean } = {}
local snapshotLimiter = RateLimiter.new(3, 0.5)

---------------------------------------------------------------------------------------
-- Replication
---------------------------------------------------------------------------------------

local function updateLeaderstats(player: Player, data: PlayerData)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats == nil then
		return
	end
	local strength = leaderstats:FindFirstChild("Strength")
	if strength and strength:IsA("NumberValue") then
		strength.Value = data.TotalStrength
	end
	local rebirths = leaderstats:FindFirstChild("Rebirths")
	if rebirths and rebirths:IsA("IntValue") then
		rebirths.Value = data.RebirthCount
	end
end

local function setupLeaderstats(player: Player, data: PlayerData)
	local existing = player:FindFirstChild("leaderstats")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local strength = Instance.new("NumberValue")
	strength.Name = "Strength"
	strength.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	folder.Parent = player
	updateLeaderstats(player, data)
end

local function refreshDerived(player: Player, data: PlayerData, capacity: boolean, pets: boolean)
	if capacity then
		player:SetAttribute("StaminaCapacity", Formulas.StaminaCapacity(data))
	end
	if pets then
		local petIds = Formulas.EquippedPetIds(data)
		player:SetAttribute("EquippedPetIds", table.concat(petIds, ","))
		player:SetAttribute("PetMultiplier", Formulas.PetMultiplierSum(petIds))
	end
end

local function replicate(player: Player, data: PlayerData, keys: { string })
	if #keys == 0 then
		return
	end
	local patch: { [string]: any } = {}
	local hasPatch = false
	local capacity = false
	local pets = false
	local leaderboard = false

	for _, key in keys do
		local value = (data :: any)[key]
		if SCALAR_KEYS[key] then
			player:SetAttribute(key, value)
		elseif type(value) == "table" then
			patch[key] = PlayerDataOps.DeepCopy(value)
			hasPatch = true
		end
		capacity = capacity or CAPACITY_KEYS[key] == true
		pets = pets or PET_KEYS[key] == true
		leaderboard = leaderboard or key == "TotalStrength" or key == "RebirthCount"
	end

	refreshDerived(player, data, capacity, pets)
	if leaderboard then
		updateLeaderstats(player, data)
	end
	if hasPatch then
		Remotes.StatePatch:FireClient(player, patch)
	end
end

local function replicateAll(player: Player, data: PlayerData)
	for key in SCALAR_KEYS do
		player:SetAttribute(key, (data :: any)[key])
	end
	refreshDerived(player, data, true, true)
	setupLeaderstats(player, data)
	Remotes.StateSnapshot:FireClient(player, PlayerDataOps.DeepCopy(data))
	player:SetAttribute("DataLoaded", true)
end

---------------------------------------------------------------------------------------
-- Profile lifecycle
---------------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if profiles[player] or loading[player] then
		return
	end
	loading[player] = true
	local key = `{GameConfig.Data.KeyPrefix}{player.UserId}`
	local ok, result = pcall(function()
		return profileStore:LoadProfileAsync(key)
	end)
	loading[player] = nil

	local profile: Profile? = if ok then result else nil
	if not ok then
		warn(`[DataService] LoadProfileAsync failed for {player.Name}: {result}`)
	end
	if profile == nil then
		-- Never let anyone play on an unloaded profile: their progress would be lost.
		player:Kick("We couldn't load your ChronoRope data. Please rejoin in a moment.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR association
	profile:Reconcile() -- fill fields added to the template since the last save
	profile:ListenToRelease(function()
		profiles[player] = nil
		sessionStartClock[player] = nil
		-- Released externally (session stolen by another server) or by us on leave.
		player:Kick("Your ChronoRope session was opened on another server.")
	end)

	if player.Parent ~= Players then
		profile:Release() -- left while we were loading
		return
	end

	local data = profile.Data
	PlayerDataOps.Migrate(data)
	PlayerDataOps.Sanitize(data)
	local now = os.time()
	if data.FirstJoinUnix == 0 then
		data.FirstJoinUnix = now
	end
	data.LastJoinUnix = now

	profiles[player] = profile
	sessionStartClock[player] = os.clock()
	replicateAll(player, data)
	DataService.ProfileLoaded:Fire(player, data)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile ~= nil then
		local started = sessionStartClock[player]
		if started then
			profile.Data.Stats.PlaySeconds += math.floor(os.clock() - started)
		end
		DataService.ProfileReleasing:Fire(player, profile.Data)
		profile:Release()
	end
	sessionStartClock[player] = nil
	snapshotLimiter:Reset(player)
end

---------------------------------------------------------------------------------------
-- Read API
---------------------------------------------------------------------------------------

function DataService.IsLoaded(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile:IsActive()
end

-- The live profile table. Treat as read-only: write through Mutate/the helpers below.
function DataService.GetData(player: Player): PlayerData?
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return nil
	end
	return profile.Data
end

function DataService.WaitForData(player: Player, timeout: number?): PlayerData?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent == Players and os.clock() < deadline do
		local data = DataService.GetData(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return DataService.GetData(player)
end

---------------------------------------------------------------------------------------
-- Write API
---------------------------------------------------------------------------------------

--[[
	Runs `mutator` atomically against the player's profile and replicates `changedKeys`.
	Returns false (and does nothing) when the profile is not loaded/active.
	Raises if the mutator yields - mutations must be synchronous.
]]
function DataService.Mutate(player: Player, changedKeys: { string }, mutator: (data: PlayerData) -> ()): boolean
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return false
	end
	local data = profile.Data

	local thread = coroutine.create(mutator)
	local ok, err = coroutine.resume(thread, data)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		error("DataService.Mutate: mutator yielded; data mutations must be synchronous", 2)
	end
	if not ok then
		error(debug.traceback(thread, tostring(err)), 2)
	end

	replicate(player, data, changedKeys)
	if #changedKeys > 0 then
		DataService.Changed:Fire(player, changedKeys)
	end
	return true
end

-- Bible §2.1: adds KP up to Stamina Capacity. Returns (added, reachedCap).
function DataService.AddKP(player: Player, amount: number): (number, boolean)
	local added, reachedCap = 0, false
	DataService.Mutate(player, { "UnbankedKP" }, function(data)
		added, reachedCap = PlayerDataOps.AddKP(data, amount)
	end)
	return added, reachedCap
end

-- Bible §2.1: converts unbanked KP into permanent TotalStrength. Returns amount banked.
function DataService.BankPower(player: Player): number
	local banked = 0
	DataService.Mutate(player, { "UnbankedKP", "TotalStrength", "Stats" }, function(data)
		banked = PlayerDataOps.BankPower(data)
	end)
	return banked
end

function DataService.AddShards(player: Player, amount: number): number
	local added = 0
	DataService.Mutate(player, { "Shards" }, function(data)
		added = PlayerDataOps.AddShards(data, amount)
	end)
	return added
end

function DataService.SpendShards(player: Player, amount: number): boolean
	local spent = false
	DataService.Mutate(player, { "Shards" }, function(data)
		spent = PlayerDataOps.SpendShards(data, amount)
	end)
	return spent
end

-- Bible §2.2 Temporal Paradox. Returns (success, message).
function DataService.Rebirth(player: Player): (boolean, string)
	local success, message = false, "Your data is still loading."
	DataService.Mutate(player, REBIRTH_KEYS, function(data)
		success, message = PlayerDataOps.Rebirth(data)
	end)
	return success, message
end

function DataService.GrantPet(player: Player, petId: string): PetRecord?
	local record: PetRecord? = nil
	DataService.Mutate(player, { "Pets", "EquippedPets", "NextPetUid" }, function(data)
		record = PlayerDataOps.GrantPet(data, petId, os.time())
	end)
	return record
end

function DataService.GrantTitle(player: Player, titleId: string): boolean
	local granted = false
	DataService.Mutate(player, { "OwnedTitles" }, function(data)
		granted = PlayerDataOps.GrantTitle(data, titleId)
	end)
	return granted
end

-- Lifetime stat bookkeeping; not replicated per bounce (Stats ride the next patch).
function DataService.RecordBounce(player: Player, onBeat: boolean, combo: number)
	DataService.Mutate(player, {}, function(data)
		PlayerDataOps.RecordBounce(data, onBeat, combo)
	end)
end

function DataService.Notify(player: Player, kind: string, message: string)
	Remotes.Notify:FireClient(player, kind, message)
end

---------------------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------------------

function DataService.Init()
	profileStore = ProfileService.GetProfileStore(GameConfig.Data.StoreName, GameConfig.DefaultPlayerData)

	Remotes.GetSnapshot.OnServerInvoke = function(player: Player): any
		if not snapshotLimiter:Allow(player) then
			return nil
		end
		local data = DataService.GetData(player)
		if data == nil then
			return nil
		end
		return PlayerDataOps.DeepCopy(data)
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
