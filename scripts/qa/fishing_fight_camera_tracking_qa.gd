extends SceneTree

const Rig = preload("res://scripts/camera_rig.gd")
const Fishing = preload("res://scripts/fishing.gd")
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var rig: Node3D
var player: Node3D
var fish: Node3D
var camera: Camera3D
var base: Transform3D

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--regressions"):
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		var isolated_name := "CodexFightCameraQA-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
		ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated_name)
		if not OS.get_user_data_dir().ends_with(isolated_name) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
			push_error("Isolated userdata setup failed; refusing gameplay QA bootstrap")
			quit(1)
			return
		print("ISOLATED USERDATA: ", OS.get_user_data_dir())
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func setup() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 480)
	root.add_child(viewport)
	player = Node3D.new()
	viewport.add_child(player)
	fish = Node3D.new()
	viewport.add_child(fish)
	rig = Rig.new()
	rig.name = "CameraRig"
	camera = Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	rig.target = player
	viewport.add_child(rig)
	rig.set_process(false)
	camera.current = true
	camera.position = Vector3(0, 4, 6)
	camera.look_at(Vector3(0, 0, -4))
	base = camera.transform
	if OS.get_cmdline_user_args().has("--mobile"):
		# Exercise the same harness-only aspect/UI-band adapter as production.
		var shell = load("res://scripts/mobile/mobile_portrait_harness.gd").new()
		viewport.size = shell.get_layout_rects(shell.get_safe_rect(Vector2(390, 844))).resolution
		shell.game = viewport
		shell.gameplay_viewport = viewport
		shell._adapt_mobile_presentation()
		shell.game = null
		shell.free()

func put_fish(pixel: Vector2, depth := 12.0) -> void:
	rig.reset_fishing_follow()
	camera.transform = base
	var logical_pixel := pixel * Vector2(640, 480)
	logical_pixel.y += float(viewport.size.y - 480) * 0.5
	var physical := camera.project_position(logical_pixel, depth)
	fish.global_position = camera.project_position(Vector2(320,220),depth)
	rig.set_fishing_fight_tracking(true, fish)
	tick()
	fish.global_position = physical

func tick(count := 1) -> void:
	for frame in range(count):
		rig._process(1.0 / 60.0)

func test_visibility_independence() -> void:
	var presentation := Sprite3D.new()
	fish.add_child(presentation)
	for x in [0.94, 0.08, 1.2, -0.2]:
		fish.visible = true
		presentation.visible = true
		put_fish(Vector2(x, 0.4))
		var physical_position := fish.global_position
		var corrections: Array[float] = []
		var transforms: Array[Transform3D] = []
		for frame in range(30):
			tick()
			corrections.append(rig.fight_camera_tracking.requested_yaw)
			transforms.append(camera.transform)
		check(corrections[0] < 0.0 if x > 0.85 else corrections[0] > 0.0,
			"physical target at screen x=%s requests correct left/right orbit" % x)
		for toggle in [false, true]:
			put_fish(Vector2(x, 0.4))
			var identical := true
			var continuously_active := true
			for frame in range(30):
				fish.visible = toggle and frame % 2 == 0
				presentation.visible = toggle and frame % 3 == 0
				tick()
				identical = identical and is_equal_approx(corrections[frame], rig.fight_camera_tracking.requested_yaw) \
					and camera.transform.is_equal_approx(transforms[frame])
				continuously_active = continuously_active and rig._fight_tracking_active
			check(identical, "hidden/toggling presentation gives identical corrections and transforms at x=%s" % x)
			check(continuously_active, "visibility never releases logical fight ownership at x=%s" % x)
			check(fish.global_position.is_equal_approx(physical_position), "hidden target remains at unchanged physical position")
	# Beyond the optical plane, the previous shared sentinel erased direction.
	for side in [-1.0, 1.0]:
		rig.reset_fishing_follow()
		camera.transform = base
		fish.global_position = camera.get_camera_transform() * Vector3(side * 8.0, 0.0, 1.0)
		fish.visible = false
		rig.set_fishing_fight_tracking(true, fish)
		rig.fishing_camera_state = rig.FishingCameraPresentationState.ANCHORED
		tick()
		check(rig.fight_camera_tracking.requested_yaw * side < 0.0,
			"hidden physical target behind optical plane retains corrective side")
		check(rig._fight_tracking_active, "behind-camera target retains fight ownership")
	# Submerged coordinates still drive the same logical target; no surface
	# visual or visible fight-shadow instance is required by the camera.
	fish.visible = true
	put_fish(Vector2(1.2, 0.4))
	fish.global_position.y = -3.0
	var submerged_position := fish.global_position
	tick()
	var submerged_request: float = rig.fight_camera_tracking.requested_yaw
	var submerged_transform := camera.transform
	rig.reset_fishing_follow()
	camera.transform = base
	fish.visible = false
	fish.global_position = submerged_position
	rig.set_fishing_fight_tracking(true, fish)
	rig.fishing_camera_state = rig.FishingCameraPresentationState.ANCHORED
	tick()
	check(is_equal_approx(submerged_request, rig.fight_camera_tracking.requested_yaw)
		and camera.transform.is_equal_approx(submerged_transform),
		"submerged world target gives identical visible/hidden correction")
	check(rig._fight_tracking_active and fish.global_position.is_equal_approx(submerged_position),
		"submerged hidden physical target remains active and unmodified")
	fish.visible = true
	presentation.free()
	rig.reset_fishing_follow()

