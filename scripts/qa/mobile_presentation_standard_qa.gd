extends SceneTree
const Shell = preload("res://actors/mobile/MobilePortraitHarness.tscn")
const Families = preload("res://scripts/world/world_shadow_families.gd")
var checks := 0
var failures: Array[String] = []
var shell: Control
var rendered := false
var captures := "build/presentation-standard-captures"

func _initialize() -> void:
	rendered = OS.get_cmdline_user_args().has("--rendered")
	var isolated := "CodexPresentationStandardQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated): quit(1); return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(captures)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func settle() -> void:
	for i in 8: await process_frame
	await physics_frame

func capture(label: String) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(captures.path_join(label + ".png")) == OK, "rendered " + label)

func inspect_view(view: ResponsiveMenuSurface, label: String) -> void:
	await settle()
	check(view.size.x == 608 and view.size.y == shell.overlay_viewport.size.y - 24, label + " uses independent menu viewport")
	for binding in view.bindings:
		var text: Label = binding.label
		check(text.get_theme_font_size("font_size") >= 18 and text.get_theme_font("font") == view.FONT, label + " approved type " + str(text.get_index()))
		check(text.scale.is_equal_approx(Vector2.ONE), label + " type never scaled down")
	check(view.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, label + " nearest artwork/filter")
	check(view.stack.get_child(0).get_theme_stylebox("panel") is StyleBoxTexture, label + " shared tiled Panel.png")
	var original_size: Vector2i = shell.overlay_viewport.size
	shell.overlay_viewport.size = Vector2i(640, 360)
	await settle()
	check(view.scroll.get_v_scroll_bar().max_value > view.scroll.size.y, label + " short viewport scrolls instead of shrinking fonts")
	var scroll_before := view.scroll.scroll_vertical
	var touch := InputEventScreenTouch.new()
	touch.index = 95
	touch.pressed = true
	touch.position = shell.gameplay_window.global_position + shell.gameplay_window.size * Vector2(0.90, 0.35)
	shell._unhandled_input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 95
	drag.position = touch.position - Vector2(0, 40)
	shell._unhandled_input(drag)
	await settle()
	check(view.scroll.scroll_vertical > scroll_before, label + " real shell touch gutter reaches shared scrolling")
	touch.pressed = false
	shell._unhandled_input(touch)
	shell.overlay_viewport.size = original_size
	await settle()
	view.scroll.scroll_vertical = 0
	await capture(label)

