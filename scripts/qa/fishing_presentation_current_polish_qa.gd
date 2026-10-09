extends SceneTree

const Bounds = preload("res://scripts/fishing_screen_water_bounds.gd")
const Current = preload("res://scripts/fishing_current_service.gd")
const Flow = preload("res://scripts/fishing_current_surface_view.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	var isolated := "CodexCurrentPolishQA-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Refusing QA without isolated userdata")
		quit(1)
		return
	print("ISOLATED USERDATA: ", OS.get_user_data_dir())
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func test_screen_bounds() -> void:
	var config := Bounds.new()
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	for size in [Vector2i(640, 480), Vector2i(1280, 960), Vector2i(320, 240)]:
		viewport.size = size
		for yaw in [-55.0, 0.0, 55.0]:
			camera.position = Vector3(0, 4, 6).rotated(Vector3.UP, deg_to_rad(yaw))
			camera.look_at(Vector3(0, 0, -4).rotated(Vector3.UP, deg_to_rad(yaw)))
			var before := camera.transform
			for pixel in [Vector2(0.5, 0.4), Vector2(0.1, 0.05), Vector2(0.9, 0.95), Vector2(-0.2, 0.05), Vector2(1.2, 0.05)]:
				var world := camera.project_position(pixel * Vector2(size), 12.0)
				var resolved: Vector3 = Bounds.constrain_position(camera, world, config.top_safe_ratio)
				var screen := camera.unproject_position(resolved) / Vector2(size)
				check(is_equal_approx(screen.y, maxf(pixel.y, config.top_safe_ratio)), "vertical ceiling survives viewport scaling and yaw: %s/%s/%s" % [size, yaw, pixel])
				check(absf(screen.x - pixel.x) < 0.0001 and is_equal_approx(resolved.y, world.y), "constraint preserves screen X and physical depth")
				if pixel.y > config.top_safe_ratio:
					check(resolved.is_equal_approx(world), "safe bait is untouched")
			check(camera.transform.is_equal_approx(before), "ceiling never changes camera transform")
	viewport.free()
	config.free()

func test_current() -> void:
	var service := Current.new()
	root.add_child(service)
	var spot := FishingSpotData.new()
	spot.current_direction = Vector2.RIGHT
	spot.current_speed = 0.2
	spot.current_gust_strength = 0.0
	service.set_spot(spot)
	var swim := FishSwimBounds.new()
	var shape := CollisionShape3D.new()
	shape.name = "BoundsShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(100, 10, 100)
	shape.shape = box
	swim.add_child(shape)
	root.add_child(swim)
	service.set_swim_bounds(swim)
	var bait = load("res://actors/bait_V2.tscn").instantiate()
	root.add_child(bait)
	bait.set_physics_process(false)
	bait.set_current_service(service)
	bait.state = bait.State.IN_WATER
	bait.global_position = Vector3.ZERO
	for frame in range(120):
		bait._update_current_drift(1.0 / 60.0)
	var weak_position: Vector3 = bait.global_position
	check(weak_position.x > 0.25 and absf(weak_position.z) < 0.00001, "waterborne drift follows canonical east current")
	bait._current_drift_velocity = Vector3.ZERO
	bait.global_position = Vector3.ZERO
	spot.current_speed = 0.4
	for frame in range(120):
		bait._update_current_drift(1.0 / 60.0)
	check(is_equal_approx(bait.global_position.x, weak_position.x * 2.0), "twice authored strength gives twice drift")
	bait.global_position = Vector3.ZERO
	bait.twitch_velocity = Vector3(0, 0, -0.4)
	bait.twitch_target_velocity = bait.twitch_velocity
	bait._update_twitch_motion(1.0 / 60.0)
	bait._update_current_drift(1.0 / 60.0)
	check(bait.global_position.x > 0.0 and bait.global_position.z < 0.0, "real steering motion and current combine")
	for state in [bait.State.IDLE, bait.State.FLYING]:
		bait.state = state
		var before: Vector3 = bait.global_position
		bait._update_current_drift(1.0)
		check(bait.global_position.is_equal_approx(before), "no drift outside waterborne state %s" % state)
	bait.state = bait.State.SINKING
	var before: Vector3 = bait.global_position
	bait._update_current_drift(0.1)
	check(bait.global_position.x > before.x, "sinking bait is already waterborne")
	bait.set_simulation_frozen(true)
	before = bait.global_position
	bait._update_current_drift(1.0)
	check(bait.global_position.is_equal_approx(before), "landing freeze stops all current influence")
	bait.set_simulation_frozen(false)
	bait.state = bait.State.IN_WATER
	spot.current_direction = Vector2.LEFT
	var previous: Vector3 = bait._current_drift_velocity
	bait._update_current_drift(1.0 / 60.0)
	check(previous.normalized().dot(bait._current_drift_velocity.normalized()) > 0.99, "authored reversal turns gradually rather than flipping")
	var view := Flow.new()
	root.add_child(view)
	view.set_process(false)
	view.configure(service, null)
	view._swim_bounds = swim
	view._uvs[0] = Vector2(0.5, 0.5)
	view._flows[0] = previous
	view._update_streaks(1.0 / 60.0)
	check(view._flows[0].is_equal_approx(bait._current_drift_velocity), "visual heading uses same canonical current/filter as bait")
	var mesh_id := view._streaks[0].mesh.get_instance_id()
	spot.current_direction = Vector2.RIGHT
	view._flows[0] = Vector3(spot.current_speed, 0, 0)
	view._uvs[0] = Vector2(0.5, 0.5)
	var monotonic := true
	var last_x := view._uvs[0].x
	for frame in range(240):
		view._update_streaks(1.0 / 60.0)
		monotonic = monotonic and view._uvs[0].x > last_x
		last_x = view._uvs[0].x
	check(monotonic, "four seconds of flow has no old short-cycle reversal/reset")
	check(view._streaks[0].mesh.get_instance_id() == mesh_id, "wave animation reuses mesh rather than rebuilding geometry")
	view._uvs[0] = Vector2(0.99999, 0.5)
	view._update_streaks(1.0 / 60.0)
	var tint: Color = view._streaks[0].material_override.get_shader_parameter("tint")
	check(tint.a < 0.005, "world-boundary wrap is faded instead of visibly snapping")
	view.free()
	bait.free()
	swim.free()
	service.free()

func test_runtime_contracts(scene: Node) -> void:
	var fishing = scene.get_node("Game/Fishing")
	var encounter = fishing.encounter
	var bounds = fishing.get_node("ScreenWaterBounds")
	check(bounds.process_priority > fishing.process_priority, "screen constraint runs after production movement/camera updates")
	var measured: float = bounds.info_view.get_fishing_covered_bottom_ratio()
	print("HUD boundary: bar_bottom=", measured, " effective_top=", maxf(bounds.top_safe_ratio, measured + bounds.info_margin_ratio))
	check(measured > 0.0 and measured < bounds.top_safe_ratio, "authored HUD fits below default top margin")
	var info = bounds.info_view
	var rest: Vector2 = info.root.position
	info.root.position += Vector2(0, -300)
	check(is_equal_approx(info.get_fishing_covered_bottom_ratio(), measured), "HUD ceiling remains stable while notice slides/changes context")
	info.root.position = rest
	var camera := root.get_viewport().get_camera_3d()
	var caster = fishing.caster
	var physical = load("res://actors/bait_V2.tscn").instantiate()
	caster.add_child(physical)
	physical.set_physics_process(false)
	physical.state = physical.State.IN_WATER
	check(physical.ripple_view.process_priority > bounds.process_priority, "surface ripple updates after screen constraint")
	caster.active_bait = physical
	var old_phase: int = fishing.phase
	fishing.phase = fishing.Phase.IN_WATER
	var ripple = physical.ripple_view
	physical.global_position = camera.project_position(root.get_visible_rect().size * Vector2(0.5, 0.55), 12.0)
	ripple.configure(physical, physical.global_position.y)
	for cycle in range(3):
		fishing._on_bite_opportunity_started()
		check(ripple.active and ripple.ripple_sprite.animation == &"Ripple", "nibble uses ripple, not splash cycle %d" % cycle)
		var texture: Texture2D = ripple.ripple_sprite.sprite_frames.get_frame_texture(&"Ripple", 0)
		var authored = load("res://actors/bait_V2.tscn").instantiate()
		var source: AtlasTexture = authored.get_node("RippleView/RippleSprite").sprite_frames.get_frame_texture(&"Ripple", 0)
		var source_image: Image = source.atlas.get_image()
		if source_image.is_compressed(): source_image.decompress()
		check(texture.get_image().get_data() == source_image.get_region(Rect2i(source.region)).get_data() and source.atlas.resource_path.ends_with("fish_ripple.png"), "nibble preserves exact authored ripple pixels in Web-safe frame textures")
		authored.free()
		check(is_equal_approx(ripple.ripple_sprite.pixel_size, ripple.ripple_pixel_size), "ripple uses readable surface cue sizing")
		physical.global_position += Vector3(0.1, 0, 0)
		ripple._process(0.0)
		var projected_bait := camera.unproject_position(physical.global_position)
		check(camera.unproject_position(ripple.global_position).distance_to(projected_bait) < 0.01,
			"surface effect follows authoritative physical bait projection")
		fishing._on_bite_missed()
		check(not ripple.active and not ripple.visible and not ripple.ripple_sprite.is_playing(), "miss clears nibble effect")
		fishing._on_bite_opportunity_started()
		fishing._on_bite_commit_ready({})
		check(ripple.active and ripple.ripple_sprite.animation == &"Ripple", "hook-ready cue retains ripple throughout opportunity")
		check(not fishing.bite_opportunity_animation_active and fishing.bite_animation_active,
			"committed bite retains strong character presentation")
		fishing._on_bite_triggered()
		check(ripple.active and ripple.ripple_sprite.animation == &"BiteSplash", "hook keeps committed splash without duplicate ripple/replay")
		var splash_frames: SpriteFrames = ripple.ripple_sprite.sprite_frames
		var splash_duration: float = splash_frames.get_frame_count(&"BiteSplash") / splash_frames.get_animation_speed(&"BiteSplash")
		await create_timer(splash_duration + 0.1).timeout
		check(not ripple.active and not ripple.visible and not ripple.ripple_sprite.is_playing(), "committed splash expires without stale effects")
		fishing._on_bite_missed()
	# Exercise the actual full-retrieve coordinator after a missed nibble.
	var rig = fishing.camera_rig
	rig.reset_fishing_follow()
	rig.set_fishing_fight_tracking(true, physical)
	rig._update_fight_camera_tracking(0.2)
	var tracked: Transform3D = camera.transform
	fishing._on_bait_returned()
	check(fishing.phase == fishing.Phase.AIM and not rig._fight_tracking_active and rig._fight_tracking_target == null,
		"miss -> full retrieve releases tracking while AIM resumes; centered shot needs no unwind")
	check(camera.transform.is_equal_approx(tracked), "full-retrieve coordinator does not snap camera")
	check(not ripple.active and not fishing.bite_opportunity_animation_active, "missed retrieve leaves no surface/character nibble ownership")
	rig.reset_fishing_follow()
	fishing.aim.stop()
	fishing.phase = old_phase
	var previous_phase: int = fishing.phase
	for phase in [fishing.Phase.IN_WATER, fishing.Phase.FIGHT, fishing.Phase.BAIT_FLYING, fishing.Phase.LANDING, fishing.Phase.INACTIVE]:
		encounter.lifecycle.finish_cast()
		encounter.lifecycle.begin_cast()
		if phase == fishing.Phase.FIGHT:
			encounter.lifecycle.confirm_hook()
		fishing.phase = phase
		var point := camera.project_position(root.get_visible_rect().size * Vector2(0.5, 0.05), 12.0)
		physical.global_position = point
		bounds._process(0.0)
		var expected: bool = phase == fishing.Phase.IN_WATER or phase == fishing.Phase.FIGHT
		check(not physical.global_position.is_equal_approx(point) if expected else physical.global_position.is_equal_approx(point), "production phase eligibility %s" % phase)
		if expected:
			var visible_correction: Vector3 = physical.global_position
			physical.visible = false
			physical.global_position = point
			bounds._process(0.0)
			check(physical.global_position.is_equal_approx(visible_correction), "hidden waterborne target has identical screen ceiling")
			physical.visible = true
	fishing.phase = fishing.Phase.IN_WATER
	physical.state = physical.State.FLYING
	var airborne := camera.project_position(root.get_visible_rect().size * Vector2(0.5, 0.05), 12.0)
	physical.global_position = airborne
	bounds._process(0.0)
	check(physical.global_position.is_equal_approx(airborne), "airborne physical bait is never screen-constrained")
	fishing.phase = previous_phase
	caster.active_bait = null
	physical.free()
	# Screen guards must never create an unreachable catch threshold.
	var saved_camera := camera.transform
	var saved_h := camera.h_offset
	var saved_v := camera.v_offset
	var pose: Camera3D = scene.get_node("CameraRig/FishingCameraPose")
	camera.transform = pose.transform
	camera.h_offset = pose.h_offset
	camera.v_offset = pose.v_offset
	for depth in [0.1, 1.0, 2.5]:
		var reel_bait = load("res://actors/bait_V2.tscn").instantiate()
		root.add_child(reel_bait)
		reel_bait.set_physics_process(false)
		reel_bait.state = reel_bait.State.IN_WATER
		reel_bait.fight_mode = true
		reel_bait.reel_target = fishing.player
		var pixel := root.get_visible_rect().size * Vector2(0.5, 0.5)
		var start = Plane(Vector3.UP, -depth).intersects_ray(camera.project_ray_origin(pixel), camera.project_ray_normal(pixel))
		reel_bait.global_position = start
		var returned := [false]
		reel_bait.returned.connect(func(): returned[0] = true)
		for frame in range(18000):
			reel_bait._update_reeling(1.0 / 60.0)
			if returned[0]:
				break
			reel_bait.global_position = Bounds.constrain_position(camera, reel_bait.global_position, bounds.top_safe_ratio)
		check(returned[0], "screen limits preserve real reeling/landing at depth %s" % depth)
		reel_bait.free()
	camera.transform = saved_camera
	camera.h_offset = saved_h
	camera.v_offset = saved_v
	var swim = scene.find_child("FishSwimBounds", true, false)
	check(swim != null, "real beach swim bounds available")
	if swim == null:
		return
	var presence := FishShadowPresence.new()
	root.add_child(presence)
	presence.set_process(false)
	presence._swim_bounds = swim
	var bait := Node3D.new()
	root.add_child(bait)
	var fish: FishData = load("res://data/bof4/fish/sea_bream.tres")
	var shadow := presence.start_fight_shadow(fish, bait)
	check(shadow != null and shadow.visible and shadow.is_hooked_tracking(), "underwater hooked shadow starts visible")
	check(shadow.process_priority > bounds.process_priority and shadow.process_priority < 110, "hooked shadow follows constrained bait before line presentation")
	encounter.lifecycle.finish_cast()
	encounter.lifecycle.begin_cast()
	encounter.lifecycle.confirm_hook()
	encounter.active_fight_shadow = shadow
	check(encounter.begin_catch_landing(), "authoritative successful landing starts")
	check(not shadow.visible and not shadow.is_hooked_tracking(), "landing hides and detaches shadow immediately before splash")
	check(encounter.active_fight_shadow == null and presence._fight_shadow == null, "landing clears encounter/presence ownership")
	check(encounter.begin_catch_landing() and encounter.active_fight_shadow == null and not shadow.visible, "duplicate landing signal is harmless and cannot restore shadow")
	shadow._process(2.0)
	check(shadow.is_queued_for_deletion() and not presence._spawned_shadows.has(shadow), "hidden landing shadow expires and leaves the population registry")
	var next := presence.start_fight_shadow(fish, bait)
	check(next != shadow and next.visible and next.is_hooked_tracking(), "consecutive catch creates a fresh visible underwater shadow")
	encounter.active_fight_shadow = next
	encounter._end_active_fight_shadow(true)
	check(next.visible and not next.is_hooked_tracking() and next._expiring, "escape retains existing visible dive/fade cleanup")
	var missed := presence.start_fight_shadow(fish, bait)
	missed.release_from_hooked_bait(false)
	missed.abandon_bait_and_dive()
	check(missed.visible and missed._expiring, "missed catch retains existing underwater dive cleanup")
	presence.free()
	bait.free()

func run() -> void:
	var orphan_before := Node.get_orphan_node_ids()
	test_screen_bounds()
	test_current()
	var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(6):
		await process_frame
	await test_runtime_contracts(scene)
	var session := root.get_node("FishingSessionServices")
	for property in ["fight_combat_qa_report", "presentation_qa_report", "system_stability_qa_report", "weather_sense_qa_report", "tide_sense_qa_report", "master_current_reader_qa_report", "master_drift_angler_qa_report", "master_weather_watcher_qa_report", "master_tide_reader_qa_report"]:
		var report: Dictionary = FishingSessionQA.reports(session).get(property)
		print(property, ": ", report.passed_count, "/", report.test_count)
		check(report.passed_count == report.test_count, property)
	scene.queue_free()
	session.queue_free()
	for frame in range(3):
		await process_frame
	for id in Node.get_orphan_node_ids():
		if not orphan_before.has(id):
			check(false, "presentation fixture leaked orphan node %d" % id)
	print("PRESENTATION/CURRENT POLISH QA: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
