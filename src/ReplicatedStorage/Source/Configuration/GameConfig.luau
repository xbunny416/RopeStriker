--!strict
--[[
	GameConfig
	==========
	Single source of truth for every tunable in ChronoRope: Epoch Striker.

	  * Types       - the full typed schema for player data, ropes, boots, pets, eggs,
	                  mobs, spawners, drop tables, eras/portals and the rebirth skill tree.
	  * Catalogues  - the Zone 1 (Ancient Rome) content set from the Project Bible.
	  * Rules       - rhythm, training, combat, reward and rebirth parameters (Bible §2).
	  * Template    - DefaultPlayerData, the ProfileService profile template.

	The table is deep-frozen at the bottom of this file: gameplay code can read it from
	both the server and the client, but nothing can mutate it at runtime. Anything that
	needs a mutable copy (e.g. a new profile) must deep-copy (see DataService/PlayerDataOps).

	Economy formulas live in Shared/Formulas.luau and only *read* these numbers.
]]

---------------------------------------------------------------------------------------
-- Schema
---------------------------------------------------------------------------------------

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type AttackKind = "GroundLash" | "AerialSweep"
export type ShapeKind = "Cone" | "Circle"
export type ItemCategory = "Rope" | "Boots" | "Title"
export type DropKind = "Pet" | "Title"
export type SkillEffect = "KPGain" | "Capacity" | "Damage" | "Shards" | "EggLuck" | "PetSlots"
export type PlayerMode = "Training" | "Combat"

-- A ground-plane hit/telegraph volume. Cones use Range as length and AngleDegrees as the
-- *full* spread; circles use Range as radius and ignore AngleDegrees.
export type ShapeData = {
	Kind: ShapeKind,
	Range: number,
	AngleDegrees: number,
}

export type RopeVisual = {
	Color: Color3,
	Width: number,
	HandleColor: Color3,
	HandleMaterial: Enum.Material,
	Glow: boolean,
	-- Optional Blender/FBX model under ReplicatedStorage.Assets.Ropes.<Template> that
	-- replaces the procedural handles (must contain HandleL + HandleR parts).
	Template: string?,
}

export type RopeData = {
	Id: string,
	DisplayName: string,
	Description: string,
	Era: number,
	Price: number, -- Shards
	BaseKP: number, -- BaseRopeKP in the KP formula
	BaseDamage: number, -- RopeBaseDamage in the DMG formula
	LayoutOrder: number,
	Visual: RopeVisual,
}

export type BootVisual = {
	Color: Color3,
	Material: Enum.Material,
	Wings: boolean,
	Visible: boolean,
}

export type BootData = {
	Id: string,
	DisplayName: string,
	Description: string,
	Era: number,
	Price: number,
	Multiplier: number, -- BootMultiplier in the KP formula
	StaminaCapacity: number, -- unbanked KP storage cap before rebirth/skill scaling
	LayoutOrder: number,
	Visual: BootVisual,
}

export type PetVisual = {
	Archetype: "Centurion" | "Mammoth" | "Eagle",
	PrimaryColor: Color3,
	SecondaryColor: Color3,
	AccentColor: Color3,
	Template: string?, -- optional ReplicatedStorage.Assets.Pets.<Template> (<= 500 tris)
}

export type PetData = {
	Id: string,
	DisplayName: string,
	Rarity: Rarity,
	Multiplier: number, -- contributes to PetMultiplierSum
	LayoutOrder: number,
	Visual: PetVisual,
}

export type EggData = {
	Id: string,
	DisplayName: string,
	Era: number,
	Price: number,
	Weights: { [string]: number }, -- PetId -> relative weight
	LayoutOrder: number,
	Color: Color3,
}

export type DropEntry = {
	Kind: DropKind,
	Id: string,
	Chance: number, -- 0..1, rolled independently for every eligible contributor
}

export type DropTable = {
	BaseShards: number, -- BaseMobShards in the payout formula
	Bonus: { DropEntry },
}

export type MobAttackData = {
	Id: string,
	DisplayName: string,
	Shape: ShapeData,
	Damage: number,
	TelegraphSeconds: number,
	RecoverySeconds: number,
	Weight: number,
}

export type MobVisual = {
	Scale: number,
	SkinColor: Color3,
	ArmorColor: Color3,
	AccentColor: Color3,
	Crest: boolean,
	Template: string?, -- optional ServerStorage.Assets.Mobs.<Template> rig
}

