extends GdUnitTestSuite
## Dodge timing (scripts/combat/dodge.gd), Combatant invulnerability (DODGED) and
## hurtbox multipliers. Frames are passed in explicitly.


func _katana() -> FormConfig:
	var f: FormConfig = FormConfig.new()
	f.can_dodge = true
	f.can_guard = false
	f.dodge_distance = 3.0
	f.dodge_duration_frames = 18
	f.dodge_iframe_start_frames = 2
	f.dodge_iframe_frames = 12
	f.dodge_cooldown_frames = 20
	return f


func _combatant() -> Combatant:
	var pc: PostureConfig = PostureConfig.new()
	pc.regen_delay_frames = 1000
	var c: CombatantConfig = CombatantConfig.new()
	c.max_health = 100.0
	c.posture = pc
	c.guard = GuardConfig.new()
	var node: Combatant = auto_free(Combatant.new()) as Combatant
	node.setup(c)
	return node


func _attack(damage: float, posture_damage: float) -> AttackData:
	var a: AttackData = AttackData.new()
	a.damage = damage
	a.posture_damage = posture_damage
	return a


func test_dodge_runs_for_its_duration() -> void:
	var d: Dodge = Dodge.new()
	assert_bool(d.start(100, _katana(), Vector3.LEFT)).is_true()
	assert_bool(d.is_dodging(100)).is_true()
	assert_bool(d.is_dodging(117)).is_true()
	assert_bool(d.is_dodging(118)).is_false()
	assert_vector(d.direction).is_equal(Vector3.LEFT)


func test_cooldown_blocks_the_next_dodge() -> void:
	var d: Dodge = Dodge.new()
	var f: FormConfig = _katana()
	d.start(100, f, Vector3.FORWARD)
	assert_bool(d.start(110, f, Vector3.FORWARD)).is_false() # still dodging
	assert_bool(d.is_ready(137)).is_false() # 118 + 20 cooldown = 138
	assert_int(d.frames_until_ready(137)).is_equal(1)
	assert_bool(d.is_ready(138)).is_true()
	assert_bool(d.start(138, f, Vector3.FORWARD)).is_true()


func test_a_form_without_dodge_cannot_dodge() -> void:
	var f: FormConfig = _katana()
	f.can_dodge = false
	assert_bool(Dodge.new().start(0, f, Vector3.FORWARD)).is_false()


func test_iframe_window_matches_the_config() -> void:
	var d: Dodge = Dodge.new()
	d.start(100, _katana(), Vector3.FORWARD)
	assert_int(d.iframe_window().x).is_equal(102)
	assert_int(d.iframe_window().y).is_equal(12)


func test_dodge_speed_covers_the_distance() -> void:
	var f: FormConfig = _katana()
	assert_float(f.dodge_speed() * float(f.dodge_duration_frames) / 60.0).is_equal_approx(f.dodge_distance, 0.0001)


func test_cancel_ends_the_dodge_and_starts_the_cooldown() -> void:
	var d: Dodge = Dodge.new()
	d.start(100, _katana(), Vector3.FORWARD)
	d.cancel(105)
	assert_bool(d.is_dodging(105)).is_false()
	assert_bool(d.is_ready(124)).is_false()
	assert_bool(d.is_ready(125)).is_true()


func test_hits_inside_the_iframes_are_dodged() -> void:
	var c: Combatant = _combatant()
	var f: FormConfig = _katana()
	c.set_invulnerable(Dodge.iframe_first(100, f), f.dodge_iframe_frames) # frames 102..113
	assert_bool(c.is_invulnerable(101)).is_false()
	assert_bool(c.is_invulnerable(102)).is_true()
	assert_bool(c.is_invulnerable(113)).is_true()
	assert_bool(c.is_invulnerable(114)).is_false()
	var r: HitResult = c.receive_attack(_attack(30.0, 40.0), null, 105)
	assert_int(r.outcome).is_equal(HitResult.Outcome.DODGED)
	assert_float(c.health).is_equal(100.0)
	assert_float(c.posture.value).is_equal(0.0)


func test_hits_outside_the_iframes_land() -> void:
	var c: Combatant = _combatant()
	c.set_invulnerable(102, 12)
	assert_int(c.receive_attack(_attack(30.0, 40.0), null, 101).outcome).is_equal(HitResult.Outcome.HIT)
	assert_int(c.receive_attack(_attack(30.0, 40.0), null, 114).outcome).is_equal(HitResult.Outcome.HIT)
	assert_float(c.health).is_equal(40.0)


