# UI / UX Blueprint

Built in code (`Controllers/UIController.luau`, `UI/*`). Every element uses
**AnchorPoint (0.5, 0.5)**, **Scale-only** UDim2 positions/sizes and a
**UIAspectRatioConstraint** where shape matters; text uses `TextScaled` with a
`UITextSizeConstraint`. The HUD ScreenGui uses `ScreenInsets = CoreUISafeInsets` so the
Roblox top bar, notches and home indicators never overlap it.

## Layout (Scale coordinates, centre anchor)

| Element | Position | Size | Notes |
| --- | --- | --- | --- |
| Strength / Shards / Rebirth pills | (0.12, 0.07 / 0.14 / 0.21) | 0.20 × 0.06, aspect 4.4 | Abbreviated numbers (15.32K, 2.5T) |
| Era + mode chip | (0.87, 0.08) | 0.24 × 0.09, aspect 3.6 | "ERA I · ANCIENT ROME" / "TRAINING - JUMP ON THE BEAT" |
| **Boss health bar** | (0.50, 0.085) | 0.46 × 0.05, aspect 12 | Visible only within **60 studs** of a living boss |
| Toast stack | (0.50, 0.27) | 0.46 × 0.22 | Rewards, banking, rift unlocks, errors; max 4 |
| **Left drawer** | (0.055, 0.50) | 0.11 × 0.40 (height-relative), aspect 0.32 | Rebirth ⏳ · Shop ⚒️ · Pets 🐾; collapsible tab slides it off-screen |
| **Kinetic Power gauge** | (0.50, 0.93) | 0.44 × 0.055, aspect 10 | 10 segments filling with `CurrentKP / StaminaCapacity`; gold + "BANK AT THE EPOCH OBELISK" when full |
| **Action Button** | touch (0.80, 0.70) · PC/console (0.88, 0.76) | touch 0.24 · other 0.15 (height-relative), aspect 1 | Circle. **JUMP** (gold) in Training, **SWING** (red) in Combat — swaps automatically by zone; key hint below on PC/console |
| Panels (Shop / Pets / Rebirth) | (0.50, 0.53) | 0.66 × 0.74, aspect 1.6 | Modal cards with title, close, scrolling grids |

The Action Button sits up and left of Roblox's own mobile jump button so jump + SWING
(Aerial Sweep) can be thumbed together.

## In-world UI

* **Rhythm Prompt** ring + combo counter on the torso (see VFX_SFX.md).
* Mob nameplates + health bars (70-stud draw distance), damage numbers.
* Rift labels: destination era, requirement and your current Strength, or "RIFT OPEN".
* Player nameplates: equipped title (colour) and rebirth count.
* ProximityPrompts: Bank (E / X), Open Blacksmith, Hatch (0.35 s hold), Temporal Paradox.

## Panels

* **Shop (Blacksmith):** tabs Ropes / Boots / Titles; cards show stats (`KP x4  DMG +28`,
  `x1.5 KP  Stamina 1K`), price, and a state button — BUY (red if unaffordable), EQUIP,
  EQUIPPED, ERA n (locked), LOCKED (titles are earned, not bought).
* **Pets:** inventory sorted by multiplier, rarity colours, tap to equip/unequip,
  EQUIP BEST, live `Equipped 2/3 · Bonus x3.7 · Inventory 5/60`.
* **Rebirth:** multiplier preview (`x1.5 -> x2.25`), Era IV and Strength checklist with a
  progress bar, what resets / what is kept, two-step confirm, and the Paradox skill tree
  (square canvas, nodes coloured gold = maxed, green = affordable, grey = locked).

## Input mapping

| Action | Keyboard & mouse | Touch | Gamepad |
| --- | --- | --- | --- |
| Rope jump (Training) | Space | Action Button / jump button | A or R2 |
| Swing (Combat) | Left click | Action Button | R2 |
| Aerial Sweep | Space then click | jump then Action Button | A then R2 |
| Interact (prompts) | E | tap | X |
| Toggle drawer | click tab | tap tab | Y |
| Close panel | click X | tap X | B |

Panels set `GuiService.SelectedObject` when opened with a gamepad, so they are fully
navigable with the D-pad.

## Readability rules

* Minimum on-screen text ≈ 14 px on a 720p phone (enforced by `UITextSizeConstraint`).
* High contrast: light text with dark strokes over translucent dark panels.
* Colour is never the only signal: tiers also change the combo number, rarity is written
  out, locked buttons say why.
