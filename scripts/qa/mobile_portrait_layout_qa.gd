extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "PortraitLayoutQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for i in range(12): await process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://build/mobile-web/portrait-captures/"+label+".png") == OK, "rendered " + label)
func run() -> void:
	var shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	shell.isolated_playtest_save = false
	shell.developer_playtest_default_enabled = false
	root.add_child(shell)
	current_scene = shell
	await settle()
	root.size = Vector2i(390,664)
	await settle()
	shell._layout()
	check(is_equal_approx(shell.gameplay_image.size.x, shell.safe_rect.size.x), "short portrait fills all safe width")
	check(shell._surface_scroll_max > 0, "short window deliberately crops vertically")
	check(is_equal_approx(shell._surface_scroll,shell._surface_scroll_max), "world crop preserves bottom HUD")
	check(shell.gameplay_viewport.size == Vector2i(640,864), "display crop never resizes canonical gameplay")
	for label in shell.controls.buttons:
		var hit: Rect2 = shell.controls.buttons[label]
		for other in shell.controls.buttons:
			if label < other: check(not hit.intersects(shell.controls.buttons[other]), "short controls separated " + label + "/" + other)
	var scale := root.get_final_transform().get_scale()
	print("SHORT PORTRAIT CSS GEOMETRY: image=",shell.gameplay_image.size*scale," display=",shell.gameplay_window.size*scale," controls=",shell.controls.size*scale)
	await capture("short-world")
	var game: Node = shell.game
	var session := root.get_node("FishingSessionServices")
	var session_id := session.get_instance_id()
	var menu: Node = game.get_node("Game/Fishing").fishing_menu
	menu.open_menu()
	await settle()
	check(is_zero_approx(shell._surface_scroll), "modal exposes canonical top first")
	await capture("short-menu-top")
	var start: Vector2 = shell.gameplay_window.get_global_rect().end - Vector2(5,50)
	var touch := InputEventScreenTouch.new()
	touch.index = 90
	touch.position = start
	touch.pressed = true
	shell._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 90
	drag.position = start - Vector2(0,1000)
	shell._input(drag)
	touch.pressed = false
	shell._input(touch)
	check(is_equal_approx(shell._surface_scroll,shell._surface_scroll_max), "actual right-edge touch drag reaches canonical bottom")
	check(shell._surface_drag == -1, "display touch ownership clears on release")
	check(session.get_instance_id() == session_id and paused, "display scroll does not steal modal/session ownership")
	await capture("short-menu-bottom")
	menu.close_menu()
	await settle()
	check(not paused and is_equal_approx(shell._surface_scroll,shell._surface_scroll_max), "menu close restores world HUD crop and processing")
	paused = true
	await settle()
	check(is_equal_approx(shell._surface_scroll,shell._surface_scroll_max), "manual pause does not crop away bottom world HUD")
	paused = false
	var specimen := FishInstance.new()
	specimen.species = load("res://data/bof4/fish/sea_bream.tres")
	var catch_view = game.get_node("Game/Fishing").fishing_catch_view
	catch_view.show_catch(specimen,{})
	await settle()
	check(not paused and is_zero_approx(shell._surface_scroll), "unpaused catch presentation exposes its header")
	catch_view.hide_catch()
	await settle()
	check(is_equal_approx(shell._surface_scroll,shell._surface_scroll_max), "catch view close restores world crop")
	shell.queue_free()
	session.queue_free()
	await settle()
	check(Node.get_orphan_node_ids().is_empty(), "display shell leaves no orphan nodes")
	print("Mobile Portrait Layout QA: %d/%d; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
