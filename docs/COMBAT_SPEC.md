# Combat spec

Owner: P · Reviewer: A · Status: **v1.2 (posture, block, parry, hit-stop, deathblow and lives — week 2; player attacks, greatsword/katana forms, katana dodge — week 3; corruption meter v0 — week 3; lock-on with part cycling and camera framing — weeks 2–3; capsule duelist AI with 3 telegraphed attacks — week 2; large-monster controller with per-part posture and monster #1 with 4 attacks and limb breaks — weeks 3–4)**
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
| **Dodged** | The hit lands during the defender's invulnerability frames (katana dodge). Checked **before** parry/block, so it beats perilous attacks too | Nothing | Nothing |

- **Parry window:** 12 frames (the press frame counts as frame 0). **Mashing** guard (re-pressing within 20 frames) shrinks the next window by 4 frames, down to 4.
- **Tap vs forced drop:** releasing the guard button keeps the window open (a quick tap parries). A **forced** guard drop closes it at once: switching to a form without guard (katana), starting a swing, dodging, healing, a deathblow, any stagger or death. So a press made just before one of those can't parry a hit landing after it.
- **Posture recovery** starts 90 frames after the last posture damage for the heroine (120 for the dummy). It's ×1.5 faster while guarding and ×0.3 slower at 0 health (scaling linearly up to full health). Nothing recovers while broken.
- **Posture break** = stagger: 90 frames for the heroine, 150 for the dummy. No moving, guarding or parrying while staggered. Posture empties when the stagger ends.
- Guard held through a stagger comes back up afterwards, without a parry window.
- **Deathblow on enemy posture break:** implemented, see "Deathblow and lives" below.

Tuning files: `data/combat/heroine_*.tres`, `data/combat/dummy_*.tres`, `data/combat/duelist_*.tres`, `data/attacks/*.tres`.

## Deathblow and lives (implemented)
Code: `scripts/combat/combatant.gd`, `scripts/combat/combatant_config.gd`, `scripts/combat/deathblow_config.gd`, `scripts/actors/player_combat.gd`. Tests: `tests/unit/deathblow_test.gd`, `tests/smoke/deathblow_smoke_test.gd`. Tuning: `CombatantConfig` (`lives`, `can_be_deathblown`, `requires_deathblow`) in `data/combat/*_combatant.tres`; the heroine's move in `data/combat/heroine_deathblow.tres`.

- **Window:** a Combatant with `can_be_deathblown` (enemies; never the heroine) is open to a deathblow for as long as it is staggered by a posture break. The window closes when the stagger ends. Signals: `deathblow_available`, `deathblow_unavailable`, `deathblow_landed(lives_left)`, `lives_changed`.
- **Doing it:** attack pressed while a target's window is open, its origin within **2.6 m** of hers (ground plane; for a large monster measured to the nearest point of its body: its `body_radius` circle, 2.3 m for monster #1, or any part hurtbox — so it can be finished from beside it, in front of its head or behind its tail) and within **±75°** of her facing, does a deathblow instead of a swing (the nearest target wins; it cancels any swing in progress). It lands on the press frame and turns her to face the target. She is then locked for **50 frames**, invulnerable throughout (hits come back DODGED). Not while staggered, dodging or airborne. Out of reach or facing away, attack is a normal swing.
- **Lives:** `lives` (default 1; bosses 2+). A deathblow takes one. At 0 lives it dies. With lives left it gets up for the next phase at once: full health, empty posture, no stagger. Revive restores all lives.
- **Requires deathblow (Sekiro rule):** with `requires_deathblow` on, 0 health doesn't kill: posture fills, it is staggered **with no time limit** and waits for a deathblow (more hits don't kill it). With it off, 0 health kills outright, whatever lives are left.
- **Training dummy:** 2 lives, `can_be_deathblown` and `requires_deathblow` on. **Duelist:** 1 life, both on. Heroine: 1 life, can't be deathblown.
- **HUD:** while the opponent's window is open a pulsing red **DEATHBLOW** prompt shows ("press Attack" when she is in reach and facing it, "get close" otherwise) with a red ◆ marker over the opponent. One pip per opponent life under its bars (filled = left).

## Hit-stop (implemented)
Code: `scripts/systems/hit_stop_service.gd` (autoload **`HitStop`**), `scripts/systems/hit_stop_config.gd`. Tests: `tests/unit/hit_stop_test.gd`, `tests/smoke/deathblow_smoke_test.gd`. Tuning: `data/combat/hitstop.tres`.

| Event | Freeze (real ms) |
|---|---|
| Parry (anyone parries) | 90 |
| Heroine's swing connects (hit, block or guard break) | 50 |
| Posture break (anyone; also 0 health → waiting for a deathblow) | 150 |
| Deathblow | 250 |

- A freeze sets `Engine.time_scale` to **0.05** and restores the previous value from a timer that ignores time scale (real milliseconds, also while paused). Overlapping requests **extend** the freeze to whichever ends last; they never add up. The time scale is also restored at once on a scene change or if the service leaves the tree.
- Godot keeps ticking physics at 60 Hz whatever the time scale (only delta shrinks), so combat timing uses its own clock: `HitStopService.combat_frame()` = physics frames minus frozen ones (`Combatant.current_frame()` returns it). Stagger, posture recovery, combo, dodge, enemy attack phases and sandbox revive timers all pause for exactly the freeze. Input is still read during a freeze (a deathblow can be pressed in it).
- Only combatants inside a scene trigger hit-stop (not bare unit-test instances).

