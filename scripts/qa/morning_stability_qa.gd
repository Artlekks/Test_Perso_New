extends SceneTree
## Production controllers, disposable persistent state, real pressed/releases.
var checks := 0
var failures: Array[String] = []
var shell: Node
var fishing: Node
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","MorningStabilityQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(count := 3) -> void:
	for frame in range(count): await process_frame
func key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
func modal_released(label: String) -> void:
	check(not paused, label + " releases modal pause")
	# Keep K held across close, including repeated keydown events after close.
	await frames()
	key(KEY_K,true)
	await frames()
	check(fishing.game_mode.is_exploration(), label + " held confirm cannot enter fishing")
	key(KEY_K,false)
	key(KEY_I,false)
	await frames()
	var event := InputEventKey.new()
	event.physical_keycode = KEY_K; event.pressed = true
	check(ModalInputOwnership.gameplay_accepts(fishing,event), label + " release permits next fresh physical press")
func run() -> void:
	shell = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	current_scene = shell
	await create_timer(1.0).timeout
	fishing = shell.game.get_node("Game/Fishing")
	fishing.player.rotation.y = PI
	check(shell.game.get_node("World/FishZone_V2").can_player_fish(fishing.player),"fixture stands at a valid fishing entry so input leaks are observable")
	var session := root.get_node("FishingSessionServices")
	var gate := root.get_node("ModalInputGate")
	gate.arm()
	key(KEY_SPACE,false)
	await frames()
	var fresh := InputEventKey.new()
	fresh.physical_keycode = KEY_K; fresh.pressed = true
	check(ModalInputOwnership.gameplay_accepts(fishing,fresh),"manual pause Space release permits next fresh action")
	DeveloperPlaytestService.current().set_enabled(true)
	var cards: Node = shell.game.get_node("UI/TripleTriadGame")
	for cycle in range(4):
		for name in ["FishingEconomyMenu","BeachCraftingMenu","FishingCardMakerMenu","FishingMenu"]:
			var menu: Node = shell.game.find_child(name,true,false)
			if name == "FishingEconomyMenu": menu.open_debug_full_catalog_menu()
			else: menu.open_menu()
			await frames()
			check(menu.is_open(),name+" opens")
			var surface := menu.find_child("ResponsiveMenuSurface",true,false)
			if surface != null:
				var selected_borders := 0
				for binding in surface.bindings:
					var border := binding.label.get_node("SelectionOverlay") as NinePatchRect
					if border.visible:
						selected_borders += 1
						check(border.z_index > 0 and not border.draw_center and border.texture.resource_path.ends_with("Menu_Hint_Panel_Selector.png"),name+" approved selector above text/dim")
				check(selected_borders > 0,name+" selection remains visible")
				if name == "BeachCraftingMenu":
					var detail_position: Vector2 = surface.fixed_stack.global_position
					menu._move_recipe(1)
					await frames()
					check(surface.fixed_stack.global_position == detail_position and not surface.scroll.is_ancestor_of(surface.fixed_stack),"crafting detail remains outside recipe scroll")
					if cycle == 0:
						await RenderingServer.frame_post_draw
						shell.gameplay_viewport.get_texture().get_image().save_png("res://build/desktop-docking/morning-crafting.png")
			key(KEY_K,true)
			await frames()
			menu.close_menu()
			await modal_released(name)
		check(cards.open_game_by_id(shell.game.get_node("World/TripleTriadOpponentNPC").opponent_id),"card NPC opens")
		await frames()
		var deck: Control = cards.deck_setup
		deck._nav_zone = deck.NAV_DECK
		key(KEY_K,true); key(KEY_K,false)
		await frames()
		check(deck._slot_replacement_requested == deck._deck_cursor_index,"K edits exact selected slot")
		check(deck._deck_outlines[deck._deck_cursor_index].visible and deck._collection_outlines.any(func(border): return border.visible),"slot and collection outlines visible simultaneously")
		key(KEY_I,true); key(KEY_I,false)
		await frames()
		check(deck._nav_zone == deck.NAV_DECK,"Back cancels slot edit")
		key(KEY_I,true); key(KEY_I,false)
		await frames()
		key(KEY_K,true)
		cards.close_game()
		await modal_released("Triple Triad/deck")
		check(session.dialogue_service.start_inline_dialogue(&"morning",[{"speaker":"QA","text":"Input owner"}]).success,"dialogue opens")
		await frames()
		key(KEY_K,true)
		if session.dialogue_service.is_active(): session.dialogue_service.advance()
		await modal_released("dialogue")
	# Real persistent cards: removing membership never changes quantities.
	DeveloperPlaytestService.current().set_enabled(false)
	var owned = cards._collection_backend
	var policy = load("res://data/triple_triad/acquisition/default_acquisition_policy.tres")
	var catalog = load("res://data/triple_triad/card_catalog.tres")
	var starter: Array = policy.build_starting_collection(catalog)
	for card in starter: owned.acquire_card(card)
	var extra: Resource
	for candidate in catalog.get_cards_for_level_range(1,1):
		if not starter.has(candidate): extra = candidate; break
	check(extra != null,"fixture has an authored unused eligible card")
	if extra != null: owned.acquire_card(extra)
	var quantities: Dictionary = owned.get_quantities_snapshot()
	var deck: Control = cards.deck_setup
	deck.open_setup(catalog,30,6,owned,policy)
	for profile in range(6):
		deck._total_profiles = maxi(deck._total_profiles,6)
		deck._profile_index = profile
		deck._deck = starter.duplicate()
		deck._nav_zone = deck.NAV_DECK
		deck._deck_cursor_index = 2
		deck._activate_navigation_target()
		var before: Array = deck._deck.duplicate()
		deck._handle_back_navigation()
		check(deck._deck == before,"profile %d cancel leaves deck untouched" % profile)
		deck._activate_navigation_target()
		deck._cursor_index = deck._cards.find(starter[2])
		deck._select_cursor_card()
		check(deck._deck.size() == 4 and not deck._deck.has(starter[2]),"profile %d explicit membership removal" % profile)
		deck._load_profile(profile)
		check(deck._deck.size() == 4 and not deck._deck.has(starter[2]),"profile %d exact short deck reload" % profile)
		check(owned.get_quantities_snapshot() == quantities,"profile %d collection ownership unchanged" % profile)
		# Replace a filled slot in an incomplete deck: never append to another slot.
		if extra != null:
			deck._nav_zone = deck.NAV_DECK
			deck._deck_cursor_index = 1
			deck._activate_navigation_target()
			deck._cursor_index = deck._cards.find(extra)
			deck._select_cursor_card()
			await create_timer(0.8).timeout
			check(deck._deck.size() == 4 and deck._deck[1] == extra,"profile %d replaces exact filled slot in short deck" % profile)
			deck._load_profile(profile)
			check(deck._deck[1] == extra,"profile %d replacement survives reload" % profile)
		check(owned.get_quantities_snapshot() == quantities,"profile %d replacement preserves ownership" % profile)
	deck._player_rank = 0
	deck._nav_zone = deck.NAV_COLLECTION
	deck._cursor_index = 0
	deck._refresh_all()
	check(deck._collection_views[0].modulate != Color.WHITE and deck._collection_outlines[0].visible,"disabled card retains visible selector")
	check(deck._collection_outlines[0].modulate == Color.WHITE and deck._collection_outlines[0].z_index > deck._collection_views[0].z_index,"selector draws above card dim and cost overlays")
	deck._player_rank = 6
	deck.hide()
	DeveloperPlaytestService.current().set_enabled(true)
	check(cards.open_game_by_id(shell.game.get_node("World/TripleTriadOpponentNPC").opponent_id),"real visible card interface opens for selector render")
	await frames()
	deck = cards.deck_setup
	deck._nav_zone = deck.NAV_DECK
	deck._deck_cursor_index = 0
	deck._activate_navigation_target()
	deck._player_rank = 0
	deck._cursor_index = 0
	deck._refresh_all()
	await frames()
	await RenderingServer.frame_post_draw
	shell.gameplay_viewport.get_texture().get_image().save_png("res://build/desktop-docking/morning-deck-selectors.png")
	cards.close_game()
	key(KEY_I,false)
	await frames()
	check(is_equal_approx(fishing.encounter.resolve_bite_opportunity_chance(0.1,true),0.7),"ready engaged fish uses authored 70 percent probability")
	check(is_equal_approx(fishing.encounter.resolve_bite_opportunity_chance(0.1,false),0.1),"nearby ambient fish does not get engaged probability")
	var passive: Node = shell.passive
	check(passive.parse_focus("20") == 1200 and passive.parse_focus("01:30") == 90 and passive.parse_focus("1:99") < 0,"timer parses minutes/MM:SS and rejects invalid seconds")
	check(passive.begin(),"production Passive auto-cast starts")
	var until := Time.get_ticks_msec()+20000
	while passive.state != passive.State.CONFIGURING and Time.get_ticks_msec() < until: await process_frame
	check(passive.state == passive.State.CONFIGURING and passive.elapsed == 0,"settled cast waits for timer confirmation; clock not running")
	await create_timer(0.3).timeout
	check(passive.elapsed == 0 and not fishing.encounter.bite_active,"unconfirmed timer never starts focus or opportunity")
	passive.timer_entry.text = "00:03"
	key(KEY_K,true); key(KEY_K,false)
	await frames()
	check(passive.state == passive.State.FOCUS and passive.focus_seconds == 3,"context K confirms selected focus duration")
	var ripple: Node = fishing.caster.active_bait.ripple_view
	ripple.show_ripple(1.2)
	check(is_equal_approx(ripple.ripple_sprite.pixel_size,0.00175) and ripple.ripple_sprite.animation == &"Ripple","authored ripple is half-size, not splash")
	check(is_equal_approx(ripple.get_authored_ripple_duration()/ripple.ripple_sprite.speed_scale,1.2),"ripple presentation lifetime matches opportunity")
	ripple.show_bite_splash()
	check(ripple.ripple_sprite.animation == &"BiteSplash" and is_equal_approx(ripple.ripple_sprite.pixel_size,ripple.bite_pixel_size),"confirmed splash keeps stronger presentation size")
	ripple.hide_ripple()
	check(not ripple.active,"surface effect cleans up")
	passive.cancel("QA end",true)
	check(not passive.timer_entry.visible,"timer cleans up on cancel")
	check(fishing.caster.active_bait == null,"cancel keeps normal bait teardown")
	shell.queue_free(); await frames()
	session.queue_free(); await frames()
	print("Morning Stability QA: %d/%d; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
