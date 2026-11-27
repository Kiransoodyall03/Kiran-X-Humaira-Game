class_name LargeMonsterConfig
extends Resource
## Tuning for a large monster's AI (docs/COMBAT_SPEC.md, "Large monsters"): its attack
## table, how it reads where the target stands, movement and colours. Its whole-body
## health, posture and lives are in its CombatantConfig; each part's in its
## MonsterPartConfig. Frames are combat frames at 60 fps.

## The attack table. MonsterBrain picks among the rows valid for the target's zone and
## distance.
@export var attacks: Array[MonsterAttackEntry] = []
## With two or more attacks valid, never pick the one used last.
@export var avoid_repeat: bool = true
## Seed for the AI's random rolls. 0 = a new seed each run.
@export var rng_seed: int = 0

@export_group("Zones")
## The target is in FRONT within this angle of the monster's facing, in degrees…
@export_range(0.0, 180.0, 1.0, "suffix:°") var front_half_angle_degrees: float = 40.0
## …REAR within this angle of straight behind; SIDE otherwise.
@export_range(0.0, 180.0, 1.0, "suffix:°") var rear_half_angle_degrees: float = 60.0

@export_group("Engage")
## Engages when the target comes this close (ground plane), in meters.
@export_range(0.0, 200.0, 0.5, "suffix:m") var aggro_radius: float = 18.0
## Gives up and walks home when the target is further than this from its home point.
@export_range(0.0, 400.0, 0.5, "suffix:m") var leash_radius: float = 32.0
## Close enough to home to stop walking, in meters.
@export_range(0.05, 10.0, 0.05, "suffix:m") var home_tolerance: float = 1.0
## Below this height (global y) it has fallen out of the level and is put back at home.
@export_range(-1000.0, 0.0, 0.5, "suffix:m") var fall_reset_height: float = -10.0

@export_group("Movement")
## Walking speed when chasing or going home, in m/s.
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var walk_speed: float = 3.5
## How fast it reaches that speed, in m/s².
@export_range(0.0, 200.0, 0.5, "suffix:m/s²") var acceleration: float = 8.0
## It stops walking in when the target is this close (ground plane, from its origin).
@export_range(0.0, 30.0, 0.05, "suffix:m") var preferred_distance: float = 5.5
## Turning toward the target when not attacking. Big and slow: she can get round it.
@export_range(0.0, 1000.0, 5.0, "suffix:°/s") var turn_speed_degrees: float = 75.0
## Turning during the wind-up of attacks that track the target.
@export_range(0.0, 1000.0, 5.0, "suffix:°/s") var startup_turn_speed_degrees: float = 50.0
## Pause between attacks (rolled between these after each recovery and on engaging).
@export_range(0, 600, 1, "suffix:frames") var think_frames_min: int = 20
@export_range(0, 600, 1, "suffix:frames") var think_frames_max: int = 50

@export_group("Body")
## Radius of its body round its origin, in meters. Her deathblow reach is measured to the
## nearest of this circle and its part hurtboxes (head, limbs, tail), not to its origin.
@export_range(0.0, 20.0, 0.05, "suffix:m") var body_radius: float = 2.3
## LockOnPoint.target_size of every part: the camera pulls back for it, in meters.
@export_range(0.1, 50.0, 0.1, "suffix:m") var target_size: float = 7.5

@export_group("Colours")
@export var stagger_color: Color = Color(0.35, 0.55, 0.95)
@export var dead_color: Color = Color(0.1, 0.1, 0.12)
## Meshes of a broken part.
@export var broken_part_color: Color = Color(0.55, 0.15, 0.12)
