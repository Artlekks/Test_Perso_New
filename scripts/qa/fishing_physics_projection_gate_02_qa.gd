extends SceneTree
## Isolated production bait + Camera3D check, no save or fishing progression.
## Dynamic floating-window FOV is allowed; bait physics still uses the same
## reference projector and retrieves toward its physical water-side target.
const BAIT_SCENE = preload("res://actors/bait_V2.tscn")
var checks: int = 0
var failures: Array[String] = []
var surface: SubViewport
var camera: Camera3D
var bait: Node3D
var goal: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("PHYSICS PROJECTION FAIL: " + label)

func on_water(pixel: Vector2) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(pixel)
	var direction: Vector3 = camera.project_ray_normal(pixel)
	return origin+direction*(-origin.y/direction.y)

func run() -> void:
	surface = SubViewport.new()
	surface.size = Vector2i(960,480)
	surface.world_3d = World3D.new()
	root.add_child(surface)
	camera = Camera3D.new()
	surface.add_child(camera)
	camera.position = Vector3(0.0,7.0,12.0)
	camera.look_at(Vector3.ZERO,Vector3.UP)
	camera.current = true
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 75.0
	camera.set_meta("desktop_base_projection", {"fov":75.0,"aspect":Camera3D.KEEP_HEIGHT})
	bait = BAIT_SCENE.instantiate()
	surface.add_child(bait)
	bait.set_physics_process(false)
	bait.simulation_frozen = true
	bait.water_y = 0.0
	bait.state = bait.State.IN_WATER
	goal = Node3D.new()
	surface.add_child(goal)
	goal.global_position = on_water(Vector2(350,446))
	bait.set_reel_target(goal)
	bait.global_position = on_water(Vector2(650,345))
	await process_frame
	var reference_points: Array[Vector3] = [on_water(Vector2(250,140)),on_water(Vector2(650,345)),on_water(Vector2(450,250))]
	var before: Array[Vector2] = []
	for point in reference_points:
		before.append(bait._free_lure_screen_point(camera,point,Vector2(surface.size)))
	var authored_region: Rect2 = bait._free_lure_screen_region()
	# Deliberately poisonous HUD provider. Physical corridor must ignore it.
	bait.free_lure_region_provider = func() -> Rect2: return Rect2(0.49,0.49,0.01,0.01)
	check(bait._free_lure_screen_region() == authored_region,"live HUD position cannot shrink physical playfield")
	for height in [560,720,960,1200]:
		surface.size = Vector2i(960,height)
		camera.fov = rad_to_deg(2.0*atan(tan(deg_to_rad(75.0)*0.5)*float(height)/480.0))
		await process_frame
		for i in range(reference_points.size()):
			var current: Vector2 = bait._free_lure_screen_point(camera,reference_points[i],Vector2(surface.size))
			check(current.distance_to(before[i]) < 0.0006,"world-to-physics projection stays fixed at %s, sample %d" % [height,i])
		# The display camera may shift its optical origin to keep the player
		# at the bottom in tall windows. Physics must ignore that shift too.
		var reference_y: float = camera.unproject_position(reference_points[1]).y
		camera.v_offset = 0.1
		var slope: float = (camera.unproject_position(reference_points[1]).y-reference_y)/0.1
		camera.v_offset = 0.0
		if slope > 0.0001:
			var present_offset: float = (float(height)-480.0)*0.5/slope
			camera.v_offset = present_offset
			camera.set_meta("desktop_vertical_presentation_offset",present_offset)
			for i in range(reference_points.size()):
				var shifted: Vector2 = bait._free_lure_screen_point(camera,reference_points[i],Vector2(surface.size))
				check(shifted.distance_to(before[i]) < 0.0006,"display-only camera height shift does not move physics point %d at %d" % [i,height])
			camera.v_offset = 0.0
			camera.set_meta("desktop_vertical_presentation_offset",0.0)
		var resized_region: Rect2 = bait._free_lure_screen_region()
		check(resized_region.position.distance_to(authored_region.position) < 0.0006 and resized_region.size.distance_to(authored_region.size) < 0.0006,"authored physical screen bounds survive resize %s" % height)
	# Explicitly reproduce a water landing *below* the authored bottom band.
	# This used to reject all candidates and could strand held D indefinitely.
	surface.size = Vector2i(960,480)
	camera.fov = 75.0
	await process_frame
	bait.global_position = on_water(Vector2(640,365))
	goal.global_position = on_water(Vector2(340,446))
	var starting_distance: float = bait.global_position.distance_to(goal.global_position)
	bait.reel_steering = 1.0
	bait.reel_steering_target = 1.0
	var made_progress := true
	for i in range(120):
		var previous: Vector3 = bait.global_position
		var distance_before: float = previous.distance_to(goal.global_position)
		bait._update_reeling(1.0/60.0,0.45)
		var distance_after: float = bait.global_position.distance_to(goal.global_position)
		if distance_after < 0.3:
			break
		if distance_after >= distance_before - 0.000001:
			made_progress = false
			break
	check(made_progress,"held D does not stall when landing lies beyond bottom screen corridor")
	check(bait.global_position.distance_to(goal.global_position) < starting_distance-0.1,"held D makes meaningful inward physical progress")
	# A corner scorer can award an imperceptibly small movement on every tick.
	# Require useful radial progress in a second held-D scenario, not merely
	# that a position changed by a nonzero floating-point amount.
	bait.global_position = on_water(Vector2(680,345))
	goal.global_position = on_water(Vector2(300,450))
	var samples: int = 0
	var motion_sum: float = 0.0
	for _tick in range(120):
		var old: Vector3 = bait.global_position
		var old_dist: float = old.distance_to(goal.global_position)
		bait._update_reeling(1.0/60.0,0.45)
		var new_dist: float = bait.global_position.distance_to(goal.global_position)
		if old_dist <= 0.3 or bait.state != bait.State.IN_WATER:
			break
		motion_sum += maxf(0.0, old_dist-new_dist)
		samples += 1
	check(samples > 0 and motion_sum > 0.05,"held D has visible cumulative radial travel in 120 frames")
	# Ensure the old late-HUD actor can no longer directly change bait position.
	var bounds_script: Script = load("res://scripts/fishing_screen_water_bounds.gd")
	var code: String = bounds_script.source_code
	check(not code.contains("bait.global_position = constrain_position"),"presentation water bounds cannot assign bait world position")
	print("FISHING STABILIZATION PHYSICS GATE 02: %d/%d passed; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
