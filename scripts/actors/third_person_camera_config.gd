class_name ThirdPersonCameraConfig
extends Resource
## Tuning values for the third-person orbit camera. Edit the .tres in data/ to tune live.

@export_group("Framing")
## Distance from the pivot to the camera when nothing is in the way, in meters.
@export_range(0.5, 20.0, 0.1, "suffix:m") var distance: float = 4.0
## Height of the orbit pivot above the target's origin (feet), in meters.
@export_range(0.0, 5.0, 0.05, "suffix:m") var pivot_height: float = 1.5
## Sideways offset of the pivot (over-the-shoulder), in meters. 0 = centered.
@export_range(-2.0, 2.0, 0.05, "suffix:m") var shoulder_offset: float = 0.0
## Vertical field of view, in degrees.
@export_range(30.0, 120.0, 1.0, "suffix:°") var fov: float = 70.0

@export_group("Collision")
## Radius of the sphere swept from the pivot to the camera; keeps this gap from walls, in meters.
@export_range(0.05, 1.0, 0.01, "suffix:m") var collision_radius: float = 0.2
## How fast the camera eases back out after an obstruction clears. It always snaps in at once.
@export_range(0.0, 60.0, 0.5) var return_sharpness: float = 6.0

@export_group("Look")
## Mouse look speed, in degrees per pixel of mouse motion.
@export_range(0.01, 1.0, 0.01) var mouse_sensitivity: float = 0.15
## Right-stick look speed at full deflection, in degrees per second.
@export_range(10.0, 720.0, 5.0, "suffix:°/s") var stick_sensitivity: float = 180.0
## Inverts vertical look for both mouse and stick.
@export var invert_y: bool = false
## Pitch on spawn, in degrees. Negative = camera above the pivot, looking down.
@export_range(-89.0, 89.0, 1.0, "suffix:°") var start_pitch_degrees: float = -15.0
## Lowest pitch (camera high, looking down), in degrees. Negative = above the pivot.
@export_range(-89.0, 0.0, 1.0, "suffix:°") var min_pitch_degrees: float = -70.0
## Highest pitch (camera low, looking up), in degrees.
@export_range(0.0, 89.0, 1.0, "suffix:°") var max_pitch_degrees: float = 40.0

@export_group("Follow")
## How tightly the pivot follows the target. Higher = snappier. Frame-rate independent.
@export_range(0.0, 60.0, 0.5) var follow_sharpness: float = 15.0
