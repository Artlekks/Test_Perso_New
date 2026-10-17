extends SceneTree
## Gate 05 was superseded: the screen-horizontal D slide was an invalid
## requirement. Re-run the full Gate 06 physical-arc/camera contract here.
## Gate 06: D is the mirrored PHYSICAL A arc; the camera—not physics—
## compensates at the depth-meter waterline. Does not access user saves.
const BaitScene = preload("res://actors/bait_V2.tscn")
const CameraRig = preload("res://scripts/camera_rig.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FISHING GATE 06 FAIL: " + label)

func down_with_positive_yaw(yaw: float) -> Vector2:
	return Vector2(0.6, 0.80 - 0.65 * yaw)

func down_with_negative_yaw(yaw: float) -> Vector2:
	return Vector2(0.6, 0.80 + 0.65 * yaw)

func on_water(camera: Camera3D, pixel: Vector2) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(pixel)
	var ray: Vector3 = camera.project_ray_normal(pixel)
	return origin + ray * (-origin.y / ray.y)

func run() -> void:
	# This is a *vertical projection feedback* test, not a free-running yaw.
	for projection in [Callable(self,"down_with_positive_yaw"), Callable(self,"down_with_negative_yaw")]:
		var yaw: float = 0.0
		var previous_y: float = (projection.call(yaw) as Vector2).y
		for frame in range(180):
			yaw = CameraRig.solve_free_d_waterline_yaw(
				yaw, projection, 0.73, 1.0 / 60.0, 18.0, 7.0
			)
			var screen_y: float = (projection.call(yaw) as Vector2).y
			check(screen_y <= previous_y + 0.000001,"camera correction never makes lower-edge violation worse, frame %d" % frame)
			previous_y = screen_y
		check(previous_y < 0.74,"camera corrects lower waterline using actual vertical response")
		check(absf(rad_to_deg(yaw)) <= 18.0001,"waterline orbit obeys Inspector maximum")
		check(absf(rad_to_deg(yaw)) > 0.1,"waterline correction is visibly nonzero")
	check(CameraRig.solve_free_d_waterline_yaw(0.0,Callable(self,"down_with_positive_yaw"),0.73,0.0,18.0,7.0)==0.0,"paused physics cannot rotate camera")
	check(CameraRig.solve_free_d_waterline_yaw(0.0,Callable(self,"down_with_positive_yaw"),0.82,1.0/60.0,18.0,7.0)==0.0,"safe lure does not trigger unnecessary yaw")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,480)
	viewport.world_3d = World3D.new()
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0,7,12)
	camera.look_at(Vector3.ZERO,Vector3.UP)
	camera.fov = 75.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	var bait: Node3D = BaitScene.instantiate()
	viewport.add_child(bait)
	bait.simulation_frozen = true
	bait.set_physics_process(false)
	bait.water_y = 0.0
	bait.state = bait.State.IN_WATER
	bait.current_service = null
	bait.shore_boundary = null
	var goal := Node3D.new()
	viewport.add_child(goal)
	await process_frame
	goal.position = on_water(camera,Vector2(335,445))
	bait.set_reel_target(goal)
	bait.position = on_water(camera,Vector2(660,350))
	var radial: Vector3 = goal.position-bait.position
	radial.y = 0.0
	radial = radial.normalized()
	var strength: float = bait.data.reel_steer_strength * bait.rod_steering_strength_multiplier
	bait.reel_steering = -1.0
	var arc_a: Vector3 = bait._free_retrieve_motion(radial,strength)
	bait.reel_steering = 1.0
	var arc_d: Vector3 = bait._free_retrieve_motion(radial,strength)
	var mirrored_a: Vector3 = radial * (2.0 * arc_a.dot(radial)) - arc_a
	check(absf(arc_a.dot(radial)-arc_d.dot(radial)) < 0.0001,"D has exactly A's radial retrieval authority")
	check(arc_d.distance_to(mirrored_a) < 0.0001,"D is A mirrored around the inward direction")
	check(arc_d.dot(radial) > 0.2,"held D retains meaningful inward speed")
	check((arc_d-radial*arc_d.dot(radial)).length() > 0.02,"held D keeps a real lateral arc")
	# Full reeling integration: the bait stays in its physical curved path;
	# a projected lower boundary is NOT allowed to replace it with a tangent.
	for height in [480,840]:
		viewport.size = Vector2i(960,height)
		camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(75.0)*0.5)*float(height)/480.0))
		await process_frame
		var reference_size := Vector2(viewport.size)
		var pixels: Vector2 = bait._free_lure_reference_ray_pixel(camera,Vector2(660.0/960.0,350.0/480.0),reference_size)
		bait.position = on_water(camera,pixels)
		goal.position = on_water(camera,bait._free_lure_reference_ray_pixel(camera,Vector2(335.0/960.0,445.0/480.0),reference_size))
		bait.reel_steering = 1.0
		bait.reel_steering_target = 1.0
		var previous_distance: float = Vector2(bait.position.x-goal.position.x,bait.position.z-goal.position.z).length()
		var moved_total: float = 0.0
		var lateral_ticks: int = 0
		for tick in range(70):
			var before: Vector3 = bait.position
			var inward: Vector3 = goal.position-before
			inward.y = 0.0
			if inward.length() < 0.35 or bait.state != bait.State.IN_WATER:
				break
			var incoming: Vector3 = inward.normalized()
			bait._update_reeling(1.0/60.0,0.45)
			var displacement: Vector3 = bait.position-before
			var distance: float = Vector2(bait.position.x-goal.position.x,bait.position.z-goal.position.z).length()
			check(distance < previous_distance-0.000001,"continuous D advances toward landing (%d, tick %d)" % [height,tick])
			previous_distance = distance
			moved_total += Vector2(displacement.x,displacement.z).length()
			if (displacement-incoming*displacement.dot(incoming)).length() > 0.00005:
				lateral_ticks += 1
		check(moved_total > 0.2,"D maintains actual cumulative physical retrieval speed at height %d" % height)
		check(lateral_ticks >= 5,"D stays curved through multiple continuous frames at height %d" % height)
	# Readable guard against accidentally reintroducing the Gate 05 slide.
	var script_source: String = (load("res://scripts/bait_V2.gd") as Script).source_code
	check(not script_source.contains("_free_d_lower_edge_slide"),"obsolete straight/screen-horizontal D substitution removed")
	print("FISHING D ARC WATERLINE GATE 05 [updated contract]: %d/%d passed; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
