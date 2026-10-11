# Architecture

## Runtime topology

```
ServerScriptService.Source.Main  (Init all, then Start all)
 ├─ WorldService      builds/validates the map (tag contract), lighting
 ├─ DataService       ProfileService profiles, atomic Mutate, replication
 ├─ EquipmentService  rope rig (HandleL/HandleR Motor6D + Beam + Trails), boots, shop remotes
 ├─ PetService        Chrono-Egg prompts (server-side), pet equip remote
 ├─ TrainingService   bounce validation + KP, combo authority, Epoch Obelisk banking
 ├─ MobService        spawners, MobBrain AI, telegraphs/strikes, shared health, payouts
 ├─ CombatService     attack validation + damage
 ├─ PortalService     rift unlocks, sector enforcement, Era/Mode attributes
 └─ RebirthService    Temporal Paradox + skill tree remotes

StarterPlayerScripts.Source.Main  (waits for game.Loaded, starts ClientState, Init all, Start all)
 ├─ RopeController        input, rhythm judging, landing raycasts, ring UI, rope rendering, attacks
 ├─ UIController          HUD, drawer, panels, toasts, boss bar
 ├─ MobVisualsController  health bars, telegraph decals, wind-up poses, damage numbers
 ├─ PetController         local pet followers for every player
 ├─ PortalController      local collision gates + rift labels
 └─ WorldController       nameplates (titles), panel prompts

ReplicatedStorage.Source  (shared, pure, unit-tested)
 GameConfig · Formulas · Rhythm · Zones · Spatial · Guard · Signal · Trove · NumberFormat · Tags · Network
```

Services and controllers are plain ModuleScripts exposing `Init()` (wire state and
remotes; never yields) and `Start()` (connect players, loops and world interactions).
Dependencies are explicit `require`s; there are no cycles.

## Data

* **Persistence:** `ProfileService.GetProfileStore("ChronoRope_PlayerData_v1", DefaultPlayerData)`.
  Keys are `Player_<UserId>`. Session locking (single active server per profile,
  force-load + release-and-kick on the old server), auto-save every ~30 s, save on
  release and at shutdown all come from ProfileService. `AddUserId` is called for GDPR
  erasure support.
* **Load path:** `LoadProfileAsync` → `AddUserId` → `Reconcile` (fills new template
  fields) → `ListenToRelease` (kick if the session is stolen) → `Migrate` (versioned
  migrations) → `Sanitize` (repairs NaN/negative numbers, unowned or deleted equipped
  items, dangling pet references, duplicate equips, over-capacity KP) → replicate.
  A failed load kicks the player rather than letting them play on an unsaved profile.
* **Atomic mutations:** `DataService.Mutate(player, changedKeys, mutator)` runs the
  mutator in its own coroutine and raises if it yields. Because Luau only interleaves
  coroutines at yields, every mutation is therefore atomic ("thread-safe"). Mutations
  are refused before load and after release. The rules themselves live in the pure
  `PlayerDataOps` module (`AddKP`, `BankPower`, `AddShards`, `SpendShards`, `Rebirth`,
  `Purchase`, `Equip`, `GrantPet`, `SetPetEquipped`, `UnlockPortal`, `UnlockSkill`, ...).
* **Replication:** scalar fields → Player attributes (`UnbankedKP`, `TotalStrength`,
  `Shards`, `RebirthCount`, `RebirthTokens`, `HighestEra`, `Equipped*`) plus derived
  `StaminaCapacity`, `PetMultiplier`, `EquippedPetIds`; table fields → `StatePatch`
  (owner only); full copy → `StateSnapshot` on load and `GetSnapshot` on demand. The
  client mirror is `Modules/ClientState`.

## Network contract

Defined once in `Network/Definitions.luau`; the `RemoteEvents` folder holds one
`*.model.json` per remote; `tests/specs/Network.spec.luau` keeps them in sync.

