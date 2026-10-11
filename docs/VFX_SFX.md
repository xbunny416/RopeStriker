# VFX & SFX

## Visual effects

### Rhythm Prompt (RopeController)
A BillboardGui (5×5 studs, always on top) on the local player's torso while the Training
stance is engaged.

* **Target ring** at 42% of the gui, turning green while the ±0.15 s window is open.
* **Approach ring** scales from 100% down to the target ring every beat
  (`scale = 0.42 + 0.58 × timeToNextBeat / 0.75`), coloured by the current combo tier
  and fading in as it closes.
* **Green burst** on an on-beat bounce: a ring expanding 0.42 → 1.15 while fading over
  0.28 s, plus "ON BEAT!" / "PERFECT!" (≤ 50 ms) or a red "MISS".
* **Combo counter** above the ring (`x1.7`), tier-coloured, with a scale pop on each hit.

### Rope trails & tension
Trails on both handles (0.18 s) and on the rope tip (0.26 s; the tip attachments follow
the Beam's apex every frame). Colour by the owner's combo tier:

| Tier | Combo | Colour |
| --- | --- | --- |
| Kinetic | 1.0–1.4x | White `#FFFFFF` |
| Charged | 1.5–1.9x | Blue `#409CFF` |
| Gilded | 2.0–2.4x | Gold `#FFC42E` |
| Overdrive | 2.5x | Red `#FF3838` |

From the Gilded tier the rope tip also emits **TensionSparks** (rate 25 × tier). Trails
are enabled only while the rope moves (Training stance or an attack).

### Rope motion
The Beam is a cubic Bézier re-aimed every frame (`Modules/BeamCurve`):
Training — orbit around the hands' axis, passing under the feet 0.27 s after each beat;
Ground Lash — whips from up-and-back to forward-and-down, extending to 14 studs;
Aerial Sweep — spins outward to 12 studs with the body; idle — hangs slack.

### Telegraph decal (MobVisualsController + Modules/Telegraph)
Red Neon ground projection built from flat wedges (cones) or discs (circles): a 65%
transparent outline of the full area appears at wind-up start, a 35% transparent fill
grows from the mob outward over the 0.8 s telegraph, and the outline flashes white on
impact. Shapes match the server's hit test exactly (same `Shared/Spatial` math).

### Other effects
Obelisk capstone sparkles + PointLight; forge embers; rift barrier motes; incubator egg
shimmer; mob death fade (LocalTransparencyModifier) with a shard burst; floating damage
numbers (gold "KO!" on kills); KP pop-ups above the gauge; hatch reveal card; rebirth
"TEMPORAL PARADOX #n" title.

## Sound design

| Event | Config key | Behaviour | Placeholder |
| --- | --- | --- | --- |
| **Rope_Whoosh** | `Sounds.RopeWhoosh` | Every rope jump and swing, on the player's root (falloff 60 studs). `PlaybackSpeed = 2^(semitones/12)` with +1 semitone per tier above Kinetic (`Rhythm.SemitonesPerTier`) → 1.000 / 1.059 / 1.122 / 1.189 | `rbxasset://sounds/swordlunge.mp3` → `swordslash.mp3` → `action_jump.mp3` |
| **Whip_Crack** | `Sounds.WhipCrack` | On confirmed hits, at the first hit position with InverseTapered falloff (min 8, max 120 studs); other players hear it via `AttackFx` | `rbxasset://sounds/swordslash.wav` → `swordslash.mp3` → `action_jump_land.mp3` |
| **Obelisk_Bank** | `Sounds.ObeliskBank` | When KP is deposited; also (pitched) on rift unlocks and rebirths | `rbxasset://sounds/electronicpingshort.wav` → `.mp3` |
| Rhythm hit | `Sounds.RhythmHit` | Soft tick on on-beat bounces, pitched like the whoosh | same as above |
| Hatch | `Sounds.Hatch` | Egg reveal | same as above |

Placeholders are built-in client sounds, which Roblox retires from time to time, so each
entry lists `Fallbacks`. At startup `SoundPlayer.Verify` preloads every id and switches to
the first fallback that loads (or mutes the sound), with one warning in the Output.

### Delivery specs for the final audio
* **Rope_Whoosh:** crisp airy swish, 0.25–0.35 s, energy around 1–4 kHz, tail ≤ 0.15 s,
  authored at the *lowest* tier pitch (code only raises it). Peak −3 dBFS, mono.
* **Whip_Crack:** sharp supersonic snap, transient < 10 ms, total ≤ 0.4 s, a little
  low-end thump for impact, mono (spatialised in engine).
* **Obelisk_Bank:** resonant harmonic chime (stacked fifths/major triad), 1.0–1.5 s
  decay, gentle attack; stereo is fine (played 2D for the depositor).
* Normalise all SFX to a consistent loudness (≈ −16 LUFS short-term) and upload as OGG.
