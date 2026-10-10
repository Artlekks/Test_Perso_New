extends SceneTree
const Surface = preload("res://scripts/ui/canonical_game_surface.gd")
const UI = preload("res://scripts/ui/portrait_ui.gd")
var checks := 0
var failures: Array[String] = []
var fixture: SessionTestFixture
var rendered := false
var mobile := false
var captures := "res://build/mobile-web/portrait-captures"

func _initialize() -> void:
	rendered = OS.get_cmdline_user_args().has("--rendered")
	mobile = OS.get_cmdline_user_args().has("--mobile")
	var isolated := "CodexCanonicalPortraitQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(captures)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func settle(count := 12) -> void:
	for i in range(count): await process_frame

func capture(game: Node, label: String) -> void:
	if not rendered: return
	await RenderingServer.frame_post_draw
	check(game.get_viewport().get_texture().get_image().save_png(captures.path_join(("mobile-" if mobile else "desktop-") + label + ".png")) == OK, "rendered " + label)
	if mobile:
		check(root.get_texture().get_image().save_png(captures.path_join("phone-" + label + ".png")) == OK, "rendered scaled phone " + label)

func fonts(surface: Node, label: String) -> void:
	for text in surface.find_children("*", "Label", true, false):
		if not text.is_visible_in_tree() or text.get_global_transform_with_canvas().get_scale().length() == 0: continue
		if text.get_meta("portrait_authored_hidden", false): continue
		check(text.get_theme_font_size("font_size") >= 18, label + " >=18px " + str(text.get_path()))
		check(text.scale == Vector2.ONE, label + " unscaled text " + str(text.name))
		var effective: Vector2 = text.get_global_transform_with_canvas().get_scale()
		check(is_equal_approx(effective.x,effective.y), label + " uniform effective text scale " + str(text.name))

func cards_inside(views: Array, surface: Node, label: String) -> void:
	var ancestor := surface
	while ancestor != null and not ancestor is CanvasLayer: ancestor = ancestor.get_parent()
	var canvas: Viewport = ancestor.custom_viewport if ancestor is CanvasLayer and ancestor.custom_viewport != null else surface.get_viewport()
	for card in views:
		if not card.visible: continue
		var transform: Transform2D = card.get_global_transform_with_canvas()
		var rect := Rect2(transform.origin, card.size * transform.get_scale())
		check(Rect2(Vector2.ZERO, canvas.get_visible_rect().size).encloses(rect), label + " unclipped " + str(card.name) + str(rect))
		check(is_equal_approx(transform.get_scale().x,transform.get_scale().y), label + " uniform card pixels")

