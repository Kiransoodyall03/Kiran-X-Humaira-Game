class_name DuelistConfig
extends Resource
## Tuning for the capsule duelist's AI (docs/COMBAT_SPEC.md, "Duelist"): its attack table,
## spacing, movement, guard odds and hit reactions. Its health, posture and guard timing
## are in its CombatantConfig. Frames are combat frames at 60 fps.

## The attack table. DuelistBrain picks from the rows valid at the current distance.
@export var attacks: Array[DuelistAttackEntry] = []
## With two or more attacks valid, never pick the one used last.
@export var avoid_repeat: bool = true
## Seed for the AI's random rolls (attack pick, guard, strafe). 0 = a new seed each run.
@export var rng_seed: int = 0

@export_group("Engage")
## Engages when the target comes this close to it (ground plane), in meters.
@export_range(0.0, 100.0, 0.5, "suffix:m") var aggro_radius: float = 10.0
## Gives up and walks home when the target is further than this from its home point.
@export_range(0.0, 200.0, 0.5, "suffix:m") var leash_radius: float = 16.0
## Close enough to home to stop walking, in meters.
@export_range(0.05, 5.0, 0.05, "suffix:m") var home_tolerance: float = 0.5
## Below this height (global y) it has fallen out of the level and is put back at home.
@export_range(-1000.0, 0.0, 0.5, "suffix:m") var fall_reset_height: float = -10.0

@export_group("Movement")
## Speed when walking toward the target or home, in m/s.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var walk_speed: float = 3.2
## Sideways speed while circling, in m/s.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var strafe_speed: float = 1.8
## Speed when backing off (target too close), in m/s.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var retreat_speed: float = 2.4
## How fast it reaches those speeds, in m/s².
@export_range(0.0, 200.0, 0.5, "suffix:m/s²") var acceleration: float = 18.0
## How fast it turns to face the target.
@export_range(0.0, 2000.0, 10.0, "suffix:°/s") var turn_speed_degrees: float = 360.0
## Turning while winding up an attack (tracking). It stops turning once the swing is active.
@export_range(0.0, 2000.0, 10.0, "suffix:°/s") var startup_turn_speed_degrees: float = 150.0

@export_group("Spacing")
## Circling keeps the target between these distances, in meters.
@export_range(0.0, 20.0, 0.05, "suffix:m") var circle_min_distance: float = 2.8
@export_range(0.0, 20.0, 0.05, "suffix:m") var circle_max_distance: float = 4.5
## Frames it circles before it tries an attack (rolled between these each time).
@export_range(0, 1200, 1, "suffix:frames") var circle_frames_min: int = 45
@export_range(0, 1200, 1, "suffix:frames") var circle_frames_max: int = 100
## After it blocks or parries, it tries to attack within this many frames (a counter).
@export_range(0, 1200, 1, "suffix:frames") var counter_frames: int = 12

@export_group("Guard")
## Chance it parries one of the target's swings (rolled once per swing, checked first).
@export_range(0.0, 1.0, 0.01) var parry_chance: float = 0.25
## Chance it blocks instead (on top of the parry chance: 0.25 + 0.35 = 60% defended).
@export_range(0.0, 1.0, 0.01) var block_chance: float = 0.35
## A parry presses guard this many frames before the swing's first active frame. Keep it
## below its GuardConfig parry window.
@export_range(1, 30, 1, "suffix:frames") var parry_lead_frames: int = 5
## A block holds guard until this many frames after the swing's last active frame.
@export_range(0, 120, 1, "suffix:frames") var block_hold_extra_frames: int = 8
## Only reacts to a swing if the target is within reach + lunge + this, in meters…
@export_range(0.0, 10.0, 0.05, "suffix:m") var guard_reach_margin: float = 1.0
## …and the target faces it within this angle.
@export_range(0.0, 180.0, 1.0, "suffix:°") var guard_facing_degrees: float = 75.0

@export_group("Hit reactions")
## Posture damage from unguarded hits that makes it flinch (cancels its wind-up).
@export_range(0.0, 1000.0, 0.5) var flinch_posture_threshold: float = 15.0
## Frames a flinch lasts (no moving, guarding or attacking).
@export_range(0, 300, 1, "suffix:frames") var flinch_frames: int = 20
## The flinch build-up is forgotten this many frames after the last hit.
@export_range(0, 1200, 1, "suffix:frames") var flinch_memory_frames: int = 90
## Perilous attacks can't be interrupted by a flinch once started (super armour).
@export var perilous_super_armor: bool = true

@export_group("Colours")
## Body colour while guard is up.
@export var guard_color: Color = Color(0.45, 0.6, 0.85)
@export var flinch_color: Color = Color(0.95, 0.95, 0.95)
@export var stagger_color: Color = Color(0.35, 0.55, 0.95)
@export var dead_color: Color = Color(0.12, 0.12, 0.14)
