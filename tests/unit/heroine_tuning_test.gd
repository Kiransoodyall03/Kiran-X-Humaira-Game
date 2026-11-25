extends GdUnitTestSuite
## Checks the heroine's tuning Resources against the metrics in docs/ART_SPEC.md,
## so a live-tuning session can't silently break the greybox contract.

const MOVEMENT: String = "res://data/heroine_movement.tres"
const CAMERA: String = "res://data/heroine_camera.tres"

## docs/ART_SPEC.md metrics (meters).
const SPEC_STEP_UP: float = 0.35
const SPEC_HIGH_CLIMB: float = 2.2


func _movement() -> PlayerMovementConfig:
	return load(MOVEMENT) as PlayerMovementConfig


func _camera() -> ThirdPersonCameraConfig:
	return load(CAMERA) as ThirdPersonCameraConfig


func _full_jump_apex(cfg: PlayerMovementConfig) -> float:
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
	return cfg.jump_velocity * cfg.jump_velocity / (2.0 * g * cfg.rise_gravity_multiplier)


func test_resources_load_with_the_right_types() -> void:
	assert_object(_movement()).is_not_null()
	assert_object(_camera()).is_not_null()


func test_step_up_matches_art_spec() -> void:
	assert_float(_movement().max_step_height).is_equal_approx(SPEC_STEP_UP, 0.001)


func test_jump_cannot_clear_the_high_climb() -> void:
	# 2.2 m ledges need a ledge grab, so a plain jump must stay below them.
	assert_float(_full_jump_apex(_movement())).is_less(SPEC_HIGH_CLIMB)


func test_jump_clears_the_step_up() -> void:
	assert_float(_full_jump_apex(_movement())).is_greater(SPEC_STEP_UP)


func test_sprint_is_faster_than_walk() -> void:
	var cfg: PlayerMovementConfig = _movement()
	assert_float(cfg.sprint_speed).is_greater(cfg.walk_speed)


func test_jump_cut_shortens_the_jump() -> void:
	var cfg: PlayerMovementConfig = _movement()
	assert_float(cfg.jump_cut_multiplier).is_between(0.0, 0.99)


func test_camera_start_pitch_is_inside_its_limits() -> void:
	var cfg: ThirdPersonCameraConfig = _camera()
	assert_float(cfg.min_pitch_degrees).is_less(cfg.max_pitch_degrees)
	assert_float(cfg.start_pitch_degrees).is_between(cfg.min_pitch_degrees, cfg.max_pitch_degrees)


func test_camera_keeps_a_gap_from_walls() -> void:
	var cfg: ThirdPersonCameraConfig = _camera()
	assert_float(cfg.collision_radius).is_greater(0.0)
	assert_float(cfg.collision_radius).is_less(cfg.distance)