export type MobData = {
	Id: string,
	DisplayName: string,
	MaxHealth: number,
	RespawnSeconds: number,
	WalkSpeed: number,
	AggroRange: number, -- studs from the mob at which it notices players
	LeashRange: number, -- studs from its spawner before it gives up a chase
	AttackRange: number, -- studs from target at which it starts a telegraph
	AttackCooldown: number, -- seconds between the end of one attack and the next telegraph
	HitRadius: number, -- body radius used by hit tests and range validation
	IsBoss: boolean,
	ResetAfterIdleSeconds: number, -- no combat for this long => full heal + ledger reset
	Attacks: { MobAttackData },
	Drops: DropTable,
	Visual: MobVisual,
}

export type SpawnerData = {
	Id: string,
	MobId: string,
	Offset: Vector3, -- relative to World.ColosseumCenter
}

export type EraTheme = {
	Ground: Color3,
	Path: Color3,
	Accent: Color3,
	Trim: Color3,
}

export type EraData = {
	Index: number,
	Id: string,
	DisplayName: string,
	Tagline: string,
	SectorMinX: number,
	SectorMaxX: number,
	SectorMinZ: number,
	SectorMaxZ: number,
	Center: Vector3,
	Theme: EraTheme,
}

export type PortalData = {
	Id: string,
	DisplayName: string,
	FromEra: number,
	ToEra: number,
	RequiredStrength: number,
	RequiredRebirths: number,
	Position: Vector3, -- centre of the rift ring, world space
}

export type SkillRequirement = {
	Id: string,
	Level: number,
}

export type SkillNodeData = {
	Id: string,
	DisplayName: string,
	Description: string,
	Effect: SkillEffect,
	PerLevel: number,
	MaxLevel: number,
	CostPerLevel: number,
	Requires: { SkillRequirement },
	LayoutPosition: Vector2, -- 0..1 scale position on the skill-tree canvas
}

export type TitleData = {
	Id: string,
	DisplayName: string,
	Description: string,
	Color: Color3,
	LayoutOrder: number,
}

export type ComboTier = {
	MinCombo: number,
	Name: string,
	Color: Color3,
}

export type AttackData = {
	Kind: AttackKind,
	DisplayName: string,
	Multiplier: number,
	Shape: ShapeData,
	Duration: number, -- animation length (Bible §4.2)
	Cooldown: number, -- minimum time between attacks of this kind
	RequiresAirborne: boolean,
}

export type SoundData = {
	SoundId: string,
	Volume: number,
	RollOffMaxDistance: number,
	-- Tried in order when SoundId fails to load (see SoundPlayer.Verify).
	Fallbacks: { string }?,
}

export type RateLimitData = {
	Capacity: number,
	RefillPerSecond: number,
}

-- Persistent profile (ProfileService). Bump DataVersion + add a migration in
-- PlayerDataOps.Migrate whenever the shape changes.
export type PetRecord = {
	Uid: string,
	Id: string,
	ObtainedUnix: number,
}

export type LifetimeStats = {
	Bounces: number,
	OnBeatBounces: number,
	BestCombo: number,
	StrengthBanked: number,
	ShardsEarned: number,
	MobsDefeated: number,
	BossesDefeated: number,
	EggsHatched: number,
	Rebirths: number,
	PlaySeconds: number,
}

