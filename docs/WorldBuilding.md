# World Building

The open world is a row of chronological **sectors** along the X axis, separated by
stone walls whose only openings are **Chronal Rifts**. `World/WorldBuilder.luau` builds
the full greybox at server start when `Workspace.ChronoWorld` does not exist (≈470 parts,
SmoothPlastic / Neon / Pebble only). All coordinates below come from `GameConfig.World`,
`GameConfig.Eras` and `GameConfig.Portals`.

## Map

```
 top view (+X → right, +Z ↓)

 X:   -320                    0                     320        720        1120       1520
 Z -420 ┌──────────────────────────────────────────┐
        │                                          │
        │            Rebirth Portal arch (0,-74)   │
        │                Spawn (0,-44)             ├──────────┬──────────┬──────────┐
        │ Blacksmith (-56,-4)  ◆ Obelisk (0,0)  Incubator (56,-4)      │          │          │
        │          TRAINING PIAZZA  r = 84         ═══road══▶ RIFT ▶ II  ▶ RIFT ▶ III ▶ RIFT ▶ IV │
        │                  ║ road                  ├──────────┴──────────┴──────────┘
        │       ┌──────── gate (faces -Z) ───────┐ │  Eras II–IV: Z −220 … 220, plaza r = 60
        │       │      GRAND COLOSSEUM           │ │  with an Epoch Obelisk at each centre
        │       │   centre (0, 268), r = 100     │ │  (520,0) · (920,0) · (1320,0)
        │       │   dais r = 18 at the centre    │ │
        │       └────────────────────────────────┘ │
 Z  440 └──────────────────────────────────────────┘
```

## Zone 1 — Ancient Rome

**Training Piazza (spawn hub)** — Pebble plaza (r 84) with a marble inlay, twelve
columns offset so both roads stay clear.

| Feature | Position | Notes |
| --- | --- | --- |
| Epoch Obelisk | (0, 0, 0) | 22-stud gold shaft, Neon glyph bands, glowing capstone (PointLight + sparkles), **Neon pedestal r 10** that auto-banks when stepped on, `BankPrompt` (E / X) |
| Blacksmith | (-56, 0, -4), facing the obelisk | open forge stall, anvil `ShopPrompt` (OpensPanel = Shop), ember particles, rope rack |
| Chrono-Egg Incubator | (56, 0, -4), facing the obelisk | three pedestals (Bronze / Silver / Gilded), `HatchPrompt` per egg (0.35 s hold) |
| Rebirth Portal arch | (0, 0, -74) | marble arch with a Neon paradox field, `RebirthPrompt` (OpensPanel = Rebirth) |
| Spawn | (0, 0.5, -44) | 4 s spawn ForceField |

**The Grand Colosseum** — centre (0, 0, 268), 200×200-stud circular sand floor,
a 40-segment ring of 20-stud stone walls (4 thick, marble cap; two segments left open
for the gate), three stepped spectator
tiers rising to 24/27/30 studs, the gate facing the piazza with pillars, a lintel and a
sign, and a central dais (r 18, 2 studs tall) ringed in red Neon with four braziers.

| Spawner | Offset from centre | Mob |
| --- | --- | --- |
| Legionary_South / East / West / North | (0,−58) (58,−10) (−58,−10) (0,62) | Roman Legionary ×4 |
| Centurion_NorthEast / NorthWest | (48,44) (−48,44) | Centurion Elite ×2 |
| Primus_Dais | (0,0) on the dais | Gladiator Primus |

The easiest mobs sit near the gate; elites hold the far half. Each spawner has a faint
red sigil on the sand.

## Chronal Rifts

Each rift is a 6-stud-thick, 60-stud-tall sector wall with a 28×28 opening at Z = 0,
framed by a 20-segment Neon ring in the destination era's accent colour, and filled with
a ForceField-material **barrier** (tag `ChronalRiftGate`, emitting particles). The
barrier collides for everyone on the server; `PortalController` turns `CanCollide` off
*locally* once the server has unlocked the rift for that player (stored Strength /
Rebirths checked within 45 studs of the rift). `PortalService` independently returns
anyone found inside a sector they have not unlocked.

## Streaming

* `StreamingEnabled = true`, `StreamingTargetRadius = 256`, `StreamingMinRadius = 64`.
* The world model is parented once after construction (one replication burst).
* Mob rigs use `ModelStreamingMode.Atomic`. Static scenery uses the default mode.
* Everything the client needs to find is tagged, so nothing assumes an instance exists.

## Tag contract (replacing the greybox)

Build the final map in Studio or import it from Blender, put it under
`Workspace.ChronoWorld` (so the runtime builder stays off) and keep these contracts:

| Tag | On | Must provide |
| --- | --- | --- |
| `EpochObelisk` | Model (PrimaryPart near the shaft) | attribute `Era`; a ProximityPrompt named `BankPrompt` |
| `ObeliskPedestal` | cylinder BasePart lying on its X axis | diameter in `Size.Y`; top surface walkable |
| `PanelPrompt` | ProximityPrompt | attribute `OpensPanel` = `Shop` / `Rebirth` / `Pets` |
| `ChronoEgg` | Model (PrimaryPart = pedestal) | attribute `EggId`; a ProximityPrompt named `HatchPrompt` |
| `MobSpawner` | BasePart on the floor | attributes `SpawnerId` (matching `GameConfig.Spawners`) and `MobId` |
| `ChronalRiftGate` | BasePart barrier (`CanCollide = true`) | attributes `PortalId`, `ToEra`, `RequiredStrength`, `RequiredRebirths`; optional `LabelAttachment` |

Also provide a `SpawnLocation` in the hub. To bake the greybox instead of building at
runtime, run in the Studio command bar and save:

```lua
require(game.ServerScriptService.Source.World.WorldBuilder).Build(workspace)
```

## Lighting

`WorldBuilder.ApplyLighting` sets a warm afternoon (ClockTime 14.5), soft shadows, an
Atmosphere for depth, a light Bloom so Neon glows, and a gentle colour grade. Set the
`ManualLighting` attribute on `Lighting` to keep hand-authored settings.
