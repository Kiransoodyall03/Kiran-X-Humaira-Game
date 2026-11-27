class_name FormConfig
extends Resource
## One sword form of the heroine (docs/COMBAT_SPEC.md "Forms"): its light combo, how she
## moves and defends in it, and its corruption rate. Frames are at 60 fps.
## Tuning files: data/forms/*.tres.

## Stable id, e.g. &"greatsword", &"katana".
@export var id: StringName = &""
@export var display_name: String = ""
## HUD colour for this form.
@export var hud_color: Color = Color.WHITE

@export_group("Attacks")
## Light combo, in order. Pressing attack again during a swing's active or recovery frames
## buffers the next step; after the last step the combo starts over.
@export var light_combo: Array[AttackData] = []
## After a swing ends with nothing buffered, an attack pressed within this many frames
## still continues the combo; later presses start again from step 1.
@export_range(0, 120, 1, "suffix:frames") var combo_window_frames: int = 24

@export_group("Movement and defence")
## Multiplies walk and sprint speed while in this form.
@export_range(0.1, 3.0, 0.05) var move_speed_multiplier: float = 1.0
## Block and parry allowed. If off, guard input is ignored.
@export var can_guard: bool = true

@export_group("Dodge")
@export var can_dodge: bool = false
## Distance covered by a dodge, in meters.
@export_range(0.0, 20.0, 0.05, "suffix:m") var dodge_distance: float = 3.5
## How long the dodge moves the heroine. The press frame is dodge frame 0.
@export_range(1, 120, 1, "suffix:frames") var dodge_duration_frames: int = 18
## First dodge frame (counted from the press frame = 0) with invulnerability.
@export_range(0, 120, 1, "suffix:frames") var dodge_iframe_start_frames: int = 2
## Number of invulnerable frames.
@export_range(0, 120, 1, "suffix:frames") var dodge_iframe_frames: int = 12
## Frames after a dodge ends before the next one is allowed.
@export_range(0, 600, 1, "suffix:frames") var dodge_cooldown_frames: int = 20

@export_group("Corruption")
## Corruption change per second while in this form: positive rises, negative drains.
## Read by the corruption meter (Corruption / CorruptionMeter; data/combat/corruption.tres).
@export_range(-100.0, 100.0, 0.1, "suffix:/s") var corruption_per_second: float = 0.0
## Multiplier on that rate while out of combat (e.g. faster drain).
@export_range(0.0, 10.0, 0.05) var corruption_out_of_combat_multiplier: float = 1.0


## Dodge speed in m/s.
func dodge_speed() -> float:
	return dodge_distance / (float(dodge_duration_frames) / 60.0)
