extends SceneTree
## Headless smoke test for healing charges, the shrine and the shrine respawn in the
## sandbox, with the real input actions. Checks that: before any rest the sandbox still
## revives her in place (SandboxRules); heal does nothing at full health; a heal locks out
## attacks, slows her walk, lands on its apply frame and spends one charge (HUD follows);
## a heal won't start mid-swing, in the air, mid-dodge, staggered or mid-deathblow;
## a hit before it lands cancels it and keeps the charge; she can run out; the shrine shows
## a Rest prompt in range (and refuses while a living hostile is near, but not a dead one;
## no guard, jump, form switch or dodge mid-heal; no rest mid-heal or mid-swing, with the
## prompt hidden then; nor while staggered); resting refills heals,
## restores health and posture, empties corruption, sets the respawn point and respawns the
## dummy and the duelist; and dying after that respawns her at the shrine after the delay
## (refilled, enemies respawned), with SandboxRules staying out of it.
## Fails on any engine/script error, and on a frame-budget timeout instead of hanging.
## Run from the project folder:
##   godot --headless --path . --script res://tests/smoke/shrine_smoke_test.gd
## Exits 0 on pass, 1 on failure.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"
const MAX_RUN_FRAMES: int = 4000

var _failures: int = 0
var _errors: SmokeErrorCounter = SmokeErrorCounter.new()
var _frames_run: int = 0
var _finished: bool = false
var _player: PlayerController
var _player_c: Combatant
var _combat: PlayerCombat
var _healing: PlayerHealing
var _rest: PlayerRest
var _meter: CorruptionMeter
var _dummy: TrainingDummy
var _duelist: Duelist
var _shrine: Shrine
var _hud: CombatHud
var _rules: SandboxRules
var _heal_cfg: HealConfig


func _initialize() -> void:
	OS.add_logger(_errors)
	physics_frame.connect(_watchdog)
	_run.call_deferred()


func _run() -> void:
	var level: Node = (load(SANDBOX) as PackedScene).instantiate()
	root.add_child(level)
	_player = level.get_node("Heroine") as PlayerController
	_player_c = _player.combatant
	_combat = _player.combat
	_healing = _player.get_node_or_null("Healing") as PlayerHealing
	_rest = _player.get_node_or_null("Rest") as PlayerRest
	_meter = _player.get_node_or_null("CorruptionMeter") as CorruptionMeter
	_dummy = level.get_node("TrainingDummy") as TrainingDummy
	_duelist = level.get_node("Duelist") as Duelist
	_shrine = level.get_node_or_null("Shrine") as Shrine
	_hud = level.get_node("CombatHud") as CombatHud
	_rules = level.get_node("SandboxRules") as SandboxRules
	_expect(_healing != null, "the heroine has a Healing node")
	_expect(_rest != null, "the heroine has a Rest node")
	_expect(_shrine != null, "the sandbox has a Shrine")
	if _healing == null or _rest == null or _shrine == null:
		_finish()
		return
	_heal_cfg = _healing.config
	_dummy.attacking_enabled = false
	_duelist.ai_enabled = false
	await _physics_frames(10)

	await _test_sandbox_revive_before_any_rest()
	await _test_heal_refused_at_full_health()
	await _test_heal()
	await _test_heal_start_rules()
	await _test_hit_interrupts_heal()
	await _test_break_and_death_interrupt_heal_without_hit_rule()
	await _test_run_out()
	await _test_rest_at_shrine()
	await _test_die_and_respawn_at_shrine()
	_finish()


## Never rested: no respawn point, so SandboxRules revives her where she fell.
func _test_sandbox_revive_before_any_rest() -> void:
	_expect(not _rest.will_respawn(), "no respawn point before any rest")
	_expect(not _rules.player_respawns_at_shrine(), "SandboxRules handles her death before any rest")
	var spot: Vector3 = _player.global_position
	_hurt(500.0)
	_expect(_player_c.is_dead, "the big hit killed her")
	_expect(not _rest.is_respawn_pending(), "no shrine respawn pending without a rest")
	await _combat_frames(_rules.revive_delay_frames + 2)
	_expect(not _player_c.is_dead, "SandboxRules revived her")
	_expect(_flat(_player.global_position - spot).length() < 0.5, "revived where she fell")


