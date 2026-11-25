extends GdUnitTestSuite
## Scene-runner checks on the heroine inside the sandbox. The full behaviour suite is
## still tests/smoke/player_smoke_test.gd; these prove gdUnit4's scene runner works here.

const SANDBOX: String = "res://scenes/levels/sandbox/Sandbox.tscn"


func test_heroine_scene_is_wired_up() -> void:
	var runner: GdUnitSceneRunner = scene_runner(SANDBOX)
	var player: PlayerController = runner.find_child("Heroine") as PlayerController
	assert_object(player).is_not_null()
	assert_object(player.config).is_not_null()
	assert_object(player.camera_rig).is_not_null()
	assert_object(player.camera_rig.target).is_same(player)


func test_walking_forward_moves_along_the_camera_view() -> void:
	var runner: GdUnitSceneRunner = scene_runner(SANDBOX)
	var player: PlayerController = runner.find_child("Heroine") as PlayerController
	await await_millis(300) # let her settle on the floor
	var start: Vector3 = player.global_position
	var view_forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, player.camera_rig.get_view_yaw())

	runner.simulate_action_press("move_forward")
	await await_millis(600)
	runner.simulate_action_release("move_forward")

	var moved: Vector3 = player.global_position - start
	moved.y = 0.0
	assert_float(moved.length()).is_greater(1.0)
	assert_float(moved.normalized().dot(view_forward)).is_greater(0.95)