## Hurtboxes (implemented)
Code: `scripts/combat/hurtbox.gd`. A `Hurtbox` is an `Area3D` on physics layer 4 **"hurtbox"** with a `combatant`, a `part_id` and a `damage_multiplier` / `posture_multiplier`. A hit on it goes through `Combatant.receive_attack`, so parry/block/dodge rules apply; the multipliers scale the health and posture damage the defender takes (not parry damage sent back). Enemies have no guard input: their guard stays down unless their AI raises it. The training dummy and the heroine each have one `body` hurtbox (×1/×1); large monsters get one per part (see "Large monsters"). A hurtbox emits `hit_received(result, attacker)` after each hit it resolves (monster parts fill their part posture from it).

## Player attacks and forms (implemented — week 3)
Code: `scripts/actors/player_combat.gd` (`PlayerCombat`, child of the heroine), `scripts/combat/combo_runner.gd`, `scripts/combat/dodge.gd`, `scripts/combat/form_config.gd`. Tests: `tests/unit/combo_runner_test.gd`, `tests/unit/dodge_test.gd`, `tests/unit/forms_tuning_test.gd`, `tests/smoke/forms_smoke_test.gd`. Tuning: `data/forms/*.tres`, `data/attacks/greatsword_*.tres`, `data/attacks/katana_*.tres`.

- **Swing timing:** the press frame is swing frame 1; then startup → active → recovery frames from the `AttackData`. She can't attack while staggered, dead, dodging or airborne. No movement input, sprint or jump while attacking; she lunges forward by `lunge_distance` over startup + active, then stands still in recovery.
- **Hits:** each active frame queries a box `hit_width × hit_height × reach` in front of her on the hurtbox layer. Each Combatant is hit **at most once per swing**, through its hurtbox with the highest damage multiplier. Her own hurtbox is ignored.
- **Combo buffering:** attack pressed during a swing's **active or recovery** frames is buffered; the next step starts on the frame after the last recovery frame. Presses during startup are ignored. With nothing buffered, a press within the form's **combo window** (greatsword 24 f, katana 18 f) after the swing still continues the combo; later presses restart at step 1. After step 3 the combo starts over.
- **Form switch** (`switch_form`, Q / Y): any time she can act. In **recovery** it cancels the rest of the recovery at once. In **startup/active** the swing lands with its original data and its recovery is cut the moment it begins. Either way the **next combo step comes from the new form** (greatsword 1 → switch → katana 2). `PlayerCombat.form_changed` fires; the HUD shows the form.
- **Guard and forms:** greatsword can block/parry; guard input is **ignored entirely in katana form**. Guard is dropped while attacking or dodging, and the parry window of an earlier press closes too (no parry mid-swing or in katana form). In greatsword, pressing block during attack **recovery** cancels it into guard (with a parry window).
- **Dodge (katana only)** (`dodge`, C or Left Alt / B): dashes in the move-input direction, or backward if there is none. Allowed when idle or in attack recovery (cancels it), on the ground, off cooldown. Invulnerable frames make `receive_attack` return **DODGED**. The dash covers exactly `dodge_distance`: when a dodge (or an attack lunge) ends she stops dead, with no slide, and walking picks up from rest.

| Form | Move speed | Guard | Dodge: distance / duration / i-frames / cooldown | Corruption |
|---|---|---|---|---|
| Greatsword | ×1.0 | Block + parry | — | −2 /s (×2 out of combat) |
| Katana | ×1.2 | None | 3.5 m / 18 f / frames 2–13 (12 f) / 20 f after it ends | +4 /s |

## Lock-on (implemented)
Code: `scripts/combat/lock_on_point.gd` (`LockOnPoint`, a `Marker3D`), `scripts/combat/lock_on_targeting.gd` (pure scoring/cycling rules), `scripts/combat/lock_on_candidate.gd`, `scripts/combat/lock_on_config.gd`, `scripts/actors/lock_on.gd` (`LockOn`, child of the heroine), lock tracking in `scripts/actors/third_person_camera.gd`, the HUD marker in `scripts/ui/combat_hud.gd`. Tests: `tests/unit/lock_on_targeting_test.gd`, `tests/smoke/lock_on_smoke_test.gd`. Tuning: `data/combat/lock_on.tres`.

