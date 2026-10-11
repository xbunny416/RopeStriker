--!strict
--[[
	Tags
	----
	CollectionService tag names: the contract between level geometry and gameplay code.
	Any map (procedural WorldBuilder output or a hand-built Blender/Studio map) works as
	long as its interactables carry these tags and attributes:

	  EpochObelisk     Model    attr Era: number; contains BankPrompt (ProximityPrompt)
	  ObeliskPedestal  BasePart glowing banking pad around an obelisk
	  PanelPrompt      ProximityPrompt  attr OpensPanel: "Shop" | "Rebirth" | "Pets"
	  ChronoEgg        Model    attr EggId: string; contains HatchPrompt
	  MobSpawner       BasePart attr SpawnerId: string, MobId: string
	  ChronalRiftGate  BasePart attr PortalId: string (+ RequiredStrength/RequiredRebirths/ToEra)
	  ChronoMob        Model    (runtime) attr MobId: number, MobType, Health, MaxHealth, State...
	  ChronoPet        Model    (client-only) follower models
]]

local Tags = {
	EpochObelisk = "EpochObelisk",
	ObeliskPedestal = "ObeliskPedestal",
	PanelPrompt = "PanelPrompt",
	ChronoEgg = "ChronoEgg",
	MobSpawner = "MobSpawner",
	ChronalRiftGate = "ChronalRiftGate",
	ChronoMob = "ChronoMob",
	ChronoPet = "ChronoPet",
}

return table.freeze(Tags)
