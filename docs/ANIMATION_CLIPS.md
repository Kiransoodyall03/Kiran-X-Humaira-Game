# Heroine animation clips

Owner: P · Reviewer: A · Status: **v1 (week 3): AnimationTree state machine running on the capsule with procedural placeholder clips**

The heroine's AnimationTree, the clip names it plays, and how Humaira's rig and clips replace the placeholders. Gameplay never reads the tree: code decides what she is doing (`PlayerController`, `PlayerCombat`, `Combatant`, `PlayerHealing`, `PlayerRest`) and the tree only shows it. Frames are at **60 fps**.

## Pieces
| What | Where | Owner |
|---|---|---|
| State machine (tree root) | `data/animation/heroine_anim_tree.tres` | P |
| Placeholder clips (capsule squash/lean/tilt/turn on `Visual/BodyMesh`) | `data/animation/heroine_placeholder_anims.tres` | P |
| Visual tuning (blend speeds, reaction lengths, cross-fades) | `data/animation/heroine_anim.tres` (`HeroineAnimConfig`) | P |
| Driver: gameplay state → tree | `scripts/animation/heroine_animation_driver.gd` (`HeroineAnimationDriver`, child `AnimationDriver` of the heroine) | P |
| Names and builders | `scripts/animation/heroine_clips.gd`, `heroine_anim_tree.gd`, `heroine_placeholder_anims.gd` | P |
| Rebuild the two `.tres` above | `godot --headless --path . --script res://scripts/animation/rebuild_heroine_anims.gd` | P |
| Real rig and clips | `assets/characters/heroine/` (glb + AnimationLibrary glbs) | A |

Tests: `tests/unit/heroine_animation_test.gd` (names, saved tree and library in sync with the forms, state priority), `tests/smoke/animation_smoke_test.gd` (the tree reaches the right state in the sandbox; missing clips never error).

## State machine
The tree root is an `AnimationNodeStateMachine` with one state per row below plus one per attack. Every state has a direct transition to every other one (immediate switch, cross-fade **8 frames** into looping states, **3 frames** into one-shots), so `travel()` always goes straight there. The driver runs after the controller each physics tick and picks **the first match**:

| # | When (gameplay) | State |
|---|---|---|
| 1 | `Combatant.is_dead` | `death` |
| 2 | Staggered (posture break, guard break) | `stagger` |
| 3 | In a deathblow's lock-out (`PlayerCombat.is_performing_deathblow`) | `deathblow` |
| 4 | Dodging | `dodge` (BlendSpace2D on the dash direction relative to her facing) |
| 5 | Swinging (`ComboRunner.attack` set) | the state named after the swing's `AttackData.id`, e.g. `greatsword_light_2` |
| 6 | Healing | `heal` |
| 7 | A hit landed (HIT) / was blocked (BLOCKED) / was parried by her (PARRIED), for the reaction's frames | `hit_react` / `guard_hit` / `parry` |
| 8 | Airborne: rising faster than **0.5 m/s** / otherwise | `jump` / `fall` |
| 9 | Landed after falling ≥ **3 m/s**, or rested at a shrine, while she stays below **0.6 m/s** | `land` / `rest` |
| 10 | Guard held | `guard` |
| 11 | Otherwise | `locomotion` (BlendSpace1D on ground speed: idle 0, walk 1.5, run 4.5, sprint 7.5 m/s) |

A new swing of the same attack, a second hit react and so on restart their state from the top. During hit-stop the tree slows with `Engine.time_scale` and the reaction timers wait.

**One-shots are stretched to gameplay length.** Each one-shot state uses a custom timeline (`use_custom_timeline` + `stretch_time_scale`) set to the gameplay frame count, refreshed from the live data at start-up: attacks from their `AttackData` (startup + active + recovery), the dodge from the form's `dodge_duration_frames`, heal from `HealConfig.use_frames`, deathblow from `DeathblowConfig.recovery_frames`, the rest from `HeroineAnimConfig`. Retuning frame data re-times the clip; the clip should still be authored at the listed length so its key poses land on the right frames.

