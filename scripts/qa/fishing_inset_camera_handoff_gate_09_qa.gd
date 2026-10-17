extends SceneTree
## Headless contract test for the two-phase BOF-style camera. Does not require
## player saves or a running fishing session.
const Rig = preload("res://scripts/camera_rig.gd")
const RodHandoff = preload("res://scripts/fishing_rod_handoff.gd")

var passes: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(works: bool, description: String) -> void:
	if works:
		passes += 1
	else:
		failures.append(description)
		push_error(description)

func run() -> void:
	await process_frame
	# The inset follow band stays within the physical camera-safe frame.
	var hard := Rect2(.18,.22,.64,.56)
	var safe := Rig.inset_follow_region(.30,.77,.58,.68,hard)
	check(safe.position.x >= hard.position.x,"inset left inside safe frame")
	check(safe.end.x <= hard.end.x,"inset right inside safe frame")
	check(safe.position.y >= hard.position.y,"inset top inside safe frame")
	check(safe.end.y <= hard.end.y,"inset bottom inside safe frame")
	check(is_equal_approx(safe.position.x,.30),"BOF inset left boundary matches red box")
	check(is_equal_approx(safe.end.x,.77),"BOF inset right boundary matches red box")
	check(is_equal_approx(safe.position.y,.58),"upper inset border follows lower-screen BOF reference")
	check(is_equal_approx(safe.end.y,.68),"lower inset border clears fishing meters")
	var phase_rig := Rig.new()
	var child_camera := Camera3D.new()
	child_camera.name = "Camera3D"
	phase_rig.add_child(child_camera)
	phase_rig.fishing_player_camera_locked = true
	check(phase_rig._inset_camera_owns_framing(),"return rail does not override offscreen inset ownership")
	phase_rig._real_player_view_engaged = true
	check(not phase_rig._inset_camera_owns_framing(),"actual rod handoff ends the inset phase permanently")
	phase_rig.free()
	for size in [Vector2(640,480),Vector2(960,480),Vector2(960,900),Vector2(320,240)]:
		check(RodHandoff.is_rod_projection_inside_frame(Vector2(8,8),size), "rod visible inside %s" % size)
		check(not RodHandoff.is_rod_projection_inside_frame(Vector2(-2,8),size),"rod outside left %s" % size)
		check(not RodHandoff.is_rod_projection_inside_frame(Vector2(8,size.y+1),size),"rod below %s" % size)
		await test_translation(size,safe)
	print("FISHING STABILIZATION INSET CAMERA GATE 09: %d/%d passed; failures=%s" % [passes,passes+failures.size(),failures])
	quit(0 if failures.is_empty() else 1)

func test_translation(size: Vector2, expected: Rect2) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size)
	root.add_child(viewport)
	var rig := Rig.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	var player := Node3D.new()
	viewport.add_child(player)
	rig.target = player
	viewport.add_child(rig)
	rig.set_process(false)
	camera.position = Vector3(0,7,11)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	rig.inset_follow_left = .30
	rig.inset_follow_right = .77
	rig.inset_follow_top = .58
	rig.inset_follow_bottom = .68
	rig.inset_follow_max_step_world = 1000.0
	# Ignore any invisible HUD: use an authored safe frame for this fixture.
	rig.fight_safe_left = .18
	rig.fight_safe_right = .82
	rig.fight_safe_top = .22
	rig.fight_safe_bottom = .78
	await process_frame
	for uv in [Vector2(.83,.68),Vector2(.17,.64),Vector2(.47,.77)]:
		var pixel := Vector2(size.x*uv.x,size.y*uv.y)
		var plane := Plane(Vector3.UP,0.0)
		var origin := camera.project_ray_origin(pixel)
		var hit: Variant = plane.intersects_ray(origin,camera.project_ray_normal(pixel))
		check(hit != null,"water ray intersection %s %s" % [size,uv])
		if hit == null:
			continue
		var bait: Vector3 = hit
		var camera_basis: Basis = camera.global_basis
		rig._pan_inset_camera_to_lure(camera,bait,size)
		var corrected: Vector2 = camera.unproject_position(bait)/size
		check(corrected.x >= expected.position.x - .008 and corrected.x <= expected.end.x + .008,"lure horizontal band %s %s" % [size,uv])
		check(corrected.y >= expected.position.y - .008 and corrected.y <= expected.end.y + .008,"lure vertical band %s %s" % [size,uv])
		check(camera.global_basis.is_equal_approx(camera_basis),"camera translates without rotating %s %s" % [size,uv])
	viewport.queue_free()
	await process_frame