- **Lock points:** a `LockOnPoint` goes on every lockable target, one per body part on large monsters. It has an owner `combatant` (found from its ancestors if unset), a `part_id`, a `priority` (higher = preferred) and a `target_size` in meters (camera framing). Points sharing a Combatant are parts of one target. The training dummy has one `body` point at 1.4 m (size 2.2 m).
- **Pick (lock_on):** candidates must be in front of the camera, within **20 m** of her, within **55°** of the view centre, and in line of sight (a ray from her eye, 1.5 m up, on the `world` layer; characters don't block it). Lowest score wins: `1.0 × angle/55° + 0.35 × distance/20 m − 0.15 × priority`, so nearest to the screen centre dominates. Pressing lock_on again unlocks. While she is defeated or staggered lock_on can't pick up a new lock (unlocking still works).
- **Cycle:** lock_cycle_next / lock_cycle_prev (wheel), a right-stick flick (deflection ≥ **0.7**; the stick must return under **0.3** before the next flick; only the joypad axis counts, so the arrow keys also bound to camera_left/right never switch target) or a fast mouse flick (**220 px** of horizontal motion, fading at ×12/s). Next = to the right on screen, previous = to the left, wrapping round. **First the other parts of the same target** not yet visited since landing on it (an off-screen part still counts if in range and in sight), **then the next other target** (within **80°** of view), landing on its best-scoring part. With no other target it goes round its own parts again.
- **While locked:** the camera yaw/pitch ease toward the point (sharpness 10 / 6, pitch −12° from straight at it, clamped −45°…35°). Yaw holds while the point is within **1.2 m** of the camera rig on the ground plane (`hold_yaw_within`), so it doesn't spin round when she passes under a big monster's head; mouse/stick look is off (the stick flicks instead). The camera pulls back by `clamp((target_size − 2.5 m) × 0.8, 0, 6 m)`, easing at 4/s (an 8 m monster: +4.4 m). The heroine turns to face the point at 900°/s (not while defeated or staggered); movement stays camera-relative, so sideways input strafes round the target. Sprinting faces the run direction (unless guarding). Every swing starts aimed at the locked point; the dodge still follows move input.
- **Lock breaks** when the target dies, the point is further than **25 m**, line of sight has been blocked **45 combat frames** in a row (it breaks on the 45th blocked frame; the count pauses during hit-stop), or the heroine dies. A deathblow that leaves a life keeps the lock. If a locked part is disabled or removed, the lock moves to another part of the same target, or breaks if there is none. Signals: `LockOn.locked`, `switched`, `unlocked(reason)` (MANUAL / TARGET_DIED / OUT_OF_RANGE / LOST_SIGHT / POINT_GONE / SELF_DEFEATED).
- **HUD:** a ring marker with the part name sits over the locked point, projected from the camera.

## Duelist (implemented — week 2)
Code: `scripts/actors/duelist.gd` (`Duelist`, the state machine, on `scripts/actors/enemy_body.gd` — `EnemyBody`, shared with the large monster: target, home/leash, fall reset, respawn, pathing (re-paths only when the goal moves 0.5 m), turning, movement, hit query), `scripts/combat/duelist_brain.gd` (`DuelistBrain`, pure decision rules), `scripts/combat/duelist_attack_entry.gd`, `scripts/combat/duelist_config.gd`. Scene: `scenes/actors/duelist.tscn`. Tests: `tests/unit/duelist_brain_test.gd`, `tests/smoke/duelist_smoke_test.gd`. Tuning: `data/combat/duelist_ai.tres` (AI, attack table rows), `data/combat/duelist_combatant.tres` / `duelist_posture.tres` / `duelist_guard.tres`, attacks in `data/attacks/duelist_*.tres`.

A capsule humanoid (1.8 m, dark body with a sword bar) with a Combatant, one `body` hurtbox (×1/×1), a `LockOnPoint` at 1.3 m (size 1.9 m) and a `NavigationAgent3D`. It joins the `hostile` group. Its timing runs on combat frames (pauses during hit-stop).

**States:** IDLE (at home) → engages when the heroine is within **10 m** of it and within its **16 m leash** of home → CIRCLE / APPROACH → STARTUP (tell) → ACTIVE → RECOVERY (punish window) → CIRCLE … Plus FLINCH, STAGGERED (posture break, deathblow window), DEAD, and RETURN (walks home when she leaves the leash or dies; idle again within 0.5 m of home).
- **Circle:** strafes sideways at **1.8 m/s** (random side, flips when it bumps into something), keeping **2.8–4.5 m**: walks in (3.2 m/s) beyond it, backs off (2.4 m/s) inside it. It circles **45–100 frames** (rolled) before trying an attack; after it blocks or parries, at most **12 frames** (a counter).
- **Attack choice:** when the circle timer runs out it **plans** one row: among rows off cooldown (`frame − last start ≥ cooldown_frames`; never-used rows are ready, `weight > 0`), dropping the last attack used if another is ready (`avoid_repeat`), one roll picks by `weight` in table order — distance is ignored, so the short-range quick slash (weight 3) is planned as often as its weight says even though it circles outside its range. If every row is cooling down it circles again. If the planned row is *valid* now (distance within its `[min_range, max_range]`, inclusive, and off cooldown) it starts at once; otherwise **APPROACH**: walk toward her (along the navmesh path if the map has a navigation region, else straight) until within that row's `max_range`, then start it. If she is closer than its `min_range`, it switches to any row valid at that distance (`DuelistBrain.pick_attack`) and starts it, and only backs off if none is valid, so hugging it or pinning it to a wall can't stop it attacking. It doesn't start an attack while it is waiting to parry or holding a block. (`DuelistBrain.select_attack` is that pick: any valid row at a distance, same repeat/weight rules.)
- **Swing:** turns toward her at **150°/s** during startup (360°/s otherwise), no turning once active. Lunges forward `lunge_distance` over startup + active. The body colour ramps from its base to the attack's tell colour over the startup and holds it while active. Hits: each active frame queries a box `hit_width × hit_height × reach` in front of it on the hurtbox layer; only her Combatant, at most once per swing. Sweeps (`misses_airborne`) miss her in the air. In recovery it stands still with guard down.
- **Guard (its own Guard / GuardConfig):** when she starts a swing within `reach + lunge + 1.0 m` of it and facing it within **±75°**, and it is idle, returning, approaching or circling (never in its own startup/active/recovery, a flinch or a stagger), it rolls once: **parry 25%**, **block 35%**, otherwise nothing. A parry presses guard **5 frames** before her swing's first active frame (her press frame + startup), well inside its **12-frame** window; a block raises guard at once. Either holds guard until **8 frames** after her last active frame. The body turns blue-grey while guard is up.
- **Flinch:** posture damage from unguarded hits (HIT) adds up; at **15** it flinches for **20 frames** (cancels a wind-up; no moving, guarding or attacking; a flinch during its swing or recovery lasts at least until that recovery would have ended, so it never shortens the punish window) and the build-up starts over. Build-up is forgotten **90 frames** after the last hit. Perilous attacks have super armour once started. (One unguarded greatsword hit = 30 × 0.5 = 15: it flinches; katana hits take three.)
- **Defence numbers:** max health **120**, posture **100**, recovery **10/s** after **150 frames** (×1.5 guarding), posture break = **120-frame** stagger. Being parried by her: it takes 100% of its attack's posture damage. Parrying her: she takes **60%** of her swing's posture damage; blocking costs it **80%** of the posture damage, no chip.
- **Sandbox:** stands at (−16, 0, −20) on a dark 7 m arena disc, ~29 m from the dummy and away from the movement course. `SandboxRules` revives it **240 frames** after death, back at home.

**Attack table — duelist** (`data/combat/duelist_ai.tres`, attacks in `data/attacks/duelist_*.tres`)
| ID | Attack | Startup (f) | Active (f) | Recovery = punish window (f) | Dmg | Posture dmg | Blockable? | Deflectable? | Perilous | Tell (colour) | Reach (m) | Lunge (m) | AI range (m) | Cooldown (f) | Weight |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| duelist_quick_slash | Quick slash | 18 | 4 | 26 | 15 | 20 | Yes | Yes | — | Yellow | 2.4 | 0.4 | 0–2.6 | 70 | 3 |
| duelist_delayed_overhead | Delayed overhead (long wind-up baits early parries) | 48 | 5 | 42 | 28 | 35 | Yes | Yes | — | Orange | 2.7 | 0.6 | 1.0–3.0 | 180 | 2 |
| duelist_perilous_thrust | Perilous thrust (gap closer) | 40 | 4 | 52 | 30 | 35 | **No** | **Yes**: parry it | Thrust | Red | 3.4 | 1.2 | 2.4–4.6 | 300 | 1.5 |

From point blank out to its 4.5 m circling edge, at least one attack is always valid (unit-tested), so it never stands and stares. Simulating circle → plan → attack with cooldowns, every row of the real table gets used, and every row's `min_range` is inside the circling band (unit-tested).
- **Keeping it in the level:** if it ever drops below `fall_reset_height` (**−10 m**) it is put back at home, idle, facing the way it started (a revive or shrine respawn restores its start facing too). The sandbox floor also has 3 m edge walls (`Greybox/EdgeWall_*`), since its home (−16, 0, −20) is only 10 m from the north edge and its leash is 16 m.

## HUD opponent
The opponent bars (with the opponent's name and life pips) follow the **locked** target; with no lock, the **nearest** body in the `hostile` group (alive or not, ground distance from the heroine); else the HUD's `opponent` export. The deathblow prompt and marker follow the same opponent.

## Inputs
attack: left mouse / RB · block: right mouse / LB · switch_form: Q / Y · dodge: C, Left Alt / B · lock_on: middle mouse / R3 · lock_cycle_next: wheel down (or flick right stick / mouse right) · lock_cycle_prev: wheel up (or flick left) · interact: E / X (rest at a shrine) · heal: R / D-pad up.

## Sandbox rules
The dummy takes health damage from her attacks; at 0 health it waits, staggered, for a deathblow. After the deathblow on its last life it goes dark (`DEAD` phase) and `SandboxRules` revives it after 180 frames with both lives. The duelist is revived 240 frames after its deathblow, at its home point; monster #1 300 frames after its last deathblow, at home with every part whole. The heroine is revived 120 frames after defeat, where she fell — but only until she has a shrine respawn point: after she rests at a shrine, her death is left to the shrine respawn (`SandboxRules.player_respawns_at_shrine()` asks her `PlayerRest.will_respawn()`), so the two never both fire. The sandbox shrine stands in the south-east corner at (18, 0, 18), its gate facing the middle.

## Core rules (from the design foundation)
- **Posture only, no stamina.** Her posture fills when she blocks; enemy posture fills from her parries and limb breaks. Full posture → deathblow / stagger.
- **Parry window:** start generous (10–12 frames), tighten after playtests. Tune in this order: parry window → posture regen → damage.
- **Lock-on** cycles between body parts (head, limbs, weak points). Camera pulls back by the target's size (implemented, see "Lock-on"); pushing toward the head during telegraphs is not done yet.
- **Healing:** limited heals, refilled at shrines (implemented — see "Healing charges").
- **Spirit arts:** small energy pool, refills from hits and parries, full at shrines. Utility first.

## Forms
| Form | Unlocked | Plays like | Defense | Cost |
|---|---|---|---|---|
| Greatsword | Start | Slow, heavy; breaks posture and limbs | Block + parry | Drains corruption slowly |
| Katana | Start | Fast attacks, faster movement | No block; i-frame dodge + counters | Corruption rises while active |
| Claw form | After taming | Claw combos, flash dashes, wall-runs | Speed | Full bond meter; 20–30 s |

## Corruption v0 (implemented — week 3)
Code: `scripts/combat/corruption.gd` (`Corruption`, pure logic), `scripts/combat/corruption_config.gd`, `scripts/actors/corruption_meter.gd` (`CorruptionMeter`, child of the heroine). Tests: `tests/unit/corruption_test.gd`, `tests/smoke/corruption_smoke_test.gd`. Tuning: `data/combat/corruption.tres` (meter-wide values) and `corruption_per_second` / `corruption_out_of_combat_multiplier` on each form in `data/forms/*.tres`.

- **One meter, 0–100.** Each combat frame (paused during hit-stop and while she is dead) it changes by the current form's rate: **katana +4 /s** (same out of combat), **greatsword −2 /s in combat, −4 /s out of combat** (×2). Clamped to 0–100. She keeps her corruption through a sandbox revive.
- **In combat** = a living Combatant whose body is in the **`hostile`** group within **12 m** (ground plane), **or** she dealt or took an attack (any outcome but MISSED, including DODGED and parries) or a deathblow within the last **300 frames** (5 s). The training dummy joins `hostile` in `_ready`.
- **Thresholds 50 / 75 / 100:** `threshold_reached(t)` fires when the meter rises to `t` from below, `threshold_dropped(t)` when it falls back below. (Nothing listens yet besides the HUD; the cat's whispers will.)
- **Rampage:** starts when the meter *reaches* 100 from below (not if her health is already critical). While it lasts the **katana dodge is locked** (`PlayerCombat.set_dodge_locked`; the HUD says "Dodge: locked (rampage)"). It ends when the meter drains to **50**, when her health falls to **25%** or lower (critical), or at a shrine. After a critical-health exit, sitting at 100 doesn't restart it: the meter has to drop below 100 and reach it again. Signals `rampage_started`, `rampage_ended(reason)` (DRAINED / CRITICAL_HEALTH / SHRINE).
- **Input hijack — stubbed:** `CorruptionMeter.should_hijack_input(rng)` rolls `hijack_chance()`: 0 up to **50**, then rising as ((c − 50) / 50)² × **0.25** to 25% per check at 100. Nothing calls it to change her input yet; rampage also changes nothing but the dodge lock.
- **Shrine rest:** `CorruptionMeter.reset_at_shrine()` empties the meter, ends any rampage (and forgets recent combat). Signal `shrine_reset`.
- **HUD:** a purple corruption bar above the form line, with "Corruption N% · in combat / out of combat" and a pulsing **RAMPAGE (no dodge)**; a RAMPAGE flash when one starts.
- Design rule: corruption should *tempt* (more damage, the cat's whispers), never only punish. Never reward behavior the story condemns. (v0 has no temptation reward yet; that comes with the hijack and the cat's lines.)

## Healing charges (implemented — week 3)
Code: `scripts/combat/heal_charges.gd` (`HealCharges`, pure logic), `scripts/combat/heal_config.gd`, `scripts/actors/player_healing.gd` (`PlayerHealing`, child "Healing" of the heroine). Tuning: `data/combat/heals.tres`. Tests: `tests/unit/heal_charges_test.gd`, `tests/smoke/shrine_smoke_test.gd`.

- **3 charges**, each restores **40 health** (clamped to max; `Combatant.heal`). `heal` (R / D-pad up) starts one when she can act, is on the floor and isn't attacking, dodging or in a deathblow. Refused at full health (`allow_at_full_health` off) or with 0 charges.
- **Timing:** the heal takes **54 frames** from the press; the health comes back and the charge is spent on frame **30**. For all 54 frames: no attack, dodge, guard, form switch or jump; she can walk at **×0.35** speed (no sprint). Counted on combat frames (paused during hit-stop).
- **Interruption (chosen rule):** a hit that lands (HIT or GUARD_BROKEN) cancels the heal (`interrupted_by_hits`). **Before frame 30 that costs nothing**: no health, charge kept — the risk is the lost time and the hit, not the charge. After frame 30 the heal is kept and only the rest of the recovery is cancelled. A posture break or death always cancels it. (Forgiving for v0; if healing under pressure feels too safe, spend the charge on the press instead.)
- **Refill:** resting at a shrine or respawning at one refills all charges.
- **HUD:** "Heals ◆◆◇ 2/3" above the corruption bar, "· healing" while one runs.

## Shrines: rest and respawn (implemented — week 3)
Code: `scripts/world/shrine.gd` (`Shrine`, greybox scene `scenes/world/shrine.tscn`), `scripts/actors/player_rest.gd` (`PlayerRest`, child "Rest" of the heroine), `scripts/world/rest_config.gd`. Tuning: `data/world/shrine.tres`. Tests: `tests/smoke/shrine_smoke_test.gd` (and scene wiring in `tests/unit/heal_charges_test.gd`).

- **Rest prompt:** while she stands in the shrine's `InteractArea` (a 2.6 m cylinder in front of the gate, player layer) an on-screen **"Rest · E / X"** prompt shows. `interact` rests. Not while dead, staggered, attacking, dodging or healing, and not while a living `hostile` Combatant is within **8 m** of the shrine (the prompt then says "enemies nearby"; a dead one doesn't count). The prompt shows only when she could rest or only a hostile is in the way: while she is dead, staggered, attacking, dodging or healing it is hidden.
- **Resting** (`PlayerRest.rest`): full health and empty posture, no stagger (`Combatant.restore`, which doesn't emit `revived` for the living); all heal charges back; corruption reset (`CorruptionMeter.reset_at_shrine`: meter 0, rampage ends with reason SHRINE); every node in the group **`respawn_on_rest`** gets `respawn()` (the training dummy: back on its start spot, revived with all lives, attack list from the top; the duelist: revived at home, idle, cooldowns cleared); and the shrine's `SpawnPoint` becomes her **respawn point**. HUD flashes "RESTED · heals refilled".
- **Respawn:** when she dies with a respawn point, after **150 frames** she is put at the last rested shrine's `SpawnPoint` (feet on its origin, facing its −Z, camera behind her, lock-on released), revived, and — with `respawn_rests` on — given a full rest too (heals, corruption, enemies). HUD flashes "RETURNED TO SHRINE". Without a respawn point nothing happens in `PlayerRest`, so a level rule (the sandbox's `SandboxRules`) can revive her instead.
- **Start shrine:** a shrine with `start_shrine` on registers itself as her respawn point when the level starts (Zone 01's "Shrine A"). The sandbox shrine has it off, so the in-place sandbox revive keeps working until she first rests.

## Level navigation and the shortcut gate (implemented — week 4)
Code: `scripts/levels/zone_navigation.gd` (`ZoneNavigation`), `scripts/world/nav_profiles_config.gd` (`NavProfilesConfig`), `scripts/world/shortcut_gate.gd` (`ShortcutGate`, greybox scene `scenes/world/shortcut_gate.tscn`), `scripts/world/shortcut_gate_config.gd`, `scripts/world/stealth_volume.gd` (`StealthVolume`). Tuning: `data/world/nav_profiles.tres`, `data/world/shortcut_gate.tres`. Baked navmeshes: `data/navigation/zone01_nav_human.tres`, `data/navigation/zone01_nav_large.tres`. Navmesh builder: `scripts/levels/rebuild_zone01_navmesh.gd`. Tests: `tests/unit/zone_navigation_test.gd`, `tests/smoke/zone01_smoke_test.gd`. Layout: `docs/ZONE01.md`.

- **One navmesh per agent size, same source geometry.** A level's `Navigation` node (`ZoneNavigation`) has two `NavigationRegion3D` children: **HumanNav** (agent radius **0.4 m**, height **1.8 m**: heroine-size enemies such as the duelist and later guardians) and **LargeNav** (radius **2.4 m**, height **5.0 m**: monster class L; monster #1's body capsule is 2.3 m). Both bake **static collision shapes only** from the node group `zone01_nav_source` (the level's `NavSource` node and its children: greybox floors, ramps, ledges, shrines, the shortcut gate), so set dressing in `*_Art.tscn` never changes them. **Solid blockers** (the walls, combat pillars and the 16 m arena landmark) sit under a separate `Blockers` node outside the group: they only carve the navmeshes, through one `NavigationObstacle3D` footprint each under `NavSource/BlockerFootprints` (*affect navigation mesh* on, *carve* off, so each profile grows it by its agent radius; avoidance off). So their tops never become walkable, unreachable islands. Shared: max climb **0.35 m** (ART_SPEC step-up), max slope **40°**, cell size **0.2 m**, cell height **0.05 m** (radii, climb and heights are whole cells, so the bake doesn't round them). The project's default navigation map uses the same cell size and height (`project.godot` `[navigation]`).
- **Separate maps.** HumanNav stays on the World3D's default map; on ready `ZoneNavigation` creates a second map for LargeNav, so the two navmeshes never merge. Every `NavigationAgent3D` under the level's `Actors` node (and any added later) is put on the map that fits it: radius **≥ 1.2 m** (`large_agent_min_radius`) → large map, else the human map. The duelist (agent radius 0.4) paths on HumanNav; monster #1 (agent radius 2.5) on LargeNav.
- **What that gives Zone 01:** the 4 m wide arena gate has no large-agent navmesh, so the boss can't path out of its arena; human agents path everywhere on foot (including up the vista ramp).
- **Rebaking:** after changing the greybox, a blocker or `nav_profiles.tres`, run `godot --headless --path . --script res://scripts/levels/rebuild_zone01_navmesh.gd`: it regenerates the blocker footprints from the blockers' box collision, then bakes both navmeshes with the shortcut gate **closed** (UIDs kept). (The editor's *Bake NavigationMesh* on `Navigation/HumanNav` / `LargeNav` gives the same navmeshes as long as the footprints are current.) `zone_navigation_test.gd` fails while a baked navmesh doesn't match the profile, or has polygons on top of or inside a wall, pillar or the landmark.
- **Shortcut gate (one-way):** its far side is its local **+Z**. In its `InteractArea` (6 × 7 m, both sides) on the far side the prompt says **"Open · E / X"** and `interact` opens it; on the near side the prompt says **"Opens from the other side"** and `interact` does nothing. Not while dead, staggered, attacking, dodging or healing. Opening takes **45 frames** (`open_frames`; the panel's mesh rises **3.2 m**, its collision stays down) and it blocks until then; then its collision turns off and its `NavLink` (`NavigationLink3D` across the gap, which the navmesh is baked around while closed) turns on so agents path through. It stays open (no save system yet; `start_open` exists for one).
- **Stealth volumes (placeholder):** `StealthVolume` areas (no layer, mask player) mark the stealth pocket's overlook, high route, low route, hide spot, lantern pools and patrol loop (`kind`, a `note`, `player_inside()`, group `stealth_volume`). No stealth rules or guardians yet.

## Large monsters: per-part posture (implemented — weeks 3–4)
Code: `scripts/actors/large_monster.gd` (`LargeMonster`, state machine on `EnemyBody`, see Duelist), `scripts/combat/monster_part.gd` (`MonsterPart` component node), `scripts/combat/monster_part_state.gd` (pure part rules), `scripts/combat/monster_part_config.gd`, `scripts/combat/monster_brain.gd` (pure zone + attack-choice rules), `scripts/combat/monster_attack_entry.gd`, `scripts/combat/large_monster_config.gd`; `Combatant.stagger()`. Scene: `scenes/actors/monster01.tscn`. Tests: `tests/unit/monster_part_test.gd`, `tests/unit/monster_brain_test.gd`, `tests/smoke/monster_smoke_test.gd`. Tuning: `data/combat/monster01_ai.tres` (AI + attack table rows), `data/combat/monster01_combatant.tres` / `monster01_posture.tres` / `monster01_guard.tres` (whole body), `data/combat/monster01_part_*.tres` (one per part, each with its own embedded part `PostureConfig`), attacks in `data/attacks/monster01_*.tres`.

**Structure.** One whole-body `Combatant` (health, posture, lives) and one `MonsterPart` per body part. A part is a `Node3D` (later parented under a `BoneAttachment3D` on the rig socket) with a `Hurtbox` (its `combatant` = the monster's) and a `LockOnPoint`. The whole body turns (yaw), so parts turn with it; its collision is a cylinder so turning never snags.
- **Each part:** its hurtbox takes `damage_multiplier` × health damage and `posture_multiplier` × whole-body posture damage (her swing hits the overlapping part with the highest damage multiplier). A breakable part also has its **own part posture bar**: each HIT / BLOCKED / GUARD_BROKEN through it fills the bar by the whole-body posture damage it dealt × `part_posture_multiplier` (2). Part posture recovers like any posture (delay, then per second) and never while broken.
- **Part break (bar full):** the part stays broken until the monster respawns: its damage multiplier × `broken_damage_multiplier` (1.5), its meshes turn dark red, attacks in its `disables_attacks` can't be chosen, and attacks in `weakens_attacks` deal `weakened_scale` × damage and posture damage (several broken parts multiply). The whole monster takes `body_posture_on_break` (60) whole-body posture; if that breaks its posture it is a normal posture break (deathblow window). Otherwise it is **staggered for `break_stagger_frames` (120)** via `Combatant.stagger()`: it can't act, its attack is cancelled, posture doesn't recover, but **no deathblow window opens** (a punish window, not a finisher). Hit-stop: the posture-break kind.
- **`Combatant.stagger(frames)`:** staggered without a posture break (`staggered(frames)` signal, `stagger_ended` when it ends). Ignored while dead or already posture-break staggered; a longer one extends a running one (a second part break restarts the full stagger); a posture break during it takes over. Hits landing during any stagger don't lengthen it. `is_staggered()` covers it; `is_break_staggered()` and `is_deathblow_available()` don't.
- **Lock-on:** every part's `LockOnPoint` gets the monster's `target_size` (7.5 m: the camera pulls back +4.0 m). Cycling visits all its parts before other targets (see "Lock-on"). The HUD shows the **locked part's posture bar** (part name, "· BROKEN" once broken) under the opponent bars.

**AI (`LargeMonster`, `MonsterBrain`).** States: IDLE (at home) → engages when she is within **18 m** and within its **32 m leash** of home → CHASE → STARTUP (tell) → ACTIVE → RECOVERY (punish window) → CHASE … plus STAGGERED (part break or posture break), DEAD, and RETURN (walks home when she leaves the leash or dies). Combat frames throughout.
- **Chase:** turns toward her at **75°/s** (slow: she can get round it) and walks in at **3.5 m/s** (along a navmesh path via its `NavigationAgent3D`, radius 2.5 m, if the map has a navigation region; else straight at her) until **5.5 m** from its origin. After each recovery (and on engaging) it waits **20–50 frames** (rolled), then tries every frame to pick an attack.
- **Zones:** where she stands round its body, on the ground plane: **FRONT** within **40°** of its facing, **REAR** within **60°** of straight behind, **SIDE** otherwise (edges inclusive).
- **Attack choice:** rows valid for her zone and her distance from its origin (inclusive), off cooldown and not disabled by a broken part; with more than one valid, the last one used is dropped (`avoid_repeat`); one roll picks by weight in table order. Nothing valid: it keeps turning and walking in. Close in (≤ 8 m) there is always an answer in every zone; in front, the charge covers 8–13 m.
- **Attacks:** the wind-up colour ramps from its base to the tell colour; front attacks keep turning toward her at **50°/s** during startup, the tail sweep and stomp don't turn. Active frames query a box in its own frame (`hit_center`, `hit_size`, moving with any lunge); only her Combatant, once per attack. The charge lunges `lunge_distance` over its **active** frames. Sweeps miss her in the air. No flinch from ordinary hits (super armour throughout): only a part break or a posture break interrupts it.
- **Respawn / sandbox:** a shrine rest (group `respawn_on_rest`) revives it at home with every part whole. Fallen below **−10 m**: put back home. `SandboxRules` revives it **300 frames** after death.

**Monster #1** (`scenes/actors/monster01.tscn`): a primitive proxy beast, size class **L — 6.0 m** tall (hump top), ~12 m from nose to tail. Whole body: max health **600**, posture **300** (recovery 6/s after 180 frames), posture break = **180-frame** stagger, **2 lives**, `can_be_deathblown` + `requires_deathblow` (boss rule: the second phase ends at 0 health, staggered until the deathblow). Body radius **2.3 m**.

| Part | Part posture (regen) | Dmg × | Whole-body posture × | Lock priority | When broken |
|---|---|---|---|---|---|
| head | 90 (4/s after 300 f) | 1.5 | 1.5 | 1 | Charge ×0.6 |
| left_forelimb | 120 (4/s after 300 f) | 1.1 | 1.0 | 0 | Front swipe ×0.5 |
| right_forelimb | 120 (4/s after 300 f) | 1.1 | 1.0 | 0 | **Front swipe disabled** |
| tail | 100 (4/s after 300 f) | 0.9 | 0.8 | −1 | Tail sweep ×0.5 |
| body | — (can't break) | 1.0 | 1.0 | 2 | — |

The body part's hurtbox is a torso box (y 1.9–4.9 m), a **flank** box from the ground to the torso (3.8 × 1.9 × 4.5 m, between the forelimbs and the hind legs, clear of the tail) and the two hind legs: her swing box only reaches `hit_height` (1.8 m) up, so the flank is what she hits from beside it (smoke-tested with greatsword and katana swings from both flanks).

All breakable parts: broken ×1.5 damage, 120-frame whole-body stagger, +60 whole-body posture. One greatsword light 1 on a forelimb (30 posture × 50% unguarded × 1.0 = 15 whole-body) fills its bar by 30, so a forelimb breaks in about 4 greatsword hits (unit-tested: 3–6).

**Attack table — monster #1** (`data/combat/monster01_ai.tres`, attacks in `data/attacks/monster01_*.tres`)
| ID | Attack | Startup (f) | Active (f) | Recovery = punish window (f) | Dmg | Posture dmg | Blockable? | Deflectable? | Perilous | Tell (colour) | Zones | AI range (m) | Cooldown (f) | Weight | Hit box (centre; size, m, own frame) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| monster01_front_swipe | Front swipe | 42 | 8 | 64 | 25 | 30 | Yes | Yes | — | Amber | Front | 0–8 | 150 | 3 | (0, 1.3, 5); 7 × 2.6 × 6 |
| monster01_tail_sweep | Tail sweep | 50 | 10 | 72 | 28 | 25 | No | No: jump over it | Sweep | Purple | Side, rear | 0–8 | 180 | 2 | (0, 0.8, −0.5); 16 × 1.6 × 15 |
| monster01_stomp | Stomp (area round it) | 56 | 6 | 80 | 35 | 40 | **No** | **No**: dodge or leave the area | — (unblockable) | Teal | All | 0–6.5 | 300 | 1.5 | (0, 1, 0); 13 × 2 × 13 |
| monster01_charge | Charge (gap closer, lunges 9 m) | 66 | 20 | 96 | 40 | 45 | **No** | **Yes**: parry it | Thrust | Red | Front | 8–13 | 360 | 2 | (0, 1.5, 4.5); 4.5 × 3 × 4, plus the lunge |

Every wind-up is ≥ 40 frames and every recovery ≥ 60 (unit-tested); every attack has its own tell colour; each hit box reaches the far edge of its AI range in every zone it is chosen from (unit-tested, allowing for the startup turn of front attacks).
- **Sandbox:** its arena is a 50 × 50 m floor east of the main sandbox (centre (80, 0, 0), 4 m walls), reached through a gap in the east edge wall (z −4…4) and a 25 m corridor. It stands at (80, 0, 0) facing the entrance; its 18 m aggro never reaches the corridor.

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
| Move | Startup | Active | Recovery | Posture dmg to enemy (before the defender's hit/block multipliers) | Notes |
|---|---|---|---|---|---|
| Greatsword light 1 | 18 | 5 | 26 | 30 (dmg 22) | Reach 2.6 m, width 1.8 m, lunge 0.6 m |
| Greatsword light 2 | 20 | 5 | 28 | 34 (dmg 24) | Reach 2.6 m, width 1.8 m, lunge 0.6 m |
| Greatsword light 3 | 26 | 6 | 40 | 50 (dmg 34) | Reach 2.8 m, width 2.0 m, lunge 1.0 m |
| Katana light 1 | 8 | 3 | 14 | 10 (dmg 12) | Reach 2.2 m, width 1.4 m, lunge 0.4 m |
| Katana light 2 | 8 | 3 | 14 | 10 (dmg 12) | Reach 2.2 m, width 1.4 m, lunge 0.4 m |
| Katana light 3 | 12 | 4 | 22 | 16 (dmg 18) | Reach 2.4 m, width 1.6 m, lunge 0.8 m |
| Form switch | Q / Y | — | — | — | Cancels attack recovery; next combo step uses the new form |
| Dodge (katana) | C, Left Alt / B | i-frames: dodge frames 2–13 | 18 f dash, 20 f cooldown | — | 3.5 m; backward if no input; cancels attack recovery |
| Deathblow | Attack on a staggered enemy in reach | lands on the press frame | 50 f lock-out, invulnerable | Takes 1 life | Reach 2.6 m, ±75° facing; see "Deathblow and lives" |
| Guard (block / parry) | Right mouse / LB | parry window: 12 | — | Parry: 100% of the attack's posture damage | Slows movement to 40%, no sprint |

## Heroine animation (implemented — week 3, placeholders)
Visual only: the AnimationTree never changes gameplay, and no rule above reads it. `HeroineAnimationDriver` (child `AnimationDriver` of the heroine) maps her state to an `AnimationNodeStateMachine` each physics tick in this priority: death → stagger → deathblow → dodge → attack (state = the swing's `AttackData.id`) → heal → hit react / guard hit / parry → jump / fall → land / rest → guard → locomotion. One-shot clips are stretched to the gameplay frame counts in the tables above (startup + active + recovery, dodge 18 f, heal 54 f, deathblow 50 f), so retuning a row re-times its clip. No root motion is applied; the body moves by `lunge_distance` / `dodge_distance`. Clip names, lengths and the rig hand-off: `docs/ANIMATION_CLIPS.md`. Tuning: `data/animation/heroine_anim.tres`. Tests: `tests/unit/heroine_animation_test.gd`, `tests/smoke/animation_smoke_test.gd`. After changing an attack row or a form's combo, run `scripts/animation/rebuild_heroine_anims.gd` (the unit test fails until the saved tree matches).

## Playtest logging
Log every player death with the attack ID. Review the death log each Friday.