## Clip list
Names follow `ART_SPEC.md`: `A_heroine_<action>`, with **`-loop`** on looping clips (Godot's import suffix, which turns looping on). Loop clips can be any length; one-shots should be authored at the target length. "Lunge / dash" is how far gameplay moves her body during the clip.

| Clip | State | Loop | Target length (frames @ 60) | Key frames | Lunge / dash | Notes |
|---|---|---|---|---|---|---|
| `A_heroine_idle-loop` | locomotion (0 m/s) | yes | any (placeholder 120) | — | in place | |
| `A_heroine_walk-loop` | locomotion (1.5 m/s) | yes | any (placeholder 40) | — | in place, 1.5 m/s | Also used for the slow heal walk (×0.35) and guard walk (×0.4). |
| `A_heroine_run-loop` | locomotion (4.5 m/s) | yes | any (placeholder 30) | — | in place, 4.5 m/s | Her normal top speed (`walk_speed`); katana ×1.2. |
| `A_heroine_sprint-loop` | locomotion (7.5 m/s) | yes | any (placeholder 24) | — | in place, 7.5 m/s | |
| `A_heroine_jump` | jump | no | 12 | take-off on 0 | — | Plays while rising. |
| `A_heroine_fall-loop` | fall | yes | any (placeholder 30) | — | — | |
| `A_heroine_land` | land | no | 10 | impact on 0 | — | Cut short if she moves. |
| `A_heroine_guard-loop` | guard | yes | any (placeholder 60) | — | — | Greatsword only (katana can't guard). |
| `A_heroine_guard_hit` | guard_hit | no | 12 | impact on 0 | — | Returns to the guard pose. |
| `A_heroine_parry` | parry | no | 14 | deflect on 0 | — | Returns to the guard pose. |
| `A_heroine_greatsword_light_1` | greatsword_light_1 | no | **49** | startup 18 · active 19–23 · recovery 26 | 0.6 m over frames 1–23 | |
| `A_heroine_greatsword_light_2` | greatsword_light_2 | no | **53** | startup 20 · active 21–25 · recovery 28 | 0.6 m over 1–25 | |
| `A_heroine_greatsword_light_3` | greatsword_light_3 | no | **72** | startup 26 · active 27–32 · recovery 40 | 1.0 m over 1–32 | Finisher. |
| `A_heroine_katana_light_1` | katana_light_1 | no | **25** | startup 8 · active 9–11 · recovery 14 | 0.4 m over 1–11 | |
| `A_heroine_katana_light_2` | katana_light_2 | no | **25** | startup 8 · active 9–11 · recovery 14 | 0.4 m over 1–11 | |
| `A_heroine_katana_light_3` | katana_light_3 | no | **38** | startup 12 · active 13–16 · recovery 22 | 0.8 m over 1–16 | |
| `A_heroine_dodge_forward` | dodge (0, 1) | no | **18** | i-frames 2–13 | 3.5 m | Katana only. |
| `A_heroine_dodge_back` | dodge (0, −1) | no | **18** | i-frames 2–13 | 3.5 m | No move input = backward. |
| `A_heroine_dodge_left` | dodge (−1, 0) | no | **18** | i-frames 2–13 | 3.5 m | |
| `A_heroine_dodge_right` | dodge (1, 0) | no | **18** | i-frames 2–13 | 3.5 m | |
| `A_heroine_hit_react` | hit_react | no | 18 | impact on 0 | in place | |
| `A_heroine_stagger-loop` | stagger | yes | any (placeholder 60) | — | in place | Lasts the posture break (90 frames for her). |
| `A_heroine_deathblow` | deathblow | no | **50** | lands on 0 | in place | She snaps to face the target first. |
| `A_heroine_heal` | heal | no | **54** | health returns on 30 | walks at ×0.35 | |
| `A_heroine_rest` | rest | no | 90 | — | in place | Kneel at a shrine; cut short if she moves. |
| `A_heroine_death` | death | no | 60 | — | in place | Holds the last frame until revive/respawn. |

Frame numbers count from the press frame = swing frame 1 (`COMBAT_SPEC.md`, "Swing timing"). Animate only clips whose rows are locked in `COMBAT_SPEC.md`. If an attack row changes, this table and the saved tree change with it (the unit test fails until `rebuild_heroine_anims.gd` is run).

**Root motion:** none is applied. Code moves her body by the data above (`lunge_distance`, `dodge_distance`, walk/sprint speeds), so clips should cover the same distance on the **root bone** (as `ART_SPEC.md` asks) to keep the feet planted. When the rig arrives the tree's `root_motion_track` is set to that root bone, which takes the motion out of the displayed pose; nothing reads it back. Locomotion loops are authored in place at the listed speed.

## Replacing the placeholders with Humaira's rig (no code changes)
1. **A** exports `assets/characters/heroine/SK_heroine.glb` (humanoid, SkeletonProfileHumanoid bone map) and animation-only glbs such as `assets/characters/heroine/anims/A_heroine_locomotion.glb` and `A_heroine_combat.glb`, each imported as an **AnimationLibrary**, with clip names from the table above. Mixamo placeholders go through the same humanoid retarget.
2. **P** edits only `scenes/actors/heroine.tscn`: instance `SK_heroine.glb` under `Visual` (it already turns to face her movement; the glb is never edited, sockets via `BoneAttachment3D`), and hide or remove the placeholder capsule `BodyMesh`.
3. On the `AnimationTree`: set **Root Node** to the instanced model so the glb track paths resolve; replace the `""` library (the placeholder `.tres`) with the glb libraries — any library names, since the driver merges them all into `""` at start-up; set `root_motion_track` to the root bone.
4. Done. The state machine, state names and the driver stay the same. A clip named without its `-loop` suffix is still found (and set looping). A clip that isn't delivered yet plays an empty stand-in of the right length instead of erroring, and `HeroineAnimationDriver.missing_clips()` lists what is still missing, so the libraries can arrive one set at a time.

A **new attack row** in a form needs no code: run `rebuild_heroine_anims.gd` (it gets a state and a placeholder clip named after its id) and add a row here. A **new kind of state** (a new reaction) needs a name in `HeroineClips` and a rule in the driver.
