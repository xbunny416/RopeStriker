--!strict
--[[
	Remotes
	-------
	Typed access to every remote in Network/RemoteEvents plus the payload types that
	cross the client/server boundary.

	  * Server: missing remotes are created (idempotent) so the game also boots from a
	    place file that was assembled without Rojo. A remote with the wrong class is a
	    hard error at boot rather than a silent runtime bug.
	  * Client: waits (bounded) for each remote to replicate.

	Never trust a payload received on the server: validate it with Shared/Guard first.
]]

local RunService = game:GetService("RunService")

local Definitions = require(script.Parent.Definitions)
local GameConfig = require(script.Parent.Parent.Configuration.GameConfig)

export type BounceResult = {
	Accepted: boolean,
	OnBeat: boolean,
	Combo: number,
	Gained: number,
	Capped: boolean,
	Reason: string?,
}

export type HitReport = {
	MobId: number,
	Damage: number,
	Killed: boolean,
	Position: Vector3,
}

export type RewardReport = {
	MobId: string,
	MobName: string,
	Shards: number,
	Contribution: number,
	Drops: { { Kind: GameConfig.DropKind, Id: string } },
}

local IS_SERVER = RunService:IsServer()
local CLIENT_WAIT_SECONDS = 30

local function resolveFolder(): Folder
	local parent = script.Parent
	if IS_SERVER then
		local existing = parent:FindFirstChild("RemoteEvents")
		if existing then
			assert(existing:IsA("Folder"), "Network.RemoteEvents must be a Folder")
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = parent
		return folder
	end
	local folder = parent:WaitForChild("RemoteEvents", CLIENT_WAIT_SECONDS)
	assert(folder and folder:IsA("Folder"), "Network.RemoteEvents folder did not replicate")
	return folder
end

local folder = resolveFolder()

local classByName: { [string]: string } = {}
for _, definition in Definitions do
	classByName[definition.Name] = definition.Class
end

local function get(name: string): any
	local className = classByName[name]
	assert(className ~= nil, `Remote "{name}" is not declared in Network/Definitions`)

	if IS_SERVER then
		local existing = folder:FindFirstChild(name)
		if existing then
			assert(existing.ClassName == className, `Remote "{name}" is a {existing.ClassName}, expected {className}`)
			return existing
		end
		local remote = Instance.new(className :: any)
		remote.Name = name
		remote.Parent = folder
		return remote
	end

	local remote = folder:WaitForChild(name, CLIENT_WAIT_SECONDS)
	assert(remote ~= nil, `Remote "{name}" did not replicate within {CLIENT_WAIT_SECONDS}s`)
	assert(remote.ClassName == className, `Remote "{name}" is a {remote.ClassName}, expected {className}`)
	return remote
end

local Remotes = {
	Folder = folder,

	ReportBounce = get("ReportBounce") :: RemoteEvent,
	BounceResult = get("BounceResult") :: RemoteEvent,
	Banked = get("Banked") :: RemoteEvent,

	RequestAttack = get("RequestAttack") :: RemoteEvent,
	CombatFeedback = get("CombatFeedback") :: RemoteEvent,
	AttackFx = get("AttackFx") :: UnreliableRemoteEvent,
	MobReward = get("MobReward") :: RemoteEvent,

	GetSnapshot = get("GetSnapshot") :: RemoteFunction,
	StateSnapshot = get("StateSnapshot") :: RemoteEvent,
	StatePatch = get("StatePatch") :: RemoteEvent,
	Notify = get("Notify") :: RemoteEvent,

	PurchaseItem = get("PurchaseItem") :: RemoteFunction,
	EquipItem = get("EquipItem") :: RemoteFunction,
	SetPetEquipped = get("SetPetEquipped") :: RemoteFunction,
	HatchResult = get("HatchResult") :: RemoteEvent,

	RequestRebirth = get("RequestRebirth") :: RemoteFunction,
	UnlockSkill = get("UnlockSkill") :: RemoteFunction,
	RebirthComplete = get("RebirthComplete") :: RemoteEvent,

	PortalUnlocked = get("PortalUnlocked") :: RemoteEvent,
}

-- Every declared remote must be exposed above; catch drift at boot.
for name in classByName do
	assert((Remotes :: any)[name] ~= nil, `Remote "{name}" is declared but not exposed by Remotes.luau`)
end

return Remotes
