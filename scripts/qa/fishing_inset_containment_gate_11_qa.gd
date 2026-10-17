extends SceneTree
## Camera-only regression: inset remains in the red frame, casts transition
## without an optical jump, and the return rail cannot overtake the inset.
const Rig = preload("res://scripts/camera_rig.gd")

var passed: int = 0
var failed: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(result: bool, label: String) -> void:
	if result:
		passed += 1
	else:
		failed.append(label)
		push_error(label)

func run() -> void:
	await process_frame
	var hard := Rect2(.32,.53,.38,.15)
	var comfort: Rect2 = Rig.inset_comfort_region(hard,.025)
	check(comfort.position.x > hard.position.x, "preemptive left inside hard inset")
	check(comfort.end.x < hard.end.x, "preemptive right inside hard inset")
	check(comfort.position.y > hard.position.y, "preemptive top inside hard inset")
	check(comfort.end.y < hard.end.y, "preemptive bottom inside hard inset")
	for size in [Vector2i(640,480), Vector2i(960,480), Vector2i(960,900), Vector2i(320,240)]:
		await test_camera(size)
	print("FISHING INSET CAMERA GATE 11: %d/%d passed; failures=%s" % [passed,passed+failed.size(),failed])
	quit(0 if failed.is_empty() else 1)

func test_camera(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	var rig := Rig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	var player := Node3D.new()
	player.position = Vector3(100,0,100) # Offscreen: CharacterView owns framing.
	viewport.add_child(player)
	rig.target = player
	viewport.add_child(rig)
	rig.set_process(false)
	camera.position = Vector3(0,7,11)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	rig.fight_safe_left = .18
	rig.fight_safe_right = .82
	rig.fight_safe_top = .22
	rig.fight_safe_bottom = .78
	await process_frame
	var size_f: Vector2 = Vector2(size)
	var actual_hard: Rect2 = Rig.inset_follow_region(
		rig.inset_follow_left,rig.inset_follow_right,
		rig.inset_follow_top,rig.inset_follow_bottom,rig.fishing_safe_region())
	# The old Gate 11 accidentally hardcoded .32/.70/.53/.68 even though the
	# actual scene exposes different inspector-configurable edges. Assert the
	# user's authored values, not a stale estimate of their screenshot.
	check(is_equal_approx(actual_hard.position.x,rig.inset_follow_left), "authored red left in %s" % size)
	check(is_equal_approx(actual_hard.end.x,rig.inset_follow_right), "authored red right in %s" % size)
	check(is_equal_approx(actual_hard.position.y,rig.inset_follow_top), "authored red top in %s" % size)
	check(is_equal_approx(actual_hard.end.y,rig.inset_follow_bottom), "authored red bottom in %s" % size)
	# Flight pan shifts the parent rig and retains the camera's authored local
	# pose; this is what makes a splashdown camera snapshot continuous.
	rig.fishing_follow_active = true
	for uv in [Vector2(.10,.60),Vector2(.92,.65),Vector2(.47,.81),Vector2(.51,.49)]:
		var pixel: Vector2 = uv*size_f
		var plane := Plane(Vector3.UP,0.0)
		var hit: Variant = plane.intersects_ray(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))
		check(hit != null, "surface test ray %s %s" % [size,uv])
		if hit == null:
			continue
		var lure: Vector3 = hit
		var before_local: Transform3D = camera.transform
		var before_parent: Vector3 = rig.global_position
		rig._pan_inset_camera_to_lure(camera,lure,size_f,1.0/60.0)
		var corrected: Vector2 = camera.unproject_position(lure)/size_f
		check(actual_hard.has_point(corrected), "airborne hard red containment %s %s -> %s" % [size,uv,corrected])
		check(camera.transform.is_equal_approx(before_local), "airborne local lens unchanged %s %s" % [size,uv])
		check(rig.global_position.distance_to(before_parent)>0.00001, "airborne parent pan %s %s" % [size,uv])
	# Water contact must preserve the already panned camera pose.
	var landing_pose: Transform3D = camera.global_transform
	rig._fight_base_valid = true
	rig._fight_base_camera_transform = camera.transform
	rig._fight_base_offsets = Vector2(camera.h_offset,camera.v_offset)
	rig.fishing_follow_active = false
	var water_pose: Transform3D = rig._water_base(Vector2.ZERO)
	check(water_pose.is_equal_approx(landing_pose), "continuous flight/water frame %s" % size)
	# The water camera cannot reenter the parent-return rail until the real
	# rod is visible, even when lure distance advances while the user is idle.
	rig._real_player_view_engaged = false
	rig.fishing_player_return_active = true
	rig.fishing_player_return_start_camera_position = rig.global_position
	rig.fishing_player_return_start_distance = 15.0
	var parent_before: Vector3 = rig.global_position
	rig._update_fishing_player_return(Vector3.ZERO)
	check(rig.global_position.is_equal_approx(parent_before), "inset holds parent return %s" % size)
	check(is_zero_approx(rig.fishing_player_return_progress), "inset return progress held %s" % size)
	# With real Ryu visible, return travel is allowed only along the lure's
	# remaining distance-driven recovery; the view must not jump or snap home.
	rig.fishing_player_return_active = false
	rig.fishing_player_camera_locked = false
	rig.begin_fishing_player_return()
	check(rig.fishing_player_camera_locked, "real rod latches the camera %s" % size)
	check(rig.fishing_player_return_active, "real-character handoff enables remaining-distance return rail %s" % size)
	check(rig.global_position.is_equal_approx(parent_before), "real view preserves world camera %s" % size)
	# Completion unwinds any remaining pan/yaw to the captured cast pose.
	rig._fight_tracking_active = true
	var before_recovery: Vector3 = rig.global_position
	rig.return_fishing_follow_to_target(true)
	check(rig.global_position.is_equal_approx(before_recovery), "no camera jump at bait disappearance %s" % size)
	rig._update_retrieve_yaw(rig.completed_reel_camera_return_seconds*0.5)
	check(rig.global_position.distance_to(player.global_position) < before_recovery.distance_to(player.global_position), "return progresses smoothly %s" % size)
	rig._update_retrieve_yaw(rig.completed_reel_camera_return_seconds*0.5)
	check(rig.global_position.is_equal_approx(player.global_position), "returns exactly home %s" % size)
	viewport.queue_free()
	await process_frame
