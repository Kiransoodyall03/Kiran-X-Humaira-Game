# Combat spec

Owner: P · Reviewer: A · Status: TEMPLATE — v1 due week 2
All tuning values live in Godot `Resource` files so they can be changed live. Frames are at **60 fps**.

## Core rules (from the design foundation)
- **Posture only, no stamina.** Her posture fills when she blocks; enemy posture fills from her parries and limb breaks. Full posture → deathblow / stagger.
- **Parry window:** start generous (10–12 frames), tighten after playtests. Tune in this order: parry window → posture regen → damage.
- **Lock-on** cycles between body parts (head, limbs, weak points). Camera pulls back by the target's bounding box; pushes toward the head during telegraphs.
- **Healing:** limited heals, refilled at shrines.
- **Spirit arts:** small energy pool, refills from hits and parries, full at shrines. Utility first.

## Forms
| Form | Unlocked | Plays like | Defense | Cost |
|---|---|---|---|---|
| Greatsword | Start | Slow, heavy; breaks posture and limbs | Block + parry | Drains corruption slowly |
| Katana | Start | Fast attacks, faster movement | No block; i-frame dodge + counters | Corruption rises while active |
| Claw form | After taming | Claw combos, flash dashes, wall-runs | Speed | Full bond meter; 20–30 s |

## Corruption v0 (month one)
- Rises per second in katana form; drains in greatsword form, faster out of combat; resets at shrines.
- Input hijack and rampage are **stubbed** in month one.
- Design rule: corruption should *tempt* (more damage, the cat's whispers), never only punish. Never reward behavior the story condemns.

## Large monsters: per-part posture
- Each body part has its own hurtbox, damage multiplier and **posture bar**.
- Breaking a part (posture full) staggers the whole monster and opens a punish window; the part may change state (weaker, disabled attack).
- Lock-on targets parts, with soft re-targeting.

## Attack table (one per enemy)
| ID | Attack | Startup (f) | Active (f) | Recovery (f) | Dmg | Posture dmg | Deflectable? | Perilous type | Tell (anim / SFX / VFX) | Punish window (f) | Phase |
|---|---|---|---|---|---|---|---|---|---|---|---|
| dummy_01 | Overhead | | | | | | Yes | — | | | 1 |
| dummy_02 | Thrust | | | | | | No | Thrust | | | 1 |
| dummy_03 | Sweep | | | | | | No | Sweep | | | 1 |

Telegraph rules: clear anticipation (longer for gap-closers); every unblockable has its own color flash; same visual language always means the same outcome.

## Player moves
| Move | Startup | Active | Recovery | Posture dmg to enemy | Notes |
|---|---|---|---|---|---|
| Greatsword light 1/2/3 | | | | | |
| Katana light 1/2/3 | | | | | |
| Form switch | | | | | Can cancel into from attack recovery |
| Dodge (katana) | | i-frames: | | | |
| Parry | window: | | | | |

## Playtest logging
Log every player death with the attack ID. Review the death log each Friday.