| Remote | Dir | Payload | Server-side validation |
| --- | --- | --- | --- |
| `ReportBounce` | C→S | `pressTime, landTime` | rate limit 6 burst / 3 per s; finite numbers; airtime 0.12–3 s; landing ≤ 2.5 s old and ≤ 0.3 s in the future; no overlap with the previous bounce; reported landings ≥ 0.3 s apart (judged on the timestamps, so jitter cannot bunch honest reports); Training zone only; **a takeoff witnessed by GroundTracker**; re-judged on the server clock |
| `RequestAttack` | C→S | `attack, direction, targetIds` | rate limit 6 / 4 per s; known attack kind; finite non-zero direction; ≤ 8 unique integer ids; per-attack cooldown booked GCRA-style (may arrive 0.2 s early for jitter, never faster on average); Aerial Sweep needs recent airborne state, Ground Lash recent ground contact; cone aim within 80° of the character's facing, waiting up to 0.35 s for the server's lagging view of a turning character to catch up; each target alive, **≤ 16 studs** (edge distance) and inside the volume + tolerance |
| `PurchaseItem`, `EquipItem` | C→S fn | `category, itemId` | rate limit; category whitelist; string ≤ 64; all rules in `PlayerDataOps` (price, era, ownership) |
| `SetPetEquipped` | C→S fn | `uid | "*best", equipped` | rate limit; types; ownership & slot count |
| `RequestRebirth` | C→S fn | — | rate limit; 3 s cooldown; Era 4 + 1M Strength from stored data |
| `UnlockSkill` | C→S fn | `nodeId` | rate limit; known node; tokens, prerequisites, max level |
| `GetSnapshot` | C→S fn | — | rate limit; returns a deep copy |
| `BounceResult`, `CombatFeedback`, `MobReward`, `Banked`, `HatchResult`, `RebirthComplete`, `PortalUnlocked`, `StateSnapshot`, `StatePatch`, `Notify` | S→C | see `Remotes.luau` types | — |
| `AttackFx` | S→all (unreliable) | `userId, attack, direction, hitPosition?` | cosmetic only |

Interactions that need proximity (banking, hatching) are **server-side ProximityPrompt
handlers** with an extra distance check — there is no remote to spoof.

## Anti-exploit model

| Threat | Mitigation |
| --- | --- |
| Remote spam | Token-bucket `RateLimiter` per player per remote family |
| Malformed payloads (NaN, huge tables, wrong types) | `Shared/Guard` on every argument; failures add Security strikes |
| Free KP without jumping | `GroundTracker` raycasts every character at 30 Hz; each bounce consumes one *witnessed takeoff* credit. Chained hops touch the ground for a single physics step, so a fall-then-rise with its low point near the floor also counts as a takeoff |
| Perfect-timing spoofing | Timestamps must be physically plausible and recent; combo authority stays on the server; gains are capped by Stamina Capacity and banking requires being at an obelisk |
| Kill-aura / long-range hits | ≤ 16-stud edge-distance check, cone/radius re-test, facing check, max 8 targets, per-attack cooldowns |
| Air/ground attack spoofing | GroundTracker airborne/grounded history with a 0.35 s grace window |
| Noclip through rifts | Client gates are cosmetic: `PortalService` checks every character's sector 4×/s and returns intruders to the hub |
| Mob manipulation | Mobs are server-owned assemblies (`SetNetworkOwner(nil)`); health and ledgers are server tables |
| Data tampering / duplication | Session-locked profiles; atomic mutations; validation inside the atomic section (e.g. hatching re-checks Shards before spending) |
| Repeat offenders | `Modules/Security` sliding-window strikes; kick at 40 within 60 s (`GameConfig.Security`) |

## Streaming

`Workspace.StreamingEnabled` with `StreamingTargetRadius = 256` and
`StreamingMinRadius = 64` (set in `default.project.json`). Client code never assumes an
instance exists: mobs (`ChronoMob`), rift gates (`ChronalRiftGate`), eggs and prompts are
discovered through CollectionService added/removed signals. Mob rigs use
`ModelStreamingMode.Atomic` so they always arrive whole. Effects (telegraph decals, pet
followers, damage numbers, rift labels) are client-local instances.

## Shared clock

The beat clock is derived from `workspace:GetServerTimeNow()`: beat `n` happens at
`n × 0.75 s`. Every client renders the same beat (prompt ring, rope orbit, procedural
pose) without any beat messages, and the server judges reported timestamps against the
same clock. Rhythm math uses a 1 µs edge epsilon because Unix-time doubles only resolve
~0.24 µs (caught by `tests/specs/Rhythm.spec.luau`).

## Testing

`lune run tests/run.luau` — the harness (`tests/harness/Loader.luau`) maps `script`,
`script.Parent` and `game:GetService(...)` onto the Rojo file tree so modules run
unmodified; `tests/harness/RobloxMock.luau` provides players/characters, a flat-ground
workspace with a controllable clock, a steppable Heartbeat, a controllable `os.clock`,
recording remotes and an in-memory ProfileService.
