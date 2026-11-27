extends GdUnitTestSuite
## Healing charges (scripts/combat/heal_charges.gd): spending charges on the apply frame,
## running out, interrupting before/after the heal lands, refill, the full-health rule;
## Combatant.heal()/restore(); the shipped tuning in data/combat/heals.tres and
## data/world/shrine.tres against docs/COMBAT_SPEC.md; and the heroine/shrine scenes wiring.
## Frames are passed in explicitly (60 fps).

const HEALS: String = "res://data/combat/heals.tres"
const REST: String = "res://data/world/shrine.tres"
const HEROINE: String = "res://scenes/actors/heroine.tscn"
const SHRINE: String = "res://scenes/world/shrine.tscn"


func _config(charges: int = 3, amount: float = 40.0, use: int = 54, apply: int = 30) -> HealConfig:
	var c: HealConfig = HealConfig.new()
	c.max_charges = charges
	c.heal_amount = amount
	c.use_frames = use
	c.apply_frame = apply
	c.allow_at_full_health = false
	return c


## Runs `frames` single-frame steps, returning the total health restored.
func _run(h: HealCharges, frames: int) -> float:
	var total: float = 0.0
	for i: int in frames:
		total += h.step(1)
	return total


func _combatant(max_health: float = 100.0) -> Combatant:
	var pc: PostureConfig = PostureConfig.new()
	pc.max_posture = 100.0
	pc.break_stagger_frames = 60
	var cc: CombatantConfig = CombatantConfig.new()
	cc.max_health = max_health
	cc.posture = pc
	cc.guard = GuardConfig.new()
	var c: Combatant = auto_free(Combatant.new()) as Combatant
	c.setup(cc)
	return c


func test_starts_full() -> void:
	var h: HealCharges = HealCharges.new(_config(3))
	assert_int(h.charges).is_equal(3)
	assert_int(h.max_charges()).is_equal(3)
	assert_bool(h.is_active()).is_false()


func test_heal_lands_on_the_apply_frame_and_spends_one_charge() -> void:
	var h: HealCharges = HealCharges.new(_config(3, 40.0, 54, 30))
	assert_bool(h.start(0.5)).is_true()
	assert_float(_run(h, 29)).is_equal(0.0)
	assert_int(h.charges).is_equal(3) # nothing spent before it lands
	assert_float(h.step(1)).is_equal(40.0)
	assert_int(h.charges).is_equal(2)
	assert_bool(h.has_applied()).is_true()
	assert_bool(h.is_active()).is_true() # recovery frames still run
	assert_float(_run(h, 23)).is_equal(0.0)
	assert_bool(h.is_active()).is_true()
	h.step(1)
	assert_bool(h.is_active()).is_false() # done after use_frames


func test_running_out() -> void:
	var h: HealCharges = HealCharges.new(_config(2, 10.0, 10, 5))
	var healed: float = 0.0
	for i: int in 2:
		assert_bool(h.start(0.1)).is_true()
		healed += _run(h, 10)
	assert_float(healed).is_equal(20.0)
	assert_int(h.charges).is_equal(0)
	assert_bool(h.can_start(0.1)).is_false()
	assert_bool(h.start(0.1)).is_false()
	assert_float(_run(h, 20)).is_equal(0.0)


func test_cant_start_twice_or_at_full_health() -> void:
	var h: HealCharges = HealCharges.new(_config())
	assert_bool(h.start(1.0)).is_false() # full health: refused
	var cfg: HealConfig = _config()
	cfg.allow_at_full_health = true
	assert_bool(HealCharges.new(cfg).start(1.0)).is_true()
	assert_bool(h.start(0.5)).is_true()
	assert_bool(h.start(0.5)).is_false() # already healing


func test_interrupt_before_landing_keeps_the_charge() -> void:
	var h: HealCharges = HealCharges.new(_config(3, 40.0, 54, 30))
	var spent: Array[bool] = []
	h.interrupted.connect(func(s: bool) -> void: spent.append(s))
	h.start(0.5)
	_run(h, 10)
	assert_bool(h.interrupt()).is_true()
	assert_bool(h.is_active()).is_false()
	assert_int(h.charges).is_equal(3)
	assert_array(spent).is_equal([false])
	assert_float(_run(h, 60)).is_equal(0.0) # nothing lands later
	assert_bool(h.interrupt()).is_false() # nothing to interrupt


func test_interrupt_after_landing_keeps_the_heal() -> void:
	var h: HealCharges = HealCharges.new(_config(3, 40.0, 54, 30))
	var spent: Array[bool] = []
	h.interrupted.connect(func(s: bool) -> void: spent.append(s))
	h.start(0.5)
	assert_float(_run(h, 35)).is_equal(40.0)
	h.interrupt()
	assert_int(h.charges).is_equal(2)
	assert_array(spent).is_equal([true])


