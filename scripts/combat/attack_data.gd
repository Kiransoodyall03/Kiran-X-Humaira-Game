class_name AttackData
extends Resource
## One row of an attack table (docs/COMBAT_SPEC.md). Frames are at 60 fps.

## Perilous attacks cannot be handled the normal way (Sekiro-style).
## THRUST: cannot be blocked, can be parried. SWEEP: jump over it. GRAB: dodge it.
enum Perilous { NONE, THRUST, SWEEP, GRAB }

## Stable id used in logs and playtest death counts, e.g. &"dummy_overhead".
@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Frames")
## Wind-up before the hit can land. This is the telegraph the player reads.
@export_range(0, 300, 1, "suffix:frames") var startup_frames: int = 30
## Frames during which the hit can land.
@export_range(1, 60, 1, "suffix:frames") var active_frames: int = 4
## Frames after the hit before the attacker can act again (the punish window).
@export_range(0, 300, 1, "suffix:frames") var recovery_frames: int = 30

@export_group("Damage")
@export_range(0.0, 1000.0, 0.5) var damage: float = 20.0
@export_range(0.0, 1000.0, 0.5) var posture_damage: float = 25.0
## How far in front of the attacker the hit reaches, in meters.
@export_range(0.0, 20.0, 0.05, "suffix:m") var reach: float = 2.5

@export_group("Hitbox")
## Width of the box swept in front of the attacker (player attacks), in meters.
@export_range(0.1, 20.0, 0.05, "suffix:m") var hit_width: float = 1.5
## Height of that box, from the attacker's feet, in meters.
@export_range(0.1, 20.0, 0.05, "suffix:m") var hit_height: float = 1.8
## Distance the attacker steps forward over startup + active frames, in meters.
@export_range(0.0, 10.0, 0.05, "suffix:m") var lunge_distance: float = 0.0

@export_group("Defence")
@export var blockable: bool = true
@export var deflectable: bool = true
@export var perilous: Perilous = Perilous.NONE
## The hit misses a target that is off the ground (sweeps).
@export var misses_airborne: bool = false

@export_group("Tell")
## Colour the attacker flashes during startup. Each perilous type gets its own colour.
@export var tell_color: Color = Color(1.0, 0.75, 0.3)


func total_frames() -> int:
	return startup_frames + active_frames + recovery_frames
