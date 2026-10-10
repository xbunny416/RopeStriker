# Art Pipeline — Blender → FBX → Studio

The shipped build uses a procedural greybox for every visual. Each piece below can be
replaced independently: drop the imported asset in the listed location and the code
picks it up (no code changes).

## Style

* Low-poly, flat-shaded, chunky silhouettes readable on a phone at 30 studs.
* Colour from either a **single gradient/palette atlas** (256×256 PNG of flat swatches and
  soft vertical gradients; UV islands are scaled into swatches) or from Studio materials
  on untextured MeshParts. Studio materials are limited to **SmoothPlastic, Neon, Pebble**
  (ForceField only for rift barriers).
* No normal maps, no PBR SurfaceAppearance, no transparency except glow/FX surfaces.
* Era palettes: see `GameConfig.Eras[*].Theme` (Ground / Path / Accent / Trim).

## Blender setup & export

1. Model at **1 Blender unit = 1 stud**. A default R15 character is ~5 studs tall: keep a
   2×5×1 reference block in every file.
2. Apply all transforms (`Ctrl+A → All Transforms`) and set origins deliberately (rules per
   asset type below). Recalculate normals; mark sharp edges and use *Shade Flat*.
3. Triangulate in Blender (Triangulate modifier, *Beauty*) so the budget you see is the
   budget you ship.
4. Export **FBX**: *Selected Objects*, Mesh (+ Armature for rigs), *Apply Transform*,
   Forward **−Z**, Up **Y**, Smoothing *Face*. Name objects exactly as the code expects
   (`HandleL`, `HandleR`, `Body`, ...).
5. Import with the **Studio 3D Importer**, verify the reference block measures 2×5×1
   studs (adjust the export scale once per project if it does not, then keep it fixed),
   set `RenderFidelity = Automatic`, `CollisionFidelity = Box` (props) or `Hull`
   (walkable architecture), `DoubleSided = false`.
6. Decorative parts: `CanCollide = false`, `CanQuery = false`, `CanTouch = false`,
   `CastShadow = false` for small pieces.

## Asset list (Zone 1)

| Asset | Budget (tris) | Location / contract | Notes |
| --- | ---: | --- | --- |
| Standard Hemp Cord, Leather Strap, Bronze Chain handles | 150 each | `ReplicatedStorage.Assets.Ropes.<Template>` containing BaseParts **`HandleL`** and **`HandleR`**; set `GameConfig.Ropes.<Id>.Visual.Template` | Handle axis = local **Y**, origin at the grip centre; the rope leaves the handle's −Y end. The rope itself stays a Beam (`Visual.Color`, `Visual.Width`). |
| Leather Sandals, Hermes Winged Greaves | 300 per foot | currently procedural (`EquipmentService.buildBoots`) | Model as R15 foot/shin shells; future: Accessory with `LeftFootAttachment` / `RightFootAttachment`. Wings: thin wedges, gold. |
| Mini Centurion, Baby War Mammoth, Golden Eagle | **≤ 500** | `ReplicatedStorage.Assets.Pets.<PetId>` Model, **PrimaryPart = `Body`** | Chibi: head ≈ 45% of height, ~2 studs tall, origin at body centre, facing −Z. Anchored, non-colliding (the code enforces it). |
| Roman Legionary rig | ≤ 2,500 | `ServerStorage.Assets.Mobs.RomanLegionary` | **Humanoid** + **HumanoidRootPart** (PrimaryPart), R15-style rig. Optional `Overhead` Attachment on the root for the health bar. For the procedural telegraph keep a Motor6D named **`WeaponShoulder`**, otherwise provide `Mob_Telegraph_Slash`. |
| Centurion Elite rig | ≤ 3,000 | `ServerStorage.Assets.Mobs.CenturionElite` | Crested helmet, cape optional; 1.3× legionary proportions. |
| Gladiator Primus rig | ≤ 6,000 | `ServerStorage.Assets.Mobs.GladiatorPrimus` | 2.2× scale, heavy armour, trident or gladius. |
| Epoch Obelisk | 600 | tag `EpochObelisk` (see WorldBuilding) | Gold shaft + Neon glyph bands + capstone; separate Neon pedestal mesh tagged `ObeliskPedestal`. |
| Blacksmith stall | 1,500 | tag the anvil prompt `PanelPrompt` | Forge glow from a Neon slab + PointLight. |
| Chrono-Egg Incubator + 3 eggs | 1,200 | tag each egg Model `ChronoEgg` | Eggs ≈ 3.6×4.5 studs, colours from `GameConfig.Eggs`. |
| Rebirth Portal arch | 800 | `PanelPrompt` with `OpensPanel = Rebirth` | Paradox field = Neon disc, 35% transparent. |
| Colosseum wall module | 200 | modular, 40 around r = 100 | 20 studs tall, 4 thick, marble cap; Hull collision. |
| Spectator tier module | 150 | 3 rings behind the wall | Stepped, 24 / 27 / 30 studs. |
| Gate + lintel + sign | 600 | faces −Z | Opening ≈ 30 studs wide. |
| Central dais + braziers | 800 | r = 18, 2 tall | Red Neon rim, four ember braziers. |
| Chronal Rift ring | 400 | ring around a `ChronalRiftGate` barrier | 28×28 opening, Neon in the destination accent colour. |

## Performance targets (mobile first)

* Visible triangles in the hub under ~150k; Colosseum fight with 7 mobs + 20 players
  under ~250k.
* Prefer one MeshPart per prop over many small parts; reuse meshes (same MeshId) so they
  instance.
* Limit dynamic lights: one PointLight per landmark, `Shadows = false`.
* Keep particle `Rate` low (≤ 30) and lifetimes short; all emitters in this repo follow that.
