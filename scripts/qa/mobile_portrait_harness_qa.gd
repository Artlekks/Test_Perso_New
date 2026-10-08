extends SceneTree

const Shell = preload("res://actors/mobile/MobilePortraitHarness.tscn")
const SceneRoot = preload("res://scripts/gameplay_scene_root.gd")
var checks := 0
var failures: Array[String] = []
var harness: Control
var controls: Control
var rendered := false
var capture_dir := OS.get_environment("TEMP").path_join("godot-mobile-portrait-qa")
var observed_keys: Array[int] = []

func _initialize() -> void:
	rendered = OS.get_cmdline_user_args().has("--rendered")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	var isolated := "CodexMobilePortraitQA-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Refusing mobile QA without isolated userdata")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle(frames := 4) -> void:
	for frame in range(frames):
		await process_frame
	await physics_frame

func capture(label: String) -> void:
	if rendered:
		for frame in range(3):
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png(capture_dir.path_join(label + ".png"))
		var point: Vector2 = root.get_final_transform() * (controls.get_global_transform_with_canvas() * (controls.size * Vector2(0.95, 0.75)))
		var pixel := image.get_pixel(int(point.x), int(point.y))
		check(pixel.r > 0.6 and pixel.g > 0.6 and pixel.b > 0.6, "touch panel pixels remain visible in " + label)

func button(label: String, index := 10) -> void:
	controls.touch_begin(index, controls.buttons[label].get_center())
	await settle(2)
	controls.touch_end(index)
	await settle(3)

