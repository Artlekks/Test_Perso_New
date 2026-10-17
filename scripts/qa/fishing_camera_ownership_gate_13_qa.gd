extends SceneTree
## Gate 13: shared visibility and NEVER auto-handoff on a splashdown
## with Ryu outside the camera. Pure scene checks plus a real SubViewport.
const Rig = preload("res://scripts/camera_rig.gd")
const Handoff = preload("res://scripts/fishing_rod_handoff.gd")

class DummyLure extends Node3D:
	func is_free_lure_framing_active() -> bool:
		return true
	func get_surface_position() -> Vector3:
		return global_position

var passed := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, description: String) -> void:
	if condition:
		passed += 1
	else:
		failures.append(description)
		push_error(description)

func run() -> void:
	for size in [Vector2i(640,480), Vector2i(960,480), Vector2i(960,900)]:
		await test_splashdown_ownership(size)
	print("FISHING CAMERA OWNERSHIP GATE 13: %d/%d passed; failures=%s" % [passed, passed+failures.size(), failures])
	quit(0 if failures.is_empty() else 1)

func test_splashdown_ownership(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var player := Node3D.new()
	viewport.add_child(player)
	var notifier := VisibleOnScreenNotifier3D.new()
	player.add_child(notifier)
	var bait := DummyLure.new()
	bait.position = Vector3(0,0,-12)
	viewport.add_child(bait)
	var rig := Rig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	rig.target = player
	rig.player_screen_notifier = notifier
	viewport.add_child(rig)
	rig.set_process(false)
	rig.global_position = Vector3(0,0,-23)
	camera.position = Vector3(0,7,11)
	camera.look_at(Vector3(0,0,-23))
	camera.current = true
	await process_frame
	verify(not Handoff.is_player_view_ready(notifier,camera), "player outside water frame %s" % size)
	rig.arm_fishing_follow(bait,Vector3.FORWARD,0.0)
	rig.set_fishing_fight_tracking(true,bait)
	verify(not rig.fishing_player_camera_locked, "splashdown must not lock offscreen Ryu %s" % size)
	verify(not rig._real_player_view_engaged, "splashdown must retain inset ownership %s" % size)
	verify(rig._inset_camera_owns_framing(), "inset owns water camera until real Ryu appears %s" % size)
	verify(Handoff.is_player_projection_ready(Vector2(.20,.85)), "normal visible player permits one handoff %s" % size)
	verify(not Handoff.is_player_projection_ready(Vector2(.02,.85)), "near-edge player does not hand off %s" % size)
	# Bringing the real fisherman into view triggers exactly one handoff.
	# This is also the exact predicate consumed by FishingCharacterView.
	rig.global_position = Vector3.ZERO
	verify(Handoff.is_player_view_ready(notifier,camera), "real visible Ryu ends inset %s" % size)
	verify(not rig._inset_camera_owns_framing(), "inset stops owning framing at visible Ryu %s" % size)
	verify(rig.fishing_player_camera_locked, "real player owns camera after handoff %s" % size)
	viewport.queue_free()
	await process_frame
