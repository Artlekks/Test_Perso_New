extends SceneTree
## Targeted BOF-style water-camera and lateral input guardrails.
## Run with: godot --headless --path . --script res://scripts/qa/fishing_water_camera_qa.gd
const CameraRig = preload("res://scripts/camera_rig.gd")
const ScreenLateral = preload("res://scripts/fishing_screen_lateral.gd")

class SurfaceTarget extends Node3D:
	var sea_level := 0.0
	func is_free_lure_framing_active() -> bool: return true
	func get_surface_position() -> Vector3:
		return Vector3(global_position.x,sea_level,global_position.z)

var failures: Array[String] = []
var checks := 0
var viewport: SubViewport
var rig: Node3D
var player: Node3D
var bait: SurfaceTarget
var camera: Camera3D
var neutral: Transform3D

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func tick(frames := 1) -> void:
	for frame in range(frames): rig._process(1.0/60.0)

func begin() -> void:
	rig.reset_fishing_follow()
	camera.transform = neutral
	bait.global_position = camera.project_position(Vector2(350,220),8)
	bait.sea_level = bait.global_position.y
	rig.set_fishing_fight_tracking(true,bait)
	tick()
	check(rig.fishing_camera_state == rig.FishingCameraPresentationState.ANCHORED,"authored player frame anchors when already visible")

func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(640,480)
	root.add_child(viewport)
	player = Node3D.new()
	viewport.add_child(player)
	bait = SurfaceTarget.new()
	viewport.add_child(bait)
	rig = CameraRig.new()
	camera = Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	rig.target = player
	viewport.add_child(rig)
	rig.set_process(false)
	camera.current = true
	camera.position = Vector3(0,4,6)
	camera.look_at(Vector3(0,-2,0))
	neutral = camera.transform
	await process_frame

	begin()
	var original_pose := camera.global_transform
	var original_marker: Vector3 = rig._fishing_tracking_position()
	bait.global_position.y -= 0.20
	check(rig._fishing_tracking_position().is_equal_approx(original_marker),"underwater depth cannot change tracking point")
	tick(45)
	check(camera.global_transform.is_equal_approx(original_pose),"depth change alone never dips, pitches, or pans the camera")
	check(rig.fishing_rotation_failures == 0,"surface tracking cannot alter pitch or roll")

	begin()
	bait.global_position = camera.project_position(Vector2(460,220),8)
	bait.sea_level = bait.global_position.y
	var player_anchor := camera.unproject_position(player.global_position)
	tick(45)
	check(absf(rig.fight_camera_tracking.yaw)>0.001,"horizontal travel starts inside the outer yellow boundary")
	check(rig.fight_camera_tracking.inside(camera.unproject_position(bait.get_surface_position()),rig.fishing_safe_region_pixels(),0.5),"soft follow retains hard yellow frame")
	check(camera.unproject_position(player.global_position).distance_to(player_anchor)<0.05,"yaw preserves player pixel")
	check(rig._water_pan == Vector2.ZERO,"ordinary sideways steering uses yaw without moving the anchor")

	var hud := Control.new()
	hud.position = Vector2(360,300)
	hud.size = Vector2(200,75)
	viewport.add_child(hud)
	rig.fishing_hud_geometry.clear()
	rig.fishing_hud_geometry.append(hud)
	check(rig.fishing_safe_region_pixels().end.y <= 288.01,"visible power bar moves safe ceiling above its top with clearance")
	hud.hide()
	check(absf(rig.fishing_safe_region().end.y-0.70)<0.00001,"hidden bar restores authored yellow boundary")

	begin()
	var water_point := bait.get_surface_position()
	var right := ScreenLateral.right(camera,water_point,Vector3.RIGHT)
	var before := camera.unproject_position(water_point)
	var after := camera.unproject_position(water_point+right*0.03)
	check(after.x > before.x,"D always steers to screen-right")
	check(absf(after.y-before.y)<0.15,"A/D lateral contribution is horizontal on-screen")
	check(absf(right.y)<0.00001,"A/D cannot change lure depth")

	rig.return_fishing_follow_to_target(true)
	tick(600)
	check(camera.transform.is_equal_approx(neutral),"retrieve restores authored post-aim composition")
	viewport.free()
	print("FISHING WATER CAMERA QA: ",checks-failures.size(),"/",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