export type PlayerData = {
	DataVersion: number,

	-- Kinetic economy (§2.1)
	UnbankedKP: number,
	TotalStrength: number,
	Shards: number,

	-- Temporal Paradox (§2.2)
	RebirthCount: number,
	RebirthTokens: number,
	SkillLevels: { [string]: number },

	-- World progression (§3.1)
	HighestEra: number,
	UnlockedPortals: { [string]: boolean },

	-- Gear (reset on rebirth)
	OwnedRopes: { [string]: boolean },
	EquippedRope: string,
	OwnedBoots: { [string]: boolean },
	EquippedBoots: string,

	-- Pets (retained on rebirth)
	Pets: { [string]: PetRecord },
	EquippedPets: { string },
	NextPetUid: number,

	-- Cosmetics (retained on rebirth)
	OwnedTitles: { [string]: boolean },
	EquippedTitle: string,

	Stats: LifetimeStats,
	FirstJoinUnix: number,
	LastJoinUnix: number,
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

---------------------------------------------------------------------------------------
-- Catalogues: Zone 1 asset list (Bible §4.1)
---------------------------------------------------------------------------------------

local Ropes: { [string]: RopeData } = {
	HempCord = {
		Id = "HempCord",
		DisplayName = "Standard Hemp Cord",
		Description = "A trusty training cord braided in the Piazza workshops.",
		Era = 1,
		Price = 0,
		BaseKP = 1,
		BaseDamage = 10,
		LayoutOrder = 1,
		Visual = {
			Color = rgb(214, 182, 128),
			Width = 0.18,
			HandleColor = rgb(118, 80, 48),
			HandleMaterial = Enum.Material.SmoothPlastic,
			Glow = false,
		},
	},
	LeatherStrap = {
		Id = "LeatherStrap",
		DisplayName = "Leather Strap",
		Description = "Oiled legionary leather. Snaps hard, swings fast.",
		Era = 1,
		Price = 250,
		BaseKP = 4,
		BaseDamage = 28,
		LayoutOrder = 2,
		Visual = {
			Color = rgb(139, 82, 45),
			Width = 0.22,
			HandleColor = rgb(72, 42, 24),
			HandleMaterial = Enum.Material.SmoothPlastic,
			Glow = false,
		},
	},
	BronzeChain = {
		Id = "BronzeChain",
		DisplayName = "Bronze Chain",
		Description = "Forged from melted Colosseum shields. Every link hums with kinetic charge.",
		Era = 1,
		Price = 2500,
		BaseKP = 15,
		BaseDamage = 75,
		LayoutOrder = 3,
		Visual = {
			Color = rgb(214, 140, 62),
			Width = 0.28,
			HandleColor = rgb(160, 98, 44),
			HandleMaterial = Enum.Material.SmoothPlastic,
			Glow = true,
		},
	},
}

local Boots: { [string]: BootData } = {
	BareFeet = {
		Id = "BareFeet",
		DisplayName = "Bare Feet",
		Description = "Every champion starts somewhere.",
		Era = 1,
		Price = 0,
		Multiplier = 1,
		StaminaCapacity = 100, -- Bible §2.1: default Stamina Capacity
		LayoutOrder = 1,
		Visual = {
			Color = rgb(255, 255, 255),
			Material = Enum.Material.SmoothPlastic,
			Wings = false,
			Visible = false,
		},
	},
	LeatherSandals = {
		Id = "LeatherSandals",
		DisplayName = "Leather Sandals",
		Description = "Laced caligae that cushion every landing.",
		Era = 1,
		Price = 400,
		Multiplier = 1.5,
		StaminaCapacity = 1000,
		LayoutOrder = 2,
		Visual = {
			Color = rgb(150, 96, 56),
			Material = Enum.Material.SmoothPlastic,
			Wings = false,
			Visible = true,
		},
	},
	HermesWingedGreaves = {
		Id = "HermesWingedGreaves",
		DisplayName = "Hermes Winged Greaves",
		Description = "Divine greaves that turn each bounce into a thunderclap.",
		Era = 1,
		Price = 6000,
		Multiplier = 3,
		StaminaCapacity = 15000,
		LayoutOrder = 3,
		Visual = {
			Color = rgb(236, 196, 74),
			Material = Enum.Material.SmoothPlastic,
			Wings = true,
			Visible = true,
		},
	},
}

local Pets: { [string]: PetData } = {
	MiniCenturion = {
		Id = "MiniCenturion",
		DisplayName = "Mini Centurion",
		Rarity = "Common",
		Multiplier = 1.2,
		LayoutOrder = 1,
		Visual = {
			Archetype = "Centurion",
			PrimaryColor = rgb(176, 38, 38),
			SecondaryColor = rgb(238, 196, 160),
			AccentColor = rgb(222, 178, 64),
		},
	},
	BabyWarMammoth = {
		Id = "BabyWarMammoth",
		DisplayName = "Baby War Mammoth",
		Rarity = "Rare",
		Multiplier = 1.6,
		LayoutOrder = 2,
		Visual = {
			Archetype = "Mammoth",
			PrimaryColor = rgb(124, 104, 92),
			SecondaryColor = rgb(240, 232, 214),
			AccentColor = rgb(176, 38, 38),
		},
	},
	GoldenEagle = {
		Id = "GoldenEagle",
		DisplayName = "Golden Eagle",
		Rarity = "Legendary",
		Multiplier = 2.5,
		LayoutOrder = 3,
		Visual = {
			Archetype = "Eagle",
			PrimaryColor = rgb(240, 190, 52),
			SecondaryColor = rgb(255, 244, 214),
			AccentColor = rgb(255, 140, 26),
		},
	},
}

local Eggs: { [string]: EggData } = {
	BronzeEgg = {
		Id = "BronzeEgg",
		DisplayName = "Bronze Chrono-Egg",
		Era = 1,
		Price = 120,
		Weights = { MiniCenturion = 80, BabyWarMammoth = 18, GoldenEagle = 2 },
		LayoutOrder = 1,
		Color = rgb(196, 124, 64),
	},
	SilverEgg = {
		Id = "SilverEgg",
		DisplayName = "Silver Chrono-Egg",
		Era = 1,
		Price = 900,
		Weights = { MiniCenturion = 50, BabyWarMammoth = 42, GoldenEagle = 8 },
		LayoutOrder = 2,
		Color = rgb(200, 210, 222),
	},
	GildedEgg = {
		Id = "GildedEgg",
		DisplayName = "Gilded Chrono-Egg",
		Era = 1,
		Price = 4500,
		Weights = { MiniCenturion = 20, BabyWarMammoth = 55, GoldenEagle = 25 },
		LayoutOrder = 3,
		Color = rgb(255, 204, 64),
	},
}

local Titles: { [string]: TitleData } = {
	Recruit = {
		Id = "Recruit",
		DisplayName = "Recruit",
		Description = "Fresh off the training piazza.",
		Color = rgb(200, 200, 200),
		LayoutOrder = 1,
	},
	RhythmMaster = {
		Id = "RhythmMaster",
		DisplayName = "Rhythm Master",
		Description = "Reached the maximum rhythm combo.",
		Color = rgb(96, 220, 255),
		LayoutOrder = 2,
	},
	Gladiator = {
		Id = "Gladiator",
		DisplayName = "Gladiator",
		Description = "Rare drop from Gladiator Primus.",
		Color = rgb(255, 84, 84),
		LayoutOrder = 3,
	},
	ParadoxWalker = {
		Id = "ParadoxWalker",
		DisplayName = "Paradox Walker",
		Description = "Survived your first Temporal Paradox.",
		Color = rgb(178, 120, 255),
		LayoutOrder = 4,
	},
	ChronoChampion = {
		Id = "ChronoChampion",
		DisplayName = "Chrono Champion",
		Description = "Five Temporal Paradoxes and still swinging.",
		Color = rgb(255, 204, 64),
		LayoutOrder = 5,
	},
}

---------------------------------------------------------------------------------------
-- Mobs & spawners: The Grand Colosseum (Bible §3.2)
---------------------------------------------------------------------------------------

local Mobs: { [string]: MobData } = {
	RomanLegionary = {
		Id = "RomanLegionary",
		DisplayName = "Roman Legionary",
		MaxHealth = 250,
		RespawnSeconds = 8,
		WalkSpeed = 11,
		AggroRange = 45,
		LeashRange = 70,
		AttackRange = 7,
		AttackCooldown = 2.4,
		HitRadius = 2,
		IsBoss = false,
		ResetAfterIdleSeconds = 12,
		Attacks = {
			{
				Id = "ShieldSlash",
				DisplayName = "Shield Slash",
				Shape = { Kind = "Cone", Range = 9, AngleDegrees = 70 },
				Damage = 12,
				TelegraphSeconds = 0.8,
				RecoverySeconds = 0.5,
				Weight = 1,
			},
		},
		Drops = {
			BaseShards = 15,
			Bonus = {
				{ Kind = "Pet", Id = "MiniCenturion", Chance = 0.004 },
			},
		},
		Visual = {
			Scale = 1,
			SkinColor = rgb(234, 184, 146),
			ArmorColor = rgb(170, 36, 36),
			AccentColor = rgb(212, 175, 55),
			Crest = false,
		},
	},
	CenturionElite = {
		Id = "CenturionElite",
		DisplayName = "Centurion Elite",
		MaxHealth = 1200,
		RespawnSeconds = 20,
		WalkSpeed = 12,
		AggroRange = 50,
		LeashRange = 80,
		AttackRange = 9,
		AttackCooldown = 2.6,
		HitRadius = 2.6,
		IsBoss = false,
		ResetAfterIdleSeconds = 15,
		Attacks = {
			{
				Id = "CenturionCleave",
				DisplayName = "Centurion Cleave",
				Shape = { Kind = "Cone", Range = 11, AngleDegrees = 90 },
				Damage = 24,
				TelegraphSeconds = 0.8,
				RecoverySeconds = 0.6,
				Weight = 1,
			},
		},
		Drops = {
			BaseShards = 90,
			Bonus = {
				{ Kind = "Pet", Id = "BabyWarMammoth", Chance = 0.01 },
			},
		},
		Visual = {
			Scale = 1.3,
			SkinColor = rgb(222, 170, 132),
			ArmorColor = rgb(120, 24, 24),
			AccentColor = rgb(236, 196, 74),
			Crest = true,
		},
	},
	GladiatorPrimus = {
		Id = "GladiatorPrimus",
		DisplayName = "Gladiator Primus",
		MaxHealth = 10000,
		RespawnSeconds = 60,
		WalkSpeed = 13,
		AggroRange = 60,
		LeashRange = 75,
		AttackRange = 12,
		AttackCooldown = 2.2,
		HitRadius = 4.5,
		IsBoss = true,
		ResetAfterIdleSeconds = 20,
		Attacks = {
			{
				Id = "PrimusCleave",
				DisplayName = "Primus Cleave",
				Shape = { Kind = "Cone", Range = 16, AngleDegrees = 110 },
				Damage = 38,
				TelegraphSeconds = 0.8,
				RecoverySeconds = 0.7,
				Weight = 2,
			},
			{
				Id = "ArenaSlam",
				DisplayName = "Arena Slam",
				Shape = { Kind = "Circle", Range = 14, AngleDegrees = 360 },
				Damage = 55,
				TelegraphSeconds = 0.8,
				RecoverySeconds = 0.9,
				Weight = 1,
			},
		},
		Drops = {
			BaseShards = 1200,
			Bonus = {
				{ Kind = "Pet", Id = "GoldenEagle", Chance = 0.02 },
				{ Kind = "Title", Id = "Gladiator", Chance = 0.1 },
			},
		},
		Visual = {
			Scale = 2.2,
			SkinColor = rgb(206, 150, 112),
			ArmorColor = rgb(92, 92, 104),
			AccentColor = rgb(236, 196, 74),
			Crest = true,
		},
	},
}

-- 4x Legionary, 2x Centurion Elite, 1x Gladiator Primus on the central dais.
-- The arena entrance faces -Z (towards the Training Piazza), so the easiest mobs sit
-- closest to it and the elites hold the far half.
local Spawners: { SpawnerData } = {
	{ Id = "Legionary_South", MobId = "RomanLegionary", Offset = Vector3.new(0, 0, -58) },
	{ Id = "Legionary_East", MobId = "RomanLegionary", Offset = Vector3.new(58, 0, -10) },
	{ Id = "Legionary_West", MobId = "RomanLegionary", Offset = Vector3.new(-58, 0, -10) },
	{ Id = "Legionary_North", MobId = "RomanLegionary", Offset = Vector3.new(0, 0, 62) },
	{ Id = "Centurion_NorthEast", MobId = "CenturionElite", Offset = Vector3.new(48, 0, 44) },
	{ Id = "Centurion_NorthWest", MobId = "CenturionElite", Offset = Vector3.new(-48, 0, 44) },
	{ Id = "Primus_Dais", MobId = "GladiatorPrimus", Offset = Vector3.new(0, 0, 0) },
}

---------------------------------------------------------------------------------------
-- World layout, eras & Chronal Rifts (Bible §3)
---------------------------------------------------------------------------------------

local World = {
	GroundY = 0,
	SpawnPosition = Vector3.new(0, 4, -44),

	-- Training Piazza (spawn hub)
	PiazzaCenter = Vector3.new(0, 0, 0),
	PiazzaRadius = 84,
	ObeliskPosition = Vector3.new(0, 0, 0),
	ObeliskPedestalRadius = 10,
	BlacksmithPosition = Vector3.new(-56, 0, -4),
	IncubatorPosition = Vector3.new(56, 0, -4),
	RebirthArchPosition = Vector3.new(0, 0, -74),

	-- The Grand Colosseum: 200x200 stud circular arena, 20-stud walls.
	ColosseumCenter = Vector3.new(0, 0, 268),
	ColosseumRadius = 100,
	ColosseumWallHeight = 20,
	ColosseumWallThickness = 4,
	DaisRadius = 18,
	DaisHeight = 2,
}

local Eras: { EraData } = {
	{
		Index = 1,
		Id = "AncientRome",
		DisplayName = "Ancient Rome",
		Tagline = "Where every champion learns the rhythm.",
		SectorMinX = -320,
		SectorMaxX = 320,
		SectorMinZ = -420,
		SectorMaxZ = 440,
		Center = Vector3.new(0, 0, 0),
		Theme = {
			Ground = rgb(176, 196, 108),
			Path = rgb(222, 205, 168),
			Accent = rgb(196, 54, 46),
			Trim = rgb(236, 226, 204),
		},
	},
	{
		Index = 2,
		Id = "FeudalJapan",
		DisplayName = "Feudal Japan",
		Tagline = "Cherry blossoms hide steel.",
		SectorMinX = 320,
		SectorMaxX = 720,
		SectorMinZ = -220,
		SectorMaxZ = 220,
		Center = Vector3.new(520, 0, 0),
		Theme = {
			Ground = rgb(140, 176, 104),
			Path = rgb(200, 186, 160),
			Accent = rgb(214, 62, 72),
			Trim = rgb(255, 196, 214),
		},
	},
	{
		Index = 3,
		Id = "SteamAge",
		DisplayName = "Steam Age",
		Tagline = "Brass, smoke and pressure.",
		SectorMinX = 720,
		SectorMaxX = 1120,
		SectorMinZ = -220,
		SectorMaxZ = 220,
		Center = Vector3.new(920, 0, 0),
		Theme = {
			Ground = rgb(122, 112, 98),
			Path = rgb(160, 136, 104),
			Accent = rgb(196, 140, 58),
			Trim = rgb(86, 76, 70),
		},
	},
	{
		Index = 4,
		Id = "NeonFuture",
		DisplayName = "Neon Future",
		Tagline = "The end of time glows.",
		SectorMinX = 1120,
		SectorMaxX = 1520,
		SectorMinZ = -220,
		SectorMaxZ = 220,
		Center = Vector3.new(1320, 0, 0),
		Theme = {
			Ground = rgb(40, 44, 66),
			Path = rgb(70, 76, 110),
			Accent = rgb(0, 236, 255),
			Trim = rgb(255, 60, 220),
		},
	},
}

-- Each rift sits on the boundary between two sectors. Requirements are checked on the
-- server against the *stored* RebirthCount/TotalStrength (§3.1).
local Portals: { [string]: PortalData } = {
	RiftToJapan = {
		Id = "RiftToJapan",
		DisplayName = "Chronal Rift: Feudal Japan",
		FromEra = 1,
		ToEra = 2,
		RequiredStrength = 10000,
		RequiredRebirths = 0,
		Position = Vector3.new(320, 0, 0),
	},
	RiftToSteam = {
		Id = "RiftToSteam",
		DisplayName = "Chronal Rift: Steam Age",
		FromEra = 2,
		ToEra = 3,
		RequiredStrength = 100000,
		RequiredRebirths = 0,
		Position = Vector3.new(720, 0, 0),
	},
	RiftToNeon = {
		Id = "RiftToNeon",
		DisplayName = "Chronal Rift: Neon Future",
		FromEra = 3,
		ToEra = 4,
		RequiredStrength = 500000,
		RequiredRebirths = 0,
		Position = Vector3.new(1120, 0, 0),
	},
}

---------------------------------------------------------------------------------------
-- Rebirth Paradox skill tree (§2.2)
---------------------------------------------------------------------------------------

local SkillTree: { [string]: SkillNodeData } = {
	KineticEcho = {
		Id = "KineticEcho",
		DisplayName = "Kinetic Echo",
		Description = "+15% KP per bounce per level.",
		Effect = "KPGain",
		PerLevel = 0.15,
		MaxLevel = 5,
		CostPerLevel = 1,
		Requires = {},
		LayoutPosition = Vector2.new(0.2, 0.2),
	},
	TemporalSatchel = {
		Id = "TemporalSatchel",
		DisplayName = "Temporal Satchel",
		Description = "+30% Stamina Capacity per level.",
		Effect = "Capacity",
		PerLevel = 0.3,
		MaxLevel = 5,
		CostPerLevel = 1,
		Requires = { { Id = "KineticEcho", Level = 1 } },
		LayoutPosition = Vector2.new(0.2, 0.55),
	},
	ParadoxEdge = {
		Id = "ParadoxEdge",
		DisplayName = "Paradox Edge",
		Description = "+15% rope damage per level.",
		Effect = "Damage",
		PerLevel = 0.15,
		MaxLevel = 5,
		CostPerLevel = 1,
		Requires = {},
		LayoutPosition = Vector2.new(0.8, 0.2),
	},
	ShardSiphon = {
		Id = "ShardSiphon",
		DisplayName = "Shard Siphon",
		Description = "+10% Shards from mob payouts per level.",
		Effect = "Shards",
		PerLevel = 0.1,
		MaxLevel = 5,
		CostPerLevel = 1,
		Requires = { { Id = "ParadoxEdge", Level = 1 } },
		LayoutPosition = Vector2.new(0.8, 0.55),
	},
	ChronoLuck = {
		Id = "ChronoLuck",
		DisplayName = "Chrono Luck",
		Description = "+10% weight for Rare and Legendary hatches per level.",
		Effect = "EggLuck",
		PerLevel = 0.1,
		MaxLevel = 5,
		CostPerLevel = 1,
		Requires = { { Id = "KineticEcho", Level = 2 }, { Id = "ParadoxEdge", Level = 2 } },
		LayoutPosition = Vector2.new(0.5, 0.38),
	},
	EpochResonance = {
		Id = "EpochResonance",
		DisplayName = "Epoch Resonance",
		Description = "+1 pet equip slot.",
		Effect = "PetSlots",
		PerLevel = 1,
		MaxLevel = 1,
		CostPerLevel = 3,
		Requires = { { Id = "TemporalSatchel", Level = 3 }, { Id = "ShardSiphon", Level = 3 } },
		LayoutPosition = Vector2.new(0.5, 0.82),
	},
}

---------------------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------------------

local Rhythm = {
	-- One beat every 0.75s (80 BPM). A default R15 jump is airborne ~0.54s, so hopping
	-- on every beat leaves a comfortable ground window between bounces.
	BeatInterval = 0.75,
	-- Bible §2.1: a press OR a landing within 0.15s of a beat counts as on-beat.
	ToleranceSeconds = 0.15,
	ComboStart = 1.0,
	ComboStep = 0.1,
	ComboCap = 2.5,
	-- Visual/audio tiers (§4.3 trails White -> Blue -> Gold -> Red, §4.4 +1 semitone/tier).
	ComboTiers = {
		{ MinCombo = 1.0, Name = "Kinetic", Color = rgb(255, 255, 255) },
		{ MinCombo = 1.5, Name = "Charged", Color = rgb(64, 156, 255) },
		{ MinCombo = 2.0, Name = "Gilded", Color = rgb(255, 196, 46) },
		{ MinCombo = 2.5, Name = "Overdrive", Color = rgb(255, 56, 56) },
	} :: { ComboTier },
	SemitonesPerTier = 1,
	-- Fraction of a beat after the beat at which the rope passes under the feet.
	RopeUnderFeetPhase = 0.36,
	-- Training stance drops after this long without a rope bounce.
	EngagedTimeout = 2.5,
}

local Training = {
	BaseStaminaCapacity = 100,
	-- Server-side bounce report validation (anti-exploit).
	MinAirtime = 0.12,
	MaxAirtime = 3,
	MaxReportAge = 2.5, -- landing timestamp may be at most this old on arrival
	MaxFutureSkew = 0.3, -- or this far in the future (clock sync jitter)
	MinBounceInterval = 0.3, -- reported landings at least this far apart
	JumpCreditCap = 3, -- server-observed takeoffs that can be banked ahead of reports
	-- Epoch Obelisk banking
	ObeliskPromptDistance = 14,
	ObeliskValidationDistance = 24,
	BankCooldown = 0.5,
}

local Combat = {
	StrengthExponent = 0.65, -- DMG = ((TotalStrength ^ 0.65) + RopeBaseDamage) * PetMultiplierSum
	MaxValidationDistance = 16, -- §6: server rejects any target further than 16 studs
	MaxTargetsPerAttack = 8,
	AngleToleranceDegrees = 15, -- extra server slack on cone checks (latency)
	HeightTolerance = 12,
	CooldownJitterSeconds = 0.2, -- attacks may arrive this much early (network jitter); the sustained rate may not
	AirborneGraceSeconds = 0.35,
	Attacks = {
		GroundLash = {
			Kind = "GroundLash",
			DisplayName = "Ground Lash",
			Multiplier = 1.0,
			Shape = { Kind = "Cone", Range = 14, AngleDegrees = 45 },
			Duration = 0.35,
			Cooldown = 0.42,
			RequiresAirborne = false,
		},
		AerialSweep = {
			Kind = "AerialSweep",
			DisplayName = "Aerial Sweep",
			Multiplier = 0.75,
			Shape = { Kind = "Circle", Range = 12, AngleDegrees = 360 },
			Duration = 0.45,
			Cooldown = 0.5,
			RequiresAirborne = true,
		},
	} :: { [AttackKind]: AttackData },
}

local Rewards = {
	ContributionThreshold = 0.05, -- §2.1: must deal >= 5% of max HP to be paid
	MinimumPayout = 1, -- eligible contributors always receive at least 1 Shard
}

local Rebirth = {
	RequiredEra = 4,
	RequiredStrength = 1000000,
	MultiplierBase = 1.5, -- +50% compound per rebirth => 1.5 ^ RebirthCount
	TokensPerRebirth = 1,
	MilestoneTitles = {
		[1] = "ParadoxWalker",
		[5] = "ChronoChampion",
	} :: { [number]: string },
}

local Pet = {
	MaxEquipped = 3,
	MaxInventory = 60,
	RarityOrder = { Common = 1, Rare = 2, Epic = 3, Legendary = 4 } :: { [Rarity]: number },
	RarityColors = {
		Common = rgb(200, 200, 200),
		Rare = rgb(64, 156, 255),
		Epic = rgb(178, 102, 255),
		Legendary = rgb(255, 196, 46),
	} :: { [Rarity]: Color3 },
}

local Starter = {
	Rope = "HempCord",
	Boots = "BareFeet",
	Title = "Recruit",
}

local Data = {
	StoreName = "ChronoRope_PlayerData_v1",
	KeyPrefix = "Player_",
	CurrentVersion = 1,
}

local Security = {
	RateLimits = {
		ReportBounce = { Capacity = 6, RefillPerSecond = 3 },
		RequestAttack = { Capacity = 6, RefillPerSecond = 4 },
		Request = { Capacity = 8, RefillPerSecond = 3 },
	} :: { [string]: RateLimitData },
	-- Suspicious-activity strikes (invalid payloads, impossible timings) inside the
	-- window before the player is kicked. 0 disables kicking (log only).
	KickStrikeThreshold = 40,
	StrikeWindowSeconds = 60,
}

local UI = {
	BossBarRange = 60, -- §5.1: boss bar appears within 60 studs of the boss
	MobBarRange = 70,
	Palette = {
		Background = rgb(18, 20, 30),
		Panel = rgb(30, 33, 48),
		PanelLight = rgb(46, 50, 72),
		Accent = rgb(255, 196, 46),
		AccentDark = rgb(196, 140, 24),
		Text = rgb(244, 240, 228),
		TextDim = rgb(170, 168, 160),
		Good = rgb(76, 224, 120),
		Bad = rgb(255, 72, 72),
		Kinetic = rgb(96, 220, 255),
		Shard = rgb(178, 120, 255),
	},
}

-- Animation asset ids (R15). Leave "" until the Blender/Animation Editor exports are
-- uploaded: controllers fall back to procedural motion when an id is empty.
local Animations = {
	JumpRopeLoop = "",
	GroundLashAttack = "",
	AirSweepAttack = "",
	MobTelegraphSlash = "",
}

-- Sound ids. The rbxasset:// paths are built-in client sounds used as placeholders until
-- the final Rope_Whoosh / Whip_Crack / Obelisk_Bank assets are uploaded. Roblox retires old
-- built-in files from time to time, so each placeholder lists fallbacks.
local PING = "rbxasset://sounds/electronicpingshort.wav"
local PING_FALLBACKS = { "rbxasset://sounds/electronicpingshort.mp3" }

local Sounds: { [string]: SoundData } = {
	RopeWhoosh = {
		SoundId = "rbxasset://sounds/swordlunge.mp3",
		Volume = 0.45,
		RollOffMaxDistance = 60,
		-- action_jump ships with the default character sounds, so it always exists.
		Fallbacks = { "rbxasset://sounds/swordslash.mp3", "rbxasset://sounds/action_jump.mp3" },
	},
	WhipCrack = {
		SoundId = "rbxasset://sounds/swordslash.wav",
		Volume = 0.8,
		RollOffMaxDistance = 120,
		Fallbacks = { "rbxasset://sounds/swordslash.mp3", "rbxasset://sounds/action_jump_land.mp3" },
	},
	ObeliskBank = { SoundId = PING, Volume = 0.9, RollOffMaxDistance = 140, Fallbacks = PING_FALLBACKS },
	RhythmHit = { SoundId = PING, Volume = 0.25, RollOffMaxDistance = 40, Fallbacks = PING_FALLBACKS },
	Hatch = { SoundId = PING, Volume = 0.7, RollOffMaxDistance = 80, Fallbacks = PING_FALLBACKS },
}

---------------------------------------------------------------------------------------
-- Profile template
---------------------------------------------------------------------------------------

local DefaultPlayerData: PlayerData = {
	DataVersion = Data.CurrentVersion,

	UnbankedKP = 0,
	TotalStrength = 0,
	Shards = 0,

	RebirthCount = 0,
	RebirthTokens = 0,
	SkillLevels = {},

	HighestEra = 1,
	UnlockedPortals = {},

	OwnedRopes = { [Starter.Rope] = true },
	EquippedRope = Starter.Rope,
	OwnedBoots = { [Starter.Boots] = true },
	EquippedBoots = Starter.Boots,

	Pets = {},
	EquippedPets = {},
	NextPetUid = 1,

	OwnedTitles = { [Starter.Title] = true },
	EquippedTitle = Starter.Title,

	Stats = {
		Bounces = 0,
		OnBeatBounces = 0,
		BestCombo = 1,
		StrengthBanked = 0,
		ShardsEarned = 0,
		MobsDefeated = 0,
		BossesDefeated = 0,
		EggsHatched = 0,
		Rebirths = 0,
		PlaySeconds = 0,
	},
	FirstJoinUnix = 0,
	LastJoinUnix = 0,
}

---------------------------------------------------------------------------------------

local GameConfig = {
	Title = "ChronoRope: Epoch Striker",

	Ropes = Ropes,
	Boots = Boots,
	Pets = Pets,
	Eggs = Eggs,
	Titles = Titles,
	Mobs = Mobs,
	Spawners = Spawners,
	World = World,
	Eras = Eras,
	Portals = Portals,
	SkillTree = SkillTree,

	Rhythm = Rhythm,
	Training = Training,
	Combat = Combat,
	Rewards = Rewards,
	Rebirth = Rebirth,
	Pet = Pet,
	Starter = Starter,
	Data = Data,
	Security = Security,
	UI = UI,
	Animations = Animations,
	Sounds = Sounds,

	DefaultPlayerData = DefaultPlayerData,
}

return deepFreeze(GameConfig)
