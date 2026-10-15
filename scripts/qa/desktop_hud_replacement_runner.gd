extends SceneTree
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
const HUD = preload("res://scripts/desktop/desktop_gameplay_hud.gd")
const HUD_FONT: Font = preload("res://assets/fonts/BOF_Font_Refined.fnt")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for frame in range(24): await process_frame

func check_actual_hud(shell: Node, expected_width: float, expected_mode: int, label: String) -> void:
	var hud: Control = shell.desktop_hud
	check(absf(hud.size.x - expected_width) < 1.1, "%s uses gameplay viewport width" % label)
	check(hud._hud_mode == expected_mode, "%s selects responsive mode" % label)
	var center_icon: TextureRect = hud.get_node("Fishing/Icon") as TextureRect
	check(absf(center_icon.get_global_rect().get_center().x - shell.image.get_global_rect().get_center().x) < 0.01,
		"%s medallion is hard centered" % label)
	var names := ["Location", "Weather", "Clock", "Fishing", "Wind", "Current", "Tide"]
	var boxes: Array[Rect2] = []
	for name in names:
		var slot: Control = hud.get_node(name) as Control
		var icon: TextureRect = slot.get_node("Icon") as TextureRect
		var box := icon.get_global_rect()
		boxes.append(box)
		check(icon.is_visible_in_tree() and hud.get_global_rect().encloses(box),
			"%s %s icon visible inside gameplay" % [label, name])
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			check(not boxes[i].intersects(boxes[j]), "%s icons %d/%d do not overlap" % [label, i, j])
	var expected_gap := 14.0 if expected_mode == HUD.HudMode.WIDE else (9.0 if expected_mode == HUD.HudMode.COMPACT else (10.0 if expected_width >= 400.0 else 7.0))
	for i in range(names.size() - 1):
		var first: Control = hud.get_node(names[i]) as Control
		var second: Control = hud.get_node(names[i + 1]) as Control
		check(absf(second.position.x - first.position.x - first.size.x - expected_gap) < 0.01,
			"%s uses equal logical gap %d" % [label, i])
	var expected_side := 64.0 if expected_mode == HUD.HudMode.WIDE else (46.0 if expected_mode == HUD.HudMode.COMPACT else (41.0 if expected_width >= 400.0 else 30.0))
	var expected_center := 90.0 if expected_mode == HUD.HudMode.WIDE else (72.0 if expected_mode == HUD.HudMode.COMPACT else (65.0 if expected_width >= 400.0 else 48.0))
	for i in range(names.size()):
		var icon: TextureRect = hud.get_node(names[i] + "/Icon") as TextureRect
		check(icon.size == Vector2.ONE * (expected_center if i == 3 else expected_side),
			"%s %s icon keeps mode size" % [label, names[i]])
		check(absf(icon.position.x + icon.get_parent().position.x - roundf(icon.position.x + icon.get_parent().position.x)) < 0.01,
			"%s %s icon is pixel aligned within gameplay" % [label, names[i]])
	for i in [0, 1, 2, 4, 5, 6]:
		var plaque: Panel = hud.get_node(names[i] + "/Plaque") as Panel
		var caption: Label = hud.get_node(names[i] + "/Value") as Label
		check(plaque.visible == (expected_mode != HUD.HudMode.MINIMAL)
			and caption.visible == (expected_mode != HUD.HudMode.MINIMAL),
			"%s %s caption follows mode" % [label, names[i]])
		if expected_mode != HUD.HudMode.MINIMAL:
			var paper: StyleBoxFlat = plaque.get_theme_stylebox("panel") as StyleBoxFlat
			check(paper.bg_color.get_luminance() > 0.5 and caption.get_theme_color("font_color").get_luminance() < 0.25,
				"%s %s caption has beige/dark contrast" % [label, names[i]])
			check(plaque.get_global_rect().encloses(caption.get_global_rect()),
				"%s %s caption inside beige plaque" % [label, names[i]])
			check(HUD_FONT.get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				caption.get_theme_font_size("font_size")).x <= caption.size.x + 0.5,
				"%s %s complete caption fits" % [label, names[i]])
	if expected_mode == HUD.HudMode.WIDE:
		check(hud.get_node("Tide").get_global_rect().end.x - hud.get_node("Location").get_global_rect().position.x <= 1050.0,
			"%s total HUD remains bounded" % label)
	check(hud.get_node("Fishing/HeadingAndAction").visible == (expected_mode != HUD.HudMode.MINIMAL),
		"%s numeric heading follows mode" % label)
	print("HUD_LAYOUT_SAMPLE " + JSON.stringify({"case": label, "viewport_width": hud.size.x,
		"mode": hud._hud_mode, "medallion_center": center_icon.get_global_rect().get_center().x,
		"viewport_center": shell.image.get_global_rect().get_center().x,
		"group_width": hud.get_node("Tide").get_global_rect().end.x - hud.get_node("Location").get_global_rect().position.x}))

