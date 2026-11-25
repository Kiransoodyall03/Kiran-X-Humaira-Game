# Combat spec

Owner: P · Reviewer: A · Status: **v1 (posture, block, parry implemented — week 2)**
All tuning values live in Godot `Resource` files so they can be changed live. Frames are at **60 fps**.

## Defence rules v1 (implemented)
Code: `scripts/combat/` (`DefenseResolver`, `Guard`, `Posture`, `Combatant`). Tests: `tests/unit/*_test.gd`, `tests/smoke/combat_smoke_test.gd`.

**Outcome order: parry > block > hit.**
| Outcome | When | Defender takes | Attacker takes |
|---|---|---|---|
| **Parry** | Attack is deflectable and guard was *pressed* within the parry window before the hit (holding not needed) | 25% of the attack's posture damage, never enough to break her posture | 100% of the attack's posture damage |
| **Block** | Attack is blockable and guard is *held* | 100% posture damage, 0% health (no chip) | — |
| **Guard break** | A block that fills posture | Staggered | — |
| **Hit** | Anything else, or the defender is staggered | Full health damage + 50% posture damage | — |

- **Parry window:** 12 frames (the press frame counts as frame 0). **Mashing** guard (re-pressing within 20 frames) shrinks the next window by 4 frames, down to 4.
- **Posture recovery** starts 90 frames after the last posture damage for the heroine (120 for the dummy). It's ×1.5 faster while guarding and ×0.3 slower at 0 health (scaling linearly up to full health). Nothing recovers while broken.
- **Posture break** = stagger: 90 frames for the heroine, 150 for the dummy. No moving, guarding or parrying while staggered. Posture empties when the stagger ends.
- Guard held through a stagger comes back up afterwards, without a parry window.
- **Deathblow on enemy posture break:** not yet. `Combatant.posture_broken` is the hook.

Tuning files: `data/combat/heroine_*.tres`, `data/combat/dummy_*.tres`, `data/attacks/*.tres`.

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
**Training dummy** (sandbox). Sequence: overhead, overhead, thrust, overhead, sweep, then repeat, with a 45-frame pause between attacks.
| ID | Attack | Startup (f) | Active (f) | Recovery (f) | Dmg | Posture dmg | Blockable? | Deflectable? | Perilous type | Tell (colour) | Punish window (f) | Reach (m) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| dummy_overhead | Overhead | 30 | 4 | 30 | 20 | 25 | Yes | Yes | — | Amber | 30 | 2.6 |
| dummy_thrust | Thrust | 36 | 4 | 40 | 25 | 30 | **No** | **Yes**: parry it, don't hold block | Thrust | Red | 40 | 3.2 |
| dummy_sweep | Sweep | 40 | 8 | 40 | 25 | 20 | No | No: jump over it | Sweep | Purple | 40 | 2.8 |

Perilous rules: a **thrust** can't be blocked but can be parried, as in Sekiro. A **sweep** can be neither; jumping makes it miss. Grabs come later; dodge them.

Telegraph rules: clear anticipation (longer for gap-closers); every unblockable has its own color flash; same visual language always means the same outcome.

## Player moves
| Move | Startup | Active | Recovery | Posture dmg to enemy | Notes |
|---|---|---|---|---|---|
| Greatsword light 1/2/3 | | | | | |
| Katana light 1/2/3 | | | | | |
| Form switch | | | | | Can cancel into from attack recovery |
| Dodge (katana) | | i-frames: | | | |
| Guard (block / parry) | Right mouse / LB | parry window: 12 | — | Parry: 100% of the attack's posture damage | Slows movement to 40%, no sprint |

## Playtest logging
Log every player death with the attack ID. Review the death log each Friday.
