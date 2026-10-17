extends SceneTree
## Regression contract: never hand off at Ryu's first edge pixel;
## quick cancel returns to THIS cast's bearing, not fishing-entry yaw;
## result fades restore the complete camera in a black frame.
const Rig = preload("res://scripts/camera_rig.gd")
const Handoff = preload("res://scripts/fishing_rod_handoff.gd")

var passes: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		failures.append(label)
		push_error(label)

func run() -> void:
	for size in [Vector2i(640, 480), Vector2i(960, 480), Vector2i(960, 900)]:
		await test_camera(size)
	print("FISHING CAMERA HANDOFF/RESET GATE 12: %d/%d passed; failures=%s" % [passes,passes+failures.size(),failures])
	quit(0 if failures.is_empty() else 1)

func test_camera(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var player := Node3D.new()
	viewport.add_child(player)
	var bait := Node3D.new()
	viewport.add_child(bait)
	var rig := Rig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	rig.target = player
	viewport.add_child(rig)
	rig.set_process(false)
	camera.position = Vector3(0, 7, 11)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await process_frame

	# First visible rod pixels are NOT sufficient: the player's whole body
	# must fit safely before inset tracking can stop.
	check(not Handoff.is_player_projection_ready(Vector2(.02,.84)),"no left-edge handoff %s" % size)
	check(not Handoff.is_player_projection_ready(Vector2(.17,.98)),"no bottom-edge handoff %s" % size)
	check(Handoff.is_player_projection_ready(Vector2(.20,.85)),"player-ready anchor %s" % size)

	# The cast starts at an AIM angle different from fishing-entry neutral.
	# Cancel without a boundary rotation must not turn back toward the beach.
	rig._fishing_neutral_yaw_valid = true
	rig._fishing_neutral_yaw = 0.0
	rig.rotation.y = .41
	rig.arm_fishing_follow(bait,Vector3.FORWARD,0.0)
	check(is_equal_approx(rig._fishing_cast_start_yaw,.41),"captures this cast bearing %s" % size)
	rig._start_aim_heading_return(.85)
	check(not rig._aim_heading_return_active,"no spurious I/reset rotation %s" % size)
	check(is_equal_approx(rig.rotation.y,.41),"reset holds cast angle %s" % size)

	# A genuine mid-cast rotation may recover, but only to the cast bearing.
	rig.rotation.y = .77
	rig._start_aim_heading_return(.85)
	check(rig._aim_heading_return_active,"real orbit allows recovery %s" % size)
	rig._update_aim_heading_return(.85)
	check(absf(rig.rotation.y-.41) < .0001,"return ends at cast bearing %s" % size)

	# Black-frame outcome: no visible parent or optical return after fade.
	var base_pose: Transform3D = camera.transform
	rig._fight_base_camera_transform = base_pose
	rig._fight_base_offsets = Vector2(camera.h_offset,camera.v_offset)
	rig._fight_base_valid = true
	rig.fishing_follow_active = true
	rig.fishing_player_camera_locked = true
	rig.global_position = Vector3(2,0,5)
	camera.position += Vector3(.7,.1,.2)
	rig.rotation.y = -.2
	rig.restore_fishing_camera_during_fade()
	check(rig.global_position.is_equal_approx(player.global_position),"fade restores parent position %s" % size)
	check(camera.transform.is_equal_approx(base_pose),"fade restores optical pose %s" % size)
	check(absf(rig.rotation.y-.41)<.0001,"fade restores cast angle %s" % size)
	check(not rig.fishing_player_camera_locked and not rig.fishing_follow_active,"fade releases tracking %s" % size)
	check(rig.is_fishing_aim_return_complete(),"no return animation after black fade %s" % size)
	viewport.queue_free()
	await process_frame
