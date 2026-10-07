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
	check(locations.get_reachable_world_data().source_issues.is_empty(), "arrival route graph has complete provider metadata")
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
	_test_route_regressions()
	var debug_zone = scene.get_node("World/FishZone_V2")
	debug_zone.set_fishing_spot(load("res://data/bof4/spots/river_2.tres"))
	check(not session.get_campaign_progression_snapshot().tackle_acquisition.targets[6].requirements[0].available_in_reachable_spots, "debug Salmon population is not normal acquisition reachability")
	check(not locations.get_access_snapshot(&"river_fishing_outpost").unlocked, "debug zone switch cannot unlock river travel")
	debug_zone.debug_spot_override = false
	debug_zone.fishing_spot = locations.current_location.fishing_spot
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
	check(current_scene.get_node("World/OceanTravel").label.text.begins_with("K: Travel"), "sign refreshes immediately after Baby Frog unlock")
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
	await open_trader(["lyp_crab", "lyp_angling_rod"])
	check(session.economy_access.trade_one(&"lyp_deep_diver").reason == "shop_not_available", "Lyp unrelated recipe denied")
	trade_confirm(&"lyp_crab")
	check(inventory.owns_lure(&"crab"), "UI Crab trade rewards ownership")
	for species in ["black_bass", "blue_gill", "piranha"]:
		check(inventory.get_fish_count(species) == 0, "Crab consumes " + species)
	check(session.get_campaign_progression_snapshot().tackle_acquisition.next_target.item_id == "floater", "early ladder advances to Floater")
	var menu = current_scene.find_child("FishingEconomyMenu", true, false)
	check(not locations.request_travel(&"wyndia_ocean_outpost").success, "modal blocks travel")
	menu.close_menu()
	var old_scene := current_scene
	check(reload_current_scene() == OK, "reload location request")
	await frames(8)
	check(current_scene != old_scene and locations.current_location.location_id == &"lyp_lake_outpost", "reload reconstructs location authority")
	check(session.economy_access.get_trade_entries().is_empty(), "reload grants no open merchant context")
	await _run_extended_spine()
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
	if species_id in ["salmon", "dorado", "martian_squid"]:
		var rod = load("res://data/bof4/rods/bamboo_rod.tres")
		var resolver = preload("res://scripts/fishing_fight_resolver.gd")
		var average := FishInstance.new()
		average.setup(selected.fish, 0, selected.fish.average_size)
		var stats: Dictionary = average.get_fight_stats()
		check(resolver.is_valid_context(resolver.resolve_context(average, rod, bait)), "pre-Angling Bamboo/Straight fight context valid " + species_id)
		var audit: Dictionary = preload("res://scripts/fishing_fight_accessibility.gd").audit_specimen(selected.fish, stats, rod, Regression.TENSION_PROFILE, false, -1.0, -1.0, bait)
		check(audit.passes_fairness_envelope, "pre-Angling loadout passes average-fish hook/endurance/grace envelope " + species_id)
		print("PRE-ANGLING FIGHT: ", species_id, " tier=", audit.fish_tier, " recommended_rod_tier=", audit.recommended_rod_power_tier, " bamboo_tier=", audit.rod_power_tier, " active_reel_seconds=", audit.active_reel_seconds)
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


