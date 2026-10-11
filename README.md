# ChronoRope: Epoch Striker

[![CI](https://github.com/xbunny416/RopeStriker/actions/workflows/ci.yml/badge.svg)](https://github.com/xbunny416/RopeStriker/actions/workflows/ci.yml)

A hybrid **incremental simulator / action RPG** for Roblox. Jump rope on the beat to
charge Kinetic Power, bank it at the Epoch Obelisk to grow permanent Strength, lash
shared-health gladiators in the Grand Colosseum for Shards, gear up, hatch chrono-pets,
punch through Chronal Rifts to Era 4 — then trigger a Temporal Paradox (rebirth) and do
it all again, 50% stronger.

Everything in this repository is modern strict Luau (`--!strict`) built with Rojo. The
place is playable straight from `rojo build`: the Zone 1 world, mobs, pets and UI are
generated procedurally as a stylised greybox until the Blender/FBX art drops in.

| Bible section | Where it lives |
| --- | --- |
| §2.1 KP, capacity, damage, 5% payouts | `Shared/Formulas.luau`, `Modules/PlayerDataOps.luau`, `Modules/DamageLedger.luau` |
| §2.1 rhythm window & combo | `Shared/Rhythm.luau`, `Controllers/RopeController.luau`, `Services/TrainingService.luau` |
| §2.2 Temporal Paradox + skill tree | `Services/RebirthService.luau`, `PlayerDataOps.Rebirth`, `UI/RebirthPanel.luau` |
| §3 world, rifts, streaming | `World/WorldBuilder.luau`, `Services/PortalService.luau`, `Controllers/PortalController.luau`, `default.project.json` |
| §3.2 mobs & spawners | `Services/MobService.luau`, `Modules/MobBrain.luau`, `World/MobFactory.luau` |
| §4 rope rig, animation, VFX, SFX | `Services/EquipmentService.luau`, `RopeController`, `Modules/ProceduralPose.luau`, `Modules/Telegraph.luau`, `MobVisualsController` |
| §5 cross-platform UI | `Controllers/UIController.luau`, `UI/*` |
| §6 code architecture | the tree below |

## Quick start

```bash
rokit install                         # rojo, stylua, selene, luau-lsp, lune (pinned in rokit.toml)
rojo build -o build/ChronoRope.rbxlx  # then open the file in Roblox Studio and press Play
# or live-sync: `rojo serve` + the Rojo Studio plugin
```

* **Data:** with Studio API access disabled, ProfileService runs on an in-memory mock
  store (nothing is saved). Enable *Game Settings → Security → Studio Access to API
  Services* to test real DataStores.
* **Art:** animations, sounds and models are optional drop-ins — see
  [Asset integration](#asset-integration).

### Controls

| | PC | Mobile | Console |
| --- | --- | --- | --- |
| Rope jump (Training zones) | `Space` | Action Button (**JUMP**) or jump button | `A` / `R2` |
| Swing (Colosseum) | Left click | Action Button (**SWING**) | `R2` |
| Aerial Sweep | Swing while airborne | Jump, then SWING | `A`, then `R2` |
| Bank KP | `E` at the Epoch Obelisk, or step on its pedestal | Tap prompt / pedestal | `X` / pedestal |
| Rebirth · Shop · Pets | Left drawer | Left drawer | `Y` toggles drawer, `B` closes panels |

## Project layout

```
default.project.json            Rojo tree (Workspace.StreamingEnabled, radius 256 / min 64)
src/
├─ ReplicatedStorage/Source/
│  ├─ Configuration/GameConfig.luau   typed schema + all tunables + profile template
│  ├─ Network/
│  │  ├─ RemoteEvents/                 Folder of RemoteEvent/RemoteFunction instances
│  │  ├─ Definitions.luau              canonical remote list (direction + payload)
│  │  └─ Remotes.luau                  typed accessors + payload types
│  ├─ Packages/ProfileService.luau     vendored, unmodified (Apache-2.0, see licenses/)
│  └─ Shared/                          Formulas, Rhythm, Zones, Spatial, Guard, Signal,
│                                      Trove, NumberFormat, Tags
├─ ServerScriptService/Source/
│  ├─ Main.server.luau                 boot order: World → Data → Equipment → Pets →
│  │                                   Training → Mobs → Combat → Portals → Rebirth
│  ├─ Services/                        DataService, TrainingService, CombatService,
│  │                                   MobService, EquipmentService, PetService,
│  │                                   PortalService, RebirthService, WorldService
│  ├─ Modules/                         PlayerDataOps, DamageLedger, MobBrain,
│  │                                   GroundTracker, RateLimiter, Security
│  └─ World/                           WorldBuilder (procedural map), MobFactory
└─ StarterPlayer/StarterPlayerScripts/Source/
   ├─ Main.client.luau
   ├─ Controllers/                     RopeController, UIController, MobVisualsController,
   │                                   PetController, PortalController, WorldController
   ├─ Modules/                         ClientState, BeamCurve, ProceduralPose, Telegraph,
   │                                   PetModels, SoundPlayer
   └─ UI/                              UIKit, PanelFrame, ShopPanel, PetsPanel,
                                       RebirthPanel, Toasts
tests/                                 Lune test harness + specs (unit + service integration)
docs/                                  design, architecture, world, art, animation, VFX/SFX, UI
scripts/validate.sh                    the full quality gate
```

## Quality gate

```bash
./scripts/validate.sh
```

1. **Strict type check** of every file with `luau-lsp analyze` against the official
   Roblox API definitions and the Rojo sourcemap — under both the legacy and the new
   Luau type solver.
2. **Lint** with Selene (Roblox std) and **format check** with StyLua.
3. **119 tests** under Lune: the economy, rhythm, payout, mutation and mob-AI modules
   run unmodified through a Roblox-shaped module loader; DataService, TrainingService
   and CombatService run end-to-end against a mocked engine (players, raycasts, clocks,
   remotes, ProfileService) to exercise the anti-exploit paths; the procedural world is
   built against Lune's reflection-checked instance model.
4. **Place build** with Rojo.

The same gate runs in GitHub Actions (`.github/workflows/ci.yml`) on every pull request
and every push to `main`, with the toolchain installed from `rokit.toml`; each run
attaches the built `ChronoRope.rbxlx` as a downloadable artifact.

## Architecture in one minute

* **Server authority everywhere.** Clients send *requests* (a bounce's timestamps, an
  attack's claimed targets); the server re-validates timing on the synchronised clock,
  physical evidence (a witnessed takeoff, airborne/grounded state), distance (≤ 16
  studs), cones, cooldowns, rate limits and payload shapes before touching data.
* **Atomic data.** All profile writes go through `DataService.Mutate`, which refuses to
  run a mutator that yields — so `AddKP`, `BankPower`, `AddShards`, `Rebirth` and every
  shop/pet/portal/skill operation is atomic. ProfileService provides session locking,
  auto-save and release-on-leave.
* **Cheap replication.** Scalars ride Player attributes (also driving other players'
  trails, pets and titles); tables ride `StatePatch`; cosmetic effects are computed
  locally from a shared beat clock and replicated attributes.
* **Streaming-safe client.** Everything world-related is found through CollectionService
  tags, so instances can stream in and out freely.

More: [docs/Architecture.md](docs/Architecture.md) ·
[docs/GameDesign.md](docs/GameDesign.md) · [docs/WorldBuilding.md](docs/WorldBuilding.md) ·
[docs/ArtPipeline.md](docs/ArtPipeline.md) · [docs/Animation.md](docs/Animation.md) ·
[docs/VFX_SFX.md](docs/VFX_SFX.md) · [docs/UI_UX.md](docs/UI_UX.md)

## Asset integration

| Asset | Drop-in location / setting | Fallback until provided |
| --- | --- | --- |
| Animations (`JumpRope_Loop`, `GroundLash_Attack`, `AirSweep_Attack`, `Mob_Telegraph_Slash`) | `GameConfig.Animations.*` asset ids | Procedural Motor6D poses (`ProceduralPose`, mob `WeaponShoulder`) |
| SFX (`Rope_Whoosh`, `Whip_Crack`, `Obelisk_Bank`) | `GameConfig.Sounds.*.SoundId` | Built-in `rbxasset://sounds/...` placeholders |
| Rope handles | `ReplicatedStorage.Assets.Ropes.<Visual.Template>` with `HandleL` / `HandleR` | Procedural handles |
| Pets (≤ 500 tris) | `ReplicatedStorage.Assets.Pets.<PetId>` (PrimaryPart set) | Procedural chibi greybox |
| Mob rigs | `ServerStorage.Assets.Mobs.<MobId>` (Humanoid + HumanoidRootPart) | Procedural legionary rigs |
| World | Any map whose interactables carry the tags in `Shared/Tags.luau`, under `Workspace.ChronoWorld` | Procedural greybox (`WorldBuilder`) |

## Third-party

`src/ReplicatedStorage/Source/Packages/ProfileService.luau` is
[ProfileService](https://github.com/MadStudioRoblox/ProfileService) by loleris
(MadStudioRoblox), vendored unmodified under the Apache License 2.0 —
see `licenses/ProfileService-LICENSE.txt`.
