# Ownership map

**Rule:** every file has exactly one owner. Only the owner edits it. The other dev requests a change (chat or GitHub issue, tag `request:art` / `request:code`).
P = Kiran (programmer) · A = Humaira (designer/modeler/animator)

| Path | Owner | Notes |
|---|---|---|
| `source_art/**` | A | .blend working files. Lock before editing (`git lfs lock` or Anchorpoint). Godot ignores this folder (`.gdignore`). |
| `assets/characters/**`, `assets/monsters/**`, `assets/env/**`, `assets/props/**` | A | Exported `.glb`, textures, AnimationLibrary glbs, extracted `MAT_*.tres`, and their `.import` files. |
| `scenes/actors/*.tscn` | P | Wrapper scenes: CharacterBody3D root → instanced glb child + script, hit/hurtboxes, AnimationTree, BoneAttachment3D sockets. |
| `scenes/levels/<zone>/<Zone>.tscn` | P | Root level scene. Contains only instances of the three sub-scenes below. |
| `scenes/levels/<zone>/<Zone>_Gameplay.tscn` | P | Greybox collision, spawns, triggers, NavigationRegion3D, stealth volumes, shrines. |
| `scenes/levels/<zone>/<Zone>_Art.tscn` | A | Set dressing placed over the greybox. No gameplay nodes. |
| `scenes/levels/<zone>/<Zone>_Lighting.tscn` | A | WorldEnvironment, lights, fog volumes, LightmapGI, ReflectionProbes. |
| `scenes/levels/sandbox/**` | P | Dev test level for trying mechanics. Exempt from the Gameplay/Art/Lighting split; its sun and sky are placeholder greybox lighting. |
| `scenes/ui/**` | P | |
| `data/**` | P | Tuning Resources (`.tres`): movement, camera, later combat frame data. A asks for value changes, or edits them only in an agreed live-tuning session. |
| `scripts/**`, `shaders/**`, `tests/**` | P | Shader *parameters* A tunes via exported uniforms in A-owned materials/scenes. |
| `project.godot` | P | Input map, autoloads, physics layers, settings. A requests changes. |
| `.gitignore`, `.gitattributes`, `CLAUDE.md` | P | |

## Docs
| Doc | Owner | Reviewer |
|---|---|---|
| `DEV_PLAN_MONTH1.md`, `WORKFLOW.md` | P | A |
| `ART_SPEC.md` | A | P (co-signed week 1) |
| `VISION.md`, `NAMING.md` | Both (edit only in the joint session; otherwise propose via comment) | — |
| `CHARACTER_BIBLE.md`, `WORLD_BIBLE.md`, `ITEM_TEXT.md` | P | A |
| `COMBAT_SPEC.md`, `BOSS_TEMPLATE.md` | P | A |
| `ZONE01.md` | P (layout sections) / A (visual sections) | each other |
| `ART_BIBLE.md` | A | P |

> **P = Kiran** (programmer) · **A = Humaira** (designer: modeling, rigging, animation)