func _test_route_regressions() -> void:
	var inventory := FishingInventory.new() # Detached, no disk initialization.
	var beach_sign = current_scene.get_node("World/OceanTravel")
	check(locations.get_unlocked_destinations(&"beach", inventory).is_empty(), "fresh Beach has zero unlocked outbound destinations")
	var world: Dictionary = locations.get_reachable_world_data(inventory)
	check(world.destination_ids.is_empty() and world.location_ids == PackedStringArray(["beach"]), "restricted snapshot retains current Beach without inventing outbound travel")
	check(world.sources.size() == 1 and world.source_issues.is_empty(), "zero outbound routes retain legitimate Beach economy")
	check(beach_sign.label.text.begins_with("Locked:") and not beach_sign.label.text.contains("K: Travel"), "locked sign offers no travel destination")
	check(not beach_sign.is_world_interaction_available(key()), "locked sign is ineligible for interaction")
	inventory.grant_lure(&"baby_frog", 1, false)
	check(locations.get_unlocked_destinations(&"beach", inventory) == PackedStringArray(["wyndia_ocean_outpost"]), "Baby Frog makes Ocean the sole Beach outbound route")
	world = locations.get_reachable_world_data(inventory)
	check(world.location_ids == PackedStringArray(["beach", "wyndia_ocean_outpost"]), "Baby Frog graph cannot bypass restored Lake prerequisites")
	inventory.grant_rod(&"bamboo_rod", 1, false)
	inventory.grant_lure(&"tail", 1, false)
	world = locations.get_reachable_world_data(inventory)
	check(world.location_ids.has("lyp_lake_outpost") and world.source_issues.is_empty(), "Ocean/Lake routes and provider mappings resolve")
	for lure_id in [&"crab", &"floater", &"popper"]:
		inventory.grant_lure(lure_id, 1, false)
	check(locations.get_reachable_world_data(inventory).location_ids.has("river_fishing_outpost"), "prior milestones resolve River route")
	inventory.grant_rod(&"angling_rod", 1, false)
	inventory.grant_lure(&"silver_top", 1, false)
	check(locations.get_reachable_world_data(inventory).location_ids.size() == 5, "all five locations resolve after their milestones")
	var lake = locations.get_location(&"lyp_lake_outpost")
	var paths: PackedStringArray = lake.economy_provider_paths.duplicate()
	lake.economy_provider_paths = PackedStringArray()
	world = locations.get_reachable_world_data(inventory)
	check(world.source_issues.size() == lake.economy_contexts.size(), "original empty Lyp provider-path regression fails closed without indexing")
	var has_lake_source := false
	for source: Dictionary in world.sources:
		has_lake_source = has_lake_source or String(source.path).begins_with("lyp_lake_outpost:")
	check(not has_lake_source, "missing mappings invent no Lyp provider or first-path fallback")
	lake.economy_provider_paths = paths
	var beach = locations.get_location(&"beach")
	var beach_paths: PackedStringArray = beach.economy_provider_paths.duplicate()
	beach.economy_provider_paths = PackedStringArray()
	var merchant = current_scene.get_node("World/BeachMerchantNPC")
	check(not locations.context_belongs_here(merchant.economy_context, merchant), "missing provider metadata also denies live merchant context without fallback")
	beach.economy_provider_paths = beach_paths
	check(locations.context_belongs_here(merchant.economy_context, merchant), "restored actual provider remains valid")
	var routes: PackedStringArray = beach.destinations.duplicate()
	beach.destinations = PackedStringArray()
	world = locations.get_reachable_world_data(inventory)
	check(world.destination_ids.is_empty() and world.location_ids == PackedStringArray(["beach"]), "empty authored route list is valid and safe")
	beach.destinations = PackedStringArray(["debug_only_unknown_location"])
	world = locations.get_reachable_world_data(inventory)
	check(world.destination_ids.is_empty() and world.location_ids == PackedStringArray(["beach"]), "zero valid filtered routes select no debug/fake fallback")
	beach_sign._refresh_label()
	check(beach_sign.label.text == "Route unavailable", "sign gracefully handles removed/invalid route")
	beach.destinations = routes
	beach_sign._refresh_label()
	var authority = locations.current_location
	locations.current_location = null
	world = locations.get_reachable_world_data(inventory)
	check(world.location_ids.is_empty() and world.destination_ids.is_empty() and world.sources.is_empty() and world.spots.is_empty(), "unbound authority returns entirely empty snapshot without Beach fallback")
	locations.current_location = authority
	for id in [&"beach", &"wyndia_ocean_outpost", &"lyp_lake_outpost", &"river_fishing_outpost", &"chiqua_supply_outpost"]:
		var location = locations.get_location(id)
		check(location.economy_contexts.size() == location.economy_provider_paths.size(), "authored source mapping lengths match " + String(id))
		var file := "user://route_roundtrip_%s.tres" % id
		check(ResourceSaver.save(location.duplicate(true), file) == OK, "location resource serializes " + String(id))
		var loaded = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(loaded != null and loaded.economy_provider_paths == location.economy_provider_paths and loaded.destinations == location.destinations and loaded.required_lure_ids == location.required_lure_ids and loaded.required_rod_ids == location.required_rod_ids, "provider/routes/unlock arrays survive save/reload " + String(id))
	inventory.free()


