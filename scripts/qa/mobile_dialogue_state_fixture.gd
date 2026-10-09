extends Node
## Rendered native/Web fixture: actual NPC entry points + actual mobile Back.
var checks := 0
var failures: Array[String] = []
var shell: Node
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","MobileDialogueStateQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for i in range(12): await get_tree().process_frame
func snapshot() -> Dictionary:
	var hud: Node = shell.game.get_node("UI/ExplorationHud")
	var result := {"camera":shell.gameplay_viewport.get_camera_3d().global_transform,
		"image":shell.gameplay_image.get_global_rect(), "display":shell.gameplay_window.get_global_rect(),
		"safe":shell.safe_rect,"controls":shell.controls.get_global_rect(),"viewport":shell.gameplay_viewport.size,
		"scroll":shell._surface_scroll,"buttons":shell.controls.buttons.duplicate(),"paused":get_tree().paused}
	for path in ["Root/Compass","Root/Location","Root/HelpPanel"]:
		var item: Control = hud.get_node(path)
		result[path] = {"visible":item.is_visible_in_tree(),"rect":item.get_global_rect(),"modulate":item.modulate}
	return result
func run() -> void:
	shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	shell.isolated_playtest_save = false
	shell.developer_playtest_default_enabled = false
	get_tree().root.add_child(shell)
	get_tree().current_scene = shell
	await settle()
	if not OS.has_feature("web"): get_window().size = Vector2i(390,664)
	await settle()
	var service = get_node("/root/FishingSessionServices").dialogue_service
	var world: Node = shell.game.get_node("World")
	for actor_name in ["FishingCardMakerNPC","BeachMerchantNPC","BeachCrafterNPC","FishingMasterStillWaterNPC","generic"]:
		for cycle in range(4):
			var before := snapshot()
			if actor_name == "generic":
				var bridge = load("res://scripts/dialogue/dialogue_npc_bridge.gd").new()
				world.add_child(bridge)
				bridge.start_single_line(&"fixture_generic",&"talk",&"generic","Traveller","The water is calm today.")
				bridge.set_meta("qa_temporary",true)
			else:
				var npc: Node = world.get_node(actor_name)
				if npc.has_method("_start_interaction"): npc._start_interaction()
				else:
					npc._player_in_range = true
					var key := InputEventKey.new()
					key.physical_keycode = KEY_K
					key.pressed = true
					npc.interact_from_world(key)
			await settle()
			check(service.is_active(), actor_name+" dialogue opens")
			var during := snapshot()
			for property in before:
				if property != "paused": check(during[property] == before[property],actor_name+" overlay preserves "+property)
			var controller = get_node("/root/FishingSessionServices").dialogue_controller
			check(shell.gameplay_window.get_global_rect().intersects(Rect2(controller.get_view().dialogue_panel.get_global_rect().position * (shell.gameplay_image.size / Vector2(640,864)) + shell.gameplay_image.global_position,controller.get_view().dialogue_panel.size * (shell.gameplay_image.size / Vector2(640,864)))),actor_name+" dialogue visible in crop")
			shell.controls.touch_begin(70,shell.controls.buttons["B"].get_center())
			await settle()
			shell.controls.touch_end(70)
			await settle()
			check(not service.is_active(),actor_name+" actual mobile B closes dialogue")
			var after := snapshot()
			for property in before: check(after[property] == before[property],actor_name+" close restores "+property)
			check(not get_tree().paused,actor_name+" player processing restored")
			for child in world.get_children():
				if child.has_meta("qa_temporary"): child.queue_free()
			await settle()
	var report := {"passed":checks-failures.size(),"total":checks,"failures":failures,"renderer":"web" if OS.has_feature("web") else DisplayServer.get_name()}
	print("MOBILE DIALOGUE STATE QA: ",JSON.stringify(report))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.mobileDialogueStateReport="+JSON.stringify(report))
	else:
		shell.queue_free()
		get_node("/root/FishingSessionServices").queue_free()
		await settle()
		get_tree().quit(0 if failures.is_empty() else 1)
