extends SceneTree
## Gate 18 -- responsive red-rectangle boundaries and early flight follow.
## Tests real Camera3D reprojection and actual HUD geometry on the outpost.
## Rendered F5 acceptance is still required: headless projections cannot
## certify the first visible pixel of an animated 3D character.
const Rig = preload("res://scripts/camera_rig.gd")
const Outpost = preload("res://actors/locations/DevelopmentFishingOutpost.tscn")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	for size in [Vector2i(640,480), Vector2i(960,480), Vector2i(960,700), Vector2i(1280,720)]:
		await check_real_hud(size)
		await check_camera_projection(size)
	print("FISHING RESPONSIVE TRACKING GATE 18: %d/%d passed; failures=%s" % [
		checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)

func check_real_hud(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var scene := Outpost.instantiate()
	viewport.add_child(scene)
	await process_frame
	await process_frame
	var rig = scene.get_node("CameraRig")
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	var power = scene.get_node("UI/FishingHud/PowerMeter")
	var depth = scene.get_node("UI/FishingHud/PowerMeter/DepthMeter")
	var inset = scene.get_node("UI/FishingHud/CharacterView")
	power._update_viewport_layout(0.0)
	# Derive every boundary from current HUD REST positions, even with inset
	# hidden during a flight: displaying the inset must not move the power bar.
	rig.set_fishing_hud_geometry(power,depth)
	var bar: Rect2 = rig._hud_rest_rect(power.get_node("Root/PowerBarBG"),power,null)
	var meter: Rect2 = rig._hud_rest_rect(depth.get_node("Frame"),null,depth)
	var character: Rect2 = rig._hud_rest_rect(inset.get_node("Grid"),null,inset)
	var old: Rect2 = Rig.inset_region_from_hud_pixels(Vector2(size),bar,meter,character,
		0.16,0.265,0.23,0.185)
	var newer: Rect2 = Rig.inset_region_from_hud_pixels(Vector2(size),bar,meter,character,
		rig.inset_left_gap_bar_width,rig.inset_right_gap_bar_width,
		rig.inset_bottom_gap_bar_width,rig.inset_height_bar_width)
	check(old.has_area() and newer.has_area(),"HUD region feasible %s" % size)
	if old.has_area() and newer.has_area():
		check(newer.position.x < old.position.x,"left tracking edge expanded toward rod %s" % size)
		check(newer.end.x > old.end.x,"right tracking edge widened while staying before gauge %s" % size)
		check(newer.end.y <= bar.position.y,"bait clear of power bar %s" % size)
		check(newer.end.x < meter.position.x,"bait clear of depth meter %s" % size)
	var hard: Rect2 = rig._inset_follow_region_for_camera(camera)
	check(hard.has_area(),"actual HUD containment feasible %s" % size)
	if hard.has_area():
		check(absf(hard.position.y - 0.43) < 0.001,"new ceiling 7pct above screen midpoint %s" % size)
		check(hard.end.x < meter.position.x / float(size.x),"no depth overlap %s" % size)
		var artwork: Rect2 = rig._inset_artwork_rect()
		if artwork.has_area():
			check(hard.position.x * size.x >= artwork.end.x - 0.1,
				"bait never intersects real inset/rod artwork %s" % size)
	var flight: Rect2 = Rig.flight_follow_region(hard,rig.fishing_follow_top_y_ratio)
	check(flight.position.y >= 0.425 and flight.position.y <= 0.435,"cast starts above viewport midpoint %s" % size)
	check(is_equal_approx(flight.position.x,hard.position.x),"cast uses HUD-relative left edge %s" % size)
	check(is_equal_approx(flight.end.x,hard.end.x),"cast uses HUD-relative right edge %s" % size)
	check(flight.end.y > hard.end.y,"airborne lower region is generous %s" % size)
	viewport.queue_free()
	await process_frame

func check_camera_projection(size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var player := Node3D.new()
	player.position = Vector3(100,0,100)  # Unambiguously offscreen.
	viewport.add_child(player)
	var rig := Rig.new()
	rig.target = player
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0,4,10)
	rig.add_child(camera)
	viewport.add_child(rig)
	rig.set_process(false)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await process_frame
	check(is_equal_approx(rig.fishing_follow_top_y_ratio,0.43),"responsive vertical follow default %s" % size)
	check(rig.fishing_follow_right_x_ratio <= 0.70,"early right follow default %s" % size)
	var viewport_size := Vector2(size)
	for uv in [Vector2(.12,.55), Vector2(.86,.55), Vector2(.51,.15),
		Vector2(.51,.85), Vector2(.90,.13)]:
		var bait: Vector3 = camera.project_position(uv*viewport_size,12.0)
		var original: Vector3 = bait
		var original_basis: Basis = camera.global_basis
		# The hard water frame MUST recover the point by optical translation,
		# without editing its physical world position or adding camera yaw.
		rig.fishing_follow_active = true
		rig._pan_inset_camera_to_lure(camera,bait,viewport_size,1.0/30.0,false)
		var region: Rect2 = rig._inset_follow_region_for_camera(camera)
		check(region.grow(0.0001).has_point(camera.unproject_position(bait)/viewport_size),
			"post-splash containment %s %s" % [size,uv])
		check(bait.is_equal_approx(original),"physical lure unchanged %s %s" % [size,uv])
		check(camera.global_basis.is_equal_approx(original_basis),"no pan yaw %s %s" % [size,uv])
		# Next sample starts from the same optical pose, avoiding cumulative tests.
		camera.global_position = rig.global_position + Vector3(0,4,10)
		rig._airborne_inset_pan = Vector3.ZERO
		rig.global_position = Vector3.ZERO
	viewport.queue_free()
	await process_frame