func run() -> void:
	for frame in range(2): await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	for dimensions in [Vector2(320, 800), Vector2(480, 900), Vector2(800, 560), Vector2(1200, 860)]:
		var geometry: Dictionary = Layout.desktop(dimensions)
		check(geometry.info.size == Vector2.ZERO, "desktop has no duplicate information band %s" % dimensions)
		check(geometry.toolbar.position.y == 0.0 and geometry.world.position.y >= geometry.toolbar.end.y,
			"one header precedes gameplay %s" % dimensions)
		check(Rect2(Vector2.ZERO, dimensions).encloses(geometry.world), "world stays inside desktop %s" % dimensions)
	var shell: Node = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	current_scene = shell
	await settle()
	root.size = Vector2i(1200, 860)
	await settle()
	shell._layout()
	var old_hud: Node = shell.game.get_node("UI/ExplorationHud")
	var hud: Control = shell.desktop_hud
	var exploration: Node = shell.game.get_node("Game/Exploration")
	check(not old_hud.compass.visible and not old_hud.location.visible,
		"old location, compass and cast artwork hidden on desktop")
	check(old_hud.help_panel.visible, "bottom-left gameplay legend remains available")
	check(hud.visible and hud.get_child_count() == 7, "seven desktop indicators are present")
	check(not shell.shell.environment_strip.visible, "beige environment strip hidden")
	check(not shell.shell.dashboard.visible and shell.shell.regions.dashboard.size.y == 0.0,
		"normal exploration has no Equipment/Records footer")
	check(shell.shell.utility["Active"].visible and shell.shell.utility["Passive"].visible,
		"mode controls remain visible")
	for action in ["Dock Left", "Dock Right", "Float"]:
		check(shell.shell.utility[action].visible, "%s is directly visible" % action)
	shell.shell.utility["Passive"].pressed.emit()
	check(shell.mode == shell.Mode.PASSIVE, "visible Passive control changes the real companion mode")
	shell.shell.utility["Active"].pressed.emit()
	check(shell.mode == shell.Mode.ACTIVE, "visible Active control restores the real companion mode")
	var game_menu: FishingMenu = shell.game.find_child("FishingMenu", true, false) as FishingMenu
	shell.request_shell_menu("Inventory")
	await settle()
	check(game_menu.is_open() and game_menu._page == FishingMenu.Page.EQUIP,
		"existing equipment menu remains reachable")
	game_menu.close_menu()
	await settle()
	var expected: Dictionary = shell.shell.environment_strip.read_state(shell.shell._read_state())
	hud.refresh(expected)
	check(hud.state == expected, "HUD uses the existing environmental state adapter")
	for pair in [[0, "spot"], [1, "weather"], [4, "wind"], [5, "current"], [6, "tide"]]:
		check(hud.get_node(["Location", "Weather", "Clock", "Fishing", "Wind", "Current", "Tide"][pair[0]] + "/Value").text == str(expected.get(pair[1], "")),
			"%s shows the runtime value" % pair[1])
	var clock: Node = root.get_node("GameClock")
	check(hud.get_node("Clock/Value").text == "%02d:%02d" % [clock.get_hour(), clock.get_minute()],
		"clock shows real game time")
	for slot_name in ["Location", "Weather", "Clock", "Fishing", "Wind", "Current", "Tide"]:
		var icon: TextureRect = hud.get_node(slot_name + "/Icon") as TextureRect
		check(icon.is_visible_in_tree() and icon.texture != null and icon.texture.get_width() > 0
			and icon.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST,
			"%s artwork is imported, visible and pixel filtered" % slot_name)
	var fishing: Node = shell.game.get_node("Game/Fishing")
	var environment: Node = fishing.fishing_environment_service
	environment.enable_live_weather(false)
	for weather_id in ["rain", "tempest", "calm"]:
		environment.activate_condition(StringName(weather_id))
		await create_timer(0.35).timeout
		var live_state: Dictionary = shell.shell.environment_strip.read_state(shell.shell._read_state())
		check(hud.get_node("Weather/Value").text == str(live_state.weather),
			"%s displays the active authored weather" % weather_id)
		check(hud.get_node("Weather/Icon").texture == hud._weather_textures.get(weather_id, hud._weather_textures["clear"]),
			"%s selects its weather artwork" % weather_id)
	clock.advance_minutes(11)
	await create_timer(0.35).timeout
	var updated_state: Dictionary = shell.shell.environment_strip.read_state(shell.shell._read_state())
	check(hud.get_node("Clock/Value").text == "%02d:%02d" % [clock.get_hour(), clock.get_minute()],
		"clock updates from the live game service")
	for pair in [["Wind", "wind"], ["Current", "current"], ["Tide", "tide"]]:
		check(hud.get_node(pair[0] + "/Value").text == str(updated_state.get(pair[1], "")),
			"%s updates from the live environment adapter" % pair[0])
	var camera_rig: Node3D = shell.game.get_node("CameraRig") as Node3D
	var original_yaw := camera_rig.rotation.y
	camera_rig.rotation.y = 0.5
	hud._process(0.0)
	check(hud.get_node("Fishing/HeadingAndAction").text.ends_with("%03d°" % posmod(roundi(-rad_to_deg(camera_rig.rotation.y)), 360)),
		"medallion retains the original compass heading convention")
	camera_rig.rotation.y = original_yaw
	# The actual Exploration signal is the sole eligibility source for both HUDs.
	exploration.cast_availability_changed.emit(true)
	check(bool((hud.get_node("Fishing/Icon").material as ShaderMaterial).get_shader_parameter("grayscale")) == false,
		"fishing eligibility enables colored medallion")
	check(not old_hud.cast_ready_overlay.is_visible_in_tree(),
		"old fishing artwork stays hidden even when casting becomes available")
	exploration.cast_availability_changed.emit(false)
	check(bool((hud.get_node("Fishing/Icon").material as ShaderMaterial).get_shader_parameter("grayscale")),
		"fishing ineligibility grays medallion")
	for case in [
		[Vector2i(483, 900), shell.WindowState.DOCK_LEFT, 475.0, HUD.HudMode.MINIMAL, "left dock 475"],
		[Vector2i(483, 1200), shell.WindowState.DOCK_RIGHT, 475.0, HUD.HudMode.MINIMAL, "right tall dock 475"],
		[Vector2i(788, 600), shell.WindowState.FLOATING, 780.0, HUD.HudMode.COMPACT, "floating 780"],
		[Vector2i(1032, 800), shell.WindowState.FLOATING, 1024.0, HUD.HudMode.COMPACT, "medium 1024"],
		[Vector2i(1608, 1300), shell.WindowState.FLOATING, 1600.0, HUD.HudMode.WIDE, "maximized 1600"]
	]:
		root.size = case[0]
		shell.window_state = case[1]
		await settle()
		shell._layout()
		check_actual_hud(shell, case[2], case[3], case[4])
		check(hud.position == shell.image.position and hud.size == shell.image.size,
			"%s HUD follows protected gameplay viewport" % case[4])
		check(not old_hud.compass.is_visible_in_tree() and not old_hud.location.is_visible_in_tree(),
			"%s duplicate gameplay artwork remains hidden" % case[4])
		if shell.docked:
			check(absf(shell.image.position.y - shell.shell.regions.toolbar.end.y - 3.0) < 0.01,
				"%s game anchored below shell header" % case[4])
	hud.size.x = 1080.0
	check(hud._hud_mode == HUD.HudMode.COMPACT, "wide exits below its retention band")
	hud.size.x = 1098.0
	check(hud._hud_mode == HUD.HudMode.COMPACT, "compact holds near wide breakpoint")
	hud.size.x = 1114.0
	check(hud._hud_mode == HUD.HudMode.WIDE, "wide enters beyond its margin")
	hud.size.x = 650.0
	check(hud._hud_mode == HUD.HudMode.MINIMAL, "minimal enters below compact breakpoint")
	hud.size.x = 690.0
	check(hud._hud_mode == HUD.HudMode.MINIMAL, "minimal holds near compact breakpoint")
	hud.size.x = 700.0
	check(hud._hud_mode == HUD.HudMode.COMPACT, "compact reenters beyond its margin")
	hud.size.x = 180.0
	check(hud._hud_mode == HUD.HudMode.MINIMAL, "extreme-width fallback stays icon only")
	check(absf(hud.get_node("Fishing/Icon").get_global_rect().get_center().x - hud.get_global_rect().get_center().x) < 0.01,
		"extreme-width fallback keeps medallion centered")
	for name in ["Location", "Weather", "Clock", "Fishing", "Wind", "Current", "Tide"]:
		check(hud.get_global_rect().encloses(hud.get_node(name + "/Icon").get_global_rect()),
			"extreme-width fallback contains %s" % name)
	shell._layout()
	current_scene = null
	shell.queue_free()
	await settle()
	var orphans := Node.get_orphan_node_ids()
	print("DESKTOP HUD REPLACEMENT: %d/%d %s" % [checks - failures.size(), checks, failures])
	Isolation.emit_result("desktop_hud_replacement_runner", checks - failures.size(), checks, failures.size(), orphans.size())
	quit(0 if failures.is_empty() and orphans.is_empty() else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