func test_water_state_coverage() -> void:
	var coordinator := Fishing.new()
	var mock_encounter := Node.new()
	mock_encounter.set_script(load("res://scripts/encounter.gd"))
	var mock_caster := Node3D.new()
	mock_caster.set_script(load("res://scripts/caster.gd"))
	coordinator.camera_rig = rig
	coordinator.encounter = mock_encounter
	coordinator.caster = mock_caster
	mock_caster.active_bait = fish
	mock_encounter.lifecycle.begin_cast()
	coordinator.phase = Fishing.Phase.IN_WATER
	for x in [0.5, -0.2, 1.2]:
		var visible_request := 0.0
		var visible_transform := Transform3D.IDENTITY
		for visible in [true, false]:
			put_fish(Vector2(x, 0.4))
			# Clear the direct fixture owner/base so water entry must acquire it.
			rig.reset_fishing_follow()
			fish.visible = visible
			var physical := fish.global_position
			fish.global_position = camera.project_position(Vector2(320,220),12)
			coordinator._sync_fight_camera_tracking()
			tick()
			fish.global_position = physical
			coordinator._sync_fight_camera_tracking()
			tick()
			check(rig._fight_tracking_active and rig._fight_tracking_target == fish,
				"IN_WATER owns physical bait even when hidden/off-screen")
			var request: float = rig.fight_camera_tracking.requested_yaw
			check(is_zero_approx(request) if x == 0.5 else request > 0.0 if x < 0.2 else request < 0.0,
				"IN_WATER inside/left/right correction at x=%s" % x)
			if visible:
				visible_request = request
				visible_transform = camera.transform
			else:
				check(is_equal_approx(request, visible_request) and camera.transform.is_equal_approx(visible_transform),
					"IN_WATER visible/hidden bait produces identical camera correction")
	var water_yaw: float = rig.fight_camera_tracking.yaw
	var water_base: Transform3D = rig._fight_base_camera_transform
	var water_transform := camera.transform
	mock_encounter.lifecycle.confirm_hook()
	coordinator.phase = Fishing.Phase.FIGHT
	coordinator._sync_fight_camera_tracking()
	check(rig._fight_tracking_active and rig._fight_tracking_target == fish,
		"IN_WATER to hooked FIGHT retains physical target and ownership")
	check(is_equal_approx(water_yaw, rig.fight_camera_tracking.yaw)
		and water_base.is_equal_approx(rig._fight_base_camera_transform)
		and water_transform.is_equal_approx(camera.transform),
		"IN_WATER to FIGHT never resets yaw/base/pose")
	for phase in [Fishing.Phase.LANDING, Fishing.Phase.LINE_BROKEN, Fishing.Phase.AIM, Fishing.Phase.EXIT]:
		coordinator.phase = phase
		coordinator._sync_fight_camera_tracking()
		check(not rig._fight_tracking_active, "landing/escape/reel-back/exit releases ownership: %s" % phase)
		check(camera.transform.is_equal_approx(water_transform), "release leaves restoration to existing flow")
	rig.reset_fishing_follow()
	check(camera.transform.is_equal_approx(base) and not rig._fight_base_valid,
		"water tracking restores through existing follow reset")
	coordinator.phase = Fishing.Phase.IN_WATER
	mock_caster.active_bait = null
	coordinator._sync_fight_camera_tracking()
	check(not rig._fight_tracking_active, "IN_WATER without a physical bait safely releases ownership")
	fish.visible = true
	coordinator.free()
	mock_encounter.free()
	mock_caster.free()

