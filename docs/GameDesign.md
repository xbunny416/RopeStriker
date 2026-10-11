# Game Design — Economy & Progression

All numbers live in `src/ReplicatedStorage/Source/Configuration/GameConfig.luau`; all
math lives in `src/ReplicatedStorage/Source/Shared/Formulas.luau` and is unit-tested
(`tests/specs/Formulas.spec.luau`). Change the config, not the code, to rebalance.

## Core loop

```
 ┌──────────── Training Piazza ─────────────┐        ┌──────── Grand Colosseum ────────┐
 │ jump rope on the beat ──► Kinetic Power  │        │ Ground Lash / Aerial Sweep       │
 │ (combo 1.0x → 2.5x)        (≤ Capacity)  │        │ shared-health mobs, ≥5% = paid   │
 │            │                             │        │            │                     │
 │            ▼                             │        │            ▼                     │
 │   Epoch Obelisk: bank ──► TotalStrength ─┼──DMG──►│         Shards                   │
 └───────────────────────────│──────────────┘        └────────────│─────────────────────┘
                             │ thresholds                        │ spend
                             ▼                                   ▼
               Chronal Rifts → Eras 2-4        Blacksmith (ropes/boots) · Incubator (pets)
                             │                                   │
                             └──── Era 4 + 1,000,000 Strength ───┘
                                          ▼
                     Temporal Paradox: reset, keep pets/rifts, x1.5 base stats,
                     +1 Rebirth Token for the Paradox skill tree
```

## Formulas (as implemented)

| Quantity | Formula |
| --- | --- |
| KP per bounce | `BaseRopeKP × BootMultiplier × PetMultiplierSum × RhythmComboBonus × RebirthMultiplier × (1 + Kinetic Echo)` |
| Rhythm combo | starts 1.0x; +0.1x per on-beat bounce; cap 2.5x; any miss → 1.0x; also → 1.0x after 2.5 s without bouncing |
| On-beat | press **or** landing within ±0.15 s of a beat (beats every 0.75 s on the synchronised server clock) |
| Stamina Capacity | `BootStaminaCapacity × RebirthMultiplier × (1 + Temporal Satchel)` (default 100); once full, bounces give 0 KP until banked |
| Banking | `TotalStrength += UnbankedKP; UnbankedKP = 0` (1:1) |
| Damage | `((TotalStrength ^ 0.65) + RopeBaseDamage) × PetMultiplierSum × AttackMultiplier × (1 + Paradox Edge)`; Ground Lash 1.0x (14-stud, 45° cone), Aerial Sweep 0.75x (12-stud radial) |
| Mob payout | contributors with ≥ 5% of max HP: `round(BaseMobShards × share × RebirthMultiplier × (1 + Shard Siphon))`, minimum 1; others 0 |
| Rebirth multiplier | `1.5 ^ RebirthCount` (+50% compound) |
| PetMultiplierSum | sum of equipped pet multipliers, floored at 1.0 |

### Interpretation decisions

The Project Bible leaves a few rules open. These are the calls made — review them with
design before launch; each is a single config value or a few lines in `Formulas.luau`.

| Question | Decision | Why |
| --- | --- | --- |
| "0.15 s tolerance window" — half-width or full width? | ±0.15 s around each beat | Reads as "tolerance"; forgiving for the 60% mobile audience whose touch latency varies. `Rhythm.ToleranceSeconds`. |
| Beat tempo | 0.75 s (80 BPM) | A default R15 jump is ~0.54 s airborne: pressing on every beat leaves a natural ground beat. `Rhythm.BeatInterval`. |
| Press or landing? | Either counts (Bible text). Judged once per bounce: an on-beat press resolves instantly, otherwise the landing is judged. | Instant green burst on good presses; "saves" on late presses. |
| What does "+50% compound base stat multiplier" scale? | KP per bounce and Stamina Capacity (so the number of bounces per bank stays constant across rebirths), plus Shard payouts where the Bible names it | Damage already scales through faster Strength gain; scaling it too would trivialise every rebirth cycle's combat. |
| PetMultiplierSum with no pets | 1.0 | A literal sum of zero pets would zero out KP and damage. |
| Where does Stamina Capacity grow? | Boots (100 → 1,000 → 15,000), rebirths, Temporal Satchel | Boots are the "endurance" slot; keeps banking trips meaningful at every gear tier. |
| "Resets Equipped Ropes/Boots" | Ownership resets to the starters (Hemp Cord, Bare Feet) | Resetting only the *equipped* slot would be a no-op re-equip. |
| "Reaching Era 4" | Having unlocked the Neon Future rift (`HighestEra ≥ 4`), retained through rebirth | Rifts are retained, so later rebirths only need the Strength again. |
| "+1 semitone per combo tier" | 4 tiers (the trail colour bands White/Blue/Gold/Red) → up to +3 semitones | Tiers are named the same way in §4.3; `Rhythm.SemitonesPerTier` exaggerates it if audio wants more. |
| Overkill damage | Not credited | Keeps the sum of shares ≤ 100%. |
| Wounded mob with nobody around | Full heal + contributor reset after 12–20 s out of combat | Prevents parking a mob at 1 HP for later. |

## Content (Zone 1)

### Ropes (Blacksmith)

| Rope | Price | BaseRopeKP | RopeBaseDamage |
| --- | ---: | ---: | ---: |
| Standard Hemp Cord | free | 1 | 10 |
| Leather Strap | 250 | 4 | 28 |
| Bronze Chain | 2,500 | 15 | 75 |

### Boots (Blacksmith)

| Boots | Price | BootMultiplier | Stamina Capacity |
| --- | ---: | ---: | ---: |
| Bare Feet | free | 1.0x | 100 |
| Leather Sandals | 400 | 1.5x | 1,000 |
| Hermes Winged Greaves | 6,000 | 3.0x | 15,000 |

