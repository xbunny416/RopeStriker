--!strict
--[[
	Network Definitions
	-------------------
	The canonical list of remotes that live in Network/RemoteEvents. The folder is
	authored in the Rojo tree (one *.model.json per remote) so it exists at edit time,
	and Remotes.luau re-creates anything missing on the server at boot. A unit test
	(tests/specs/Network.spec.luau) keeps the two in sync.

	Direction legend:  C->S client to server, S->C server to client, S->*C broadcast.
]]

export type RemoteClass = "RemoteEvent" | "RemoteFunction" | "UnreliableRemoteEvent"

export type Definition = {
	Name: string,
	Class: RemoteClass,
	Direction: "C->S" | "S->C" | "S->*C",
	Payload: string,
}

local Definitions: { Definition } = {
	-- Training (Bible §2.1 rhythm + KP)
	{
		Name = "ReportBounce",
		Class = "RemoteEvent",
		Direction = "C->S",
		Payload = "(pressTime: number, landTime: number)",
	},
	{
		Name = "BounceResult",
		Class = "RemoteEvent",
		Direction = "S->C",
		Payload = "(result: BounceResult)",
	},
	{ Name = "Banked", Class = "RemoteEvent", Direction = "S->C", Payload = "(amount: number, totalStrength: number)" },

	-- Combat (§2.1 damage, §6 validation)
	{
		Name = "RequestAttack",
		Class = "RemoteEvent",
		Direction = "C->S",
		Payload = "(attack: AttackKind, direction: Vector3, targetIds: {number})",
	},
	{ Name = "CombatFeedback", Class = "RemoteEvent", Direction = "S->C", Payload = "(hits: {HitReport})" },
	{
		Name = "AttackFx",
		Class = "UnreliableRemoteEvent",
		Direction = "S->*C",
		Payload = "(userId: number, attack: AttackKind, direction: Vector3, hitPosition: Vector3?)",
	},
	{ Name = "MobReward", Class = "RemoteEvent", Direction = "S->C", Payload = "(reward: RewardReport)" },

	-- Data replication
	{ Name = "GetSnapshot", Class = "RemoteFunction", Direction = "C->S", Payload = "() -> PlayerData?" },
	{ Name = "StateSnapshot", Class = "RemoteEvent", Direction = "S->C", Payload = "(data: PlayerData)" },
	{ Name = "StatePatch", Class = "RemoteEvent", Direction = "S->C", Payload = "(patch: {[string]: any})" },
	{ Name = "Notify", Class = "RemoteEvent", Direction = "S->C", Payload = "(kind: string, message: string)" },

	-- Shop / pets / cosmetics
	{
		Name = "PurchaseItem",
		Class = "RemoteFunction",
		Direction = "C->S",
		Payload = "(category: ItemCategory, itemId: string) -> (boolean, string)",
	},
	{
		Name = "EquipItem",
		Class = "RemoteFunction",
		Direction = "C->S",
		Payload = "(category: ItemCategory, itemId: string) -> (boolean, string)",
	},
	{
		Name = "SetPetEquipped",
		Class = "RemoteFunction",
		Direction = "C->S",
		Payload = '(petUid: string | "*best", equipped: boolean) -> (boolean, string)',
	},
	{ Name = "HatchResult", Class = "RemoteEvent", Direction = "S->C", Payload = "(eggId: string, pet: PetRecord)" },

	-- Rebirth & skill tree (§2.2)
	{ Name = "RequestRebirth", Class = "RemoteFunction", Direction = "C->S", Payload = "() -> (boolean, string)" },
	{
		Name = "UnlockSkill",
		Class = "RemoteFunction",
		Direction = "C->S",
		Payload = "(nodeId: string) -> (boolean, string)",
	},
	{ Name = "RebirthComplete", Class = "RemoteEvent", Direction = "S->C", Payload = "(rebirthCount: number)" },

	-- Portals (§3.1)
	{ Name = "PortalUnlocked", Class = "RemoteEvent", Direction = "S->C", Payload = "(portalId: string)" },
}

return Definitions