func run() -> void:
	setup()
	await process_frame
	test_wide_dead_zone()
	test_visibility_independence()
	test_water_state_coverage()
	put_fish(Vector2(0.5, 0.4))
	tick(60)
	check(is_zero_approx(rig.fight_camera_tracking.yaw), "inside safe region: no yaw")
	check(camera.transform.is_equal_approx(base), "inside safe region: original shot unchanged")
	put_fish(Vector2(0.94, 0.4))
	var fish_before := fish.global_transform
	var distance_before := camera.global_position.distance_to(player.global_position)
	var pitch_before := camera.global_basis.z.y
	var fov_before := camera.fov
	tick()
	check(rig.fight_camera_tracking.requested_yaw < 0.0, "right edge requests camera yaw right (negative world Y)")
	check(absf(rig.fight_camera_tracking.yaw) < absf(rig.fight_camera_tracking.requested_yaw), "response is smoothed, not snapped")
	tick(180)
	check(camera.unproject_position(fish.global_position).x <= (rig.fight_safe_right + .001) * 640, "right run returns inside safe edge")
	check(fish.global_transform.is_equal_approx(fish_before), "tracking never moves the fish")
	check(is_equal_approx(distance_before, camera.global_position.distance_to(player.global_position)), "physical pivot distance preserved")
	check(is_equal_approx(pitch_before, camera.global_basis.z.y), "world pitch preserved")
	check(is_equal_approx(camera.fov, fov_before), "FOV preserved")
	check(rig.fight_camera_tracking.inside(camera.unproject_position(fish.global_position)/Vector2(viewport.size),rig.fishing_safe_region(),0.001), "hard containment takes priority over unchanged optical player framing only outside bounds")
	check(is_zero_approx(rig.rotation.y), "rig heading untouched")
	var settled: float = rig.fight_camera_tracking.yaw
	tick(240)
	check(absf(settled - rig.fight_camera_tracking.yaw) < 0.001, "stationary boundary does not oscillate")
	var neutral_fish := (rig.global_transform * base) * Vector3(0, 0, -12)
	fish.global_position = neutral_fish
	tick(300)
	check(is_equal_approx(rig.fight_camera_tracking.yaw,settled), "safe central fish holds established yaw; retrieve owns neutral return")
	put_fish(Vector2(0.08, 0.4))
	tick()
	check(rig.fight_camera_tracking.requested_yaw > 0.0, "left edge requests camera yaw left (positive world Y)")
	tick(180)
	check(camera.unproject_position(fish.global_position).x >= (rig.fight_safe_left - .001) * 640, "left run returns inside safe edge")
	rig.fight_max_yaw_degrees = 5.0
	put_fish(Vector2(1.5, 0.4))
	tick(240)
	check(absf(rig.fight_camera_tracking.yaw) <= deg_to_rad(5.0), "maximum yaw respected")
	check(rig.fight_camera_tracking.limited and rig.safe_containment_failures>0, "infeasible capped yaw reports failure rather than moving player framing or increasing cap")
	rig.fight_max_yaw_degrees = 55.0
	put_fish(Vector2(0.90, 0.705),2.0)
	tick(240)
	check(camera.unproject_position(fish.global_position).y <= rig.fight_safe_bottom * viewport.size.y + 0.5, "lateral fish descending toward HUD stops at legal boundary with vertical clearance")
	var held := camera.transform
	rig.set_fishing_fight_tracking(false)
	tick(60)
	check(camera.transform.is_equal_approx(held), "fight exit holds shot for existing landing/result flow")
	rig.reset_fishing_follow()
	check(camera.transform.is_equal_approx(base), "existing follow reset restores neutral pose")
	check(not rig._fight_base_valid and is_zero_approx(rig.fight_camera_tracking.yaw), "existing restoration clears tracking state")
	var latch = load("res://scripts/fishing_fight_camera_tracking.gd").new()
	var outer := Rect2(0.2, 0.08, 0.65, 0.67)
	latch.step(0.016, func(_yaw): return Vector2(0.86, 0.4), outer, 0.025, 1.0, 6.0, 2.0)
	check(latch.tracking, "outer threshold starts tracking")
	for x in [0.84, 0.86, 0.84]:
		latch.step(0.016, func(_yaw): return Vector2(x, 0.4), outer, 0.025, 1.0, 6.0, 2.0)
		check(latch.tracking == (x > outer.end.x), "safe entry holds immediately; outside edge reactivates")
	latch.step(0.016, func(_yaw): return Vector2(0.82, 0.4), outer, 0.025, 1.0, 6.0, 2.0)
	check(not latch.tracking, "inner threshold stops tracking")
	for phase in [Fishing.Phase.AIM, Fishing.Phase.THROW, Fishing.Phase.BAIT_FLYING]:
		# Exercise the coordinator's actual phase/lifecycle gate without booting a save.
		var coordinator := Fishing.new()
		var mock_encounter := Node.new()
		mock_encounter.set_script(load("res://scripts/encounter.gd"))
		var mock_caster := Node3D.new()
		mock_caster.set_script(load("res://scripts/caster.gd"))
		coordinator.camera_rig = rig
		coordinator.encounter = mock_encounter
		coordinator.caster = mock_caster
		coordinator.phase = phase
		mock_encounter.lifecycle.begin_cast()
		mock_encounter.lifecycle.confirm_hook()
		mock_caster.active_bait = fish
		coordinator._sync_fight_camera_tracking()
		tick()
		check(not rig._fight_tracking_active and camera.transform.is_equal_approx(base), "no tracking in phase %s" % phase)
		coordinator.phase = Fishing.Phase.FIGHT
		mock_encounter.lifecycle.finish_cast()
		coordinator._sync_fight_camera_tracking()
		check(not rig._fight_tracking_active, "FIGHT without hooked lifecycle cannot track")
		mock_encounter.lifecycle.begin_cast()
		mock_encounter.lifecycle.confirm_hook()
		coordinator._sync_fight_camera_tracking()
		check(rig._fight_tracking_active, "hooked FIGHT enables camera ownership")
		fish.visible = false
		coordinator._sync_fight_camera_tracking()
		tick()
		check(rig._fight_tracking_active, "hooked lifecycle retains ownership when physical target is hidden")
		check(rig.fishing_player_camera_locked, "hooked fight uses existing player rail without waiting for visibility")
		mock_encounter.lifecycle.begin_landing()
		coordinator._sync_fight_camera_tracking()
		check(not rig._fight_tracking_active, "logical landing ends tracking even with a valid hidden target")
		fish.visible = true
		rig.reset_fishing_follow()
		coordinator.free()
		mock_encounter.free()
		mock_caster.free()
	var state: SceneState = load("res://actors/FishingTestScene_V2.tscn").get_state()
	var found_pose := false
	for index in range(state.get_node_count()):
		if not String(state.get_node_path(index)).ends_with("CameraRig/FishingCameraPose"):
			continue
		for property in range(state.get_node_property_count(index)):
			var name := state.get_node_property_name(index, property)
			if name == &"transform":
				base = state.get_node_property_value(index, property)
				found_pose = true
			elif name == &"h_offset" or name == &"v_offset":
				camera.set(name, state.get_node_property_value(index, property))
	check(found_pose, "QA loads current authored fishing camera pose")
	for x in [0.08, 0.94]:
		put_fish(Vector2(x, 0.4))
		var initial_distance := camera.global_position.length()
		var initial_pitch := camera.global_basis.z.y
		tick(240)
		var projected := camera.unproject_position(fish.global_position) / Vector2(viewport.size)
		check(projected.x >= rig.fight_safe_left - .001 and projected.x <= rig.fight_safe_right + .001, "authored pose tracks lateral fish into safe region")
		check(not camera.is_position_behind(fish.global_position) and rig.fight_camera_tracking.inside(projected,rig.fishing_safe_region(),0.001),
			"authored camera contains physical target with minimal boundary framing")
		check(is_equal_approx(camera.global_position.length(), initial_distance) and is_equal_approx(camera.global_basis.z.y, initial_pitch),
			"authored pose pitch/distance preserved")
		var measured: Vector2 = rig._project_fight_orbit(0.0, camera.get_camera_transform(),
			camera.get_camera_projection(), player.global_position, fish.global_position)
		check(measured.distance_to(projected) < 0.00001,
			"projection math matches active Camera3D including authored h/v offsets")
	await test_complete_retrieve()
	test_vertical_retrieve()
	put_fish(Vector2(0.94, 0.4))
	tick(120)
	# Full exploration exit retains the tracked start shot and uses its existing tween.
	var exit_start := camera.transform
	rig.exploration_camera_transform_before_fishing = base
	rig.exit_fishing_view()
	check(camera.transform.is_equal_approx(exit_start) and not rig._fight_base_valid,
		"exploration exit starts existing tween from tracked shot without snap")
	await create_timer(0.8).timeout
	check(camera.transform.is_equal_approx(base), "existing exploration exit tween completes restoration")
	viewport.free()
	if OS.get_cmdline_user_args().has("--regressions"):
		await run_existing_regressions()
	print("FIGHT CAMERA QA: %d/%d passed" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func test_wide_dead_zone() -> void:
	var outer := Rect2(rig.fight_safe_left,rig.fight_safe_top,rig.fight_safe_right-rig.fight_safe_left,rig.fight_safe_bottom-rig.fight_safe_top)
	var margin: float = rig.fight_tracking_hysteresis
	check(is_equal_approx(outer.position.x,0.18) and is_equal_approx(outer.end.x,0.82),"canonical 4:3 safe edges are 18/82 percent")
	check(is_equal_approx(outer.position.x+margin,0.20) and is_equal_approx(outer.end.x-margin,0.80),"inner horizontal stops are centralized 20/80 percent")
	for x in [0.18,0.19,0.20,0.5,0.79,0.80,0.82]:
		put_fish(Vector2(x,0.4))
		tick(120)
		check(not rig.fight_camera_tracking.tracking and is_zero_approx(rig.fight_camera_tracking.yaw),"visible bait including old/exact outer boundary holds camera: %s" % x)
	for side in [-1,1]:
		var latch = load("res://scripts/fishing_fight_camera_tracking.gd").new()
		var point := [Vector2(0.175 if side<0 else 0.825,0.4)]
		var projection := func(_yaw): return point[0]
		latch.step(1.0/60.0,projection,outer,margin,deg_to_rad(55),6,2)
		check(latch.tracking,"clear outer crossing starts tracking on side %d" % side)
		point[0].x=0.179 if side<0 else 0.821
		for frame in range(120): latch.step(1.0/60.0,projection,outer,margin,deg_to_rad(55),6,2)
		check(latch.tracking,"slight inward movement keeps tracking latched on side %d" % side)
		point[0].x=0.205 if side<0 else 0.795
		latch.step(1.0/60.0,projection,outer,margin,deg_to_rad(55),6,2)
		check(not latch.tracking,"sufficient inner crossing stops side %d" % side)
		latch.yaw=deg_to_rad(15)*side
		var held: float = latch.yaw
		# Slow current / passive drift and edge noise use the same projection.
		for frame in range(600):
			point[0].x=(0.205 if side<0 else 0.795)+sin(frame*.03)*.005
			latch.step(1.0/60.0,projection,outer,margin,deg_to_rad(55),6,2)
		check(not latch.tracking and is_equal_approx(latch.yaw,held),"current/passive drift has no reactivation or micro-unwind on side %d" % side)
		point[0]=Vector2(0.5,0.77)
		latch.step(1.0/60.0,projection,outer,margin,deg_to_rad(55),6,2)
		check(not latch.tracking and is_equal_approx(latch.yaw,held),"vertical bounds cannot rotate bait through horizontal center")
		for y in [lerpf(outer.position.y,outer.end.y,0.25),lerpf(outer.position.y,outer.end.y,0.75)]:
			latch.pan_state = latch.PanState.PAN_LEFT if side < 0 else latch.PanState.PAN_RIGHT
			point[0] = Vector2(0.5,y)
			latch.step(1.0/60.0,projection,outer,margin,deg_to_rad(55),6,2)
			check(not latch.tracking and latch.yaw == held,"already active edge latch stops on central safe-rectangle entry")
	rig.reset_fishing_follow()

func run_existing_regressions() -> void:
	var orphan_before := Node.get_orphan_node_ids()
	# Boot only the existing beach scene; travel/economy route authoring is
	# outside this camera regression and must not gate its independent suites.
	var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(6):
		await process_frame
	var session := root.get_node("FishingSessionServices")
	for property in ["fight_combat_qa_report", "presentation_qa_report", "system_stability_qa_report"]:
		var report: Dictionary = FishingSessionQA.reports(session).get(property)
		print(property, ": ", report.passed_count, "/", report.test_count)
		check(report.passed_count == report.test_count, property)
	var harness = load("res://scripts/fishing_regression_harness.gd").new()
	var result: Dictionary = harness.run_all()
	print("FULL FISHING REGRESSION: ", result.summary)
	check(result.failed == 0, "existing full fishing regression")
	for failure in result.failures:
		push_error(str(failure))
	harness = null
	scene.queue_free()
	session.queue_free()
	for frame in range(3):
		await process_frame
	# Each fixture must release its own nodes; never hide a leak by scavenging it.
	for id in Node.get_orphan_node_ids():
		if not orphan_before.has(id):
			check(false, "regression fixture leaked orphan node %d" % id)


func test_complete_retrieve() -> void:
	for x in [0.08, 0.94, 0.5, 0.08, 0.94]:
		put_fish(Vector2(x, 0.4))
		tick(120)
		var start := camera.transform
		var start_yaw: float = rig.fight_camera_tracking.yaw
		var physical := fish.global_position
		var distance := camera.position.length()
		var pitch := camera.basis.z.y
		var fov := camera.fov
		rig.return_fishing_follow_to_target(true)
		check(camera.transform.is_equal_approx(start), "retrieve x=%s starts without a snap" % x)
		check(not rig._fight_tracking_active and rig._fight_tracking_target == null and rig.fishing_follow_target == null,
			"retrieve releases physical tracking target immediately")
		check(rig.fishing_follow_returning == (absf(start_yaw) > deg_to_rad(rig.retrieve_yaw_stop_degrees)), "retrieve has one return owner; center does not drift")
		# Simulate production AIM synchronization while the existing tween runs.
		rig.set_fishing_fight_tracking(false)
		tick(21)
		if absf(start_yaw) > 0.001:
			check(not camera.transform.is_equal_approx(start) and not camera.transform.is_equal_approx(base),
				"left/right retrieve has an intermediate orbit, not a delayed snap")
		check(is_equal_approx(rig._retrieve_yaw, start_yaw * exp(-rig.fight_yaw_return_response * 0.35)) if absf(start_yaw) > 0.001 else not rig.fishing_follow_returning, "return reuses exponential tracker damping, not fixed duration")
		check(is_equal_approx(camera.position.length(), distance) and is_equal_approx(camera.basis.z.y, pitch)
			and is_equal_approx(camera.fov, fov), "retrieve preserves radius/pitch/FOV")
		tick(360)
		check(camera.transform.is_equal_approx(base), "retrieve completes at original cast-ready pose")
		check(not rig.fishing_follow_returning and not rig._retrieve_yaw_return_active and not rig._fight_base_valid,
			"repeat retrieve leaves no return/tracking ownership")
		check(fish.global_position.is_equal_approx(physical), "retrieve return never changes physical bait")
	var settle_counts: Array[int] = []
	for degrees in [5.0, 55.0]:
		rig.reset_fishing_follow()
		camera.transform = base
		rig.set_fishing_fight_tracking(true, fish)
		rig.fight_camera_tracking.yaw = deg_to_rad(degrees)
		camera.transform = rig._fight_orbit_transform(base, Vector3.ZERO, deg_to_rad(degrees))
		rig.return_fishing_follow_to_target(true)
		var frames := 0
		while rig.fishing_follow_returning and frames < 600:
			tick()
			frames += 1
		settle_counts.append(frames)
	check(settle_counts[1] > settle_counts[0], "large yaw naturally takes longer to settle than tiny yaw")
	print("RETURN SETTLE 5deg/55deg seconds: ", settle_counts[0]/60.0, "/",settle_counts[1]/60.0)
	# Exiting fishing midway must hand its current shot to the original exit tween.
	put_fish(Vector2(0.94, 0.4))
	tick(120)
	rig.return_fishing_follow_to_target(true)
	tick(6)
	var interrupted := camera.transform
	rig.exploration_camera_transform_before_fishing = base
	rig.exit_fishing_view()
	check(camera.transform.is_equal_approx(interrupted), "exit during retrieve preserves transition start")
	check(not rig.fishing_follow_returning, "exit cancels retrieve tween to avoid competing rotations")
	await create_timer(0.8).timeout
	check(camera.transform.is_equal_approx(base), "interrupted retrieve uses original exploration restoration")


func test_vertical_retrieve() -> void:
	for endpoint in [Vector2(.5,.705),Vector2(.90,.705)]:
		put_fish(endpoint,2.0)
		tick(180)
		var physical := fish.global_position
		var offsets := Vector2(camera.h_offset,camera.v_offset)
		var pose := camera.transform
		var neutral: Vector2 = rig._fight_base_offsets
		var initial_pan: Vector2 = rig._water_pan
		rig.return_fishing_follow_to_target(true)
		check(camera.transform.is_equal_approx(pose) and Vector2(camera.h_offset,camera.v_offset).is_equal_approx(offsets),"vertical/corner retrieve starts without optical or pose snap")
		check(rig.fishing_follow_returning,"vertical-only framing uses existing retrieve owner even at zero yaw")
		tick(21)
		check(rig._retrieve_pan.length()<initial_pan.length() and rig._retrieve_pan.length()>0.00001 if initial_pan.length()>0.00001 else is_zero_approx(rig._retrieve_pan.length()),"ground pan unwinds only when the solved framing needed pan")
		tick(600)
		check(camera.transform.is_equal_approx(base) and Vector2(camera.h_offset,camera.v_offset).is_equal_approx(neutral),"vertical/corner retrieve restores exact post-aim shot")
		check(not rig.fishing_follow_returning and not rig._retrieve_yaw_return_active,"no stale framing return owner")
		check(fish.global_position.is_equal_approx(physical),"framing return never changes physical bait")