func test_refill() -> void:
	var h: HealCharges = HealCharges.new(_config(3, 10.0, 4, 2))
	var changes: Array[int] = []
	h.charges_changed.connect(func(c: int, _m: int) -> void: changes.append(c))
	for i: int in 3:
		h.start(0.1)
		_run(h, 4)
	assert_int(h.charges).is_equal(0)
	h.refill()
	assert_int(h.charges).is_equal(3)
	assert_array(changes).is_equal([2, 1, 0, 3])
	h.refill() # already full: no signal
	assert_array(changes).is_equal([2, 1, 0, 3])
	h.set_charges(99)
	assert_int(h.charges).is_equal(3)


func test_combatant_heal_clamps_and_skips_the_dead() -> void:
	var c: Combatant = _combatant(100.0)
	var hit: AttackData = AttackData.new()
	hit.damage = 70.0
	c.receive_attack(hit, null, 0)
	assert_float(c.health).is_equal(30.0)
	assert_float(c.heal(40.0)).is_equal(40.0)
	assert_float(c.heal(40.0)).is_equal(30.0) # clamped to max
	assert_float(c.health).is_equal(100.0)
	hit.damage = 500.0
	c.receive_attack(hit, null, 10)
	assert_bool(c.is_dead).is_true()
	assert_float(c.heal(40.0)).is_equal(0.0)
	assert_float(c.health).is_equal(0.0)


func test_combatant_restore() -> void:
	var c: Combatant = _combatant(100.0)
	var hit: AttackData = AttackData.new()
	hit.damage = 50.0
	hit.posture_damage = 200.0 # breaks posture: staggered
	c.receive_attack(hit, null, 0)
	assert_bool(c.is_staggered()).is_true()
	var revived: Array[int] = [0]
	c.revived.connect(func() -> void: revived[0] += 1)
	c.restore()
	assert_float(c.health).is_equal(100.0)
	assert_float(c.posture.value).is_equal(0.0)
	assert_bool(c.is_staggered()).is_false()
	assert_bool(c.can_act()).is_true()
	assert_int(revived[0]).is_equal(0) # living: no revived signal
	hit.damage = 500.0
	hit.posture_damage = 0.0
	c.receive_attack(hit, null, 10)
	assert_bool(c.is_dead).is_true()
	c.restore()
	assert_bool(c.is_dead).is_false()
	assert_int(revived[0]).is_equal(1)


func test_shipped_tuning_matches_the_spec() -> void:
	var heal: HealConfig = load(HEALS) as HealConfig
	assert_object(heal).is_not_null()
	assert_int(heal.max_charges).is_equal(3)
	assert_float(heal.heal_amount).is_equal(40.0)
	assert_int(heal.use_frames).is_equal(54)
	assert_int(heal.apply_frame).is_equal(30)
	assert_bool(heal.apply_frame <= heal.use_frames).is_true()
	assert_float(heal.move_speed_multiplier).is_equal(0.35)
	assert_bool(heal.interrupted_by_hits).is_true()
	assert_bool(heal.allow_at_full_health).is_false()
	var rest: RestConfig = load(REST) as RestConfig
	assert_object(rest).is_not_null()
	assert_int(rest.respawn_delay_frames).is_equal(150)
	assert_bool(rest.respawn_rests).is_true()
	assert_float(rest.hostile_block_radius).is_equal(8.0)


func test_heroine_has_healing_and_rest() -> void:
	var heroine: PlayerController = auto_free((load(HEROINE) as PackedScene).instantiate()) as PlayerController
	var healing: PlayerHealing = heroine.get_node_or_null(^"Healing") as PlayerHealing
	var rest: PlayerRest = heroine.get_node_or_null(^"Rest") as PlayerRest
	assert_object(healing).is_not_null()
	assert_object(rest).is_not_null()
	assert_object(healing.config).is_same(load(HEALS))
	assert_object(rest.config).is_same(load(REST))
	assert_object(heroine.healing).is_same(healing)


func test_shrine_scene_is_wired_up() -> void:
	var shrine: Shrine = auto_free((load(SHRINE) as PackedScene).instantiate()) as Shrine
	assert_object(shrine).is_not_null()
	assert_object(shrine.config).is_same(load(REST))
	var area: Area3D = shrine.get_node_or_null(^"InteractArea") as Area3D
	assert_object(area).is_not_null()
	assert_int(area.collision_mask).is_equal(2) # the player layer
	assert_object(shrine.get_node_or_null(^"SpawnPoint") as Marker3D).is_not_null()
	assert_object(shrine.get_node_or_null(^"Prompt/Label") as Label).is_not_null()
