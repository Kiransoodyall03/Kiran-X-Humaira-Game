# Asset spec (the art ↔ code contract)

Owner: A · Co-signed by P in week 1 · Status: **SIGNED by A on 2026-11-27**
Changing anything marked 🔒 after sign-off needs both devs to agree, because P's scenes depend on it.

## Units and orientation 🔒
- 1 Blender unit = 1 meter. Apply all transforms (Ctrl+A → All Transforms) before export.
- Export: glTF 2.0 Binary (`.glb`), +Y up.
- Characters face **+Z** (Godot humanoid profile).

## Pivots 🔒
- Characters/monsters: origin at the feet, centered between them.
- Props: bottom center. Weapons: at the grip.
- Modular environment pieces: snap to a **1 m grid**, origin at a grid corner.

## Gameplay metrics 🔒 (greybox is built to these; tune in week 2, then lock)
| Metric | Value |
|---|---|
| Heroine height | 1.70 m |
| Door / passage height | 2.4 m |
| Step-up (no animation) | 0.35 m |
| Low climb / vault | 1.0 m |
| High climb (ledge grab) | 2.2 m |
| Monster class S | 2–3 m |
| Monster class L | 5–8 m |
| Monster class XL | 12 m+ |

## Naming
| Prefix | Use | Example |
|---|---|---|
| `SM_` | Static mesh | `SM_shrine_gate_a` |
| `SK_` | Skinned mesh | `SK_heroine` |
| `A_<char>_<action>` | Animation clip | `A_heroine_parry`, `A_heroine_run-loop` |
| `MAT_` | Material (.tres) | `MAT_heroine_body` |
| `T_<name>_<map>` | Texture | `T_heroine_body_albedo` |

Godot import suffixes on object names: `-col` (trimesh collision), `-convcol` (convex collision), `-colonly` / `-convcolonly` (collision only), `-navmesh`, `-occ`, `-noimp`, and `-loop` on animation names.

## Sockets 🔒 (empties/bones P attaches to with BoneAttachment3D)
| Name | Where |
|---|---|
| `weapon_R` | Right hand grip |
| `weapon_back` | Sheathed position on back |
| `cat_perch` | Shoulder spot where the cat spirit sits |
| `fx_chest` | Chest center for corruption/bond VFX |

Bone names in the humanoid rig must not change once P has built the AnimationTree.

## Rigs
- **Heroine:** humanoid rig mapped to **SkeletonProfileHumanoid** in Godot (BoneMap in Advanced Import Settings). Rest fixer: Overwrite Axis on, Normalize Position Tracks on.
- **Placeholders:** Mixamo clips are fine for prototyping. Add a root bone with the Mixamo-Root add-on before export. Check Mixamo's license before shipping any of it.
- **Monsters:** 2–3 shared rig families for the whole game. Reskin and re-proportion within a family.
  1. Large biped / oni
  2. Quadruped / beast
  3. Serpentine / long-body
  Each gets a custom SkeletonProfile.

## Animation
- Animation-only glbs are imported as an **AnimationLibrary** (`assets/characters/<char>/anims/A_<char>_<set>.glb`).
- Root motion goes on the **root bone** (it must actually move in the clip).
- Clip list and frame timings (startup/active/recovery) come from `COMBAT_SPEC.md`. Animate only clips that have a locked row in an attack table.

## Budgets (starting values; revisit after the week-4 look test)
| Asset | Triangles |
|---|---|
| Heroine | 30–60k |
| Large monster | 60–120k |
| Modular environment piece | 1–10k |

Texel density: 512–1024 px/m. The painterly hand-painted style allows the lower end. Godot auto-generates LODs on import.

## Materials
- On first import, extract materials to `MAT_*.tres` (Advanced Import → Materials → Use External) so they survive re-exports.
- One material should have one source of truth: the `.tres`, not the Blender file.