func _test_heal_refused_at_full_health() -> void:
	_expect(is_equal_approx(_player_c.health, _player_c.config.max_health), "full health")
	_expect(_healing.charges_left() == _heal_cfg.max_charges, "%d charges to start" % _heal_cfg.max_charges)
	await _physics_frames(1)
	await _hud_refresh()
	_expect(_hud.heal_text().contains("%d/%d" % [_heal_cfg.max_charges, _heal_cfg.max_charges]), "the HUD shows full heals (%s)" % _hud.heal_text())
	await _tap(&"heal")
	_expect(not _healing.is_healing(), "heal does nothing at full health")
	_expect(_healing.charges_left() == _heal_cfg.max_charges, "no charge spent at full health")


func _test_heal() -> void:
	_place_open()
	await _physics_frames(3)
	_hurt(60.0)
	var hurt_health: float = _player_c.health
	var applied: Array[int] = [0]
	var on_applied: Callable = func(_a: float) -> void: applied[0] += 1
	_healing.heal_applied.connect(on_applied)
	var started_at: Array[int] = [-1]
	var on_started: Callable = func() -> void: started_at[0] = Combatant.current_frame()
	_healing.heal_started.connect(on_started)
	await _tap(&"heal")
	_healing.heal_started.disconnect(on_started)
	var start_frame: int = started_at[0]
	_expect(start_frame >= 0, "heal_started fired")
	_expect(_healing.is_healing(), "heal started")
	_expect(_player.is_healing(), "the controller knows she is healing")
	await _physics_frames(1)
	await _hud_refresh()
	_expect(_hud.heal_text().contains("healing"), "the HUD says healing (%s)" % _hud.heal_text())
	# Attacks are locked out and she walks slowly.
	await _tap(&"attack")
	_expect(not _combat.is_attacking(), "no attack while healing")
	Input.action_press(&"move_forward")
	await _physics_frames(12)
	var speed: float = _flat(_player.velocity).length()
	Input.action_release(&"move_forward")
	var cap: float = _player.config.walk_speed * _heal_cfg.move_speed_multiplier * _combat.current_form().move_speed_multiplier
	_expect(speed > 0.1 and speed <= cap + 0.05, "walks slowly while healing (%.2f m/s, cap %.2f)" % [speed, cap])
	_expect(is_equal_approx(_player_c.health, hurt_health), "no health back before the apply frame")
	await _combat_frames_from(start_frame, _heal_cfg.apply_frame + 1)
	_healing.heal_applied.disconnect(on_applied)
	_expect(applied[0] == 1, "the heal landed once")
	_expect(is_equal_approx(_player_c.health, hurt_health + _heal_cfg.heal_amount), "healed %.0f (%.1f -> %.1f)" % [_heal_cfg.heal_amount, hurt_health, _player_c.health])
	_expect(_healing.charges_left() == _heal_cfg.max_charges - 1, "one charge spent (%d left)" % _healing.charges_left())
	await _combat_frames_from(start_frame, _heal_cfg.use_frames + 2)
	_expect(not _healing.is_healing(), "the heal ended after its use frames")
	await _tap(&"attack")
	_expect(_combat.is_attacking(), "she can attack again after the heal")
	await _wait_idle()
	await _physics_frames(1)
	await _hud_refresh()
	_expect(_hud.heal_text().contains("%d/%d" % [_heal_cfg.max_charges - 1, _heal_cfg.max_charges]), "the HUD shows one heal used (%s)" % _hud.heal_text())


