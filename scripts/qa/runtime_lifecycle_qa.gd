extends SceneTree

## Disposable runtime ownership test. No orphan scavenging: leaks must fail.
const SceneRoot = preload("res://scripts/gameplay_scene_root.gd")
var checks := 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var session: Node
var shell: Node
var mobile := false
var baseline: Dictionary

func _initialize() -> void:
	var isolated := "CodexRuntimeLifecycleQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		quit(1)
		return
	mobile = OS.get_cmdline_user_args().has("--mobile")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle(count := 12) -> void:
	for frame in range(count):
		await process_frame

func game() -> Node:
	return SceneRoot.resolve(self)

func snapshot(label: String) -> Dictionary:
	if label == "cycle_0":
		for id in Node.get_orphan_node_ids():
			var orphan = instance_from_id(id)
			print("LIFECYCLE ORPHAN: ", id, " ", orphan, " script=", orphan.get_script())
	var timers := 0
	var active_timers := 0
	var services := 0
	for node in root.find_children("*", "Timer", true, false):
		timers += 1
		if not node.is_stopped(): active_timers += 1
	for child in root.get_children():
		if child is FishingSessionServices: services += 1
	var connections := 0
	var persistent_nodes: Array[Node] = [session, root.get_node("WorldLocations")]
	persistent_nodes.append_array(session.find_children("*", "", true, false))
	for node in persistent_nodes:
		for signal_info in node.get_signal_list():
			for connection in node.get_signal_connection_list(signal_info.name):
				connections += 1
				check(connection.callable.is_valid(), label + " persistent signal receiver valid")
	var ambient_nodes := 0
	for presence in root.find_children("FishShadowPresence", "", true, false):
		ambient_nodes += presence.find_children("*", "", true, false).size()
	var node_count := root.find_children("*", "", true, false).size() + 1
	var owned_specimens := 0
	for quantity in session.inventory.get_all_fish_counts().values(): owned_specimens += int(quantity)
	var sample := {"label":label, "nodes":node_count, "ambient_nodes":ambient_nodes,
		"owned_specimens":owned_specimens,
		"structural_nodes":node_count - ambient_nodes,
		"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources":int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphans":Node.get_orphan_node_ids().size(), "timers":timers, "active_timers":active_timers,
		"tweens":get_processed_tweens().size(), "services":services, "connections":connections}
	print("LIFECYCLE SAMPLE: ", JSON.stringify(sample))
	var paths: Array[String] = []
	for node in root.find_children("*", "", true, false): paths.append(str(node.get_path()))
	var tree_file := FileAccess.open("res://build/mobile-web/lifecycle-tree-%s-%s.txt" % ["mobile" if mobile else "native", label], FileAccess.WRITE)
	if tree_file != null: tree_file.store_string("\n".join(paths))
	samples.append(sample)
	return sample

