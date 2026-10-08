extends Node

## Run from the actual Web export on a disposable loopback origin. Native
## execution uses isolated userdata; never import or modify a normal save.
var checks := 0
var failures: Array[String] = []
var card_action_events: Array[bool] = []
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
	if OS.get_name() == "Web":
		browser_touch(event)
	else:
		Input.parse_input_event(event)
	await settle()
	event.pressed = false
	if OS.get_name() == "Web":
		browser_touch(event)
	else:
		Input.parse_input_event(event)
	await settle()

func browser_touch(event: InputEventScreenTouch) -> void:
	# Browser integration: DOM TouchEvent -> canvas/Emscripten -> Godot ->
	# MobileTouchControls. Never invoke a gameplay action or NPC directly.
	var data := JSON.stringify({"x":event.position.x,"y":event.position.y,"pressed":event.pressed,"id":event.index})
	JavaScriptBridge.eval("(()=>{const e=" + data + ";const c=document.getElementById('canvas');const r=c.getBoundingClientRect();const t=new Touch({identifier:e.id,target:c,clientX:r.left+e.x*r.width/c.width,clientY:r.top+e.y*r.height/c.height});c.dispatchEvent(new TouchEvent(e.pressed?'touchstart':'touchend',{bubbles:true,cancelable:true,touches:e.pressed?[t]:[],targetTouches:e.pressed?[t]:[],changedTouches:[t]}));})()")

func run() -> void:
	print("WEB PREBOOT ROUTES: ", load("res://data/world/locations/beach.tres").destinations)
	var shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	shell.developer_playtest_default_enabled = false
	shell.isolated_playtest_save = false
	root.add_child(shell)
	current_scene = shell
	await settle(1.0)
	var game: Node = shell.game
	shell.controls.action_requested.connect(func(event: InputEventAction):
		if event.action == &"world_card_challenge": card_action_events.append(event.pressed))
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
	var developer := DeveloperPlaytestService.current()
	var initial_monitoring: bool = game.get_node("World/TripleTriadOpponentNPC").interaction_area.monitoring
	developer.set_enabled(true)
	await settle(0.8)
	check(developer.indicator.visible and triad.is_card_game_unlocked(), "Web DEV indicator and transient card gate")
	check(locations.get_access_snapshot(&"lyp_lake_outpost").unlocked, "Web DEV grants authored location access")
	var dev_npc := game.get_node("World/TripleTriadOpponentNPC")
	var dev_player := game.get_node("Player/CharacterBody3D")
	dev_player.global_position = dev_npc.global_position + Vector3(0,0,0.35)
	dev_player.rotation.y = PI
	await settle(0.8)
	await touch(shell, "C")
	check(session.dialogue_service.is_active(), "Web actual DOM touch C enters DEV card conversation")
	if session.dialogue_service.is_active():
		await touch(shell, "A")
		check(triad.is_open(), "Web DEV confirms actual card game")
		triad.close_game()
	await settle()
	await touch(shell, "SELECT")
	var debug_menu = game.get_node("Game/Fishing").debug_controller.debug_menu
	check(debug_menu.is_open(), "Web SELECT opens same F10 menu")
	await touch(shell, "SELECT")
	check(not debug_menu.is_open(), "Web SELECT closes same F10 menu")
	developer.set_enabled(false)
	await settle(0.8)
	card_action_events.clear()
	check(dev_npc.interaction_area.monitoring == initial_monitoring, "Web OFF restores underlying normal campaign interaction state")
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
	check(card_action_events == [true,false] and not Input.is_action_pressed(&"world_card_challenge"), "browser C emits one named press/release and clears held state")
	check(session.dialogue_service.is_active(), "Web ScreenTouch C reaches card challenge")
	if session.dialogue_service.is_active():
		await touch(shell, "A")
		check(triad.is_open(), "Web C and confirm open actual card game")
		triad.close_game()
		await settle()
	check(not paused, "Web card exit restores pause")
	if OS.get_name() == "Web" and JavaScriptBridge.eval("new URLSearchParams(location.search).has('shadow_orbits')"):
		await web_shadow_orbits(game, shell)
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

func web_shadow_orbits(game: Node, shell: Node) -> void:
	# Opt-in rendered Web QA only; production harness never calls this fixture.
	var camera := Camera3D.new()
	shell.gameplay_viewport.add_child(camera)
	var original_camera: Camera3D = shell.gameplay_viewport.get_camera_3d()
	camera.current = true
	var layers := game.find_children("*", "CanvasLayer", true, false)
	var states: Array[bool] = []
	for layer in layers:
		states.append(layer.visible)
		layer.visible = false
	var zone = game.get_node("World/FishZone_V2")
	zone.hide()
	var was_paused := get_tree().paused
	get_tree().paused = true
	var actors: Array[Node3D] = []
	var actor_visibility: Array[bool] = []
	for p in game.find_children("GroundPresentation", "Node3D", true, false):
		actors.append(p.get_parent())
		actor_visibility.append(p.get_parent().visible)
	var labels := game.find_children("*", "Label3D", true, false)
	var label_visibility: Array[bool] = []
	for label in labels:
		label_visibility.append(label.visible)
		label.hide()
	var Direction = preload("res://scripts/world/view_relative_direction.gd")
	for path in ["Player/CharacterBody3D", "World/BeachMerchantNPC", "World/FishingCardMakerNPC", "World/FishingMasterStillWaterNPC"]:
		var npc = game.get_node(path)
		for actor in actors: actor.visible = actor == npc
		var presentation = npc.get_node("GroundPresentation")
		var shadow = presentation.shadow
		var original: Transform3D = shadow.global_transform
		var physical: Transform3D = npc.global_transform
		var sprite = presentation.sprite
		var animation: StringName = sprite.animation
		var reference: Node3D = npc.camera_reference if path.begins_with("Player/") else null
		for angle in 4:
			camera.global_position = npc.global_position + Vector3(sin(angle * PI / 2) * 1.5, 1.0, cos(angle * PI / 2) * 1.5)
			camera.look_at(npc.global_position + Vector3(0,0.2,0))
			if reference != null:
				npc.camera_reference = camera
				npc._update_facing_from_world(npc.global_basis.z)
				npc._play_animation("Idle", npc.last_dir)
			await settle(0.5)
			check(shadow.global_transform.is_equal_approx(original) and npc.global_transform.is_equal_approx(physical), "%s Web orbit fixes root/shadow %d" % [path, angle])
			if not presentation.directional_pose.is_empty():
				var chosen = Direction.resolve(presentation._directions, Direction.sector(presentation.world_facing, camera.global_basis))
				check(sprite.animation == StringName(chosen.animation), "%s Web authored relative view %d" % [path,angle])
			elif reference == null:
				check(sprite.animation == animation, "%s preserves one-direction fallback %d" % [path,angle])
			print("WEB GROUNDING ORBIT: ", path, " angle=", angle, " animation=", sprite.animation, " transform=", shadow.global_transform)
			await settle(1.5)
		if reference != null: npc.camera_reference = reference
	for i in actors.size(): actors[i].visible = actor_visibility[i]
	for i in labels.size(): labels[i].visible = label_visibility[i]
	get_tree().paused = was_paused
	for i in layers.size(): layers[i].visible = states[i]
	zone.show()
	original_camera.current = true
	camera.queue_free()