func run() -> void:
	shell = Shell.instantiate()
	shell.isolated_playtest_save = false
	root.add_child(shell)
	current_scene = shell
	await settle()
	await create_timer(1).timeout
	var game: Node = shell.game
	var fishing: Node = game.get_node("Game/Fishing")
	var reference: Dictionary = shell.get_layout_rects(shell.get_safe_rect(Vector2(390,844)))
	check(reference.resolution == Vector2i(640,480), "iPhone 13 Pro uses fixed canonical 640x480 gameplay")
	check(reference.controls.size.y >= 236 and reference.controls.end.y == 810, "comfortable controls and home clearance")
	for key in shell.controls.buttons:
		var hit: Rect2 = shell.controls.buttons[key]
		check(hit.size.x >= 44 and hit.size.y >= 44 and Rect2(Vector2.ZERO, shell.controls.size).encloses(hit), "44px contained target " + key)
	var economy: Node = fishing.fishing_economy_menu
	economy.open_debug_full_catalog_menu()
	await inspect_view(economy.root.get_node("ResponsiveMenuSurface"), "merchant")
	var old_row: int = economy._row_index
	economy._move_selection(1)
	await settle()
	var view: ResponsiveMenuSurface = economy.root.get_node("ResponsiveMenuSurface")
	check(economy._row_index != old_row and view.bindings[2].label.text != "", "controller selection updates read-only responsive list")
	economy.close_menu()
	check(economy._open_menu_in_mode(economy.MODE_TRADE, null, null, true), "real fish trade controller opens")
	await inspect_view(economy.root.get_node("ResponsiveMenuSurface"), "fish-trade")
	check(not economy._current_page_entries().is_empty(), "authored trade list populated")
	var authored_requirement: String = economy.trade_requirements_label.text
	check(not authored_requirement.is_empty(), "exact recipe species/counts available")
	var mirrored := false
	for binding in view.bindings:
		if binding.paths.has("TradeRequirementsPanel/Requirements"): mirrored = binding.label.text == authored_requirement
	check(mirrored, "responsive fish requirements come from controller recipe output")
	economy.close_menu()
	var crafter := game.get_node("World/BeachCrafterNPC/BeachCraftingMenu")
	check(crafter.open_menu(), "real crafting menu opens")
	await inspect_view(crafter.root.get_node("ResponsiveMenuSurface"), "crafting")
	crafter.close_menu()
	var maker := game.get_node("World/FishingCardMakerNPC/FishingCardMakerMenu")
	check(maker.open_menu(), "real card crafting menu opens")
	await inspect_view(maker.root.get_node("ResponsiveMenuSurface"), "card-crafting")
	maker.close_menu()
	var triad := game.get_node("UI/TripleTriadGame")
	triad.open_game_by_id(game.get_node("World/TripleTriadOpponentNPC").opponent_id)
	await settle()
	check(triad.deck_setup.COLLECTION_SCALE == Vector2.ONE and triad.deck_setup.PAGE_SIZE == 10, "shared deck uses native cards and ten-card pages")
	await capture("deck")
	check(triad.deck_setup._deck.size() == 5 and triad.deck_setup.mobile_start_enabled, "empty real collection has valid transient hand and mobile START")
	var start := InputEventKey.new()
	start.pressed = true
	start.physical_keycode = KEY_SPACE
	check(triad.deck_setup._is_start(start), "mobile Space uses original deck confirmation")
	triad.close_game()
	await settle()
	var patrol_actor := game.get_node("World/FishingCardMakerNPC") as Node3D
	patrol_actor._begin_next_patrol_leg()
	var patrol_start := patrol_actor.global_position
	await create_timer(0.7).timeout
	check(not patrol_actor.global_position.is_equal_approx(patrol_start), "Card Maker actual collision-safe patrol still moves")
	check(patrol_actor.get_node("WorldMarkerAnchor").global_position.is_equal_approx(patrol_actor.global_position + Vector3.UP * 0.72), "marker follows actual moving patrol root")
	# Shared family mutation is runtime only. Restore resources before leaving QA.
	var humanoid: WorldShadowFamily = Families.resolve(&"humanoid_standard")
	var old_width := humanoid.width
	var old_depth := humanoid.depth
	var player := game.get_node("Player/CharacterBody3D/GroundPresentation") as GroundPresentation
	var player_width := player.shadow.width
	humanoid.width *= 1.2
	humanoid.depth *= 1.2
	await settle()
	for p in game.find_children("GroundPresentation", "Node3D", true, false):
		if p.profile != null and p.profile.resolved_shadow_family() == humanoid:
			check(is_equal_approx(p.shadow.width, humanoid.width * p.profile.shadow_scale_multiplier), "family propagates to " + String(p.get_parent().name))
	check(player.shadow.width == player_width, "player independent of humanoid tuning")
	var npc := game.get_node("World/FishingCardMakerNPC") as Node3D
	var ground := npc.get_node("GroundPresentation") as GroundPresentation
	var old_profile := ground.profile
	ground.profile = old_profile.duplicate()
	ground.profile.shadow_scale_multiplier = 1.15
	await settle()
	check(is_equal_approx(ground.shadow.width, humanoid.width * 1.15), "reusable profile multiplier propagates")
	ground.profile = old_profile
	humanoid.width = old_width
	humanoid.depth = old_depth
	await settle()
	var camera: Camera3D = shell.gameplay_viewport.get_camera_3d()
	for actor_path in ["World/FishingCardMakerNPC", "World/BeachCrafterNPC", "World/HarborRequestBoard"]:
		var actor := game.get_node(actor_path) as Node3D
		actor.set_physics_process(false)
		var anchor := actor.get_node("WorldMarkerAnchor") as WorldMarkerAnchor
		actor.position += Vector3(0.12,0,0.08)
		await settle()
		check(anchor.global_position.is_equal_approx(actor.global_position + Vector3.UP * anchor.height), actor_path + " root follows moved actor")
		var marker := actor.get_node("RequestMarker") as Node3D
		marker.set_request_state(&"available")
		marker.get_node("Label3D").visible = true
		var before := marker.global_position
		var shadow_before: Transform3D = actor.get_node("GroundPresentation/ShadowAnchor/WorldBlobShadow").global_transform
		for turn in 8:
			camera.global_position = actor.global_position + Vector3(sin(turn*PI/4)*1.6,1.0,cos(turn*PI/4)*1.6)
			camera.look_at(actor.global_position + Vector3.UP * 0.3)
			await settle()
			check(marker.global_position.is_equal_approx(before), actor_path + " fixed marker orbit " + str(turn))
			check(actor.get_node("GroundPresentation/ShadowAnchor/WorldBlobShadow").global_transform.is_equal_approx(shadow_before), actor_path + " fixed family shadow orbit " + str(turn))
			if turn % 2 == 0: await capture(actor.name + "-orbit-" + str(turn))
	shell.free()
	await inspect_desktop()
	print("Mobile Presentation Standard QA: %d/%d passed" % [checks-failures.size(), checks])
	quit(0 if failures.is_empty() else 1)

func inspect_desktop() -> void:
	current_scene = null
	root.content_scale_size = Vector2i(640,480)
	root.size = Vector2i(640,480)
	var desktop: Node = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(desktop)
	current_scene = desktop
	await settle()
	var economy: Node = desktop.get_node("Game/Fishing").fishing_economy_menu
	economy.open_debug_full_catalog_menu()
	await settle()
	check(economy.root.has_node("ResponsiveMenuSurface") and economy.root.get_node("ResponsiveMenuSurface").size == Vector2(608,456), "desktop merchant fits 4:3 overlay; shell menus retain a separate canvas")
	await capture("desktop-merchant")
	economy.close_menu()
	var crafter: Node = desktop.get_node("World/BeachCrafterNPC/BeachCraftingMenu")
	crafter.open_menu()
	await settle()
	check(crafter.root.has_node("ResponsiveMenuSurface"), "desktop crafting uses shared portrait composition")
	await capture("desktop-crafting")
	crafter.close_menu()
	var maker: Node = desktop.get_node("World/FishingCardMakerNPC/FishingCardMakerMenu")
	maker.open_menu()
	await settle()
	check(maker.root.has_node("ResponsiveMenuSurface"), "desktop card crafting uses shared portrait composition")
	await capture("desktop-card-crafting")
	maker.close_menu()
	var triad: Node = desktop.get_node("UI/TripleTriadGame")
	triad.open_game_by_id(desktop.get_node("World/TripleTriadOpponentNPC").opponent_id)
	await settle()
	check(not triad.deck_setup.mobile_start_enabled and not triad.deck_setup.has_node("ResponsiveMenuSurface"), "desktop deck uses same native-card layout without touch key override")
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	check(triad.deck_setup._is_start(enter), "desktop Enter confirmation retained")
	enter.physical_keycode = KEY_SPACE
	check(not triad.deck_setup._is_start(enter), "desktop Space mapping unchanged")
	await capture("desktop-deck")
	triad.close_game()
	desktop.free()