func run() -> void:
	var probe_a := Node.new()
	var probe_b := Node.new()
	root.add_child(probe_a)
	root.add_child(probe_b)
	# Install after Node.ready: this probes acquisition without evaluating the
	# Fishing scene's unrelated @onready child paths on an empty test node.
	probe_a.set_script(load("res://scripts/fishing.gd"))
	probe_b.set_script(load("res://scripts/fishing.gd"))
	var first = probe_a._get_or_create_session_services()
	check(first == probe_b._get_or_create_session_services(), "same-frame requests share pending session owner")
	probe_a.free()
	probe_b.free()
	await settle(3)
	if mobile:
		shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
		shell.isolated_playtest_save = false
		root.add_child(shell)
		current_scene = shell
	else:
		var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
	await settle(30)
	session = root.get_node("FishingSessionServices")
	# Hold progression constant across stress samples. Otherwise normal catch
	# milestones legitimately add the starter salvage bottle after warmup.
	game().get_node("UI/TripleTriadGame").claim_salvaged_card_case()
	var session_id := session.get_instance_id()
	var world := root.get_node("WorldLocations")
	DeveloperPlaytestService.current().set_enabled(true)
	var bridge = load("res://scripts/dialogue/dialogue_npc_bridge.gd").new()
	game().add_child(bridge)
	bridge.configure_service(session.dialogue_service)
	check(bridge.start_single_line(&"lifecycle_owner", &"probe", &"qa", "QA", "Ownership probe", null, false), "non-cancellable NPC dialogue opens")
	bridge.free()
	check(not session.dialogue_service.is_active() and not paused, "departing source closes its own conversation and releases pause")
	check(session.dialogue_service.start_inline_dialogue(&"other_owner", [{"speaker":"QA", "text":"Other ownership"}]).success, "unrelated dialogue opens")
	var unrelated_bridge = load("res://scripts/dialogue/dialogue_npc_bridge.gd").new()
	game().add_child(unrelated_bridge)
	unrelated_bridge.configure_service(session.dialogue_service)
	unrelated_bridge.free()
	check(session.dialogue_service.is_active(), "unrelated bridge teardown cannot close another conversation")
	session.dialogue_service.force_close()
	for preview_cycle in range(3):
		var preview = load("res://actors/npc/NPC_Catalogue_Preview.tscn").instantiate()
		var preview_ref: WeakRef = weakref(preview)
		root.add_child(preview)
		preview.get_node("Camera3D").current = false
		await settle(2)
		preview.queue_free()
		await settle(3)
		check(preview_ref.get_ref() == null, "catalogue preview hierarchy released")
	# Warm all scene/resource/menu caches before comparing like-for-like Beach samples.
	for cycle in range(6):
		var telemetry = FishingDevelopmentLayer.ensure(session).get_economy_playtest_telemetry()
		check(telemetry.start_recording(), "telemetry starts isolated recording")
		for destination in [&"wyndia_ocean_outpost", &"lyp_lake_outpost", &"river_fishing_outpost", &"chiqua_supply_outpost", &"river_fishing_outpost", &"lyp_lake_outpost", &"wyndia_ocean_outpost", &"beach"]:
			await exercise_scene()
			var previous: WeakRef = weakref(game())
			check(world.request_travel(destination).success, "travel " + String(destination))
			await settle(24)
			check(previous.get_ref() == null, "old scene released " + String(destination))
			check(root.get_node("FishingSessionServices").get_instance_id() == session_id, "session identity preserved")
		await exercise_scene()
		telemetry.stop_recording()
		check(telemetry._connections.is_empty() and telemetry._runtime_connections.is_empty(), "telemetry disconnects recording owners")
		await create_timer(1.5).timeout
		var sample := snapshot("cycle_%d" % cycle)
		if cycle == 0: baseline = sample
		else:
			for metric in ["structural_nodes", "orphans", "timers", "active_timers", "services", "connections"]:
				check(sample[metric] == baseline[metric], "stable " + metric + " cycle " + str(cycle))
			check(sample.tweens == 0, "no surviving tween at settled boundary")
			check(sample.resources <= baseline.resources + 2, "resource count bounded after warmup")
			# Each successful landing intentionally adds one session-owned
			# FishingFishSpecimen (RefCounted). Measure growth beyond real loot.
			check(sample.objects - sample.ambient_nodes - sample.owned_specimens <= baseline.objects - baseline.ambient_nodes - baseline.owned_specimens + 4, "object count bounded excluding actual owned loot and ambient actors")
		check(sample.services == 1, "exactly one session service")
		check(sample.orphans == 0, "zero orphan nodes; no cleanup hiding leaks")
	var previous: WeakRef = weakref(game())
	var pending_fishing := game().get_node("Game/Fishing")
	var catches_before: Dictionary = session.inventory.get_all_fish_counts()
	pending_fishing.phase = pending_fishing.Phase.LANDING
	pending_fishing._run_catch_landing_sequence()
	var cancellation_tween: Tween = pending_fishing.camera_rig.create_tween()
	cancellation_tween.tween_interval(30.0)
	current_scene.queue_free()
	current_scene = null
	await create_timer(pending_fishing.catch_landing_hold_time + 0.2).timeout
	await settle(8)
	check(not cancellation_tween.is_valid(), "scene-bound tween killed when camera owner frees")
	check(session.inventory.get_all_fish_counts() == catches_before, "pending landing timer cannot commit after owner frees")
	check(previous.get_ref() == null, "final gameplay scene released")
	check(session.active_loadout == null and session.save_integrity_service.loadout == null and session.beach_crafting_service.get_active_loadout() == null, "departing scene releases all session loadout bindings")
	check(session.beach_crafting_service.get_equipped_lure() == null, "post-scene crafted lookup does not call a freed loadout")
	# Session-owned UI must have returned from the mobile viewport before shell destruction.
	check(session.dialogue_controller.get_view().get_parent() == session.dialogue_controller, "dialogue view restored to session owner")
	session.queue_free()
	await settle(12)
	check(Node.get_orphan_node_ids().is_empty(), "shutdown has no project orphan nodes")
	var regression = load("res://scripts/fishing_regression_harness.gd").new()
	var regression_report: Dictionary = regression.run_all()
	print("LIFECYCLE FULL FISHING REGRESSION: ", regression_report.summary)
	check(regression_report.failed == 0, "full fishing regression remains green")
	check(Node.get_orphan_node_ids().is_empty(), "full regression releases its own detached fixtures without scavenging")
	print("Runtime Lifecycle QA: %d/%d passed" % [checks - failures.size(), checks])
	var output := FileAccess.open("res://build/mobile-web/lifecycle-%s.json" % ("mobile" if mobile else "native"), FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify({"samples":samples,"failures":failures}, "\t"))
	quit(0 if failures.is_empty() else 1)

