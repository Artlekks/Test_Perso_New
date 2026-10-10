extends RefCounted
## Calls the existing menu/controller paths, including their modal/progression guards.
static func request(host: Node, id: String) -> void:
	if not is_instance_valid(host.game): return
	if id == "Menu":
		send_key(host,KEY_J)
		return
	if id == "Cards":
		if host.get_tree().paused: return
		var event := InputEventAction.new()
		event.action = &"world_card_challenge"
		event.pressed = true
		host.gameplay_viewport.push_input(event,true)
		event = InputEventAction.new()
		event.action = &"world_card_challenge"
		event.pressed = false
		host.gameplay_viewport.push_input(event,true)
		return
	var menu := host.game.find_child("FishingMenu",true,false) as FishingMenu
	if menu == null: return
	if host.get_tree().paused and not menu.is_open(): return
	if id == "Menu" and menu.is_open(): menu.close_menu(); return
	menu.open_menu()
	if not menu.is_open(): return
	match id:
		"Inventory": menu._transition_from_main(FishingMenu.Page.EQUIP)
		"Journal": menu._transition_from_main(FishingMenu.Page.DATA)
		"Settings":
			menu._transition_from_main(FishingMenu.Page.OPTIONS)
			if host.get("controls") != null: _mobile_shortcuts(host,menu)

static func _mobile_shortcuts(host: Node, menu: FishingMenu) -> void:
	# Preserve access to the existing F10 tools without adding controls to the
	# reference active shell. No new debug action or bypass is introduced.
	if menu.options_page.has_node("PlaytestTools"): return
	var button := Button.new()
	button.name = "PlaytestTools"
	button.text = "Playtest tools (F10)"
	button.position = Vector2(24,170)
	button.size = Vector2(272,44)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func():
		if not is_instance_valid(host) or not is_instance_valid(menu): return
		menu.close_menu()
		host.controls._emit_key(KEY_F10,true)
		host.controls._emit_key(KEY_F10,false))
	menu.options_page.add_child(button)

static func send_key(host: Node, key: int) -> void:
	if host.get("controls") != null:
		host.controls._emit_key(key,true)
		host.controls._emit_key(key,false)
	else:
		for pressed in [true,false]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			event.keycode = key
			event.pressed = pressed
			host.gameplay_viewport.push_input(event,true)
