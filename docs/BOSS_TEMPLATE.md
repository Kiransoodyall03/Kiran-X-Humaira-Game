# Boss / large monster template

Owner: P · Copy this file per boss as `docs/bosses/<name>.md`.

## 1. Brief (one paragraph)
- **Folklore inspiration:** (a yokai/kami type, reinterpreted — not copied)
- **Fantasy:** what fighting it feels like.
- **Lesson it teaches:** the one skill the player must learn here.
- **Size class / rig family:** S / L / XL · biped-oni / quadruped / serpentine

## 2. Arena metrics
Size, shape, cover, verticality, stealth-opener approach, camera notes.

## 3. Parts
| Part | Hurtbox | Damage mult. | Posture max | On break |
|---|---|---|---|---|

## 4. Phases
| Phase | Trigger (HP / posture / part break) | New moves | Behavior change |
|---|---|---|---|

## 5. Moveset
Use the attack-table format from `COMBAT_SPEC.md`. Include combos and string logic (what follows what).

## 6. Unblockables
Each perilous type has its own color flash and sound. List the counter for each.

## 7. Player counter-tools
Which form, spirit art or cat action works best, and why.

## 8. Story
Lore beat, the cat's commentary lines (before/during/after), item dropped + its item text.

## 9. Death-feedback goal
After every death the player should know exactly why they died and what to try next.

## 10. Art pipeline checklist (A)
1. [ ] Brief approved
2. [ ] 20 silhouette thumbnails → 1 picked
3. [ ] Capsule proxy on the shared rig, tested in the greybox arena with placeholder poses
4. [ ] Attack table locked → animate only those clips
5. [ ] Sculpt → retopo → texture → skin to the existing rig
6. [ ] Animation polish + VFX tells
