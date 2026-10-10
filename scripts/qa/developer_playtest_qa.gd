extends SceneTree
var checks := 0
var failures: Array[String] = []
var shell: Node
func _initialize() -> void:
	var isolated := "CodexDeveloperPlaytestQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated): quit(1); return
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func bytes_snapshot() -> Dictionary:
	var result := {}
	var dir := DirAccess.open("user://")
	for file in dir.get_files(): result[file] = FileAccess.get_file_as_bytes("user://" + file)
	return result
func settle() -> void:
	await create_timer(0.7).timeout
func run() -> void:
	shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	shell.isolated_playtest_save = false
	root.add_child(shell)
	preload("res://scripts/qa/mobile_qa_canvas.gd").prepare(self)
	current_scene = shell
	await settle()
	var developer := DeveloperPlaytestService.current()
	check(developer.enabled and developer.indicator.visible, "mobile defaults ON with DEV visible")
	developer.set_enabled(false)
	await settle()
	var session := root.get_node("FishingSessionServices")
	var locations := root.get_node("WorldLocations")
	var game: Node = shell.game.get_node("UI/TripleTriadGame")
	var npc: Node = shell.game.get_node("World/TripleTriadOpponentNPC")
	check(not game.is_card_game_unlocked() and not npc.interaction_area.monitoring, "fresh normal cards locked")
	check(not locations.get_access_snapshot(&"lyp_lake_outpost").unlocked, "normal Lake locked")
	var gated_lesson: Resource = null
	for technique in session.mastery_service._catalog.techniques:
		if not technique.prerequisite_ids.is_empty(): gated_lesson = technique; break
	check(gated_lesson != null and not session.mastery_service.can_learn(gated_lesson.technique_id, gated_lesson.teacher_id).can_learn, "normal authored master prerequisite locked")
	var access: Node = session.economy_access
	var original_context: Dictionary = access.get_access_context_snapshot()
	access.set_access_context(PackedStringArray(["faerie_diligent"]))
	check(access.buy_one(&"faerie_bamboo_rod").reason == "availability_locked", "normal authored shop progression tag locked")
	var before := bytes_snapshot()
	var inventory_before: Dictionary = session.inventory.create_transaction_snapshot()
	developer.set_enabled(true)
	await settle()
	check(game.is_card_game_unlocked() and npc.interaction_area.monitoring, "DEV cards and campaign interaction available without case")
	check(game.get_opponent_availability(npc.opponent_id).available, "authored opponent available")
	check(session.mastery_service.can_learn(gated_lesson.technique_id, gated_lesson.teacher_id).can_learn, "DEV opens prerequisite-gated lesson without granting mastery")
	var rows: Array = access.get_buy_entries()
	var faerie_row: Dictionary = {}
	for row in rows:
		if str(row.id) == "faerie_bamboo_rod": faerie_row = row
	check(not faerie_row.is_empty() and faerie_row.reason != "availability_locked", "DEV bypasses shop access tag")
	check(access.buy_one(&"lyp_popper").reason == "shop_not_available", "DEV cannot fabricate provider scope")
	check(access.trade_one(&"lyp_crab").reason == "shop_not_available", "DEV cannot fabricate trade source")
	for location in locations.get_all_locations(): check(locations.get_access_snapshot(location.location_id).unlocked, "DEV authored access " + String(location.location_id))
	var blank := FishingInventory.new()
	check(not locations.get_access_snapshot(&"lyp_lake_outpost", blank).unlocked, "explicit progression snapshot stays pure")
	blank.free()
	locations._refresh_unlocks()
	check(bytes_snapshot() == before, "toggle + unlock refresh leaves all save bytes unchanged")
	check(session.inventory.create_transaction_snapshot() == inventory_before, "no inventory/loadout from toggle")
	check(not locations.get_access_snapshot(&"missing_location").unlocked and not locations.request_travel(&"missing_location").success, "DEV rejects nonexistent content")
	check(not developer.grant_loadout("wallet").success, "QA/production profile loadout blocked")
	var player: Node3D = shell.game.get_node("Player/CharacterBody3D")
	player.global_position = npc.global_position + Vector3(0, 0, 0.35)
	player.rotation.y = PI
	await settle()
	shell.controls.touch_begin(77, shell.controls.buttons.C.get_center())
	await process_frame
	shell.controls.touch_end(77)
	await settle()
	check(session.dialogue_service.is_active(), "actual mobile C opens card conversation in DEV without case")
	if session.dialogue_service.is_active():
		shell.controls.touch_begin(78, shell.controls.buttons.A.get_center())
		await process_frame
		shell.controls.touch_end(78)
		await settle()
		check(game.is_open(), "A confirms actual card game entry without granting inventory")
		check(game.deck_setup.developer_test_deck.size() == 5 and game.deck_setup._deck.size() == 5, "empty real collection gets exactly five temporary legitimate cards")
		var deck_before := bytes_snapshot()
		game.deck_setup._enter_collection_for_profile(0)
		check(game.deck_setup._nav_zone == game.deck_setup.NAV_DECK, "saved deck entry focuses five slots")
		# Exercise the existing collection add/remove path after slot-first entry.
		game.deck_setup._return_to_collection()
		game.deck_setup._cursor_index = 4
		shell.controls.touch_begin(86, shell.controls.buttons.A.get_center())
		await settle()
		shell.controls.touch_end(86)
		await create_timer(0.6).timeout
		check(game.deck_setup._deck.size() == 4, "real mobile A removes last temporary card")
		shell.controls.touch_begin(87, shell.controls.buttons.A.get_center())
		await settle()
		shell.controls.touch_end(87)
		await create_timer(0.6).timeout
		check(game.deck_setup._deck.size() == 5, "real mobile A selects fifth card before START")
		shell.shell.shortcut.pressed.emit()
		await settle()
		check(game._session.phase != game.PHASE_DECK_SETUP, "temporary deck starts normal match")
		check(game._live_match.get_starting_player_cards().size() == 5, "normal match uses five borrowed cards")
		check(game._collection_backend.get_owned_cards().is_empty(), "borrowed match does not mutate real collection")
		game._finish_match(game.OWNER_OPPONENT, &"surrender")
		game._begin_result_transition()
		check(bytes_snapshot() == deck_before, "temporary match/start/result/close never saves borrowed cards or stakes")
		game.open_game_by_id(npc.opponent_id)
		check(game.is_open() and game.deck_setup.developer_test_deck.size() == 5, "fallback can be reopened without permanent grant")
		developer.set_enabled(false)
		check(not game.is_open() and game.deck_setup.developer_test_deck.is_empty(), "DEV OFF immediately releases temporary deck/session")
		check(bytes_snapshot() == deck_before and game._collection_backend.get_owned_cards().is_empty(), "DEV OFF leaves real collection and save bytes unchanged")
		game.close_game()
	await settle()
	developer.set_enabled(false)
	await settle()
	check(not game.is_card_game_unlocked() and not npc.interaction_area.monitoring, "OFF restores underlying card lock")
	check(not locations.get_access_snapshot(&"lyp_lake_outpost").unlocked, "OFF restores Lake lock")
	check(not session.mastery_service.can_learn(gated_lesson.technique_id, gated_lesson.teacher_id).can_learn, "OFF restores lesson prerequisite lock")
	check(access.buy_one(&"faerie_bamboo_rod").reason == "availability_locked", "OFF restores shop tag restriction")
	access.set_access_context(original_context.shop_ids, original_context.trade_shop_ids, original_context.availability, original_context.full_catalog_access, original_context.trade_recipe_ids)
	check(game.get_acquisition_snapshot().claimed_bundle_ids.is_empty(), "no case or bundle permanently claimed")
	# Scene replacement must retain service and access mode through the host.
	developer.set_enabled(true)
	for id in [&"wyndia_ocean_outpost", &"lyp_lake_outpost", &"river_fishing_outpost", &"chiqua_supply_outpost", &"beach"]:
		var result: Dictionary = locations.request_travel(id)
		check(result.success, "normal transition request " + String(id))
		await settle()
		check(locations.current_location.location_id == id and developer.enabled, "scene handoff retains session mode " + String(id))
	var aim_before: bool = shell.game.get_node("Game/Fishing").debug_controller._aim.active
	shell.request_shell_menu("Settings")
	await settle()
	shell.game.get_node("Game/Fishing").fishing_menu.options_page.get_node("PlaytestTools").pressed.emit()
	await settle()
	var menu: Node = shell.game.get_node("Game/Fishing").debug_controller.debug_menu
	check(menu.is_open() and paused, "Settings tools opens modal existing F10 menu during exploration")
	check(menu._playtest_page and menu._playtest_rows[0].text.contains("Developer Mode: ON"), "Developer Mode is initial top entry")
	shell.controls.touch_begin(83, shell.controls.buttons.A.get_center())
	await process_frame
	shell.controls.touch_end(83)
	await settle()
	check(not developer.enabled, "mobile A toggles Developer Mode OFF")
	shell.controls.touch_begin(84, shell.controls.buttons.A.get_center())
	await process_frame
	shell.controls.touch_end(84)
	await settle()
	check(developer.enabled, "mobile A toggles Developer Mode ON")
	menu._playtest_row = 1
	menu._playtest_activate()
	check(menu._travel_submenu, "A activation opens authored Travel To submenu")
	var back := InputEventKey.new()
	back.physical_keycode = KEY_I
	back.pressed = true
	check(not menu.handle_input(back) and not menu._travel_submenu and menu.is_open(), "B backs out of travel without closing F10")
	shell.shell.shortcut.pressed.emit()
	await settle()
	check(not menu._playtest_page, "START switches PLAYTEST to existing FISHING QA")
	menu._toggle_playtest_page()
	if OS.get_cmdline_user_args().has("--rendered"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("build/developer-playtest-menu.png")
	shell.controls.touch_begin(82, shell.controls.buttons.B.get_center())
	await process_frame
	shell.controls.touch_end(82)
	await settle()
	check(not menu.is_open() and not paused, "B closes F10 and restores exploration")
	check(shell.game.get_node("Game/Fishing").debug_controller._aim.active == aim_before, "exploration debug modal preserves fishing aim state")
	# Explicit loadout QA only after access-purity checks, in this unique save.
	developer.authorize_isolated_mobile_save(true)
	check(developer.grant_loadout("fishing").success, "explicit fishing loadout succeeds in disposable authorized save")
	var catalog = preload("res://data/bof4/catalogs/all_content.tres")
	for lure in catalog.tackle.lure_catalog.lures: check(session.inventory.get_lure_count(lure.lure_id) >= 2, "authored lure loadout " + String(lure.lure_id))
	for rod in catalog.tackle.rods: check(session.inventory.get_rod_count(rod.rod_id) >= 1, "authored rod loadout " + String(rod.rod_id))
	check(developer.grant_loadout("wallet").success and session.inventory.get_zenny() == 10000, "explicit isolated wallet command")
	check(developer.grant_loadout("cards").success, "explicit isolated card loadout command")
	game = shell.game.get_node("UI/TripleTriadGame")
	check(game._collection_backend.get_owned_cards().size() >= 5, "card loadout provides valid collection")
	check(DeveloperPlaytestService.card_test_deck(game.card_catalog, game._collection_backend.get_owned_cards(), game.acquisition_policy, 6, 30).is_empty(), "real legal collection preserves real deck workflow")
	check(game.get_acquisition_snapshot().claimed_bundle_ids.is_empty(), "loadout does not forge starter case claim")
	developer.authorize_isolated_mobile_save(false)
	developer.set_enabled(false)
	print("Developer Playtest QA: %d/%d passed" % [checks-failures.size(), checks])
	shell.free()
	quit(0 if failures.is_empty() else 1)
