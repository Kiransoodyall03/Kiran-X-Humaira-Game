class_name PlayerMovementConfig
extends Resource
## Tuning values for the player's locomotion. Edit the .tres in data/ to tune live.

@export_group("Ground")
## Top speed while walking/jogging, in m/s.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var walk_speed: float = 4.5
## Top speed while holding sprint, in m/s.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var sprint_speed: float = 7.5
## How fast the player reaches target speed, in m/s².
@export_range(0.0, 200.0, 0.5, "suffix:m/s²") var acceleration: float = 30.0
## How fast the player stops when there is no input, in m/s².
@export_range(0.0, 200.0, 0.5, "suffix:m/s²") var deceleration: float = 40.0
## How fast the body turns to face its movement direction, in degrees per second.
@export_range(0.0, 2000.0, 10.0, "suffix:°/s") var turn_speed_degrees: float = 720.0
## Speed multiplier while guarding. Sprint is unavailable while guarding.
@export_range(0.0, 1.0, 0.05) var guard_speed_multiplier: float = 0.4
## Tallest ledge walked onto without jumping (docs/ART_SPEC.md "step-up"), in meters.
@export_range(0.0, 1.0, 0.01, "suffix:m") var max_step_height: float = 0.35
## How far ahead the step-up check looks for a flat landing. About the capsule radius.
@export_range(0.05, 1.0, 0.01, "suffix:m") var step_probe_distance: float = 0.35

@export_group("Air")
## Upward speed applied on jump, in m/s. Apex height ≈ v² / (2g).
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var jump_velocity: float = 5.0
## Fraction of ground acceleration available in the air (0–1).
@export_range(0.0, 1.0, 0.01) var air_control: float = 0.35
## Gravity multiplier while rising.
@export_range(0.0, 5.0, 0.05) var rise_gravity_multiplier: float = 1.0
## Gravity multiplier while falling; > 1 makes jumps feel less floaty.
@export_range(0.0, 5.0, 0.05) var fall_gravity_multiplier: float = 1.6
## Upward velocity is multiplied by this when jump is released early (variable jump height).
@export_range(0.0, 1.0, 0.01) var jump_cut_multiplier: float = 0.5
## Terminal fall speed, in m/s.
@export_range(0.0, 100.0, 0.5, "suffix:m/s") var max_fall_speed: float = 40.0
## Grace period after walking off a ledge during which jump still works, in seconds.
@export_range(0.0, 0.5, 0.01, "suffix:s") var coyote_time: float = 0.1
## A jump pressed this long before landing still fires on landing, in seconds.
@export_range(0.0, 0.5, 0.01, "suffix:s") var jump_buffer_time: float = 0.12