func run() -> void:
	if not mobile:
		root.content_scale_size = Surface.SIZE
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.size = Surface.SIZE
	fixture = SessionTestFixture.new()
	fixture.mount(self, mobile, true)
	await settle(30)
	var game: Node = fixture.scene.game if mobile else fixture.scene
	check(game.get_viewport().get_visible_rect().size == Vector2(Surface.SIZE), "authoritative 640x480 world")
	if mobile:
		var layout: Dictionary = fixture.scene.get_layout_rects(Rect2(0,47,390,763))
		check(layout.resolution == Surface.SIZE, "phone cannot change game geometry")
		check(layout.gameplay.size.is_equal_approx(Vector2(378,283.5)), "reference framed iPhone game 378x283.5 CSS pixels")
		check(is_equal_approx(layout.controls.position.y,layout.gameplay.end.y+6) and layout.controls.end.y == 810, "touch shell separate and safe")
		for hit in fixture.scene.controls.buttons.values(): check(hit.size.x >= 44 and hit.size.y >= 44, "phone practical touch target")
		var short: Dictionary = fixture.scene.get_layout_rects(Rect2(0,47,390,583))
		check(short.resolution == Surface.SIZE and short.controls.size.x == 390, "short Safari keeps canonical pixels and full-width controls")
		check(short.gameplay.size.is_equal_approx(Vector2(378,283.5)) and short.display.size.is_equal_approx(Vector2(378,283.5)), "short Safari uses full uncropped 4:3 world")
		var original_controls: Vector2 = fixture.scene.controls.size
		var original_landscape: bool = fixture.scene.controls.landscape
		fixture.scene.controls.landscape = false
		fixture.scene.controls.size = short.controls.size
		fixture.scene.controls._layout()
		for label in fixture.scene.controls.buttons:
			for other in fixture.scene.controls.buttons:
				if label < other: check(not fixture.scene.controls.buttons[label].intersects(fixture.scene.controls.buttons[other]), "short Safari touch targets separated: " + label + "/" + other)
		for hit in fixture.scene.controls.buttons.values():
			check(hit.size.x >= 44 and hit.size.y >= 44 and Rect2(Vector2.ZERO, short.controls.size).encloses(hit), "short Safari retains contained 44px targets")
		fixture.scene.controls.landscape = original_landscape
		fixture.scene.controls.size = original_controls
		fixture.scene.controls._layout()
	DeveloperPlaytestService.current().set_enabled(true)
	var triad := game.get_node("UI/TripleTriadGame")
	var input_policy = load("res://scripts/triple_triad/triple_triad_input_controller.gd").new()
	check(input_policy.action_for_event(key(KEY_R),false) == input_policy.ACTION_ROTATE, "desktop R retains rotation action")
	check(input_policy.action_for_event(key(KEY_E),false) == input_policy.ACTION_ROTATE, "unchanged shell R/E reaches same rotation action")
	check(triad.open_game_by_id(game.get_node("World/TripleTriadOpponentNPC").opponent_id), "canonical deck opens through provider")
	await settle()
	var deck: Control = triad.deck_setup
	check(deck.PAGE_SIZE == 10 and deck._collection_views.size() == 10, "ten-card collection pagination")
	cards_inside(deck._deck_views, deck, "deck")
	cards_inside(deck._collection_views, deck, "collection")
	fonts(deck, "deck")
	check(deck._is_start(key(KEY_ENTER)), "desktop Enter confirms deck")
	if mobile: check(deck._is_start(key(KEY_SPACE)), "shell START uses original confirmation")
	await capture(game, "deck")
	var before: Array = deck._deck.duplicate()
	deck._enter_collection_for_profile(deck._profile_index)
	check(deck._nav_zone == deck.NAV_DECK, "entering Deck focuses slots")
	deck._deck_cursor_index = 0
	deck._unhandled_input(key(KEY_K))
	check(deck._nav_zone == deck.NAV_COLLECTION, "select slot focuses collection")
	check(deck._deck == before, "browsing slot preserves ownership/composition")
	triad._on_deck_confirmed(deck._deck.duplicate())
	await create_timer(2).timeout
	await settle()
	cards_inside(triad._presentation.get_player_views(), triad, "player hand")
	cards_inside(triad._presentation.get_opponent_views(), triad, "opponent hand")
	cards_inside(triad._presentation.get_board_views(), triad, "board")
	fonts(triad.get_node("Root/TripleTriadMatchHUD"), "battle")
	await capture(game, "battle")
	triad.close_game()
	var reward := game.get_node("UI/TripleTriadGame/Root/TripleTriadRewardView")
	for winner in [1,2,0]:
		reward.open_reward(before, before, winner, true)
		reward._refresh_rows()
		# Observe the established entrance's final geometry without new rewards.
		for i in range(5):
			reward._opponent_views[i].position = Vector2(i * reward.ROW_STEP_X,0)
			reward._player_views[i].position = Vector2(i * reward.ROW_STEP_X,0)
		triad.get_node("Root").show()
		await settle()
		cards_inside(reward._opponent_views, reward, "result top")
		cards_inside(reward._player_views, reward, "result bottom")
		fonts(reward, "result")
		await capture(game, "result-" + str(winner))
		reward.close_reward()
	triad.get_node("Root").hide()
	await deck_edit_contract(game, triad)
	var fishing := game.get_node("Game/Fishing")
	var economy: Node = fishing.fishing_economy_menu
	economy.open_debug_full_catalog_menu()
	await menu(game, economy.root, "merchant")
	economy.close_menu()
	economy._open_menu_in_mode(economy.MODE_TRADE, null, null, true)
	await menu(game, economy.root, "fish-trade")
	economy.close_menu()
	for path in ["World/BeachCrafterNPC/BeachCraftingMenu", "World/FishingCardMakerNPC/FishingCardMakerMenu"]:
		var controller := game.get_node(path)
		check(controller.open_menu(), path + " opens existing controller")
		await menu(game, controller.root, controller.name)
		controller.close_menu()
	fishing.fishing_menu.open_menu()
	await menu(game, fishing.fishing_menu.root, "inventory")
	fishing.fishing_menu.close_menu()
	if not mobile:
		# Real window stretch test: size changes while the logical canvas does not.
		for window_size in [Vector2i(1280,864),Vector2i(1920,1080)]:
			root.size = window_size
			await settle()
			check(root.get_visible_rect().size == Vector2(Surface.SIZE), "wide/fullscreen retains same logical composition")
			var scale := root.get_final_transform().get_scale()
			check(is_equal_approx(scale.x, scale.y), "fullscreen uniform letterboxing")
		await capture(game, "wide-window")
		if rendered:
			root.mode = Window.MODE_FULLSCREEN
			await settle(20)
			check(root.get_visible_rect().size == Vector2(Surface.SIZE), "actual fullscreen retains canonical canvas")
			var scale := root.get_final_transform().get_scale()
			# Godot rounds the letterboxed render rectangle to whole output pixels.
			# Its two reported scale factors may differ by that one pixel only.
			print("FULLSCREEN SCALE: ", scale, "; logical=", root.get_visible_rect().size)
			check(absf(scale.x - scale.y) * 480.0 <= 1.0, "actual fullscreen uniform within one output-pixel quantization")
			await capture(game, "fullscreen")
			root.mode = Window.MODE_WINDOWED
	fixture.release()
	await settle()
	check(Node.get_orphan_node_ids().is_empty(), "shared presentation releases with controllers")
	print("Canonical Portrait QA (%s%s): %d/%d" % ["mobile" if mobile else "desktop", " rendered" if rendered else "",checks-failures.size(),checks])
	quit(0 if failures.is_empty() else 1)

