extends GdUnitTestSuite
## PainterlyEffect parameter clamping and the push-constant block it hands the shader.


func test_tuned_effect_loads_in_range() -> void:
	var e: PainterlyEffect = load("res://data/rendering/painterly.tres") as PainterlyEffect
	assert_object(e).is_not_null()
	assert_int(e.radius).is_between(PainterlyEffect.RADIUS_MIN, PainterlyEffect.RADIUS_MAX)
	assert_float(e.strength).is_between(0.0, 1.0)
	assert_float(e.saturation).is_between(0.0, PainterlyEffect.SATURATION_MAX)


func test_radius_clamps() -> void:
	var e: PainterlyEffect = PainterlyEffect.new()
	e.radius = -4
	assert_int(e.radius).is_equal(PainterlyEffect.RADIUS_MIN)
	e.radius = 50
	assert_int(e.radius).is_equal(PainterlyEffect.RADIUS_MAX)
	e.radius = 6
	assert_int(e.radius).is_equal(6)


func test_float_params_clamp() -> void:
	var e: PainterlyEffect = PainterlyEffect.new()
	e.sharpness = 0.0
	e.hardness = 500.0
	e.strength = 1.5
	e.edge_darkening = -0.2
	e.edge_threshold = 3.0
	e.saturation = 4.0
	assert_float(e.sharpness).is_equal(PainterlyEffect.SHARPNESS_MIN)
	assert_float(e.hardness).is_equal(PainterlyEffect.HARDNESS_MAX)
	assert_float(e.strength).is_equal(1.0)
	assert_float(e.edge_darkening).is_equal(0.0)
	assert_float(e.edge_threshold).is_equal(1.0)
	assert_float(e.saturation).is_equal(PainterlyEffect.SATURATION_MAX)


func test_push_constants_layout() -> void:
	var e: PainterlyEffect = PainterlyEffect.new()
	e.radius = 4
	e.sharpness = 6.0
	e.hardness = 10.0
	e.strength = 0.5
	e.edge_darkening = 0.25
	e.edge_threshold = 0.125
	e.saturation = 1.25
	var push: PackedFloat32Array = e.build_push_constants(Vector2i(1920, 1080), 0)
	assert_int(push.to_byte_array().size() % 16).is_equal(0)
	assert_array(Array(push)).is_equal([1920.0, 1080.0, 4.0, 6.0, 10.0, 0.5, 0.25, 0.125, 1.25, 0.0, 0.0, 0.0])
	assert_float(e.build_push_constants(Vector2i(8, 8), 1)[9]).is_equal(1.0)


func test_supported_only_on_forward_plus_with_a_device() -> void:
	assert_bool(PainterlyEffect.is_supported_on("forward_plus", true)).is_true()
	assert_bool(PainterlyEffect.is_supported_on("forward_plus", false)).is_false()
	assert_bool(PainterlyEffect.is_supported_on("mobile", true)).is_false()
	assert_bool(PainterlyEffect.is_supported_on("gl_compatibility", false)).is_false()
	assert_bool(PainterlyEffect.is_supported_on("dummy", false)).is_false()


func test_support_override_forces_is_supported() -> void:
	PainterlyEffect.support_override = PainterlyEffect.SUPPORT_FORCE_ON
	assert_bool(PainterlyEffect.is_supported()).is_true()
	PainterlyEffect.support_override = PainterlyEffect.SUPPORT_FORCE_OFF
	assert_bool(PainterlyEffect.is_supported()).is_false()
	PainterlyEffect.support_override = PainterlyEffect.SUPPORT_AUTO


func test_camera_picks_compositor_only_when_enabled_and_supported() -> void:
	var comp: Compositor = Compositor.new()
	assert_object(ThirdPersonCamera.pick_compositor(comp, true, true)).is_same(comp)
	assert_object(ThirdPersonCamera.pick_compositor(comp, false, true)).is_null()
	assert_object(ThirdPersonCamera.pick_compositor(comp, true, false)).is_null()
	assert_object(ThirdPersonCamera.pick_compositor(comp, false, false)).is_null()
	assert_object(ThirdPersonCamera.pick_compositor(null, true, true)).is_null()
