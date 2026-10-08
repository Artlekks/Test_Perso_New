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
	check(harness.gameplay_viewport.size.x == 640 and harness.gameplay_viewport.size.y > 480, "mobile retains logical width and reveals extra vertical gameplay")
	check(harness.gameplay_image.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "gameplay scaling remains nearest neighbor")
	for camera in game.find_children("*", "Camera3D", true, false):
		var original: Dictionary = camera.get_meta("mobile_original_projection")
		var desktop_projection := Projection.create_perspective(original.fov, 640.0 / 480.0, camera.near, camera.far, original.aspect == Camera3D.KEEP_WIDTH)
		check(camera.keep_aspect == Camera3D.KEEP_WIDTH and is_equal_approx(camera.get_camera_projection().x.x, desktop_projection.x.x), "mobile camera preserves authored horizontal projection: " + camera.name)
	check(game.get_viewport() == harness.gameplay_viewport and harness.gameplay_viewport.get_camera_3d() != null, "game/camera inside top viewport")
	check(session.dialogue_controller.get_view().get_viewport() == harness.gameplay_viewport, "persistent dialogue presentation contained")
	check(game.is_ancestor_of(fishing.fishing_menu) and fishing.fishing_menu.get_viewport() == harness.gameplay_viewport, "existing menu contained in actual game")
	for dimensions in [Vector2(390, 844), Vector2(393, 852), Vector2(844, 390)]:
		var rect: Rect2 = harness.get_safe_rect(dimensions)
		check(Rect2(Vector2.ZERO, dimensions).encloses(rect), "fallback safe rectangle inside window %s" % dimensions)
	var hardware: Rect2 = harness.get_safe_rect(Vector2(390, 844), Rect2(0, 141, 1170, 2289), Vector2(1170, 2532))
	check(hardware.position.is_equal_approx(Vector2(0, 47)) and hardware.size.is_equal_approx(Vector2(390, 763)), "physical safe area converts to logical portrait units")
	var reference: Dictionary = harness.get_layout_rects(hardware)
	check(reference.resolution == Vector2i(640, 751) and reference.gameplay.position.is_equal_approx(Vector2(0, 47)), "iPhone reference derives 640x751 gameplay resolution from safe area")
	check(absf(reference.gameplay.size.y / hardware.size.y - 0.60) < 0.002 and is_equal_approx(reference.controls.end.y, 810.0), "iPhone reference uses 60/40 split and keeps 34-point home inset")
	for dimensions in [Vector2(390, 844), Vector2(390, 664), Vector2(393, 852), Vector2(844, 390)]:
		var available: Rect2 = harness.get_safe_rect(dimensions)
		var layout: Dictionary = harness.get_layout_rects(available)
		check(available.encloses(layout.gameplay) and available.encloses(layout.controls), "game and controls stay in safe area %s" % dimensions)
		check(is_equal_approx(layout.gameplay.size.x / 640.0, layout.gameplay.size.y / layout.resolution.y), "uniform uncropped taller display scale %s" % dimensions)
		check(is_equal_approx(layout.gameplay.position.y, available.position.y) and is_equal_approx(layout.controls.position.y, layout.gameplay.end.y) and is_equal_approx(layout.controls.end.y, available.end.y), "no top/game/control gap and bottom safe inset retained %s" % dimensions)
		if dimensions.x < dimensions.y:
			check(is_equal_approx(layout.gameplay.size.x, available.size.x), "portrait uses maximum safe width even with Safari chrome %s" % dimensions)
	check(harness.gameplay_image.position.is_equal_approx(harness.safe_rect.position) and is_equal_approx(harness.gameplay_image.size.y / harness.gameplay_viewport.size.y, harness.gameplay_image.size.x / 640.0), "live game image has no outer letterbox region or distortion")
	check(is_equal_approx(controls.position.y, harness.gameplay_image.position.y + harness.gameplay_image.size.y), "live controls immediately follow game image")
	check(harness.safe_rect.encloses(Rect2(controls.position, controls.size)), "control panel inside safe region")
	for label in controls.buttons:
		check(Rect2(Vector2.ZERO, controls.size).encloses(controls.buttons[label]), label + " hit region contained")
		check(controls.buttons[label].encloses(controls.button_visuals[label]), label + " visual inside comfortable hit region")
		for other in controls.buttons:
			if label < other:
				check(not controls.buttons[label].intersects(controls.buttons[other]), "touch buttons do not overlap: %s / %s" % [label, other])
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
	await button("A")
	await create_timer(0.4).timeout
	var menu = fishing.fishing_menu
	check(menu._page == menu.Page.EQUIP, "touch confirm still enters existing equipment menu")
	check(menu.equip_slot_selector.get_global_transform_with_canvas().origin.is_equal_approx(menu._item_screen_position(menu.equip_slot_list, menu._equip_slot_index) + menu.equip_left_selector_offset), "equipment selector aligns after mobile UI band translation")
	await capture("mobile-portrait-equipment")
	await button("B")
	await create_timer(0.4).timeout
	await button("START")
	check(paused and fishing.fishing_menu.is_open(), "START cannot steal menu-owned pause")
	await button("MENU")
	check(not paused and not fishing.fishing_menu.is_open(), "MENU closes via existing menu owner")
	await button("START")
	check(paused, "START uses existing manual pause")
	await button("START")
	check(not paused, "START resumes only its own pause")
	# The disposable profile earns the existing starter bundle; C must reach
	# the real NPC conversation through the ordinary world input router.
	var triad := game.get_node("UI/TripleTriadGame")
	check(triad.claim_salvaged_card_case().success, "C QA uses canonical starter acquisition in disposable save")
	var card_npc := game.get_node("World/TripleTriadOpponentNPC")
	player.global_position = card_npc.global_position + Vector3(0, 0, 0.35)
	player.rotation.y = PI
	for frame in range(6):
		await physics_frame
		await process_frame
	# Campaign presentation re-enables the card interaction Area on its
	# periodic refresh after the genuine starter acquisition.
	await create_timer(1.0).timeout
	check(card_npc._player_in_range and triad.get_opponent_availability(card_npc.opponent_id).available, "real Triple Triad NPC is available with authored starter acquisition")
	await button("C")
	check(session.dialogue_service.is_active() and paused, "touch C opens real Triple Triad challenge conversation")
	await capture("mobile-portrait-card-challenge")
	await button("B")
	check(not session.dialogue_service.is_active() and not paused, "challenge cancellation retains existing dialogue ownership")
	await button("C")
	await button("A")
	await settle(8)
	check(triad.is_open() and paused, "C then canonical confirm opens real Triple Triad game")
	triad.close_game()
	await settle(3)
	check(not triad.is_open() and not paused, "real card-game close restores pause ownership")
	var merchant: Node3D = game.get_node("World/BeachMerchantNPC")
	player.global_position = merchant.global_position + Vector3(0.5, 0, 0)
	await settle(8)
	check(merchant._player_in_range, "merchant modal QA uses actual interaction range")
	merchant._start_interaction()
	await settle(4)
	check(paused and session.dialogue_service.is_active(), "real merchant dialogue opens")
	var dialogue = session.dialogue_controller.get_view()
	check(dialogue.body_label.get_theme_font_size("font_size") == 18 and dialogue.choice_label.get_theme_font_size("font_size") == 16, "mobile uses global larger dialogue baseline without another multiplier")
	var location_label: Label = game.get_node("UI/ExplorationHud").location_label
	for label in [dialogue.body_label, dialogue.speaker_label, dialogue.choice_label]:
		check(label.get_theme_font("font") == location_label.get_theme_font("font") and label.get_theme_color("font_color") == location_label.get_theme_color("font_color"), "dialogue uses Ocean Spot font and native glyph modulation: " + label.name)
		check(label.material == location_label.material and label.get_theme_constant("outline_size") == location_label.get_theme_constant("outline_size") and label.get_theme_color("font_shadow_color") == location_label.get_theme_color("font_shadow_color"), "dialogue matches Ocean Spot material/outline/shadow: " + label.name)
	check(not dialogue.has_node("Root/DialoguePanel/HintLabel"), "mobile production dialogue has no footer hints")
	check(dialogue.root.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "dialogue bitmap filtering stays nearest")
	check(Rect2(Vector2.ZERO, Vector2(harness.gameplay_viewport.size)).encloses(dialogue.dialogue_panel.get_rect()), "dialogue panel stays inside taller mobile viewport")
	check(dialogue.content_scroll.size.y >= dialogue.body_label.size.y + (dialogue.choice_label.size.y + 8.0 if dialogue.choice_label.visible else 0.0), "real merchant dialogue fits: scroll=%s body=%s choices=%s measured=%s/%s" % [dialogue.content_scroll.size, dialogue.body_label.size, dialogue.choice_label.size, dialogue.body_label.custom_minimum_size, dialogue.choice_label.custom_minimum_size])
	await capture("mobile-portrait-dialogue")
	await button("B")
	check(not paused and not session.dialogue_service.is_active(), "B cancels existing dialogue")
	merchant._start_interaction()
	await settle(4)
	await button("A")
	var economy = fishing.fishing_economy_menu
	check(economy.is_open() and paused, "A opens real merchant menu through existing dialogue choice")
	check(economy.root.size.is_equal_approx(Vector2(640, 480)), "merchant UI retains authored 640x480 geometry in taller viewport")
	check(economy.row_name_labels[0].get_theme_font_size("font_size") == 12 and economy.info_label.get_theme_font_size("font_size") == 12, "mobile economy uses targeted larger text, without changing global economy typography")
	for label in economy.row_name_labels + economy.row_owned_labels + economy.row_price_labels:
		check(label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x <= label.size.x, "real merchant row fits enlarged type: " + label.name)
	check(dialogue._text_height(economy.info_label, economy.info_label.size.x, "Black Bass 0/1\nBlue Gill 0/1\nPiranha 0/1\nNeed more fish.") <= economy.info_label.size.y, "multi-species owned/required details fit mobile economy info box")
	check(dialogue._text_height(economy.trade_requirements_label, economy.trade_requirements_label.size.x, "Black Bass x1\nBlue Gill x1\nPiranha x1") <= economy.trade_requirements_label.size.y, "three fish requirements fit widened mobile requirement box")
	await capture("mobile-portrait-merchant")
	await button("B")
	check(not economy.is_open() and not paused, "B closes real merchant menu with original pause ownership")
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
	var catch_view = fishing.fishing_catch_view
	var specimen := FishInstance.new()
	specimen.species = load("res://data/bof4/fish/sea_bream.tres")
	specimen.size = 32
	specimen.points = 25
	catch_view.show_catch(specimen, {"fishing_points": 125})
	await create_timer(0.5).timeout
	await capture("mobile-portrait-catch")
	check(catch_view.fish_name_label.text == "Sea Bream", "catch presentation retains actual fish data")
	catch_view.hide_catch()
	await create_timer(0.5).timeout
	# Reserved SELECT produces no key; L/R retain existing Q/E behavior.
	var before := observed_keys.size()
	await button("SELECT")
	check(observed_keys.size() == before, "SELECT explicitly reserved")
	await button("L")
	await button("R")
	check(observed_keys.has(KEY_Q) and observed_keys.has(KEY_E), "shoulders use existing Q/E keys")
	for mapping in {"L": &"cam_right", "R": &"cam_left"}:
		controls.touch_begin(61, controls.buttons[mapping].get_center())
		await settle(2)
		check(Input.is_action_pressed({"L": &"cam_right", "R": &"cam_left"}[mapping]), "shoulder activates canonical InputMap action " + mapping)
		controls.touch_end(61)
	controls.touch_begin(62, controls.stick_zone.get_center())
	controls.touch_drag(62, controls.stick_origin + Vector2(controls.stick_radius, 0))
	controls.touch_begin(63, controls.buttons["C"].get_center())
	controls.touch_begin(64, controls.buttons["A"].get_center())
	controls.touch_begin(65, controls.buttons["B"].get_center())
	await settle(2)
	check(observed_keys.has(KEY_C) and Input.is_physical_key_pressed(KEY_C) and controls.stick_touch == 62 and Input.is_action_pressed("move_right"), "C/A/B and stick retain independent simultaneous ownership")
	controls.touch_end(63)
	check(controls.touches.has(64) and controls.touches.has(65) and controls.stick_touch == 62, "C release does not release other fingers")
	controls.release_all()
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