### Pets & Chrono-Eggs (3 equip slots, 60 inventory; retained through rebirth)

| Pet | Rarity | Multiplier |
| --- | --- | ---: |
| Mini Centurion | Common | 1.2x |
| Baby War Mammoth | Rare | 1.6x |
| Golden Eagle | Legendary | 2.5x |

| Egg | Price | Mini Centurion | Baby War Mammoth | Golden Eagle |
| --- | ---: | ---: | ---: | ---: |
| Bronze Chrono-Egg | 120 | 80% | 18% | 2% |
| Silver Chrono-Egg | 900 | 50% | 42% | 8% |
| Gilded Chrono-Egg | 4,500 | 20% | 55% | 25% |

Chrono Luck multiplies the weight of every pet rarer than the egg's most common pet.

### Grand Colosseum mobs

| Mob | Count | HP | Respawn | Attack (0.8 s telegraph) | Damage | BaseMobShards | Bonus drops |
| --- | ---: | ---: | ---: | --- | ---: | ---: | --- |
| Roman Legionary | 4 | 250 | 8 s | Shield Slash, 9-stud 70° cone | 12 | 15 | Mini Centurion 0.4% |
| Centurion Elite | 2 | 1,200 | 20 s | Cleave, 11-stud 90° cone | 24 | 90 | Baby War Mammoth 1% |
| Gladiator Primus | 1 (dais) | 10,000 | 60 s | Primus Cleave 16-stud 110° cone (2:1) / Arena Slam 14-stud circle | 38 / 55 | 1,200 | Golden Eagle 2%, *Gladiator* title 10% |

Bonus drops roll independently for every eligible (≥ 5%) contributor.

### Eras & Chronal Rifts

| Era | Sector (X) | Rift requirement (stored stats) |
| --- | --- | --- |
| I · Ancient Rome | −320 … 320 | — (hub) |
| II · Feudal Japan | 320 … 720 | 10,000 Strength |
| III · Steam Age | 720 … 1,120 | 100,000 Strength |
| IV · Neon Future | 1,120 … 1,520 | 500,000 Strength |

Rift configs also support `RequiredRebirths` for post-rebirth content; Eras II–IV keep it
at 0 so the first Temporal Paradox is reachable.

### Temporal Paradox & skill tree

* **Cost:** Era IV unlocked + 1,000,000 Strength. **Resets:** unbanked KP, Strength,
  ropes, boots. **Keeps:** rifts, pets, titles, Rebirth Tokens, skill levels.
* **Rewards:** `RebirthCount + 1` (x1.5 compound), +1 Rebirth Token, titles at rebirth 1
  (*Paradox Walker*) and 5 (*Chrono Champion*).

| Node | Effect / level | Max | Cost | Requires |
| --- | --- | ---: | ---: | --- |
| Kinetic Echo | +15% KP per bounce | 5 | 1 | — |
| Temporal Satchel | +30% Stamina Capacity | 5 | 1 | Kinetic Echo 1 |
| Paradox Edge | +15% damage | 5 | 1 | — |
| Shard Siphon | +10% Shard payouts | 5 | 1 | Paradox Edge 1 |
| Chrono Luck | +10% rare-hatch weight | 5 | 1 | Kinetic Echo 2, Paradox Edge 2 |
| Epoch Resonance | +1 pet slot | 1 | 3 | Temporal Satchel 3, Shard Siphon 3 |

## Pacing reference

Computed with the live formulas (no rebirths, no skills, average combo 2.0x, one bounce
per beat):

| Loadout | KP / bounce @1.0x | @2.5x | Capacity | Bounces per bank | KP / s |
| --- | ---: | ---: | ---: | ---: | ---: |
| Starter (Hemp, Bare Feet, no pets) | 1.0 | 2.5 | 100 | 50 | 2.7 |
| Leather Strap + Sandals + 1 Mini Centurion | 7.2 | 18 | 1,000 | 70 | 19.2 |
| Bronze Chain + Hermes + 3 Mammoths | 216 | 540 | 15,000 | 35 | 576 |
| Bronze Chain + Hermes + 3 Golden Eagles | 337.5 | 843.8 | 15,000 | 23 | 900 |

| TotalStrength | Hemp Cord hit | Bronze + 3 Eagles hit | Hits to kill a Legionary (Hemp) | Hits to kill Primus (Bronze + Eagles) |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 10 | 562 | 25 | 18 |
| 1,000 | 99 | 1,231 | 3 | 9 |
| 10,000 | 408 | 3,548 | 1 | 3 |
| 100,000 | 1,788 | 13,900 | 1 | 1 |

Rough first-cycle arc: ~3 minutes of training before the arena is comfortable, Leather
gear within the first 10 minutes, Era II around minute 15, Bronze/Hermes by ~35 minutes,
Era IV and the first Temporal Paradox at roughly 60–90 minutes for an engaged player.
Every later cycle is faster (x1.5 compounding, retained pets and rifts).

## Tuning checklist

* Session feel: `Rhythm.BeatInterval`, `Rhythm.ToleranceSeconds`, `Rhythm.EngagedTimeout`.
* Banking rhythm: boots `StaminaCapacity`, Temporal Satchel `PerLevel`.
* Early combat: `Ropes.HempCord.BaseDamage`, `Mobs.RomanLegionary.MaxHealth`.
* Shard faucet: `Mobs.*.Drops.BaseShards`, Shard Siphon; sinks: rope/boot/egg prices.
* Rebirth cadence: `Rebirth.RequiredStrength`, rift requirements, `Rebirth.MultiplierBase`.