func menu(game: Node, authored: Control, label: String) -> void:
	await settle()
	var view: Control = authored.get_node("ResponsiveMenuSurface")
	var layer: CanvasLayer = authored.get_parent()
	var canvas: Viewport = layer.custom_viewport if layer.custom_viewport != null else game.get_viewport()
	check(view.size == canvas.get_visible_rect().size - Vector2(32,24), label + " fits independent menu canvas")
	check(view.is_set_as_top_level(), label + " does not inherit legacy root animation transforms")
	fonts(view, label)
	check(view.stack.get_child(0).get_theme_stylebox("panel") == UI.panel_style(), label + " shared Panel.png")
	await capture(game, label)

func deck_edit_contract(game: Node, triad: Node) -> void:
	# Disposable owned-card fixture. Exercise the production slot/replacement,
	# pagination and save operations, rather than merely checking card rectangles.
	var collection = load("res://scripts/triple_triad/triple_triad_collection.gd").new()
	collection.initialize(triad.card_catalog, triad.acquisition_policy)
	var candidates: Array = triad.card_catalog.get_cards_for_level_range(1,6).filter(func(card): return card.deck_cost <= 5)
	check(candidates.size() >= 15, "owned-card UI fixture has at least two pages")
	if candidates.size() < 15: return
	for card in candidates.slice(0,15): collection.acquire_card(card,1,false)
	check(collection.save_state() == OK, "isolated owned-card fixture committed")
	var editor: Control = load("res://actors/TripleTriadDeckSetup.tscn").instantiate()
	var game_ui: Control = triad.get_node("Root")
	var was_visible := game_ui.visible
	game_ui.add_child(editor)
	game_ui.show()
	editor.open_setup(triad.card_catalog,30,6,collection,triad.acquisition_policy)
	editor._enter_collection_for_profile(0)
	editor._deck = candidates.slice(0,5)
	editor._refresh_all()
	var before: Array = editor._deck.duplicate()
	var ownership: Dictionary = collection.get_quantities_snapshot()
	editor._deck_cursor_index = 2
	editor._unhandled_input(key(KEY_K))
	check(editor._nav_zone == editor.NAV_COLLECTION and editor._slot_replacement_requested == 2, "slot three selects replacement target")
	editor._cursor_index = editor._cards.find(candidates[5])
	editor._page_index = floori(editor._cursor_index / float(editor.PAGE_SIZE))
	editor._refresh_all()
	editor._unhandled_input(key(KEY_K))
	await create_timer(0.8).timeout
	check(editor._deck[2] == candidates[5] and editor._deck[0] == before[0] and editor._deck[4] == before[4], "production replacement updates exactly selected slot")
	check(editor._nav_zone == editor.NAV_DECK, "replacement returns focus to deck")
	check(collection.get_quantities_snapshot() == ownership, "deck edit never changes owned quantities")
	editor._return_to_collection()
	editor._page_index = 0
	editor._cursor_index = 0
	editor._refresh_all()
	editor._unhandled_input(key(KEY_E))
	await settle()
	check(editor._page_index > 0, "owned collection advances through ten-card pages")
	cards_inside(editor._collection_views, editor, "owned collection page")
	await capture(game, "owned-deck-page")
	editor.close_setup()
	editor.open_setup(triad.card_catalog,30,6,collection,triad.acquisition_policy)
	check(editor._deck[2] == candidates[5], "reopening reproduces saved replacement")
	editor.close_setup()
	editor.free()
	game_ui.visible = was_visible

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = code
	return event
