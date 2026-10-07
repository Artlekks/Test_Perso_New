extends SceneTree

## Full scene/physics/input QA; all persistence is in a disposable named folder.
const Regression = preload("res://scripts/fishing_regression_harness.gd")
var checks := 0
var failures: Array[String] = []
var session: Node
var locations: Node
var orphan_before: Array[int] = []
var _selection_context: Dictionary = {}

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	var isolated_name := "CodexWorldLocationQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated_name)
	if not OS.get_user_data_dir().ends_with(isolated_name) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Isolated userdata setup failed; refusing to bootstrap gameplay")
		quit(1)
		return
	print("ISOLATED USERDATA: ", OS.get_user_data_dir())
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func frames(count := 4) -> void:
	for frame in range(count):
		await process_frame

func key(pressed := true, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_K
	event.physical_keycode = KEY_K
	event.pressed = pressed
	event.echo = echo
	return event

func position_at(node: Node3D) -> void:
	var player: CharacterBody3D = current_scene.get_node("Player/CharacterBody3D")
	player.global_position = node.global_position + Vector3(0, 0, 0.2)
	player.rotation.y = PI
	for frame in range(4):
		await physics_frame
		await process_frame

func travel(point_name: String, expected: StringName) -> void:
	var point = current_scene.get_node("World/" + point_name)
	await position_at(point)
	var router = current_scene.get_node("Game/Exploration/WorldInteractionRouter")
	router.handle_event(key(false))
	check(router.handle_event(key()), "explicit routed K claims travel " + point_name)
	check(locations.transitioning, "transition marked busy before next input")
	check(not locations.request_travel(expected).success, "duplicate travel is rejected")
	await frames(8)
	check(locations.current_location != null and locations.current_location.location_id == expected, "arrives at " + String(expected))
	check(not session.economy_access.get_access_context_snapshot().full_catalog_access and session.economy_access.get_trade_entries().is_empty(), "arrival clears trade/debug access")

func _run() -> void:
	orphan_before.assign(Node.get_orphan_node_ids())
	locations = root.get_node("WorldLocations")
	var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(6)
	session = root.get_node("FishingSessionServices")
	var inventory: FishingInventory = session.inventory
	check(locations.current_location.location_id == &"beach", "original beach location identity")
	check(scene.get_node("World/FishZone_V2").get_fishing_spot().spot_id == &"ocean_2", "original beach population")
	check(not locations.get_access_snapshot(&"wyndia_ocean_outpost").unlocked, "ocean locked before Baby Frog")
	check(not locations.get_access_snapshot(&"lyp_lake_outpost").unlocked, "lake locked before rod and Tail")
	var snapshot: Dictionary = session.get_campaign_progression_snapshot().tackle_acquisition
	check(snapshot.targets[0].accessible and not snapshot.targets[1].accessible and not snapshot.targets[2].accessible and not snapshot.targets[3].accessible, "fresh early ladder access")
	check(not locations.request_travel(&"wyndia_ocean_outpost").success, "locked normal travel denied")
	var beach_context = scene.get_node("World/BeachMerchantNPC").economy_context
	beach_context.apply_to(session.economy_access)
	check(session.economy_access.get_buy_entries().size() == 4 and session.economy_access.get_trade_entries().is_empty(), "Beach Merchant retains Shyde only")
	inventory.add_fish("sea_bass", 4, false)
	for i in range(4):
		session.economy_access.sell_one("sea_bass")
	check(session.economy_access.buy_one(&"shyde_baby_frog").get("can_purchase", false) and inventory.owns_lure(&"baby_frog"), "normal contextual Baby Frog purchase")
	session.economy_access.clear_access_context()
	check(locations.get_access_snapshot(&"wyndia_ocean_outpost").unlocked, "ownership unlocks ocean without time")
	snapshot = session.get_campaign_progression_snapshot().tackle_acquisition
	check(snapshot.targets[1].accessible and snapshot.targets[2].accessible and not snapshot.targets[3].accessible, "reachable ocean source and population unlock guidance")
	check(not snapshot.targets[1].requirements[0].available_in_current_spots and snapshot.targets[1].requirements[0].available_in_reachable_spots, "guidance distinguishes current beach from reachable Sea Bream water")
	check(not snapshot.targets[2].requirements[0].available_in_current_spots and snapshot.targets[2].requirements[0].available_in_reachable_spots, "guidance distinguishes current beach from reachable Flying Fish water")
	await travel("OceanTravel", &"wyndia_ocean_outpost")
	check(current_scene.get_node("World/FishZone_V2").get_fishing_spot().spot_id == &"ocean_1", "ocean outpost uses authored Ocean 1")
	await prove_fishing_entry()
	check(not locations.request_travel(&"lyp_lake_outpost").success, "lake remains locked after arrival")
	await collect_species("sea_bream", 2)
	await collect_species("flying_fish", 3)
	await open_trader(["wyndia_bamboo_rod", "wyndia_tail"])
	check(session.economy_access.trade_one(&"lyp_crab").reason == "shop_not_available", "Wyndia cannot trade Lyp")
	check(session.economy_access.trade_one(&"wyndia_toad").reason == "shop_not_available", "Wyndia unrelated recipe denied")
	trade_confirm(&"wyndia_bamboo_rod")
	check(inventory.owns_rod(&"bamboo_rod") and inventory.get_fish_count("sea_bream") == 0, "UI Bamboo trade consumes two Sea Bream")
	trade_confirm(&"wyndia_tail")
	check(inventory.owns_lure(&"tail") and inventory.get_fish_count("flying_fish") == 0, "UI Tail trade consumes three Flying Fish")
	current_scene.find_child("FishingEconomyMenu", true, false).close_menu()
	check(not paused and session.economy_access.get_trade_entries().is_empty(), "trade close releases pause and context")
	check(locations.get_access_snapshot(&"lyp_lake_outpost").unlocked, "actual trades unlock lake")
	check(session.get_campaign_progression_snapshot().tackle_acquisition.next_target.source_id == "lyp_crab", "ownership advances to reachable Crab")
	await travel("LakeTravel", &"lyp_lake_outpost")
	check(current_scene.get_node("World/FishZone_V2").get_fishing_spot().spot_id == &"lake_2", "lake outpost uses authored Lake 2")
	await prove_fishing_entry()
	for species in ["black_bass", "blue_gill", "piranha"]:
		await collect_species(species, 1)
	await open_trader(["lyp_crab"])
	check(session.economy_access.trade_one(&"lyp_deep_diver").reason == "shop_not_available", "Lyp unrelated recipe denied")
	trade_confirm(&"lyp_crab")
	check(inventory.owns_lure(&"crab"), "UI Crab trade rewards ownership")
	for species in ["black_bass", "blue_gill", "piranha"]:
		check(inventory.get_fish_count(species) == 0, "Crab consumes " + species)
	check(session.get_campaign_progression_snapshot().tackle_acquisition.complete, "early acquisition ladder complete")
	var menu = current_scene.find_child("FishingEconomyMenu", true, false)
	check(not locations.request_travel(&"wyndia_ocean_outpost").success, "modal blocks travel")
	menu.close_menu()
	var old_scene := current_scene
	check(reload_current_scene() == OK, "reload location request")
	await frames(8)
	check(current_scene != old_scene and locations.current_location.location_id == &"lyp_lake_outpost", "reload reconstructs location authority")
	check(session.economy_access.get_trade_entries().is_empty(), "reload grants no open merchant context")
	await travel("ReturnTravel", &"wyndia_ocean_outpost")
	await travel("ReturnTravel", &"beach")
	var zone = current_scene.get_node("World/FishZone_V2")
	zone.set_fishing_spot(load("res://data/bof4/spots/lake_1.tres"))
	check(zone.debug_spot_override and locations.current_location.fishing_spot.spot_id == &"ocean_2", "debug selector does not rewrite normal location")
	check(session.economy_access.get_trade_entries().is_empty(), "debug fish selection grants no trade access")
	menu = current_scene.find_child("FishingEconomyMenu", true, false)
	check(menu.open_debug_full_catalog_menu(), "explicit debug full access still opens")
	check(session.economy_access.get_trade_entries().size() == 14, "debug full catalog independent of narrowed traders")
	menu.close_menu()
	check(session.economy_access.get_trade_entries().is_empty(), "debug close leaves no access")
	current_scene.get_node("Game/GameMode").current_mode = 1
	check(not locations.request_travel(&"wyndia_ocean_outpost").success, "fishing mode owns input and denies travel")
	current_scene.get_node("Game/GameMode").current_mode = 0
	var loaded := FishingInventory.new()
	loaded.load_from_disk()
	check(locations.get_access_snapshot(&"lyp_lake_outpost", loaded).unlocked, "saved ownership reconstructs lake unlock")
	loaded.free()
	inventory.remove_lure(&"baby_frog", 1, false)
	inventory.remove_lure(&"tail", 1, false)
	check(locations.get_access_snapshot(&"wyndia_ocean_outpost").unlocked and locations.get_access_snapshot(&"lyp_lake_outpost").unlocked, "lost tackle cannot relock visited progression routes")
	var saved_unlocks := FishingUnlockState.new()
	saved_unlocks.load_from_disk()
	check(saved_unlocks.has_flag(&"world.location.wyndia_ocean_outpost") and saved_unlocks.has_flag(&"world.location.lyp_lake_outpost"), "existing unlock save preserves latched location capabilities")
	saved_unlocks.free()
	_run_regressions()
	current_scene.queue_free()
	session.queue_free()
	await frames(3)
	for id in Node.get_orphan_node_ids():
		if not orphan_before.has(id):
			var orphan = instance_from_id(id)
			if is_instance_valid(orphan):
				orphan.free()
	print("World Location Access QA: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func collect_species(species_id: String, amount: int) -> void:
	var zone = current_scene.get_node("World/FishZone_V2")
	var selector: FishSelector = current_scene.get_node("Game/Fishing/Encounter").fish_selector
	var bait: BaitData = load("res://data/bof4/lures/straight.tres")
	var selected: FishSpawnEntry
	seed(71023)
	for attempt in range(2000):
		var choice := selector.choose(zone.get_fish_population(), bait, zone.get_water_depth() * 0.75, zone.get_water_depth(), false, {}, _selection_context)
		if choice != null and choice.fish.get_stable_species_id() == species_id:
			selected = choice
			break
	check(selected != null, "normal full-population selector can choose " + species_id)
	if selected == null:
		return
	var weight := selected.get_bite_selection_weight(bait, zone.get_water_depth() * 0.75, zone.get_water_depth(), false, _selection_context)
	check(weight > 0, "positive actual lure/depth/environment bite weight " + species_id)
	print("CATCHABILITY: ", species_id, " spot=", zone.get_fishing_spot().spot_id, " lure=straight depth=75% weight=", weight)
	for i in range(amount):
		var fish := FishInstance.new()
		fish.setup(selected.fish)
		var result: Dictionary = session.catch_repository.commit_catch(fish)
		check(result.get("committed", false), "normal specimen commits " + species_id)
	check(session.inventory.get_fish_count(species_id) == amount, "caught specimens reach trade inventory " + species_id)

func prove_fishing_entry() -> void:
	var zone = current_scene.get_node("World/FishZone_V2")
	var player = current_scene.get_node("Player/CharacterBody3D")
	player.global_position = Vector3(0, 0.06, -0.16)
	player.rotation.y = PI
	for frame in range(4):
		await physics_frame
		await process_frame
	check(zone.can_player_fish(player), "outpost shoreline allows normal fishing entry")
	Input.parse_input_event(key(false))
	Input.parse_input_event(key())
	await frames(3)
	var game = current_scene.get_node("Game/GameMode")
	check(game.is_fishing() and game.active_fish_zone == zone, "normal K enters fishing in authored outpost zone")
	_selection_context = session.environment_service.get_selection_context(zone.get_fish_population())
	check(not locations.request_travel(&"beach").success, "active fishing blocks world travel")
	Input.parse_input_event(key(false))
	game.exit_fishing()
	await frames(3)

func open_trader(expected_ids: Array) -> void:
	var trader = current_scene.get_node("World/ManilloTrader")
	await position_at(trader)
	var router = current_scene.get_node("Game/Exploration/WorldInteractionRouter")
	router.handle_event(key(false))
	check(router.handle_event(key()), "routed K opens contextual trader")
	await frames(2)
	var menu = current_scene.find_child("FishingEconomyMenu", true, false)
	check(menu.is_open() and menu._mode == menu.MODE_TRADE, "trade UI opens through normal interaction")
	var ids: Array = []
	for entry in session.economy_access.get_trade_entries():
		ids.append(entry.id)
	ids.sort()
	expected_ids.sort()
	check(ids == expected_ids, "trader exposes exact selected authored recipe IDs")
	check(session.economy_access.get_buy_entries().is_empty(), "trader has no unrelated cash shop")
	menu._toggle_mode()
	check(menu._mode == menu.MODE_TRADE, "trade-only UI cannot toggle to shop")

func trade_confirm(id: StringName) -> void:
	var menu = current_scene.find_child("FishingEconomyMenu", true, false)
	for index in range(menu._source_entries.size()):
		if menu._source_entries[index].id == String(id):
			menu._row_index = index
	menu._begin_confirmation()
	check(menu._confirm_active and not menu._confirm_yes, "trade confirmation defaults to No " + String(id))
	menu._confirm_yes = true
	menu._execute_confirmed_transaction()
	check(not menu._confirm_active, "trade confirmation clears " + String(id))

func _run_regressions() -> void:
	var harness := Regression.new()
	var result := harness.run_all()
	print("FULL FISHING REGRESSION: ", result.summary)
	check(result.failed == 0, "full existing fishing regression")
	for failure in result.failures:
		push_error(str(failure))
	for property in ["campaign_loop_qa_report", "campaign_progression_director_qa_report", "campaign_qa_guide_qa_report", "campaign_presentation_qa_report", "fresh_save_rehearsal_qa_report", "system_stability_qa_report"]:
		var report: Dictionary = session.get(property)
		print(property, ": ", report.passed_count, "/", report.test_count)
		check(report.passed_count == report.test_count, property)
