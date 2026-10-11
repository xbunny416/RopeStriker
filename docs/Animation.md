# Animation (R15)

Author in Blender (R15 rig) or the Studio Animation Editor, upload, then paste the asset
ids into `GameConfig.Animations`. Until an id is set, the game uses code-driven poses
(`Modules/ProceduralPose.luau` for players, the mob `WeaponShoulder` Motor6D for
telegraphs), so every state already reads correctly.

| Config key | Clip | Length | Loop | Priority | Played by |
| --- | --- | --- | --- | --- | --- |
| `JumpRopeLoop` | JumpRope_Loop | 0.75 s (one beat) | yes | Action | RopeController while the Training stance is engaged; speed is re-timed so one cycle = one beat and phase-locked to the beat clock |
| `GroundLashAttack` | GroundLash_Attack | 0.35 s | no | Action2 | RopeController on SWING while grounded |
| `AirSweepAttack` | AirSweep_Attack | 0.45 s | no | Action2 | RopeController on SWING while airborne |
| `MobTelegraphSlash` | Mob_Telegraph_Slash | 0.8 s wind-up + strike | no | Action | MobService (server) at telegraph start |

Clips played on the local character replicate to everyone automatically. The rope Beam
is animated in code from the same clock, so clips only need to move the body.

## JumpRope_Loop — 0.75 s, looping

Fast arm orbit with a simultaneous hop. The rope passes under the feet at 36% of the
beat (`Rhythm.RopeUnderFeetPhase`); match the hop apex to it.

| Time | Pose |
| --- | --- |
| 0.00 | Land/crouch: knees bent 20°, hands at hip height 0.6 studs out to the sides, wrists cocked back |
| 0.12 | Push off: legs extend, hands sweep down and forward (wrist circles start) |
| 0.27 | Hop apex (0.6 studs root lift), toes pointed, hands at the bottom of their circle (rope under feet) |
| 0.45 | Falling, hands rising behind the hips |
| 0.60 | Contact: knees absorb, hands at the top of the circle |
| 0.75 | = 0.00 |

Keep the motion in the forearms/wrists; shoulders stay low and relaxed (the procedural
fallback swings the whole arm because it only has shoulder joints).

## GroundLash_Attack — 0.35 s

Right-to-left, downward diagonal whip crack.

| Time | Pose |
| --- | --- |
| 0.00–0.08 | Anticipation: torso twists right 25°, right arm raised high behind the head, left arm forward for balance |
| 0.08–0.16 | Strike: right arm slashes down and across to the left hip, torso unwinds 40°, front knee bends; **impact frame 0.16** (whip crack; add an animation event `Crack` here) |
| 0.16–0.35 | Follow-through and recover to guard |

## AirSweep_Attack — 0.45 s

360° horizontal spin in mid-air with the rope extended.

| Time | Pose |
| --- | --- |
| 0.00–0.05 | Tuck: knees up, arms gather |
| 0.05–0.40 | Full 360° yaw on the root (ease in/out), both arms extended horizontally, legs tucked |
| 0.40–0.45 | Open up for landing |

## Mob_Telegraph_Slash — 0.8 s wind-up

Must sync with the red ground decal (0.8 s) — the strike lands exactly when it flashes.

| Time | Pose |
| --- | --- |
| 0.00–0.70 | Weapon arm rises overhead (shield arm braces forward), weight shifts back |
| 0.70–0.80 | Hold at the top (the telltale beat before impact) |
| 0.80–0.95 | Strike forward and down across the telegraphed area |
| 0.95–1.30 | Recover (matches each attack's `RecoverySeconds`) |

The boss's Arena Slam reuses the same clip; a dedicated two-handed slam can be added by
giving the attack its own animation key.
