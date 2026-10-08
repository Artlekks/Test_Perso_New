extends Node

## Run from the actual Web export on a disposable loopback origin. Native
## execution uses isolated userdata; never import or modify a normal save.
var checks := 0
var failures: Array[String] = []
var root: Window:
	get:
		return get_tree().root
var current_scene: Node:
	get:
		return get_tree().current_scene
	set(value):
		get_tree().current_scene = value
var paused: bool:
	get:
		return get_tree().paused

func _ready() -> void:
	if OS.get_name() != "Web":
		var profile := "CodexWebParity-%d" % Time.get_ticks_usec()
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", profile)
		if not OS.get_user_data_dir().ends_with(profile) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
			get_tree().quit(1)
			return
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle(seconds := 0.2) -> void:
	await get_tree().create_timer(seconds).timeout

func touch(shell: Node, label: String) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 12
	event.position = root.get_final_transform() * shell.controls.get_global_transform_with_canvas() * shell.controls.buttons[label].get_center()
	event.pressed = true
	Input.parse_input_event(event)
	await settle()
	event.pressed = false
	Input.parse_input_event(event)
	await settle()

func run() -> void:
	print("WEB PREBOOT ROUTES: ", load("res://data/world/locations/beach.tres").destinations)
	var shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	shell.isolated_playtest_save = false
	root.add_child(shell)
	current_scene = shell
	await settle(1.0)
	var game: Node = shell.game
	var locations := root.get_node("WorldLocations")
	var sign := game.get_node("World/OceanTravel")
	var session := root.get_node("FishingSessionServices")
	print("WEB ROUTE EVIDENCE: os=", OS.get_name(), " id=", locations.current_location.location_id, " routes=", locations.current_location.destinations, " sign_destination=", sign.destination_id, " label=", sign.label.text)
	check(locations.is_current_scene(game), "Web host resolves authoritative gameplay scene")
	check(locations.current_location.destinations == PackedStringArray(["wyndia_ocean_outpost"]), "export retains authored Beach route")
	check(sign.destination_id == &"wyndia_ocean_outpost", "export retains travel sign destination")
	check(sign.label.text != "Route unavailable", "Web authored route resolves regardless of current unlock")
	# Explicit blank ownership must remain restricted, even if this disposable
	# browser origin already has a persisted flag from an earlier QA run.
	var blank := FishingInventory.new()
	check(not locations.get_access_snapshot(&"wyndia_ocean_outpost", blank).unlocked and locations.get_unlocked_destinations(&"beach", blank).is_empty(), "Web blank progression never gains free travel")
	blank.free()
	var triad := game.get_node("UI/TripleTriadGame")
	var acquisition: Dictionary = triad.claim_salvaged_card_case()
	check(acquisition.success or acquisition.reason == "already_claimed", "Web test uses authored starter acquisition")
	var npc := game.get_node("World/TripleTriadOpponentNPC")
	var player := game.get_node("Player/CharacterBody3D")
	player.global_position = npc.global_position + Vector3(0, 0, 0.35)
	player.rotation.y = PI
	await settle(1.0)
	print("WEB C EVIDENCE: range=", npc._player_in_range, " availability=", triad.get_opponent_availability(npc.opponent_id), " mapping=", shell.controls.BUTTON_KEYS["C"])
	check(npc._player_in_range, "Web card NPC real interaction range")
	await touch(shell, "C")
	check(session.dialogue_service.is_active(), "Web ScreenTouch C reaches card challenge")
	if session.dialogue_service.is_active():
		await touch(shell, "A")
		check(triad.is_open(), "Web C and confirm open actual card game")
		triad.close_game()
		await settle()
	check(not paused, "Web card exit restores pause")
	session.inventory.grant_lure(&"baby_frog", 1, false)
	check(locations.get_unlocked_destinations().has("wyndia_ocean_outpost"), "Web equivalent progression unlocks Ocean route")
	check(locations.request_travel(&"wyndia_ocean_outpost").success, "Web canonical travel starts")
	await settle(1.0)
	check(locations.current_location.location_id == &"wyndia_ocean_outpost" and locations.is_current_scene(shell.game), "Web canonical travel binds Ocean in same mobile host")
	for id in [&"bamboo_rod", &"angling_rod"]:
		session.inventory.grant_rod(id, 1, false)
	for id in [&"tail", &"crab", &"floater", &"popper", &"silver_top"]:
		session.inventory.grant_lure(id, 1, false)
	for destination in [&"lyp_lake_outpost", &"river_fishing_outpost", &"chiqua_supply_outpost"]:
		check(locations.request_travel(destination).success, "Web authored route starts " + String(destination))
		await settle(1.0)
		check(locations.current_location.location_id == destination and locations.is_current_scene(shell.game), "Web route binds actual destination " + String(destination))
	print("MOBILE WEB PARITY QA: %d/%d" % [checks - failures.size(), checks])
	if OS.get_name() != "Web":
		get_tree().quit(0 if failures.is_empty() else 1)
