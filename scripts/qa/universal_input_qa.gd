extends SceneTree
var checks := 0
var failures: Array[String] = []
var bindings: UniversalInput
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","UniversalInputQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute("res://build/mobile-web/input-qa")
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func key(code: int,down := true) -> InputEventKey:
	var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=down
	return event
func settle() -> void:
	await create_timer(.35).timeout
func run() -> void:
	bindings=root.get_node("InputBindings")
	bindings.store_path="res://build/mobile-web/input-qa/preferences-%d.json" % Time.get_ticks_usec()
	bindings.reset_defaults(false)
	for action in bindings.DEFINITIONS:
		var default_key: int = bindings.DEFINITIONS[action].key
		check(UniversalInput.matches_key(key(default_key),default_key),"default "+str(action))
		check(bindings.rebind(action,KEY_P,false),"custom binding applies "+str(action))
		check(UniversalInput.matches_key(key(KEY_P),default_key) and not UniversalInput.matches_key(key(default_key),default_key),"old key stops; new semantic key works "+str(action))
		for alias in bindings.DEFINITIONS[action].aliases: check(key(KEY_P).is_action(alias),"shared context alias "+str(alias))
		check(UniversalInput.event_for_key(default_key,true).physical_keycode == KEY_P,"virtual input resolves current binding")
		bindings.reset_defaults(false)
	var gamepad := InputEventJoypadButton.new(); gamepad.button_index=JOY_BUTTON_A
	InputMap.action_add_event("enter_fishing",gamepad)
	bindings.rebind(&"enter_fishing",KEY_P,false)
	check(InputMap.action_get_events("enter_fishing").any(func(event): return event is InputEventJoypadButton),"keyboard edits preserve live non-key bindings")
	InputMap.action_erase_event("enter_fishing",gamepad); bindings.reset_defaults(false)
	check(not bindings.rebind(&"enter_fishing",KEY_A,false),"conflicting group rejected")
	check(not bindings.rebind(&"enter_fishing",KEY_SPACE,false),"Start existing Space command preserved")
	check(not bindings.rebind(&"enter_fishing",KEY_R,false),"fixed deck command reserved")
	for cycle in range(8):
		check(bindings.rebind(&"enter_fishing",KEY_P),"atomic write succeeds repeatedly")
		check(UniversalInput.format_action_hints("K: Confirm I: Back Q/E: Page").begins_with("P:"),"action captions resolve current mapping")
		var exact := bindings.bindings.duplicate()
		bindings.reset_defaults(false); bindings.load_preferences()
		check(bindings.bindings == exact,"save reload exact")
	check(bindings.reset_defaults(),"defaults persisted")
	bindings.load_preferences(); check(bindings.bindings == bindings.defaults(),"defaults survive reload")
	var file := FileAccess.open(bindings.store_path,FileAccess.WRITE); file.store_string("{bad"); file.close()
	var backup := bindings._read(bindings.store_path+".bak")
	bindings.load_preferences(); check(bindings.bindings == backup,"corrupt current recovers validated backup")
	check(bindings.reset_defaults(),"recover then save canonical defaults")
	var canonical := bindings.store_path
	var before := bindings.bindings.duplicate()
	bindings.store_path="res://build/mobile-web/input-qa/missing-directory/preferences.json"
	check(not bindings.rebind(&"enter_fishing",KEY_P) and bindings.bindings == before,"failed commit preserves current mapping")
	check(not bindings.reset_defaults() and bindings.bindings == before and bindings.status.contains("Could not save"),"failed defaults write remains visible and does not mutate bindings")
	bindings.store_path=canonical
	var malformed := bindings.defaults(); malformed[&"enter_fishing"]=KEY_A
	file=FileAccess.open(canonical,FileAccess.WRITE); file.store_string(JSON.stringify({"version":1,"bindings":malformed})); file.close()
	check(bindings._read(canonical).is_empty(),"duplicate binding payload rejected")
	file=FileAccess.open(canonical,FileAccess.WRITE); file.store_string(JSON.stringify({"version":1,"bindings":{"enter_fishing":KEY_P}})); file.close()
	bindings.load_preferences()
	check(bindings.bindings[&"enter_fishing"] == KEY_P and bindings.bindings[&"main_menu"] == KEY_J,"older partial profile fills new actions with validated defaults")
	bindings.reset_defaults()
	var fixture := SessionTestFixture.new()
	var scene: Node = fixture.mount(self)
	await settle()
	var fishing: Node = scene.get_node("Game/Fishing")
	var menu: FishingMenu = scene.find_child("FishingMenu",true,false)
	menu.open_menu(); await settle(); menu._transition_from_main(FishingMenu.Page.OPTIONS); await settle()
	var controls: Control = menu.keybinding_controls
	controls.rows[&"enter_fishing"].pressed.emit()
	Input.parse_input_event(key(KEY_B)); await settle()
	check(bindings.bindings[&"enter_fishing"] == KEY_B,"Settings capture applies and persists")
	check(menu.is_open() and fishing.game_mode.is_exploration(),"capture never casts or closes menu")
	Input.parse_input_event(key(KEY_B,false)); await settle()
	bindings.begin_capture(&"enter_fishing",controls)
	Input.parse_input_event(key(KEY_C)); await settle()
	check(bindings.capture_action == &"enter_fishing" and bindings.status.contains("Already assigned"),"conflict remains visible until resolved")
	check(not scene.find_child("TripleTriadGame",true,false).is_open(),"captured C cannot open card match")
	check(not Input.is_action_pressed("world_card_challenge"),"capture clears held polling state, not just event dispatch")
	Input.parse_input_event(key(KEY_C,false)); Input.parse_input_event(key(KEY_ESCAPE)); await settle()
	check(bindings.capture_action == &"" and menu.is_open(),"Escape cancels capture without closing Settings")
	Input.parse_input_event(key(KEY_ESCAPE,false))
	var triad = load("res://scripts/triple_triad/triple_triad_input_controller.gd").new()
	check(triad.action_for_event(key(KEY_B),false) == triad.ACTION_CONFIRM,"cards use remapped primary")
	check(triad.action_for_event(key(KEY_K),false) == triad.ACTION_NONE,"cards reject obsolete primary")
	var semantic := InputEventAction.new(); semantic.action=&"enter_fishing"; semantic.pressed=true
	check(triad.action_for_event(semantic,false) == triad.ACTION_CONFIRM,"semantic input supports future device adapters")
	bindings.begin_capture(&"main_menu",controls); menu.close_menu(); await settle()
	check(bindings.capture_action == &"","closing owner cancels capture")
	bindings.reset_defaults(false)
	fixture.release(); await settle()
	await desktop_controls()
	await mobile_settings()
	print("UNIVERSAL INPUT QA: ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)

func desktop_controls() -> void:
	OS.set_environment("FISHING_COMPANION_IPC",ProjectSettings.globalize_path("res://build/mobile-web/input-qa/ipc"))
	var host: Control = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(host); current_scene=host; await settle()
	check(host.get_script() != null,"desktop script loaded before counting controls tests")
	if host.get_script() == null: host.queue_free(); return
	var controls: Control = host.shell.desktop_actions
	for id in ["Dock Left","Dock Right","Float"]: check(host.shell.utility[id].visible,"direct header window control "+id)
	bindings.rebind(&"enter_fishing",KEY_P,false)
	check(controls.buttons[KEY_K].text == "P","clickable primary label follows preferences")
	var touch: Control = load("res://scripts/mobile/mobile_touch_controls.gd").new()
	var events: Array[InputEventKey] = []
	touch.key_requested.connect(func(event): events.append(event))
	root.add_child(touch)
	touch._hold(KEY_K)
	check(events.size() == 1 and events[0].physical_keycode == KEY_P,"mobile primary uses current semantic binding")
	bindings.rebind(&"enter_fishing",KEY_O,false)
	check(events.size() == 2 and not events[1].pressed and events[1].physical_keycode == KEY_P,"rebind releases old touch generation exactly once")
	touch._stick_keys[KEY_A]=true; touch.stick_vector=Vector2(-1,0); touch._process(0)
	bindings.begin_capture(&"main_menu")
	check(touch._stick_keys.is_empty() and not Input.is_action_pressed("move_left"),"capture releases analog polling owner")
	bindings.cancel_capture()
	touch.queue_free()
	bindings.rebind(&"enter_fishing",KEY_P,false)
	var fishing: Node = host.game.get_node("Game/Fishing")
	var menu: FishingMenu = host.game.find_child("FishingMenu",true,false)
	host.request_shell_menu("Settings"); await settle(); await settle()
	check(menu.is_open() and menu._page == FishingMenu.Page.OPTIONS,"desktop Settings opens Controls through existing menu")
	var pane: Control = menu.keybinding_controls
	var ui_scale := minf(host.menu_image.size.x/host.menu_viewport.size.x,host.menu_image.size.y/host.menu_viewport.size.y)
	var display := Rect2(host.menu_image.global_position+(host.menu_image.size-Vector2(host.menu_viewport.size)*ui_scale)*.5,Vector2(host.menu_viewport.size)*ui_scale)
	for selected in [&"move_forward",&"enter_fishing"]:
		var target: Button = pane.rows[selected]
		var logical: Vector2 = target.get_global_transform_with_canvas()*(target.size*.5)
		var point := display.position+logical*ui_scale
		for down in [true,false]:
			var mouse := InputEventMouseButton.new(); mouse.position=point; mouse.button_index=MOUSE_BUTTON_LEFT; mouse.pressed=down
			Input.parse_input_event(mouse); await process_frame
		await settle()
		check(bindings.capture_action == selected,"actual desktop mouse chooses "+str(selected))
		if selected == &"enter_fishing":
			Input.parse_input_event(key(KEY_N)); await settle(); Input.parse_input_event(key(KEY_N,false)); await settle()
			check(bindings.bindings[&"enter_fishing"] == KEY_N and controls.buttons[KEY_K].text == "N","mouse-selected capture updates authoritative mapping and click label")
		else:
			controls.press(KEY_I); await process_frame; controls.release(KEY_I); await settle()
			check(bindings.capture_action == &"" and menu.is_open(),"clickable back cancels capture without menu exit")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mobile-web/input-qa/settings-desktop.png")
	controls.press(KEY_I); await process_frame; controls.release(KEY_I); await settle()
	controls.press(KEY_I); await process_frame; controls.release(KEY_I); await settle()
	check(not menu.is_open() and fishing.game_mode.is_exploration(),"clickable back closes modal without entering fishing")
	fishing.player.global_basis=host.game.get_node("World/FishZone_V2/WaterFacing").global_basis
	fishing.game_mode.enter_fishing(host.game.get_node("World/FishZone_V2"))
	for frame in range(600):
		if fishing.phase == fishing.Phase.AIM: break
		await process_frame
	for attempt in range(6):
		if fishing.phase == fishing.Phase.IN_WATER: break
		controls.press(KEY_K); controls.press(KEY_K)
		check(controls.held.size() == 1,"button duplicate-down ignored")
		await process_frame; controls.release(KEY_K); await create_timer(.8).timeout
		if fishing.phase in [fishing.Phase.THROW,fishing.Phase.BAIT_FLYING]: await create_timer(2).timeout
	check(fishing.phase == fishing.Phase.IN_WATER,"bound clickable primary completes real cast")
	if fishing.phase == fishing.Phase.IN_WATER:
		fishing.encounter.bite_timer.stop(); fishing.encounter.bite_window_timer.stop()
		var bait: Node3D = fishing.caster.active_bait
		var distance := bait.global_position.distance_to(fishing.player.global_position)
		controls.press(KEY_K)
		await process_frame
		check(Input.is_action_pressed("enter_fishing"),"click-to-hold drives authoritative held action")
		await create_timer(.12).timeout
		check(not is_instance_valid(bait) or bait.global_position.distance_to(fishing.player.global_position) < distance,"held clickable primary reels inward")
		controls.release(KEY_K)
		await process_frame
		check(not Input.is_action_pressed("enter_fishing"),"release ends reel hold")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/mobile-web/input-qa/desktop-controls-fishing.png")
	bindings.reset_defaults(false)
	var session := root.get_node_or_null("FishingSessionServices")
	host.queue_free(); await settle()
	if session != null: session.queue_free()
	await settle()

func mobile_settings() -> void:
	var fixture := SessionTestFixture.new()
	var host: Control = fixture.mount(self,true)
	for dimensions in [Vector2i(390,844),Vector2i(932,430)]:
		root.size=dimensions; await settle()
		host.request_shell_menu("Settings"); await settle(); await settle()
		var menu: FishingMenu = host.game.find_child("FishingMenu",true,false)
		var pane: Control = menu.keybinding_controls
		check(pane.is_visible_in_tree() and pane.modulate.a > 0,"mobile uses the visible shared Controls editor")
		var button: Button = pane.rows[&"move_forward"]
		var logical: Vector2 = button.get_global_transform_with_canvas()*(button.size*.5)
		var point: Vector2 = host.overlay_image.global_position+logical*host.overlay_image.size/Vector2(host.overlay_viewport.size)
		for down in [true,false]:
			var event := InputEventScreenTouch.new(); event.index=82; event.position=point; event.pressed=down
			Input.parse_input_event(event); await process_frame
		await settle()
		check(bindings.capture_action == &"move_forward","actual mobile touch enters key capture")
		host.controls._hold(KEY_C); await process_frame; await process_frame
		check(not Input.is_action_pressed("world_card_challenge"),"named mobile X cannot acquire held state during capture")
		host.controls._release(KEY_C)
		host.controls.touch_begin(91,host.controls.buttons.B.get_center()); await process_frame
		host.controls.touch_end(91); await settle()
		check(bindings.capture_action == &"" and menu.is_open(),"mobile B cancels capture without closing Settings")
		var scroll_touch := InputEventScreenTouch.new(); scroll_touch.index=94; scroll_touch.pressed=true; scroll_touch.position=point
		Input.parse_input_event(scroll_touch); await process_frame
		var scroll_drag := InputEventScreenDrag.new(); scroll_drag.index=94; scroll_drag.position=point-Vector2(0,110); scroll_drag.relative=Vector2(0,-110)
		Input.parse_input_event(scroll_drag); await process_frame
		scroll_touch.pressed=false; scroll_touch.position=scroll_drag.position; Input.parse_input_event(scroll_touch); await settle()
		check(pane.scroller.scroll_vertical > 0,"touch scroll reaches lower keyboard actions")
		check(bindings.capture_action == &"","scroll gesture does not bind a row")
		bindings.rebind(&"enter_fishing",KEY_O,false)
		var gutter: Rect2 = host.overlay_image.get_global_rect().intersection(host.gameplay_window.get_global_rect())
		var down := InputEventScreenTouch.new(); down.index=92; down.pressed=true; down.position=Vector2(gutter.end.x-8,gutter.get_center().y)
		Input.parse_input_event(down); await process_frame
		var drag := InputEventScreenDrag.new(); drag.index=92; drag.position=down.position-Vector2(0,300); drag.relative=Vector2(0,-300)
		Input.parse_input_event(drag); await process_frame
		down.pressed=false; down.position=drag.position; Input.parse_input_event(down); await settle()
		check(host._surface_scroll > 0,"existing outer menu gutter still scrolls")
		var reset: Button = pane.get_child(0).get_child(2).get_child(0)
		logical=reset.get_global_transform_with_canvas()*(reset.size*.5)
		point=host.overlay_image.global_position+logical*host.overlay_image.size/Vector2(host.overlay_viewport.size)
		check(host.gameplay_window.get_global_rect().has_point(point),"mobile reset button reachable after existing menu scroll")
		for pressed in [true,false]:
			var tap := InputEventScreenTouch.new(); tap.index=93; tap.position=point; tap.pressed=pressed
			Input.parse_input_event(tap); await process_frame
		await settle()
		check(bindings.bindings == bindings.defaults() and bindings._read(bindings.store_path) == bindings.defaults(),"actual mobile touch resets and persists defaults")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://build/mobile-web/input-qa/settings-mobile-%dx%d.png" % [dimensions.x,dimensions.y])
		menu.close_menu(); await settle()
	fixture.release(); await settle()