func run() -> void:
	var desktop_fixture := Node.new()
	root.add_child(desktop_fixture)
	current_scene = desktop_fixture
	check(SceneRoot.resolve(self) == desktop_fixture, "ordinary desktop scene identity unchanged")
	current_scene = null
	desktop_fixture.free()
	harness = Shell.instantiate()
	harness.isolated_playtest_save = false
	root.add_child(harness)
	current_scene = harness
	await settle(30)
	controls = harness.controls
	controls.key_requested.connect(func(event):
		if event.pressed:
			observed_keys.append(event.physical_keycode))
	var game: Node = harness.game
	var player: CharacterBody3D = game.get_node("Player/CharacterBody3D")
	var mode: Node = game.get_node("Game/GameMode")
	var fishing: Node = game.get_node("Game/Fishing")
	var session := root.get_node("FishingSessionServices")
	check(SceneRoot.resolve(self) == game and current_scene == harness, "wrapper resolves authoritative gameplay root")
	check(harness.gameplay_viewport.size == Vector2i(640, 480), "existing rendering dimensions preserved")
	check(game.get_viewport() == harness.gameplay_viewport and harness.gameplay_viewport.get_camera_3d() != null, "game/camera inside top viewport")
	check(session.dialogue_controller.get_view().get_viewport() == harness.gameplay_viewport, "persistent dialogue presentation contained")
	check(game.is_ancestor_of(fishing.fishing_menu) and fishing.fishing_menu.get_viewport() == harness.gameplay_viewport, "existing menu contained in actual game")
	for dimensions in [Vector2(390, 844), Vector2(393, 852), Vector2(844, 390)]:
		var rect: Rect2 = harness.get_safe_rect(dimensions)
		check(Rect2(Vector2.ZERO, dimensions).encloses(rect), "fallback safe rectangle inside window %s" % dimensions)
	var hardware: Rect2 = harness.get_safe_rect(Vector2(390, 844), Rect2(0, 141, 1170, 2289), Vector2(1170, 2532))
	check(hardware.position.is_equal_approx(Vector2(0, 47)) and hardware.size.is_equal_approx(Vector2(390, 763)), "physical safe area converts to logical portrait units")
	check(harness.safe_rect.encloses(Rect2(controls.position, controls.size)), "control panel inside safe region")
	for label in controls.buttons:
		check(Rect2(Vector2.ZERO, controls.size).encloses(controls.buttons[label]), label + " hit region contained")
	await capture("mobile-portrait-gameplay")
	# Drive actual ScreenTouch/Drag events, two independent touch identities.
	player.global_position = Vector3(100, 0, 100)
	player.camera_reference = null
	var start := player.global_position
	var origin: Vector2 = controls.stick_zone.get_center()
	var touch := InputEventScreenTouch.new()
	touch.index = 1
	var screen_transform := root.get_final_transform() * controls.get_global_transform_with_canvas()
	touch.position = screen_transform * origin
	touch.pressed = true
	Input.parse_input_event(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = screen_transform * (origin + Vector2(controls.stick_radius * 0.7, 0))
	Input.parse_input_event(drag)
	await settle(8)
	check(controls.stick_touch == 1 and controls.stick_origin.is_equal_approx(origin), "stick floats at initial touch")
	check(Input.is_action_pressed("move_right") and Input.is_action_pressed("ds_right"), "stick activates exploration and existing fishing steering actions")
	check(is_equal_approx(Input.get_action_strength("move_right"), 0.7), "movement strength follows analog displacement: vector=%s strength=%s" % [controls.stick_vector, Input.get_action_strength("move_right")])
	check(player.global_position.x > start.x, "stick moves real player through production physics")
	var action_touch := InputEventScreenTouch.new()
	action_touch.index = 2
	action_touch.position = screen_transform * controls.buttons["A"].get_center()
	action_touch.pressed = true
	Input.parse_input_event(action_touch)
	await settle(2)
	check(Input.is_action_pressed("enter_fishing") and Input.is_action_pressed("move_right"), "stick plus A multitouch")
	check(observed_keys.count(KEY_K) == 1, "one A press emits one canonical confirm event")
	action_touch.pressed = false
	Input.parse_input_event(action_touch)
	await settle(2)
	check(not Input.is_action_pressed("enter_fishing") and Input.is_action_pressed("move_right"), "A release does not release stick")
	touch.pressed = false
	Input.parse_input_event(touch)
	await settle(2)
	check(controls.stick_touch == -1 and not Input.is_action_pressed("move_right") and not Input.is_action_pressed("ds_right"), "stick release clears all mapped movement")
	await button("MENU")
	check(fishing.fishing_menu.is_open() and paused, "MENU opens existing paused game menu")
	await capture("mobile-portrait-menu")
	await button("START")
	check(paused and fishing.fishing_menu.is_open(), "START cannot steal menu-owned pause")
	await button("MENU")
	check(not paused and not fishing.fishing_menu.is_open(), "MENU closes via existing menu owner")
	await button("START")
	check(paused, "START uses existing manual pause")
	await button("START")
	check(not paused, "START resumes only its own pause")
	game.get_node("World/BeachMerchantNPC")._start_interaction()
	await settle(4)
	check(paused and session.dialogue_service.is_active(), "real merchant dialogue opens")
	await capture("mobile-portrait-dialogue")
	await button("B")
	check(not paused and not session.dialogue_service.is_active(), "B cancels existing dialogue")
	mode.enter_fishing(game.get_node("World/FishZone_V2"))
	await settle(4)
	fishing.phase = fishing.Phase.AIM
	fishing.cast_input_gate.release(fishing.cast_input_gate.Stage.AIM)
	await button("A")
	check(fishing.phase == fishing.Phase.PREP_THROW, "A reaches existing cast input gate")
	controls.touch_begin(30, controls.buttons["A"].get_center())
	controls.release_all()
	await settle(2)
	check(controls.touches.is_empty() and not Input.is_action_pressed("enter_fishing"), "focus/resize cleanup releases held confirmation")
	mode.exit_fishing()
	await settle(4)
	# Reserved SELECT produces no key; L/R retain existing Q/E behavior.
	var before := observed_keys.size()
	await button("SELECT")
	check(observed_keys.size() == before, "SELECT explicitly reserved")
	await button("L")
	await button("R")
	check(observed_keys.has(KEY_Q) and observed_keys.has(KEY_E), "shoulders use existing Q/E keys")
	controls.touch_begin(40, controls.buttons["A"].get_center())
	controls.touch_begin(41, controls.buttons["A"].get_center())
	controls.touch_end(40)
	await settle(2)
	check(Input.is_action_pressed("enter_fishing"), "one button's second finger retains ownership")
	controls.touch_end(41)
	await settle(2)
	check(not Input.is_action_pressed("enter_fishing"), "last button finger releases confirmation")
	controls.touch_begin(50, controls.stick_zone.get_center())
	controls.touch_drag(50, controls.stick_origin + Vector2(controls.stick_radius * 3, 0))
	await settle(2)
	check(controls.stick_vector.length() <= 1.0, "stick displacement constrained to radius")
	controls.touch_drag(50, controls.stick_origin + Vector2(controls.stick_radius * 0.1, 0))
	await settle(2)
	check(not Input.is_action_pressed("move_right") and controls.stick_touch == 50, "neutral deadzone releases movement while retaining touch")
	controls.touch_begin(51, controls.buttons["A"].get_center())
	root.focus_exited.emit()
	await settle(2)
	check(controls.touches.is_empty() and not Input.is_action_pressed("enter_fishing"), "actual window focus-loss signal clears all fingers")
	var locations := root.get_node("WorldLocations")
	check(locations.is_current_scene(game) and locations.current_location.location_id == &"beach", "world context uses actual hosted game")
	# Load through the shared hosting seam without bypassing progression travel.
	var error := SceneRoot.change_scene_to_file(self, "res://actors/FishingTestScene_V2.tscn")
	await settle(20)
	check(error == OK and current_scene == harness and harness.game != game, "scene replacement retains optional shell")
	check(locations.is_current_scene(harness.game), "replacement location context remains authoritative")
	check(session.dialogue_controller.get_view().get_viewport() == harness.gameplay_viewport, "persistent UI survives scene replacement")
	check(not locations.request_travel(&"wyndia_ocean_outpost").success, "hosted travel still rejects locked routes")
	# QA-only authored prerequisite, in the disposable profile; production
	# travel still evaluates the same progression and ownership contracts.
	session.inventory.grant_lure(&"baby_frog", 1, false)
	check(locations.request_travel(&"wyndia_ocean_outpost").success, "unlocked travel uses existing authoritative route")
	check(not locations.request_travel(&"wyndia_ocean_outpost").success, "hosted duplicate travel rejected during transition")
	await settle(20)
	check(current_scene == harness and harness.game.get_viewport() == harness.gameplay_viewport and locations.current_location.location_id == &"wyndia_ocean_outpost", "actual Ocean travel remains inside shell")
	check(session.dialogue_controller.get_view().get_viewport() == harness.gameplay_viewport, "session UI persists through authoritative travel")
	controls.release_all()
	print("MOBILE PORTRAIT HARNESS QA: %d/%d" % [checks - failures.size(), checks])
	current_scene = null
	harness.queue_free()
	await settle(3)
	quit(0 if failures.is_empty() else 1)
