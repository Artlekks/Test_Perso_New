extends SceneTree

## Production HUD signal/animation and camera composition comparison. State
## snapshots hold the coordinator still; full mechanics are covered separately.
var checks := 0
var failures: Array[String] = []
var desktop_rows: Dictionary = {}
var desktop_y := 0.0
var capture_dir := ""
var rendered := false

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "CodexMobileParity-%d" % Time.get_ticks_usec())
	if not OS.get_user_data_dir().get_file().begins_with("CodexMobileParity-") or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Refusing parity QA without isolated userdata")
		quit(1)
		return
	rendered = OS.get_cmdline_user_args().has("--rendered")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func wait(seconds := 0.85) -> void:
	await create_timer(seconds).timeout

func snapshot(game: Node, mobile: bool, state: String) -> void:
	var hud := game.get_node("UI/ExplorationHud")
	var meter := game.get_node("UI/FishingHud/PowerMeter")
	var depth := meter.get_node("DepthMeter")
	var location: Control = hud.location
	var top: Vector2 = location.get_global_transform_with_canvas().origin
	var height: float = game.get_viewport().get_visible_rect().size.y
	var row := [top.y >= 0 and top.y < height, meter.root.visible, meter.tension_meter.visible, depth.visible]
	print("HUD ", "mobile" if mobile else "desktop", " ", state, " ", row, " power_home=", meter._rest_position, " power_actual=", meter.root.get_global_transform_with_canvas().origin)
	if mobile:
		check(row == desktop_rows[state], "production HUD state parity " + state)
	else:
		desktop_rows[state] = row
	if meter.root.visible:
		check(meter.root.get_global_transform_with_canvas().origin.y < height - 20, "power/tension animation remains on screen " + state)
	if depth.visible:
		check(depth.get_global_transform_with_canvas().origin.y < height - 40, "depth remains on screen " + state)
	if state == "exploration":
		check(is_equal_approx(top.y, 22.0) and is_equal_approx(hud.compass.position.y, 0.0), "top exploration HUD remains at viewport edges")
		check(is_equal_approx(hud.help_panel.position.y, height - 480.0), "exploration commands retain authored bottom clearance")
	if rendered:
		DirAccess.make_dir_recursive_absolute(capture_dir)
		for frame in range(3):
			await RenderingServer.frame_post_draw
		game.get_viewport().get_texture().get_image().save_png(capture_dir.path_join(("mobile-" if mobile else "desktop-") + state + ".png"))

func run() -> void:
	for mobile in [false, true]:
		var shell: Node = null
		var game: Node
		if mobile:
			shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
			shell.isolated_playtest_save = false
			root.add_child(shell)
			current_scene = shell
			await wait()
			game = shell.game
		else:
			root.size = Vector2i(640, 480)
			root.content_scale_size = Vector2i(640, 480)
			game = load("res://actors/FishingTestScene_V2.tscn").instantiate()
			root.add_child(game)
			current_scene = game
			await wait()
		var mode := game.get_node("Game/GameMode")
		var fishing := game.get_node("Game/Fishing")
		var rig := game.get_node("CameraRig")
		var player := game.get_node("Player/CharacterBody3D")
		var meter := game.get_node("UI/FishingHud/PowerMeter")
		var caster := fishing.get_node("Caster")
		await snapshot(game, mobile, "exploration")
		var locations := root.get_node("WorldLocations")
		var sign := game.get_node("World/OceanTravel")
		check(locations.is_current_scene(game) and locations.current_location.destinations.has(String(sign.destination_id)), "host has authored route and authoritative world context")
		check(sign.label.text != "Route unavailable", "valid fresh profile is Locked rather than Route unavailable")
		var merchant := game.get_node("World/BeachMerchantNPC")
		var saved_position: Vector3 = player.global_position
		player.global_position = merchant.global_position + Vector3(0.5, 0, 0)
		await wait(0.2)
		merchant._start_interaction()
		var session := root.get_node("FishingSessionServices")
		check(session.dialogue_service.is_active(), "production merchant dialogue opens in each host")
		await snapshot(game, mobile, "dialogue-choices")
		session.dialogue_service.cancel()
		player.global_position = saved_position
		await wait(0.2)
		# Use the authored water-facing direction, as valid exploration entry
		# requires, rather than entering fishing while facing away from the sea.
		player.global_basis = game.get_node("World/FishZone_V2/WaterFacing").global_basis
		mode.enter_fishing(game.get_node("World/FishZone_V2"))
		await wait(1.5)
		fishing.set_process(false)
		rig.set_process(false)
		await snapshot(game, mobile, "entry-aim")
		var camera: Camera3D = rig.get_node("Camera3D")
		var before: Vector3 = player.global_position
		var measured: float = camera.unproject_position(before).y / game.get_viewport().get_visible_rect().size.y
		print("FEET Y ", "mobile" if mobile else "desktop", "=", measured, " v_offset=", camera.v_offset, " correction=", rig.mobile_fishing_vertical_offset)
		if mobile:
			check(absf(measured - desktop_y) < 0.002, "mobile fishing normalized foot Y matches desktop")
		else:
			desktop_y = measured
		fishing.phase = fishing.Phase.CHARGE
		fishing.power.start()
		await wait(0.4)
		await snapshot(game, mobile, "charge")
		fishing.power.capture()
		fishing.phase = fishing.Phase.BAIT_FLYING
		await wait(0.4)
		await snapshot(game, mobile, "airborne")
		fishing.phase = fishing.Phase.IN_WATER
		caster.bait_depth_changed.emit(1.0, 3.0)
		await wait(0.5)
		await snapshot(game, mobile, "in-water")
		fishing.phase = fishing.Phase.FIGHT
		meter._on_fish_hooked()
		fishing.encounter.tension_changed.emit(0.45)
		await snapshot(game, mobile, "fight")
		var bait := Node3D.new()
		game.add_child(bait)
		for x in [0.05, 0.95]:
			bait.global_position = camera.project_position(Vector2(x, 0.45) * game.get_viewport().get_visible_rect().size, 10)
			rig.set_fishing_fight_tracking(true, bait)
			for frame in range(120):
				rig._process(1.0 / 60.0)
			check(absf(camera.unproject_position(before).y / game.get_viewport().get_visible_rect().size.y - measured) < 0.002, "yaw retains normalized foot Y")
			await snapshot(game, mobile, "fight-left" if x < 0.5 else "fight-right")
			rig._clear_fight_camera_tracking(false)
		bait.free()
		fishing.phase = fishing.Phase.LANDING
		await snapshot(game, mobile, "landing")
		meter._on_bait_returned()
		game.get_node("UI/FishingHud/PowerMeter/DepthMeter")._on_bait_returned()
		await wait(0.5)
		await snapshot(game, mobile, "result")
		mode.exit_fishing()
		# The coordinator is held for snapshots: explicitly exercise the same
		# restoration entry point its put-away animation normally calls.
		rig.exit_fishing_view()
		await wait(1.2)
		check(is_equal_approx(camera.v_offset, rig.exploration_v_offset) and player.global_position.is_equal_approx(before), "existing return restores offset without moving actor")
		await snapshot(game, mobile, "return")
		current_scene = null
		if shell != null:
			shell.free()
		else:
			game.free()
		await wait(0.1)
	print("MOBILE GAMEPLAY PARITY QA: %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