## A heal only starts when she can act, is on the floor and isn't attacking, dodging or in
## a deathblow (COMBAT_SPEC "Healing charges"): heal pressed in each case does nothing, and
## no charge is spent.
func _test_heal_start_rules() -> void:
	_place_open()
	await _physics_frames(3)
	_hurt(10.0)
	var charges: int = _healing.charges_left()
	_expect(charges > 0 and _player_c.health < _player_c.config.max_health, "hurt with a charge left before the heal-start checks")

	# Mid-swing.
	await _tap(&"attack")
	_expect(_combat.is_attacking(), "attacking before the heal press")
	await _tap(&"heal")
	_expect(_combat.is_attacking() and not _healing.is_healing(), "no heal mid-swing")
	await _wait_idle()
	_expect(not _healing.is_healing(), "no heal once the swing ended either")
	_cancel_stray_heal(charges)

	# In the air.
	await _physics_frames(2)
	await _tap(&"jump")
	await _physics_frames(3)
	_expect(not _player.is_on_floor(), "airborne before the heal press")
	await _tap(&"heal")
	_expect(not _player.is_on_floor() and not _healing.is_healing(), "no heal in the air")
	await _wait_landed()
	_expect(not _healing.is_healing(), "no heal after landing either")
	_cancel_stray_heal(charges)

	# Mid-dodge (katana form; the greatsword can't dodge).
	var start_form: FormConfig = _combat.current_form()
	await _tap(&"switch_form")
	_expect(_combat.current_form().can_dodge, "switched to a form that can dodge (%s)" % _combat.current_form().id)
	await _physics_frames(2)
	Input.action_press(&"move_right")
	await _tap(&"dodge")
	Input.action_release(&"move_right")
	_expect(_combat.is_dodging(), "dodging before the heal press")
	await _tap(&"heal")
	_expect(_combat.is_dodging() and not _healing.is_healing(), "no heal mid-dodge")
	await _wait_idle()
	_cancel_stray_heal(charges)
	await _tap(&"switch_form")
	_expect(_combat.current_form() == start_form, "back in the starting form")
	await _physics_frames(2)

	# Staggered.
	_player_c.stagger(30)
	_expect(not _player_c.can_act(), "staggered before the heal press")
	await _tap(&"heal")
	_expect(not _healing.is_healing(), "no heal while staggered")
	await _combat_frames(32)
	_cancel_stray_heal(charges)
	_expect(_player_c.can_act(), "the stagger ended")

	# Mid-deathblow: 2 m in front of the dummy, facing it, its posture broken.
	var dummy_c: Combatant = _dummy.get_combatant()
	_player.global_position = _dummy.global_position + Vector3(0.0, 0.0, 2.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.reset_physics_interpolation()
	await _physics_frames(3)
	dummy_c.take_posture_damage(dummy_c.config.posture.max_posture * 2.0)
	_expect(dummy_c.is_deathblow_available(), "the dummy is open to a deathblow")
	await _tap(&"attack")
	_expect(_combat.is_performing_deathblow(), "performing a deathblow before the heal press")
	await _tap(&"heal")
	_expect(_combat.is_performing_deathblow() and not _healing.is_healing(), "no heal mid-deathblow")
	await _wait_idle()
	_expect(not _healing.is_healing(), "no heal after the deathblow either")
	_cancel_stray_heal(charges)
	_place_open()
	await _physics_frames(3)


func _test_hit_interrupts_heal() -> void:
	_hurt(30.0)
	var before_health: float = _player_c.health
	var before_charges: int = _healing.charges_left()
	await _tap(&"heal")
	_expect(_healing.is_healing(), "second heal started")
	await _test_heal_lockouts()
	_expect(_healing.is_healing(), "still healing after the lockout checks")
	_expect(is_equal_approx(_player_c.health, before_health), "the heal hasn't landed yet")
	_hurt(5.0)
	_expect(not _healing.is_healing(), "a hit cancels the heal")
	await _combat_frames(_heal_cfg.use_frames)
	_expect(_healing.charges_left() == before_charges, "the cancelled heal kept its charge (%d)" % _healing.charges_left())
	_expect(is_equal_approx(_player_c.health, before_health - 5.0), "no health from the cancelled heal (%.1f)" % _player_c.health)


## With HealConfig.interrupted_by_hits off, plain hits leave the heal running, but a posture
## break or death still cancels it and keeps the charge.
func _test_break_and_death_interrupt_heal_without_hit_rule() -> void:
	var old_rule: bool = _heal_cfg.interrupted_by_hits
	_heal_cfg.interrupted_by_hits = false
	var charges: int = _healing.charges_left()

	_hurt(20.0)
	await _tap(&"heal")
	_expect(_healing.is_healing(), "heal started (hit rule off)")
	_hurt(1.0)
	_expect(_healing.is_healing(), "with the hit rule off a plain hit leaves the heal running")
	var health: float = _player_c.health
	_expect(_player_c.take_posture_damage(_player_c.config.posture.max_posture * 2.0), "her posture broke mid-heal")
	_expect(not _healing.is_healing(), "a posture break cancels the heal with the hit rule off")
	await _combat_frames(_heal_cfg.use_frames)
	_expect(_healing.charges_left() == charges, "the heal cancelled by a posture break kept its charge (%d)" % _healing.charges_left())
	_expect(is_equal_approx(_player_c.health, health), "no health from the heal cancelled by a posture break (%.1f)" % _player_c.health)
	_player_c.revive()
	await _physics_frames(2)

	_hurt(20.0)
	await _tap(&"heal")
	_expect(_healing.is_healing(), "heal started before dying (hit rule off)")
	_hurt(500.0)
	_expect(_player_c.is_dead, "the big hit killed her mid-heal")
	_expect(not _healing.is_healing(), "death cancels the heal with the hit rule off")
	await _combat_frames(_rules.revive_delay_frames + 2)
	_expect(not _player_c.is_dead, "SandboxRules revived her after the mid-heal death")
	_expect(_healing.charges_left() == charges, "the heal cancelled by death kept its charge (%d)" % _healing.charges_left())

	_heal_cfg.interrupted_by_hits = old_rule
	_place_open()
	await _physics_frames(3)


## Mid-heal: block, jump, switch_form and dodge all do nothing (COMBAT_SPEC "Healing
## charges"). Takes about 12 physics frames, well inside the heal's apply frame.
func _test_heal_lockouts() -> void:
	Input.action_press(&"block")
	await _physics_frames(2)
	_expect(not _player.is_guarding() and not _player_c.guard.is_held, "no guard while healing")
	Input.action_release(&"block")
	await _physics_frames(1)
	Input.action_press(&"jump")
	await _physics_frames(2)
	_expect(_player.is_on_floor() and _player.velocity.y <= 0.0, "no jump while healing (vy %.2f)" % _player.velocity.y)
	Input.action_release(&"jump")
	await _physics_frames(1)
	_expect(_player.is_on_floor() and _player.velocity.y <= 0.0, "no buffered jump while healing (vy %.2f)" % _player.velocity.y)
	var form: FormConfig = _combat.current_form()
	await _tap(&"switch_form")
	_expect(_combat.current_form() == form, "no form switch while healing")
	Input.action_press(&"move_right")
	await _tap(&"dodge")
	Input.action_release(&"move_right")
	_expect(not _combat.is_dodging(), "no dodge while healing")


func _test_run_out() -> void:
	while _healing.charges_left() > 0:
		var left: int = _healing.charges_left()
		_hurt(10.0)
		await _tap(&"heal")
		_expect(_healing.is_healing(), "heal with %d left" % left)
		await _combat_frames(_heal_cfg.use_frames + 2)
		_expect(_healing.charges_left() == left - 1, "charge spent (%d left)" % _healing.charges_left())
		if _healing.charges_left() == left:
			break # don't loop forever on a failure
	_hurt(10.0)
	var health: float = _player_c.health
	await _tap(&"heal")
	_expect(not _healing.is_healing(), "no heal with 0 charges")
	await _combat_frames(_heal_cfg.use_frames)
	_expect(is_equal_approx(_player_c.health, health), "no health with 0 charges")
	await _hud_refresh()
	_expect(_hud.heal_text().contains("0/%d" % _heal_cfg.max_charges), "the HUD shows no heals left (%s)" % _hud.heal_text())


func _test_rest_at_shrine() -> void:
	# Things the rest should undo: posture, corruption, a hurt dummy moved off its spot,
	# a hurt duelist away from home.
	_player_c.take_posture_damage(20.0)
	_meter.corruption.set_value(60.0)
	var dummy_c: Combatant = _dummy.get_combatant()
	_dummy.global_position = _dummy.home + Vector3(2.0, 0.0, 0.0)
	_dummy.reset_physics_interpolation()
	var small: AttackData = AttackData.new()
	small.damage = 30.0
	small.posture_damage = 0.0
	dummy_c.receive_attack(small)
	var duelist_c: Combatant = _duelist.get_combatant()
	duelist_c.receive_attack(small)
	_duelist.global_position = _duelist.home + Vector3(3.0, 0.0, 3.0)
	_duelist.reset_physics_interpolation()
	_expect(dummy_c.health < dummy_c.config.max_health and duelist_c.health < duelist_c.config.max_health, "both enemies are hurt before the rest")

	# Away from the shrine: no prompt, interact does nothing.
	await _tap(&"interact")
	_expect(not _shrine.prompt_visible(), "no Rest prompt away from the shrine")
	_expect(not _rest.will_respawn(), "interact away from the shrine doesn't rest")

	_place_at_shrine()
	await _physics_frames(4)
	_expect(_shrine.player_in_range(), "standing at the shrine counts as in range")
	_expect(_shrine.prompt_visible() and _shrine.prompt_text() == Shrine.PROMPT_REST, "the Rest prompt shows (%s)" % _shrine.prompt_text())

	# A living hostile nearby blocks resting.
	var dummy_spot: Vector3 = _dummy.global_position
	_dummy.global_position = _shrine.global_position + Vector3(0.0, 0.0, -4.0)
	_dummy.reset_physics_interpolation()
	await _physics_frames(2)
	_expect(_shrine.prompt_text() == Shrine.PROMPT_BLOCKED, "the prompt says enemies are near (%s)" % _shrine.prompt_text())
	await _tap(&"interact")
	_expect(not _rest.will_respawn(), "can't rest with a hostile near")
	_dummy.global_position = dummy_spot
	_dummy.reset_physics_interpolation()
	await _physics_frames(2)

	# No resting mid-heal: the prompt hides and interact does nothing. The heal spends a
	# charge; the rest below must still refill to full.
	_healing.refill()
	_hurt(20.0)
	await _tap(&"heal")
	_expect(_healing.is_healing(), "heal started at the shrine")
	await _physics_frames(1)
	_expect(not _shrine.prompt_visible(), "no Rest prompt while healing")
	await _tap(&"interact")
	_expect(not _rest.will_respawn(), "can't rest while healing")
	await _combat_frames(_heal_cfg.use_frames + 2)
	_expect(not _healing.is_healing(), "the shrine heal finished")

	# No resting mid-swing either.
	await _tap(&"attack")
	_expect(_combat.is_attacking(), "attacking at the shrine")
	_expect(not _shrine.prompt_visible(), "no Rest prompt while attacking")
	await _tap(&"interact")
	_expect(not _rest.will_respawn(), "can't rest while attacking")
	await _wait_idle()
	_place_at_shrine()
	await _physics_frames(4)

	# Nor while staggered: the prompt hides and interact does nothing.
	_expect(_shrine.prompt_visible(), "the Rest prompt is back before the stagger")
	_player_c.stagger(30)
	await _physics_frames(1)
	_expect(not _shrine.prompt_visible(), "no Rest prompt while staggered")
	_expect(not _shrine.can_rest(), "can_rest() is false while staggered")
	await _tap(&"interact")
	_expect(not _rest.will_respawn(), "can't rest while staggered")
	await _combat_frames(32)
	_expect(_player_c.can_act(), "the stagger at the shrine ended")
	await _physics_frames(2)
	_expect(_healing.charges_left() < _heal_cfg.max_charges, "a heal is spent before the rest (%d)" % _healing.charges_left())

	# A dead hostile by the shrine doesn't block it (the rest below respawns it at home).
	_dummy.global_position = _shrine.global_position + Vector3(0.0, 0.0, -4.0)
	_dummy.reset_physics_interpolation()
	_kill(dummy_c)
	_expect(dummy_c.is_dead, "the dummy by the shrine is dead")
	await _physics_frames(2)
	_expect(_shrine.prompt_visible() and _shrine.prompt_text() == Shrine.PROMPT_REST, "a dead hostile doesn't block the prompt (%s)" % _shrine.prompt_text())
	_expect(_shrine.can_rest(), "a dead hostile doesn't block resting")

	var rested: Array[int] = [0]
	_rest.rested.connect(func(_s: Node3D) -> void: rested[0] += 1)
	await _tap(&"interact")
	_expect(rested[0] == 1, "interact at the shrine rested once")
	_expect(_healing.charges_left() == _heal_cfg.max_charges, "rest refilled heals (%d)" % _healing.charges_left())
	_expect(is_equal_approx(_player_c.health, _player_c.config.max_health), "rest restored health")
	_expect(_player_c.posture.value < 0.5, "rest emptied posture (%.1f)" % _player_c.posture.value)
	_expect(is_zero_approx(_meter.value()), "rest reset corruption (%.2f)" % _meter.value())
	_expect(_rest.will_respawn() and _rest.respawn_shrine == _shrine, "the shrine is the respawn point")
	_expect(_rest.respawn_transform.origin.is_equal_approx(_shrine.spawn_transform().origin), "respawn point = the shrine's SpawnPoint")
	_expect(_rules.player_respawns_at_shrine(), "SandboxRules now leaves her death to the shrine")
	await _physics_frames(2)
	_expect(is_equal_approx(dummy_c.health, dummy_c.config.max_health) and not dummy_c.is_dead, "rest respawned the dummy (full health)")
	_expect(_flat(_dummy.global_position - _dummy.home).length() < 0.2, "the dummy is back on its spot")
	_expect(is_equal_approx(duelist_c.health, duelist_c.config.max_health), "rest respawned the duelist (full health)")
	_expect(_flat(_duelist.global_position - _duelist.home).length() < 0.3, "the duelist is back home")
	await _hud_refresh()
	_expect(_hud.heal_text().contains("%d/%d" % [_heal_cfg.max_charges, _heal_cfg.max_charges]), "the HUD shows full heals again (%s)" % _hud.heal_text())


func _test_die_and_respawn_at_shrine() -> void:
	# Spend a heal and raise corruption so the respawn's rest has something to refill.
	_place_open()
	await _physics_frames(3)
	_hurt(30.0)
	await _tap(&"heal")
	await _combat_frames(_heal_cfg.use_frames + 2)
	_expect(_healing.charges_left() == _heal_cfg.max_charges - 1, "spent a heal before dying")
	_meter.corruption.set_value(40.0)
	# Hurt both enemies and move them off home: the respawn's rest must respawn them.
	var dummy_c: Combatant = _dummy.get_combatant()
	var duelist_c: Combatant = _duelist.get_combatant()
	var small: AttackData = AttackData.new()
	small.damage = 30.0
	small.posture_damage = 0.0
	dummy_c.receive_attack(small)
	duelist_c.receive_attack(small)
	_dummy.global_position = _dummy.home + Vector3(2.0, 0.0, 0.0)
	_dummy.reset_physics_interpolation()
	_duelist.global_position = _duelist.home + Vector3(3.0, 0.0, 3.0)
	_duelist.reset_physics_interpolation()
	_expect(dummy_c.health < dummy_c.config.max_health and duelist_c.health < duelist_c.config.max_health, "both enemies are hurt before she dies")
	var fell_at: Vector3 = _player.global_position
	var respawned: Array[int] = [0]
	_rest.respawned.connect(func(_s: Node3D) -> void: respawned[0] += 1)
	_hurt(500.0)
	_expect(_player_c.is_dead, "she died")
	_expect(_rest.is_respawn_pending(), "a shrine respawn is pending")
	await _combat_frames(_rest.config.respawn_delay_frames - 10)
	_expect(_player_c.is_dead and respawned[0] == 0, "still down before the respawn delay")
	_expect(_flat(_player.global_position - fell_at).length() < 0.5, "SandboxRules didn't revive her in place")
	await _combat_frames(15)
	_expect(respawned[0] == 1, "respawned once after the delay")
	_expect(not _player_c.is_dead and is_equal_approx(_player_c.health, _player_c.config.max_health), "alive with full health")
	_expect(_flat(_player.global_position - _shrine.spawn_transform().origin).length() < 0.3, "she is at the shrine's spawn point")
	var forward: Vector3 = -_shrine.spawn_transform().basis.z
	_expect(_player.get_facing_direction().dot(_flat(forward).normalized()) > 0.95, "facing the spawn point's forward")
	_expect(_healing.charges_left() == _heal_cfg.max_charges, "respawn refilled heals")
	_expect(is_zero_approx(_meter.value()), "respawn reset corruption")
	await _physics_frames(2)
	_expect(is_equal_approx(dummy_c.health, dummy_c.config.max_health) and not dummy_c.is_dead, "respawn respawned the dummy (full health)")
	_expect(_flat(_dummy.global_position - _dummy.home).length() < 0.2, "the dummy is back on its spot after the respawn")
	_expect(is_equal_approx(duelist_c.health, duelist_c.config.max_health), "respawn respawned the duelist (full health)")
	_expect(_flat(_duelist.global_position - _duelist.home).length() < 0.3, "the duelist is back home after the respawn")
	await _physics_frames(28)
	_expect(_player.is_on_floor() and _flat(_player.global_position - _shrine.spawn_transform().origin).length() < 0.3, "she stands at the shrine")
	_expect(not _player_c.is_dead, "no extra SandboxRules revive or second death")


## Kills `c` for good: health to 0, then deathblows until no lives are left.
func _kill(c: Combatant) -> void:
	var big: AttackData = AttackData.new()
	big.id = &"smoke_shrine_kill"
	big.damage = 10000.0
	big.posture_damage = 0.0
	for i: int in 10:
		if c.is_dead:
			return
		c.receive_attack(big)
		c.receive_deathblow()


## Direct hit on her: `damage` health, no posture damage, no attacker.
func _hurt(damage: float) -> void:
	var hit: AttackData = AttackData.new()
	hit.id = &"smoke_shrine_hit"
	hit.damage = damage
	hit.posture_damage = 0.0
	var r: HitResult = _player_c.receive_attack(hit)
	_expect(r.outcome == HitResult.Outcome.HIT, "the test hit landed (%s)" % r.outcome_name())


## Open ground near the sandbox centre (far from enemies and the shrine), camera yaw 0.
func _place_open() -> void:
	_player.global_position = Vector3(0.0, 0.0, 14.0)
	_player.velocity = Vector3.ZERO
	_player.set_facing_direction(Vector3.FORWARD)
	_player.camera_rig.set_view_yaw(0.0)
	_player.reset_physics_interpolation()


func _place_at_shrine() -> void:
	_player.global_position = _shrine.spawn_transform().origin
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _wait_idle() -> void:
	for i: int in 400:
		if not _combat.is_busy():
			return
		await physics_frame
	_expect(false, "the swing finished within 400 frames")


## After a refused heal press: checks no charge was spent, then (only if the check above
## failed) cancels the stray heal and puts the charges back, so each case is independent.
func _cancel_stray_heal(charges: int) -> void:
	_expect(_healing.charges_left() == charges, "the refused heal spent no charge (%d)" % _healing.charges_left())
	if _healing.is_healing() or _healing.charges_left() != charges:
		_healing.interrupt()
		_healing.refill()
		while _healing.charges_left() > charges:
			_healing.charges.charges -= 1
		_player_c.health = minf(_player_c.health, _player_c.config.max_health - 10.0)


func _wait_landed() -> void:
	for i: int in 300:
		if _player.is_on_floor():
			return
		await physics_frame
	_expect(false, "she landed within 300 frames")


func _tap(action: StringName, hold_frames: int = 2) -> void:
	Input.action_press(action)
	await _physics_frames(hold_frames)
	Input.action_release(action)


func _physics_frames(count: int) -> void:
	for i: int in count:
		await physics_frame


## Waits `count` combat frames (physics ticks frozen by hit-stop don't count).
func _combat_frames(count: int) -> void:
	await _combat_frames_from(Combatant.current_frame(), count)


## Waits until `count` combat frames after `start`.
func _combat_frames_from(start: int, count: int) -> void:
	var target: int = start + count
	for i: int in count + 600:
		if Combatant.current_frame() >= target:
			return
		await physics_frame


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _watchdog() -> void:
	_frames_run += 1
	if _frames_run > MAX_RUN_FRAMES and not _finished:
		_expect(false, "finished within %d frames (watchdog)" % MAX_RUN_FRAMES)
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	_expect(_errors.errors == 0, "no engine/script errors (%d; first: %s)" % [_errors.errors, _errors.first_error])
	print("SHRINE SMOKE TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		printerr("  FAIL ", message)


## CombatHud refreshes its widgets in _process, and physics_frame waits don't promise a
## process frame ran after them (several physics ticks can run in one frame). Its
## `refreshed` signal fires at the end of that _process, so a read right after it sees the
## latest physics tick, with no tick (and no camera/body move) in between.
func _hud_refresh() -> void:
	await _hud.refreshed
