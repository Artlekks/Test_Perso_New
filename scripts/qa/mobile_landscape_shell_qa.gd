extends SceneTree
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
var checks := 0
var failures: Array[String] = []
const SIZES := [Vector2i(568,320),Vector2i(667,375),Vector2i(844,390),Vector2i(932,430),Vector2i(320,568),Vector2i(375,667),Vector2i(390,844),Vector2i(430,932)]
var measurements: Array[Dictionary] = []
var host: Control
var keys: Array[InputEventKey] = []
var actions: Array[InputEventAction] = []

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","CodexLandscapeQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func settle() -> void:
	for i in range(30): await process_frame

func tap_control(id: String) -> void:
	host.controls.touch_begin(71,host.controls.buttons[id].get_center())
	await process_frame
	host.controls.touch_end(71)
	await settle()

func tap_ui(button: Button) -> void:
	for pressed in [true,false]:
		var event := InputEventScreenTouch.new()
		event.index = 72
		event.position = root.get_final_transform() * button.get_global_transform_with_canvas() * (button.size*.5)
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame
	await settle()
	await create_timer(0.7).timeout

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/mobile-web/ui-v3"))
	host = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	host.isolated_playtest_save = false
	root.add_child(host)
	current_scene = host
	await settle()
	host.controls.key_requested.connect(func(event): keys.append(event))
	host.controls.action_requested.connect(func(event): actions.append(event))
	var game_id: int = host.game.get_instance_id()
	var camera: Camera3D = host.gameplay_viewport.get_camera_3d()
	var camera_pose := camera.global_transform
	for dimensions in SIZES:
		root.size = dimensions
		await settle()
		host._layout()
		await settle()
		var layout: Dictionary = host.shell.regions
		check(layout.variant == ("mobile_landscape" if dimensions.x > dimensions.y else "mobile_portrait"),"responsive orientation variant")
		check(host.safe_rect.encloses(layout.frame),"game frame respects device safe area")
		check(host.safe_rect.encloses(layout.info),"continuous environmental strip respects safe area")
		check(is_equal_approx(layout.world.size.x/layout.world.size.y,float(layout.resolution.x)/layout.resolution.y),"uncropped active aspect display")
		print("IMAGE SIZE ",host.gameplay_image.size," WINDOW SIZE ",host.gameplay_window.size)
		check(host.gameplay_image.size.is_equal_approx(host.gameplay_window.size),"display shows full canonical image without crop")
		check(host.gameplay_viewport.size == layout.resolution,"orientation render resolution")
		check(host.game.get_instance_id() == game_id and camera.global_transform.is_equal_approx(camera_pose),"resize preserves gameplay instance and camera")
		for id in host.controls.buttons:
			var hit: Rect2 = host.controls.buttons[id]
			check(hit.size.x >= 44 and hit.size.y >= 44,"comfortable "+id+" touch target")
			check(Rect2(Vector2.ZERO,host.controls.size).encloses(hit),"entire "+id+" hit target is usable")
			if layout.fallback != "edge_overlay": check(not hit.intersects(Rect2(layout.world.position-host.controls.global_position,layout.world.size)),"permanent "+id+" does not overlap gameplay")
		for a in ["X","Y","A","B"]:
			for b in ["X","Y","A","B"]:
				if a >= b: continue
				var first: Rect2 = host.controls.buttons[a]
				var second: Rect2 = host.controls.buttons[b]
				check(first.get_center().distance_to(second.get_center()) >= (first.size.x+second.size.x)*.5+4.0,"face circle targets have comfortable separation")
		var boxes: Array[Rect2] = host.shell.environment_strip.cells()
		check(boxes.size() == (6 if dimensions.x > dimensions.y else 5),"environment has separate landscape clock cell and existing portrait groups")
		if dimensions.x > dimensions.y:
			check(layout.info.size.y == 40 and boxes.all(func(box): return box.position.y == boxes[0].position.y),"40px single-row landscape environment")
		var cluster: Rect2 = host.controls.buttons.X
		for id in ["Y","A","B"]: cluster = cluster.merge(host.controls.buttons[id])
		check(absf(cluster.get_center().x+host.controls.global_position.x-layout.right.get_center().x) < .01,"full face diamond has equal left/right margins")
		check(host.controls.button_visuals.L.size.y == (44 if dimensions.x > dimensions.y else 32),"portrait shoulder artwork shorter without shrinking touch")
		check(host.shell.environment_strip.visible,"both orientations use shared environment strip")
		check(not host.shell.utility.Menu.visible and not host.shell.utility.Inventory.visible and not host.shell.utility.Journal.visible,"no obsolete permanent portrait utility row")
		for id in ["Settings","Equipment"]:
			var hit: Rect2 = host.shell.utility[id].get_global_rect()
			if layout.fallback == "scroll_controls": host.controls_scroll.scroll_vertical = 1000
			await settle()
			hit = host.shell.utility[id].get_global_rect()
			check(hit.size.x >= 44 and hit.size.y >= 44 and host.safe_rect.encloses(hit) and (layout.fallback == "edge_overlay" or not hit.intersects(layout.world)),"usable "+id+" with explicit fallback")
		host.controls_scroll.scroll_vertical = 0
		await settle()
		check(host.controls.stick_zone.size.x >= 100,"100px or larger stick interaction diameter")
		measurements.append({"viewport":str(dimensions),"safe":str(host.safe_rect),"game":str(layout.world.size),"game_percent":100.0*layout.world.get_area()/host.safe_rect.get_area(),"fallback":layout.fallback,"resolution":str(layout.resolution),"joystick_hit":str(host.controls.stick_zone.size),"face":str(host.controls.buttons.X.size),"primary":str(host.controls.buttons.A.size),"header":layout.info.size.y,"left":str(layout.left.size),"right":str(layout.right.size)})
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/mobile-web/ui-v3/explore-%dx%d.png" % [dimensions.x,dimensions.y])
		print("LANDSCAPE ",dimensions," safe=",host.safe_rect," game=",layout.world)
		if layout.fallback != "scroll_controls": check(host.safe_rect.encloses(host.shell.utility.Equipment.get_global_rect()),"actual Select button stays inside safe area")
		var before := actions.size()
		await tap_control("X")
		check(actions.size() == before+2 and actions[-2].pressed and not actions[-1].pressed,"one balanced named X action in "+str(dimensions))
	actions.clear()
	keys.clear()
	await tap_control("X")
	check(actions.size() == 2 and actions[0].action == &"world_card_challenge" and actions[0].pressed and not actions[1].pressed,"X sends exactly one card action press/release")
	check(keys.is_empty(),"X never duplicates card action as raw keyboard event")
	var menu: FishingMenu = host.game.find_child("FishingMenu",true,false)
	await tap_control("Y")
	check(menu.is_open(),"Y opens existing J menu")
	await tap_control("B")
	check(not menu.is_open(),"B closes existing menu")
	await tap_control("START")
	check(paused,"Start uses existing pause")
	await tap_control("START")
	check(not paused,"Start resumes through existing pause")
	await tap_ui(host.shell.utility.Equipment)
	check(host.shell.equipment_drawer.visible,"Select opens equipment drawer")
	check(host.get_layout_rects(host.safe_rect).world == host.shell.regions.world,"drawer never reallocates the gameplay rectangle")
	var fishing: Node = host.game.get_node("Game/Fishing")
	check(host.shell.snapshot.rod == fishing.loadout.get_selected_rod().rod_name,"drawer uses authoritative rod")
	check(host.shell.snapshot.bait == fishing.loadout.get_selected_lure().display_name,"drawer uses authoritative lure/bait")
	var column: Node = host.shell.equipment_drawer.get_child(0)
	await tap_ui(column.get_child(1).get_child(0))
	check(host.shell.equipment_pinned,"pin is presentation state")
	await tap_ui(column.get_child(2))
	print("DRAWER ACTION menu=",menu.is_open()," page=",menu._page," open=",host.shell.equipment_open," pinned=",host.shell.equipment_pinned," button=",column.get_child(2).get_global_rect())
	check(menu.is_open() and menu._page == FishingMenu.Page.EQUIP,"drawer opens existing equipment page")
	check(not host.shell.equipment_drawer.visible,"drawer does not obscure modal")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mobile-web/ui-v3/equipment-modal.png")
	for dimensions in SIZES:
		root.size = dimensions
		await settle()
		host._layout()
		await create_timer(.35).timeout
		check(menu.is_open() and not host.shell.equipment_drawer.visible,"equipment modal owns presentation through orientation change")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/mobile-web/ui-v3/modal-%dx%d.png" % [dimensions.x,dimensions.y])
	for step in range(4):
		if not menu.is_open(): break
		await tap_control("B")
		await create_timer(.7).timeout
	check(not menu.is_open(),"equipment modal closes through real B release boundary")
	await create_timer(0.35).timeout
	check(host.shell.equipment_drawer.visible,"pinned drawer restores after modal")
	await tap_ui(host.shell.utility.Settings)
	check(menu.is_open() and menu._page == FishingMenu.Page.OPTIONS,"gear opens existing settings")
	for step in range(4):
		if not menu.is_open(): break
		await tap_control("B")
		await create_timer(.7).timeout
	check(not menu.is_open(),"settings closes through real B release boundary")
	check(host.shell.environment_strip.state.wind == "N/A","unimplemented wind is explicit")
	for dimensions in SIZES:
		root.size = dimensions
		await settle()
		host._layout()
		await create_timer(.7).timeout
		print("DRAWER CAPTURE visible=",host.shell.equipment_drawer.visible," open=",host.shell.equipment_open," pin=",host.shell.equipment_pinned," modal=",host._has_surface_modal())
		check(host.shell.equipment_drawer.visible,"pinned drawer survives orientation resize")
		check(host.safe_rect.encloses(host.shell.equipment_drawer.get_global_rect()),"drawer remains inside safe area at "+str(dimensions))
		for id in host.controls.buttons:
			var hit: Rect2 = host.controls.buttons[id]
			hit.position += host.controls.global_position
			check(not host.shell.equipment_drawer.get_global_rect().intersects(hit),"drawer leaves "+id+" accessible at "+str(dimensions))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/mobile-web/ui-v3/drawer-%dx%d.png" % [dimensions.x,dimensions.y])
	host.shell.equipment_open = false
	var npc: Node3D = host.game.get_node("World/TripleTriadOpponentNPC")
	DeveloperPlaytestService.current().set_enabled(true)
	var saved_position: Vector3 = fishing.player.global_position
	fishing.player.global_position = npc.global_position+Vector3(0,0,0.35)
	fishing.player.rotation.y = PI
	await create_timer(1.2).timeout
	print("LANDSCAPE CARD range=",npc._player_in_range," position=",fishing.player.global_position," npc=",npc.global_position," dev=",DeveloperPlaytestService.current().enabled," paused=",paused)
	var card_event := InputEventAction.new()
	card_event.action = &"world_card_challenge"
	card_event.pressed = true
	print("CARD ELIGIBILITY exploration=",fishing.game_mode.is_exploration()," facing=",fishing.player.global_basis.z," available=",host.game.get_node("UI/TripleTriadGame").get_opponent_availability(npc.opponent_id)," selected=",WorldInteractionRouter.select_target(fishing.player,get_nodes_in_group(&"world_interaction_targets"),card_event))
	await tap_control("X")
	await create_timer(.3).timeout
	var services_for_cards: Node = root.get_node("FishingSessionServices")
	check(services_for_cards.dialogue_service.is_active(),"landscape X opens real DEV card challenge conversation")
	await tap_control("A")
	await create_timer(.4).timeout
	var triad: Node = host.game.get_node("UI/TripleTriadGame")
	check(triad.is_open(),"landscape A confirms through existing Triple Triad path")
	triad.close_game()
	await create_timer(.4).timeout
	fishing.player.global_position = saved_position
	fishing.player.global_basis = host.game.get_node("World/FishZone_V2/WaterFacing").global_basis
	fishing.game_mode.enter_fishing(host.game.get_node("World/FishZone_V2"))
	await create_timer(2.0).timeout
	check(fishing.game_mode.is_fishing(),"landscape enters normal fishing through existing game mode")
	check(host.gameplay_viewport.size == host.shell.regions.resolution,"fishing retains active surface")
	host.shell.environment_strip.refresh(host.shell.snapshot)
	check(host.shell.environment_strip.state.current != "N/A","active fishing current resolves from physical current service")
	var tide_snapshot: Dictionary = fishing.fishing_environment_service.get_debug_snapshot().tide
	check(host.shell.environment_strip.state.tide == tide_snapshot.phase_name,"strip uses authoritative tide phase")
	fishing.fishing_environment_service.activate_condition(&"rain")
	host.shell.environment_strip.refresh(host.shell.snapshot)
	check(host.shell.environment_strip.state.weather == preload("res://data/bof4/environment/all_environment_conditions.tres").get_condition_by_id(&"rain").display_name,"weather change uses authored condition name")
	# Exercise real cast inputs and capture waterborne HUD/sea, not only AIM.
	for attempt in range(6):
		if fishing.phase in [fishing.Phase.IN_WATER,fishing.Phase.FIGHT]: break
		await tap_control("A")
		await create_timer(.8).timeout
		if fishing.phase in [fishing.Phase.THROW,fishing.Phase.BAIT_FLYING]: await create_timer(2.0).timeout
	check(fishing.phase == fishing.Phase.IN_WATER and is_instance_valid(fishing.caster.active_bait),"balanced mobile inputs reach real waterborne cast")
	for dimensions in SIZES:
		root.size = dimensions
		await settle()
		host._layout()
		await create_timer(.35).timeout
		check(host.gameplay_image.size.is_equal_approx(host.gameplay_window.size),"fishing remains uncropped at "+str(dimensions))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/mobile-web/ui-v3/fishing-%dx%d.png" % [dimensions.x,dimensions.y])
	var output := FileAccess.open("res://build/mobile-web/ui-v3/geometry.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(measurements,"  "))
	output.close()
	host.queue_free()
	await settle()
	var services := root.get_node_or_null("FishingSessionServices")
	if services != null: services.queue_free()
	await settle()
	check(not Input.is_action_pressed("ds_left") and not Input.is_action_pressed("ds_right"),"teardown releases steering")
	print("MOBILE LANDSCAPE QA: ",checks-failures.size(),"/",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