func exercise_scene() -> void:
	var scene := game()
	var fishing := scene.get_node("Game/Fishing")
	var mode := scene.get_node("Game/GameMode")
	var zone := scene.get_node("World/FishZone_V2")
	mode.enter_fishing(zone)
	await settle(45)
	if root.get_node("WorldLocations").current_location.location_id == &"beach":
		for outcome in ["retrieve", "land"]:
			fishing.phase = fishing.Phase.BAIT_FLYING
			var bait = fishing.caster.perform_cast(0.5, Vector3.FORWARD, zone.get_water_y(), zone.get_bottom_y(), fishing.loadout.get_selected_lure(), zone.get_swim_bounds(), zone.get_shore_boundary())
			check(is_instance_valid(bait), "production caster creates owned bait")
			var bait_ref: WeakRef = weakref(bait)
			bait.set_physics_process(false)
			bait.state = bait.State.IN_WATER
			bait.global_position = zone.water_surface.global_position
			fishing.caster._on_bait_landed(bait.global_position)
			check(fishing.phase == fishing.Phase.IN_WATER, "production water entry")
			if outcome == "land":
				fishing.encounter.pending_fish_entry = zone.get_fish_population()[0]
				check(fishing.encounter._confirm_hit(), "production encounter hook")
				check(fishing.phase == fishing.Phase.FIGHT, "hook enters fight")
			fishing.caster._on_bait_returned()
			if outcome == "land":
				await create_timer(fishing.catch_landing_hold_time + 0.1).timeout
				check(fishing.phase == fishing.Phase.CATCH, "landing timer commits through production flow")
				mode.exit_fishing()
				await settle(45)
				mode.enter_fishing(zone)
				await settle(45)
			await settle(3)
			check(bait_ref.get_ref() == null, "retrieve/landing releases physical bait")
	mode.exit_fishing()
	await settle(45)
	check(mode.is_exploration(), "fishing exit releases mode")
	check(session.dialogue_service.start_inline_dialogue(&"lifecycle_probe", [{"speaker":"QA", "text":"Ownership probe"}]).success, "dialogue opens")
	session.dialogue_service.advance()
	check(not paused and not session.dialogue_service.is_active(), "dialogue releases pause and state")
	for name in ["FishingEconomyMenu", "BeachCraftingMenu", "FishingCardMakerMenu"]:
		var menu := scene.find_child(name, true, false)
		if menu != null:
			if name == "FishingEconomyMenu": check(menu.open_debug_full_catalog_menu(), "merchant opens")
			else: check(menu.open_menu(), name + " opens")
			menu.close_menu()
			check(not paused and not menu.is_open(), name + " closes")
	var cards := scene.get_node("UI/TripleTriadGame")
	var opponent := scene.find_child("TripleTriadOpponentNPC", true, false)
	if opponent != null:
		check(cards.open_game_by_id(opponent.opponent_id), "card session opens")
		var deck: Array = cards._collection_backend.get_owned_cards().slice(0, 5)
		check(deck.size() == 5, "starter collection supplies five actual cards")
		cards._on_deck_confirmed(deck)
		check(cards._live_match.get_starting_player_cards().size() == 5, "production card match starts")
		await settle(2)
	cards.close_game()
	check(not cards.is_open() and not paused, "card session closes")
	var debug_menu = fishing.debug_controller.debug_menu
	# Use existing modal controller, so ownership of pause is exercised too.
	fishing.debug_controller.toggle(true)
	await settle(2)
	if debug_menu.is_open(): fishing.debug_controller.toggle(true)
	DeveloperPlaytestService.current().set_enabled(false)
	DeveloperPlaytestService.current().set_enabled(true)
	await settle(12)
	check(not paused, "all modal owners released")