func _run_extended_spine() -> void:
	var inventory: FishingInventory = session.inventory
	check(not locations.get_access_snapshot(&"river_fishing_outpost").unlocked and not locations.get_access_snapshot(&"chiqua_supply_outpost").unlocked, "Crab alone unlocks neither new destination")
	check(not locations.request_travel(&"river_fishing_outpost").success, "normal river travel denied before purchases")
	var rod_row: Dictionary = session.get_campaign_progression_snapshot().tackle_acquisition.targets[6]
	check(rod_row.accessible and not rod_row.requirements_reachable, "Lyp trade exists but Salmon water is honestly locked")
	await travel("ReturnTravel", &"wyndia_ocean_outpost")
	await travel("ReturnTravel", &"beach")
	var merchant = current_scene.get_node("World/BeachMerchantNPC")
	var menu = current_scene.find_child("FishingEconomyMenu", true, false)
	check(menu.open_merchant_menu(merchant.economy_context, merchant), "Floater uses original Beach Merchant shop")
	# Funding fixture: sell normal inventory through the existing merchant.
	inventory.add_fish("sea_bass", 45, false)
	for i in range(45):
		session.economy_access.sell_one("sea_bass")
	var balance := inventory.get_zenny()
	trade_confirm(&"shyde_floater")
	check(inventory.owns_lure(&"floater") and balance - inventory.get_zenny() == 300, "Floater charges canonical 300z at Beach")
	menu.close_menu()
	check(not locations.get_access_snapshot(&"river_fishing_outpost").unlocked, "Floater plus Crab still needs Popper")
	await travel("OceanTravel", &"wyndia_ocean_outpost")
	await travel("LakeTravel", &"lyp_lake_outpost")
	await open_shop("LypItemShop", "lyp_item")
	check(session.economy_access.trade_one(&"lyp_angling_rod").reason == "shop_not_available" and session.economy_access.buy_one(&"chiqua_hanger").reason == "shop_not_available", "Lyp shop grants neither fish trades nor Chiqua buys")
	balance = inventory.get_zenny()
	trade_confirm(&"lyp_popper")
	check(inventory.owns_lure(&"popper") and balance - inventory.get_zenny() == 350, "Popper charges canonical 350z at Lyp shop")
	menu = current_scene.find_child("FishingEconomyMenu", true, false)
	menu.close_menu()
	check(locations.get_access_snapshot(&"river_fishing_outpost").unlocked and not inventory.owns_rod(&"angling_rod"), "prior lure milestones unlock Salmon water without circular rod requirement")
	check(session.get_campaign_progression_snapshot().tackle_acquisition.next_target.item_id == "angling_rod", "ownership advances LIVE target to Angling Rod")
	await prove_fishing_entry()
	for species in ["dorado", "martian_squid"]:
		await collect_species(species, 2)
	await travel("RiverTravel", &"river_fishing_outpost")
	check(current_scene.get_node("World/FishZone_V2").get_fishing_spot().spot_id == &"river_2", "normal river scene uses authored River 2")
	check(inventory.owns_rod(&"bamboo_rod") and not inventory.owns_rod(&"angling_rod"), "required species available before Angling Rod")
	check(current_scene.get_node("World/ManilloTrader/BodyCollider/CollisionShape3D").disabled, "unused river trader has no invisible blocker")
	check(not locations.request_travel(&"chiqua_supply_outpost").success, "Chiqua remains locked before specialization milestones")
	await prove_fishing_entry()
	await collect_species("salmon", 2)
	rod_row = session.get_campaign_progression_snapshot().tackle_acquisition.targets[6]
	check(rod_row.requirements_reachable and rod_row.requirements_met, "all actual Angling fish and source reachable")
	var actual_costs := {}
	for requirement: Dictionary in rod_row.requirements:
		actual_costs[requirement.species_id] = requirement.required
	check(actual_costs == {"salmon": 2, "dorado": 2, "martian_squid": 2}, "Angling recipe is exact authored three-species trade")
	await travel("ReturnTravel", &"lyp_lake_outpost")
	await open_trader(["lyp_crab", "lyp_angling_rod"])
	check(session.economy_access.buy_one(&"lyp_popper").reason == "shop_not_available", "Lyp Manillo grants no item-shop purchases")
	menu = current_scene.find_child("FishingEconomyMenu", true, false)
	for index in range(menu._source_entries.size()):
		if menu._source_entries[index].id == "lyp_angling_rod":
			menu._move_selection(index - menu._row_index)
	check(menu.row_price_labels[menu._row_index].text == "3 species" and menu.trade_requirements_label.text == "Salmon x2\nDorado x2\nMartian Squid x2", "Angling menu displays all recipe-driven ASCII requirements")
	trade_confirm(&"lyp_angling_rod")
	check(inventory.owns_rod(&"angling_rod"), "normal contextual Angling trade rewards rod")
	for species in ["salmon", "dorado", "martian_squid"]:
		check(inventory.get_fish_count(species) == 0, "Angling consumes two " + species)
	menu.close_menu()
	check(not locations.get_access_snapshot(&"chiqua_supply_outpost").unlocked, "Angling alone still requires Silver Top")
	await open_shop("LypItemShop", "lyp_item")
	balance = inventory.get_zenny()
	trade_confirm(&"lyp_silver_top")
	check(inventory.owns_lure(&"silver_top") and balance - inventory.get_zenny() == 450, "Silver Top charges canonical 450z")
	menu.close_menu()
	check(locations.get_access_snapshot(&"chiqua_supply_outpost").unlocked, "rod and Silver Top unlock Chiqua")
	await travel("RiverTravel", &"river_fishing_outpost")
	await travel("ChiquaTravel", &"chiqua_supply_outpost")
	await open_shop("ManilloTrader", "chiqua")
	check(session.economy_access.buy_one(&"lyp_popper").reason == "shop_not_available" and session.economy_access.trade_one(&"lyp_angling_rod").reason == "shop_not_available", "Chiqua cannot leak Lyp purchase/trade access")
	balance = inventory.get_zenny()
	trade_confirm(&"chiqua_hanger")
	check(inventory.owns_lure(&"hanger") and balance - inventory.get_zenny() == 600, "Hanger purchased at canonical 600z from Chiqua")
	check(session.get_campaign_progression_snapshot().tackle_acquisition.complete, "all nine ownership targets complete")
	menu = current_scene.find_child("FishingEconomyMenu", true, false)
	menu.close_menu()
	check(reload_current_scene() == OK, "Chiqua reload request")
	await frames(8)
	check(locations.current_location.location_id == &"chiqua_supply_outpost" and session.economy_access.get_buy_entries().is_empty(), "Chiqua reload reconstructs identity without shop access leak")
	var loaded := FishingInventory.new()
	loaded.load_from_disk()
	check(loaded.owns_rod(&"angling_rod") and loaded.owns_lure(&"hanger"), "new rewards saved in existing schema")
	loaded.free()
	var unlocks := FishingUnlockState.new()
	unlocks.load_from_disk()
	check(unlocks.has_flag(&"world.location.river_fishing_outpost") and unlocks.has_flag(&"world.location.chiqua_supply_outpost"), "new capabilities persist through existing unlock schema")
	unlocks.free()
	await travel("ReturnTravel", &"river_fishing_outpost")
	await travel("ReturnTravel", &"lyp_lake_outpost")


func open_shop(node_name: String, shop_id: String) -> void:
	var shop = current_scene.get_node("World/" + node_name)
	await position_at(shop)
	var router = current_scene.get_node("Game/Exploration/WorldInteractionRouter")
	router.handle_event(key(false))
	check(router.handle_event(key()), "normal routed K opens " + shop_id + " shop")
	await frames(2)
	var menu = current_scene.find_child("FishingEconomyMenu", true, false)
	check(menu.is_open() and menu._mode == menu.MODE_BUY, "separate shop NPC opens purchases")
	var entries: Array[Dictionary] = session.economy_access.get_buy_entries()
	check(not entries.is_empty() and session.economy_access.get_trade_entries().is_empty(), "item shop has offers and no Manillo access")
	for entry: Dictionary in entries:
		check(entry.shop_id == shop_id, "item shop lists only its authored source " + entry.id)
