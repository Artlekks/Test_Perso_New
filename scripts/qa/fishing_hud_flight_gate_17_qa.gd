extends SceneTree
## Gate 17: inspect real responsive HUD anchors and the actual Camera3D pan
## contract. The casting sequence still requires a rendered F5 test.
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

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	for viewport_size in [Vector2i(640,480),Vector2i(960,480),Vector2i(960,700)]:
		await check_hud_stays_at_rest(viewport_size)
		await check_flight_pan_is_bounded(viewport_size)
	print("FISHING HUD / FLIGHT GATE 17: %d/%d passed; failures=%s" % [
		checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)

func check_hud_stays_at_rest(viewport_size: Vector2i) -> void:
	# Use the real fishing HUD with its real dimensions and child artwork.
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var game := Outpost.instantiate()
	viewport.add_child(game)
	await process_frame
	await process_frame
	var power := game.get_node("UI/FishingHud/PowerMeter")
	var inset := game.get_node("UI/FishingHud/CharacterView") as Control
	var depth := game.get_node("UI/FishingHud/PowerMeter/DepthMeter") as Control
	# Disable only the view's visibility updates while sampling both cases.
	inset.set_process(false)
	inset.visible = false
	power._update_viewport_layout(1.0/30.0)
	var home_power: Vector2 = power._rest_position
	var home_depth: Vector2 = depth.get("rest_position")
	var home_inset: Vector2 = inset.get("rest_position")
	inset.visible = true
	for i in range(35):
		power._update_viewport_layout(1.0/30.0)
	check(power._rest_position.is_equal_approx(home_power),
		"power X/Y must not shift as inset appears %s" % viewport_size)
	check(Vector2(depth.get("rest_position")).is_equal_approx(home_depth),
		"depth X/Y must not shift as inset appears %s" % viewport_size)
	check(Vector2(inset.get("rest_position")).is_equal_approx(home_inset),
		"inset anchor must not shift when shown %s" % viewport_size)
	inset.visible = false
	power._update_viewport_layout(1.0/30.0)
	check(power._rest_position.is_equal_approx(home_power),
		"power must not move when inset retires %s" % viewport_size)
	viewport.queue_free()
	await process_frame

func check_flight_pan_is_bounded(viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.own_world_3d = true
	root.add_child(viewport)
	var player := Node3D.new()
	viewport.add_child(player)
	var rig := Rig.new()
	rig.target = player
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0.0,3.0,8.0)
	rig.add_child(camera)
	viewport.add_child(rig)
	rig.set_process(false)
	camera.current = true
	await process_frame
	var size := Vector2(viewport_size)
	var bait := camera.project_position(Vector2(size.x * 0.90, size.y * 0.35),12.0)
	rig.fishing_follow_active = true
	var start: Vector3 = camera.global_position
	const STEP: float = 1.0/30.0
	rig._pan_inset_camera_to_lure(camera,bait,size,STEP,true)
	check(camera.global_position.distance_to(start) <= rig.inset_follow_pan_speed * STEP + 0.0001,
		"pre-splash camera pan must be bounded, never one-frame jump %s" % viewport_size)
	check(rig.inset_containment_failures == 0,
		"flight (no inset) must not claim a post-splash violation %s" % viewport_size)
	# When inset-mode takes ownership, the same actual optical projection
	# must be brought inside the rectangle without moving the physical lure.
	var lure_original: Vector3 = bait
	rig._pan_inset_camera_to_lure(camera,bait,size,STEP,false)
	var target_box: Rect2 = rig._inset_follow_region_for_camera(camera)
	var normalized: Vector2 = camera.unproject_position(bait) / size
	check(target_box.grow(0.0001).has_point(normalized),
		"post-splash hard red frame must contain the lure %s" % viewport_size)
	check(bait.is_equal_approx(lure_original),
		"camera safety must not move physical lure %s" % viewport_size)
	viewport.queue_free()
	await process_frame
