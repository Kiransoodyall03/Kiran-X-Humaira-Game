# Request (art): Zone 01 Art and Lighting scenes

From: P (Kiran) · To: A (Humaira) · Tag: `request:art` · Status: open

The Zone 01 greybox slice is in (`docs/ZONE01.md` "Greybox slice"). Per `docs/OWNERS.md`, the art and lighting sub-scenes are yours, so I have **not** created them. Please create:

1. **`scenes/levels/zone01/Zone01_Art.tscn`** — set dressing over the greybox. Root `Node3D` at the origin (same space as `Zone01_Gameplay.tscn`). No gameplay nodes (no collision that blocks, no Areas, no NavigationRegion3D). If a piece needs to block the player, tell me and I'll add greybox collision for it on the Gameplay side, so the navmeshes stay right.
2. **`scenes/levels/zone01/Zone01_Lighting.tscn`** — WorldEnvironment, sun and other lights, fog volumes, LightmapGI, ReflectionProbes (the week-4 painterly look test can live here).

When they exist, tell me and I'll instance both in `Zone01.tscn` and delete the placeholder.

## What to replace
| Placeholder (P-owned, will be removed or hidden) | Where | Replace with |
|---|---|---|
| `TEMP_PlaceholderLighting` (WorldEnvironment with a procedural sky + one shadowed sun) | `Zone01.tscn` | Everything in `Zone01_Lighting.tscn`. I delete this node when I instance yours. |
| Grey floor/wall boxes (`NavSource/Greybox/Floors`, `Walls`) | `Zone01_Gameplay.tscn` | Ground, cliff/wall kit, fences. The collision boxes stay; I can hide their meshes once your art covers them. |
| `VistaPlatform_6m`, `VistaRamp_27deg` | Gameplay | The vista overlook (a rock outcrop or a tower stair). It should read as "go up here". |
| `Doorway_2_4m_South/North` lintels | Gameplay | Gates/torii-like frames (2.4 m clear height, ART_SPEC). |
| `Stealth_Rooftop_2_2m_A/B`, `Stealth_Crate_1_0m_A/B` | Gameplay | Guardian camp huts (2.2 m ledge-grab roof edge) and crates/carts (1.0 m vault). Keep the top heights. |
| Stealth volume debug boxes (`StealthPocket/*`: overlook, high/low routes, hide spot, lantern pools, patrol loop) | Gameplay | Tall grass along the low route, lanterns at the two lantern pools, a hide spot prop (barrel/hay). The coloured boxes are debug-only and stay on my side. |
| `Combat_Pillar_A/B` | Gameplay | Ruined pillars or rocks in the duelist's yard. |
| `Arena_Landmark_16m` | Gameplay | The arena landmark visible from the vista (dead tree, broken shrine tower…), about 16 m tall. |
| Shrine A / Shrine B greybox (`scenes/world/shrine.tscn`) | Gameplay | The shrine kit piece. Shrines are reused, so this could be an `assets/props/` glb I wrap in the shrine scene. |
| Shortcut gate panel (`scenes/world/shortcut_gate.tscn`, red box that rises) | Gameplay | A one-way gate/door that obviously opens from one side (bar or latch on the hall side). 6 m wide, 3 m tall; I animate it rising 3.2 m over 45 frames, or swap to your animation. |

## Metrics to keep
- Floors at y = 0; walls 3 m (7 m around the 6 m vista platform). 1 m grid, `docs/ART_SPEC.md` metrics.
- The arena gate gap is 4 m wide on purpose (the boss can't fit through). Please don't widen it visually in a way that suggests it can.
- Keep the vista → arena sightline clear: from the vista platform (0, 7.6, −68) to the arena centre (30, 3, −135). The Zone 01 smoke test fails if any blocking collision cuts it, and art without collision should not hide it either.
