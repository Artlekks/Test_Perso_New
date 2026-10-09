extends Node
## Same production controllers in native Compatibility and rendered Web.
var shell: Node
var checks := 0
var failures: Array[String] = []
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","MobileOverlayQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for i in range(12): await get_tree().process_frame
func snapshot() -> Dictionary:
	return {"camera":shell.gameplay_viewport.get_camera_3d().global_transform,
		"image":shell.gameplay_image.get_global_rect(),"crop":shell._surface_scroll_max,
		"display":shell.gameplay_window.get_global_rect(),"controls":shell.controls.get_global_rect(),
		"viewport":shell.gameplay_viewport.size,"safe":shell.safe_rect}
func unchanged(before: Dictionary,label: String) -> void:
	var after := snapshot()
	for property in before: check(before[property]==after[property],label+" fixed "+property)
func hud(label: String) -> void:
	var layer: Node = shell.game.get_node("UI/ExplorationHud")
	check(layer.custom_viewport==shell.hud_viewport,label+" pinned HUD canvas")
	for path in ["Root/Compass/CompassFace","Root/Location"]:
		var control: Control = layer.get_node(path)
		var rect := Rect2(shell.hud_image.global_position+control.get_global_rect().position*shell.hud_image.size/Vector2(640,864),control.size*shell.hud_image.size/Vector2(640,864))
		check(control.is_visible_in_tree() and shell.gameplay_window.get_global_rect().encloses(rect),label+" visible "+path)
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	if not OS.has_feature("web"):
		DirAccess.make_dir_recursive_absolute("res://build/mobile-web/overlay-captures")
		check(get_tree().root.get_texture().get_image().save_png("res://build/mobile-web/overlay-captures/"+label+".png")==OK,"rendered "+label)
	else:
		check(not shell.hud_viewport.get_texture().get_image().is_empty(),"rendered HUD texture "+label)
func run() -> void:
	shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	shell.isolated_playtest_save = false
	get_tree().root.add_child(shell)
	get_tree().current_scene = shell
	await get_tree().create_timer(1).timeout
	if not OS.has_feature("web"): get_window().size=Vector2i(390,664)
	await settle()
	hud("fresh exploration")
	await capture("world")
	var game: Node = shell.game
	var fishing: Node = game.get_node("Game/Fishing")
	var merchant: Node = fishing.fishing_economy_menu
	var crafter: Node = game.get_node("World/BeachCrafterNPC/BeachCraftingMenu")
	var maker: Node = game.get_node("World/FishingCardMakerNPC/FishingCardMakerMenu")
	var cards: Node = game.get_node("UI/TripleTriadGame")
	for cycle in range(3):
		for label in ["merchant","fish-trade","lure-crafting","card-maker","triple-triad","inventory","dialogue"]:
			var before := snapshot()
			match label:
				"merchant": check(merchant.open_debug_full_catalog_menu(),"merchant opens")
				"fish-trade": check(merchant._open_menu_in_mode(merchant.MODE_TRADE,null,null,true),"trade opens")
				"lure-crafting": check(crafter.open_menu(),"existing lure/crafting opens")
				"card-maker": check(maker.open_menu(),"Card Maker opens")
				"triple-triad": check(cards.open_game_by_id(game.get_node("World/TripleTriadOpponentNPC").opponent_id),"cards open")
				"inventory": fishing.fishing_menu.open_menu()
				"dialogue": game.get_node("World/FishingCardMakerNPC")._start_interaction()
			await settle()
			unchanged(before,label+" open")
			if cycle==0: await capture(label)
			# Shell scrolling may move UI; it must never move the world.
			if label!="dialogue":
				var touch := InputEventScreenTouch.new()
				touch.index=99; touch.pressed=true
				touch.position=shell.gameplay_window.get_global_rect().end-Vector2(5,50)
				shell._input(touch)
				var drag := InputEventScreenDrag.new()
				drag.index=99; drag.position=touch.position-Vector2(0,1000)
				shell._input(drag)
				touch.pressed=false; shell._input(touch)
				unchanged(before,label+" UI scroll")
			match label:
				"merchant","fish-trade": merchant.close_menu()
				"lure-crafting": crafter.close_menu()
				"card-maker": maker.close_menu()
				"triple-triad": cards.close_game()
				"inventory": fishing.fishing_menu.close_menu()
				"dialogue":
					shell.controls.touch_begin(70,shell.controls.buttons["B"].get_center())
					await settle()
					shell.controls.touch_end(70)
			await settle()
			unchanged(before,label+" close")
			hud("after "+label)
			check(not get_tree().paused,label+" releases modal")
	# Production fishing entry/exit and shell scene replacement restore the HUD.
	var player: Node3D = game.get_node("Player/CharacterBody3D")
	var zone: Node = game.get_node("Game/Exploration").fish_zone
	var forward: Vector3 = zone.get_water_forward()
	player.rotation.y=atan2(forward.x,forward.z)
	fishing.game_mode.enter_fishing(zone)
	var entry_deadline := Time.get_ticks_msec()+15000
	while fishing.phase!=fishing.Phase.AIM and Time.get_ticks_msec()<entry_deadline: await get_tree().process_frame
	check(fishing.phase==fishing.Phase.AIM,"normal fishing entry completes")
	var cancel := InputEventAction.new()
	cancel.action=&"cancel_fishing"; cancel.pressed=true
	fishing._unhandled_input(cancel)
	var hud_layer: Node = game.get_node("UI/ExplorationHud")
	var exit_deadline := Time.get_ticks_msec()+15000
	while not hud_layer.compass.position.is_equal_approx(hud_layer.compass_home) and Time.get_ticks_msec()<exit_deadline: await get_tree().process_frame
	await settle()
	hud("after fishing")
	shell.load_gameplay_scene("res://actors/FishingTestScene_V2.tscn")
	await get_tree().create_timer(1).timeout
	hud("after travel replacement")
	await capture("after-replacement")
	var report := {"passed":checks-failures.size(),"total":checks,"failures":failures,"renderer":"web" if OS.has_feature("web") else DisplayServer.get_name()}
	print("MOBILE OVERLAY STABILITY QA: ",JSON.stringify(report))
	if OS.has_feature("web"): JavaScriptBridge.eval("window.mobileOverlayStabilityReport="+JSON.stringify(report))
	else:
		shell.queue_free()
		get_node("/root/FishingSessionServices").queue_free()
		await settle()
		get_tree().quit(0 if failures.is_empty() else 1)