func test_iframes_beat_perilous_attacks() -> void:
	var c: Combatant = _combatant()
	c.set_invulnerable(100, 10)
	for kind: AttackData.Perilous in [AttackData.Perilous.THRUST, AttackData.Perilous.SWEEP, AttackData.Perilous.GRAB]:
		var a: AttackData = _attack(30.0, 30.0)
		a.perilous = kind
		a.blockable = false
		assert_int(c.receive_attack(a, null, 105).outcome).is_equal(HitResult.Outcome.DODGED)
	assert_float(c.health).is_equal(100.0)


func test_dodged_hit_does_not_hurt_the_attacker() -> void:
	var c: Combatant = _combatant()
	var attacker: Combatant = _combatant()
	c.guard_press(100) # even with a parry window open, i-frames win
	c.set_invulnerable(100, 10)
	assert_int(c.receive_attack(_attack(30.0, 30.0), attacker, 101).outcome).is_equal(HitResult.Outcome.DODGED)
	assert_float(attacker.posture.value).is_equal(0.0)


func test_clear_and_revive_end_invulnerability() -> void:
	var c: Combatant = _combatant()
	c.set_invulnerable(100, 10)
	c.clear_invulnerability()
	assert_bool(c.is_invulnerable(105)).is_false()
	c.set_invulnerable(100, 10)
	c.revive()
	assert_bool(c.is_invulnerable(105)).is_false()


func test_receive_attack_multipliers_scale_damage_taken() -> void:
	var c: Combatant = _combatant()
	var r: HitResult = c.receive_attack(_attack(20.0, 40.0), null, 10, 1.5, 2.0)
	assert_float(r.health_damage).is_equal(30.0)
	assert_float(c.health).is_equal(70.0)
	# unguarded hits take 50% posture (GuardConfig default) × 2.0 part multiplier
	assert_float(c.posture.value).is_equal(40.0)


func test_hurtbox_routes_hits_through_its_combatant_with_multipliers() -> void:
	var c: Combatant = _combatant()
	var hb: Hurtbox = auto_free(Hurtbox.new()) as Hurtbox
	hb.combatant = c
	hb.damage_multiplier = 2.0
	hb.posture_multiplier = 0.5
	assert_int(hb.collision_layer).is_equal(Hurtbox.LAYER_MASK)
	var r: HitResult = hb.receive_hit(_attack(10.0, 40.0), null, 10)
	assert_int(r.outcome).is_equal(HitResult.Outcome.HIT)
	assert_float(c.health).is_equal(80.0)
	assert_float(c.posture.value).is_equal(10.0)


func test_hurtbox_layer_is_named_in_project_settings() -> void:
	var layer_name: String = ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % Hurtbox.LAYER, "") as String
	assert_str(layer_name).is_equal("hurtbox")


func _hurtbox(owner_c: Combatant, multiplier: float) -> Hurtbox:
	var h: Hurtbox = auto_free(Hurtbox.new()) as Hurtbox
	h.combatant = owner_c
	h.damage_multiplier = multiplier
	return h


func test_best_hurtbox_is_highest_multiplier_in_any_order() -> void:
	var c: Combatant = _combatant()
	var low: Hurtbox = _hurtbox(c, 0.5)
	var body: Hurtbox = _hurtbox(c, 1.0)
	var head: Hurtbox = _hurtbox(c, 2.0)
	var orders: Array[Array] = [[low, body, head], [head, body, low], [body, head, low], [body, low, head]]
	for order: Array in orders:
		var candidates: Array[Hurtbox] = []
		candidates.assign(order)
		var picked: Array[Hurtbox] = Hurtbox.best_per_combatant(candidates)
		assert_int(picked.size()).is_equal(1)
		assert_object(picked[0]).is_same(head)


func test_best_hurtbox_one_per_combatant() -> void:
	var a: Combatant = _combatant()
	var b: Combatant = _combatant()
	var a_body: Hurtbox = _hurtbox(a, 1.0)
	var b_body: Hurtbox = _hurtbox(b, 1.0)
	var b_head: Hurtbox = _hurtbox(b, 1.5)
	var orphan: Hurtbox = _hurtbox(null, 3.0)
	var candidates: Array[Hurtbox] = [b_body, orphan, a_body, b_head]
	var picked: Array[Hurtbox] = Hurtbox.best_per_combatant(candidates)
	assert_int(picked.size()).is_equal(2)
	assert_object(picked[0]).is_same(b_head)
	assert_object(picked[1]).is_same(a_body)
