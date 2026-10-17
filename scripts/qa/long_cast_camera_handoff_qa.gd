extends SceneTree
## Long-cast camera lifecycle regression. Run ONLY through the isolated QA
## launcher: --script res://scripts/qa/long_cast_camera_handoff_qa.gd
const CameraRig = preload("res://scripts/camera_rig.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

class FreeLure extends Node3D:
	var sea_level: float = 0.0
	func is_free_lure_framing_active() -> bool: return true
	func get_surface_position() -> Vector3:
		return Vector3(global_position.x, sea_level, global_position.z)

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	for dimensions in [Vector2i(640, 480), Vector2i(960, 480)]:
		await exercise(dimensions)
		await exercise_home_fishing_hud_clearance(dimensions)
	Isolation.emit_result("long_cast_camera_handoff_qa", checks - failures.size(), checks, failures.size(), 0)
	quit(0 if failures.is_empty() else 1)

func exercise(dimensions: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	root.add_child(viewport)
	var player := Node3D.new()
	viewport.add_child(player)
	var lure := FreeLure.new()
	viewport.add_child(lure)
	var rig := CameraRig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	rig.target = player
	viewport.add_child(rig)
	rig.set_process(false)
	camera.current = true
	camera.position = Vector3(0, 4, 6)
	camera.look_at(Vector3(0, -2, 0))
	await process_frame
	var home := rig.global_position
	var authored := camera.transform
	var player_pixel := camera.unproject_position(player.global_position)

	# Short casts never activate the translation rail.
	lure.global_position = camera.project_position(Vector2(dimensions) * 0.5, 8.0)
	rig.arm_fishing_follow(lure, Vector3.FORWARD, -100.0)
	check(rig.fishing_follow_armed and not rig.fishing_player_camera_locked, "flight arming enables follow")
	for frame in range(4):
		rig._process(1.0 / 60.0)
	check(rig.global_position.is_equal_approx(home), "short cast holds player camera")
	check(camera.transform.is_equal_approx(authored), "short cast preserves local camera pose")
	rig.reset_fishing_follow()

	# A real distant flight (not manually setting 'active') must cross the
	# screen-space trigger, move the rig, and eventually hide Ryu.
	var start := camera.project_position(Vector2(dimensions) * 0.5, 8.0)
	var edge := camera.project_position(Vector2(float(dimensions.x) * 0.86, float(dimensions.y) * 0.15), 8.0)
	lure.global_position = start
	var heading := edge - start
	heading.y = 0.0
	rig.arm_fishing_follow(lure, heading, -100.0)
	lure.global_position = edge
	rig._process(1.0 / 60.0)
	check(rig.fishing_follow_active, "real upper/right edge activates follow")
	var physical_lure := lure.global_position
	var heading_flat := heading.normalized()
	lure.global_position += heading_flat * 8.0
	for frame in range(4):
		rig._process(1.0 / 60.0)
	check(rig.global_position.distance_to(home) > 0.1, "long flight translates camera toward lure")
	check(camera.transform.is_equal_approx(authored), "flight follows without changing pitch, distance or lens")
	check(lure.global_position.distance_to(physical_lure + heading_flat * 8.0) < 0.00001, "camera follow does not alter lure physics")
	var at_contact := camera.global_transform
	lure.sea_level = lure.global_position.y
	rig.notify_fishing_target_landed()
	rig.set_fishing_fight_tracking(true, lure)
	check(camera.global_transform.is_equal_approx(at_contact), "water handoff has zero-position snap")
	check(rig._fight_tracking_active, "water view owns tracking after flight")
	check(rig.fishing_player_anchor.distance_to(player_pixel / Vector2(dimensions)) < 0.001, "water return retains the authored player anchor")

	# A long cast must come home monotonically as the lure is retrieved.
	var previous_distance := rig.global_position.distance_to(home)
	var initial_distance := previous_distance
	for frame in range(60):
		lure.global_position = lure.global_position.lerp(player.global_position, 0.075)
		rig._process(1.0 / 60.0)
		var remaining := rig.global_position.distance_to(home)
		check(remaining <= previous_distance + 0.001, "retrieve never sends camera away from player")
		previous_distance = remaining
	check(previous_distance < initial_distance, "reeling advances the water camera home")
	check(rig.fishing_rotation_failures == 0,
		"real long-cast water camera keeps yaw-only orientation without false pitch/roll errors")
	viewport.queue_free()
	await process_frame


func exercise_home_fishing_hud_clearance(dimensions: Vector2i) -> void:
	# The real player clears the fixed power bar. An animated CharacterView
	# must never move the camera home position between identical casts.
	var viewport := SubViewport.new()
	viewport.size = dimensions
	root.add_child(viewport)
	var player := Node3D.new()
	viewport.add_child(player)
	var rig := CameraRig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	rig.target = player
	viewport.add_child(rig)
	rig.set_process(false)
	camera.current = true
	var hud := CanvasLayer.new()
	viewport.add_child(hud)
	var inset := Control.new()
	inset.name = "CharacterView"
	inset.position = Vector2(102, 231)
	hud.add_child(inset)
	var meter := CanvasLayer.new()
	meter.name = "PowerMeter"
	hud.add_child(meter)
	var meter_root := Control.new()
	meter_root.name = "Root"
	meter.add_child(meter_root)
	var bar := Sprite2D.new()
	bar.name = "PowerBarBG"
	bar.centered = false
	var pixels := Image.create(220, 40, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	bar.texture = ImageTexture.create_from_image(pixels)
	bar.position = Vector2(175, 410)
	meter_root.add_child(bar)
	rig.set_fishing_hud_geometry(meter, null)
	await process_frame
	# Native authored FishingCameraPose. Only the h_offset should adjust;
	# focal length, pitch, translation rail and gauge placement cannot change.
	var pose := Transform3D(
		Basis(Vector3(-0.1374445, 0.0, -0.99050945),
			Vector3(-0.90487546, 0.4067366, 0.1255618),
			Vector3(0.40287647, 0.9135455, -0.05590371)),
		Vector3(0.35, 1.38, -0.3))
	var original_bar_position := bar.global_position
	var base_h := rig.fishing_h_offset
	var corrected_h := rig._home_fishing_h_offset_for_fixed_hud(camera, pose, 0.0)
	check(corrected_h >= base_h and corrected_h <= base_h + rig.fishing_home_extra_offset_limit,
		"entry-only HUD clearance offset is bounded")
	# Regression: the inset can be hidden, visible, or partially slid in from
	# beyond the left edge when fishing is entered. All must yield one camera.
	inset.visible = true
	inset.position.x = -118.0
	var sliding_h := rig._home_fishing_h_offset_for_fixed_hud(camera, pose, 0.0)
	inset.position.x = 150.0
	var visible_h := rig._home_fishing_h_offset_for_fixed_hud(camera, pose, 0.0)
	check(is_equal_approx(corrected_h, sliding_h) and is_equal_approx(corrected_h, visible_h),
		"fishing entry camera is independent of CharacterView slide and visibility")
	for heading in [PI * 0.5, PI, -PI * 0.5]:
		check(is_equal_approx(corrected_h,
			rig._home_fishing_h_offset_for_fixed_hud(camera, pose, heading)),
			"fishing entry clearance is identical at heading %.3f" % heading)
	camera.transform = pose
	camera.h_offset = corrected_h
	camera.v_offset = rig.fishing_v_offset
	var player_x := camera.unproject_position(player.global_position).x
	var allowed_x := bar.global_position.x - rig.fishing_player_body_right_pixels - rig.fishing_player_to_bar_gap_pixels
	check(player_x <= allowed_x + 1.5,
		"home fisherman returns to inset, clear of stationary power bar at %s" % dimensions)
	check(bar.global_position == original_bar_position,
		"home composition changes camera, never meter position")
	check(rig.fishing_h_offset == base_h,
		"art-authored baseline remains unchanged for later camera transitions")
	viewport.queue_free()
	await process_frame
