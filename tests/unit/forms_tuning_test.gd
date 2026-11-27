extends GdUnitTestSuite
## Checks the form tuning files (data/forms/*.tres) against the design rules in
## docs/COMBAT_SPEC.md "Forms", so live tuning can't silently swap the forms' identities.

const GREATSWORD: String = "res://data/forms/greatsword.tres"
const KATANA: String = "res://data/forms/katana.tres"
const HEROINE: String = "res://scenes/actors/heroine.tscn"
const NEW_ACTIONS: Array[StringName] = [&"attack", &"switch_form", &"dodge", &"lock_on",
		&"lock_cycle_next", &"lock_cycle_prev", &"interact", &"heal"]


func _gs() -> FormConfig:
	return load(GREATSWORD) as FormConfig


func _kt() -> FormConfig:
	return load(KATANA) as FormConfig


func _sum(form: FormConfig, field: StringName) -> float:
	var total: float = 0.0
	for a: AttackData in form.light_combo:
		total += float(a.get(field))
	return total


func _frames(form: FormConfig) -> int:
	var total: int = 0
	for a: AttackData in form.light_combo:
		total += a.total_frames()
	return total


func test_forms_load_with_three_hit_combos() -> void:
	for form: FormConfig in [_gs(), _kt()]:
		assert_object(form).is_not_null()
		assert_int(form.light_combo.size()).is_equal(3)
		for a: AttackData in form.light_combo:
			assert_object(a).is_not_null()
			assert_bool(String(a.id).begins_with(String(form.id))).is_true()


func test_greatsword_is_slow_and_heavy() -> void:
	assert_int(_frames(_gs())).is_greater(_frames(_kt()))
	assert_float(_sum(_gs(), &"posture_damage")).is_greater(_sum(_kt(), &"posture_damage") * 2.0)
	for i: int in 3:
		assert_float(_gs().light_combo[i].posture_damage).is_greater(_kt().light_combo[i].posture_damage)


func test_katana_is_fast_and_moves_faster() -> void:
	for i: int in 3:
		assert_int(_kt().light_combo[i].startup_frames).is_less(_gs().light_combo[i].startup_frames)
	assert_float(_kt().move_speed_multiplier).is_greater(_gs().move_speed_multiplier)


func test_only_the_greatsword_guards_and_only_the_katana_dodges() -> void:
	assert_bool(_gs().can_guard).is_true()
	assert_bool(_gs().can_dodge).is_false()
	assert_bool(_kt().can_guard).is_false()
	assert_bool(_kt().can_dodge).is_true()


func test_katana_iframes_fit_inside_the_dodge() -> void:
	var kt: FormConfig = _kt()
	assert_int(kt.dodge_iframe_frames).is_greater(0)
	assert_int(kt.dodge_iframe_start_frames + kt.dodge_iframe_frames).is_less_equal(kt.dodge_duration_frames)


func test_corruption_rises_in_katana_and_drains_in_greatsword() -> void:
	assert_float(_kt().corruption_per_second).is_greater(0.0)
	assert_float(_gs().corruption_per_second).is_less(0.0)


func test_heroine_scene_has_both_forms_and_a_hurtbox() -> void:
	var heroine: PlayerController = (load(HEROINE) as PackedScene).instantiate() as PlayerController
	assert_object(heroine.combat).is_not_null()
	assert_int(heroine.combat.forms.size()).is_equal(2)
	assert_str(String(heroine.combat.forms[0].id)).is_equal("greatsword")
	var hb: Hurtbox = heroine.get_node_or_null(^"Hurtbox") as Hurtbox
	assert_object(hb).is_not_null()
	assert_int(hb.collision_layer).is_equal(Hurtbox.LAYER_MASK)
	heroine.free()


func test_new_input_actions_exist() -> void:
	for action: StringName in NEW_ACTIONS:
		assert_bool(InputMap.has_action(action)).override_failure_message("missing action %s" % action).is_true()
		assert_bool(InputMap.action_get_events(action).is_empty()).is_false()
