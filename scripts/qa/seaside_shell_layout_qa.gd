extends SceneTree
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	var isolated := "CodexSeasideShellQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name",isolated)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for i in range(24): await process_frame
func run() -> void:
	for dimensions in [Vector2(390,763),Vector2(844,390),Vector2(320,560),Vector2(1024,768)]:
		var area := Rect2(Vector2.ZERO,dimensions)
		var r := Layout.mobile(area)
		check(area.encloses(r.world),"mobile world safe "+str(dimensions))
		check(is_equal_approx(r.world.size.x/r.world.size.y,4.0/3),"mobile uniform world")
		check(r.variant == ("mobile_landscape" if dimensions.x>dimensions.y else "mobile_portrait"),"orientation variant")
	for dimensions in [Vector2(480,776),Vector2(899,1000),Vector2(900,800),Vector2(1200,860)]:
		var r := Layout.desktop(dimensions)
		check(Rect2(Vector2.ZERO,dimensions).encloses(r.world),"desktop world safe")
		check(is_equal_approx(r.world.size.x/r.world.size.y,4.0/3),"desktop uniform world")
		check(r.variant == ("desktop_wide" if dimensions.x>=900 else "desktop_narrow"),"breakpoint")
	for mobile in [true,false]:
		var shell: Control = load("res://actors/mobile/MobilePortraitHarness.tscn" if mobile else "res://actors/desktop/DesktopCompanion.tscn").instantiate()
		if mobile: shell.isolated_playtest_save = false
		root.add_child(shell)
		current_scene = shell
		await settle()
		var game: Node = shell.game
		var camera: Camera3D = shell.gameplay_viewport.get_camera_3d()
		var original_fov := camera.fov
		var original_instance := game.get_instance_id()
		var captures := [Vector2i(390,844),Vector2i(844,390)] if mobile else [Vector2i(480,900),Vector2i(1200,860),Vector2i(480,900)]
		for dimensions in captures:
			root.size = dimensions
			if mobile: check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED,"mobile uses CSS/logical pixels in both orientations")
			await settle()
			shell._layout()
			check(game.get_instance_id() == original_instance,"layout preserves session instance")
			check(camera.fov == original_fov,"layout preserves camera FOV")
			check(shell.gameplay_viewport.size == Vector2i(640,480),"layout preserves world canvas")
			check(shell.shell.utility.Settings.visible,"real utility buttons visible")
			if mobile:
				check(shell.controls.BUTTON_KEYS.C == KEY_C,"C mapping preserved")
				check(shell.controls.BUTTON_KEYS.A == KEY_K,"A mapping preserved")
				for rect in shell.controls.buttons.values(): check(Rect2(Vector2.ZERO,shell.controls.size).encloses(rect),"touch hit target contained")
			else:
				check(shell.mode == shell.Mode.ACTIVE,"resize preserves mode")
				check(not shell.passive.timer_entry.visible,"active has no timer panel")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://build/mobile-web/shell-layout/%s-%dx%d.png" % ["mobile" if mobile else "desktop",dimensions.x,dimensions.y])
		var menu: FishingMenu = game.find_child("FishingMenu",true,false)
		for id in ["Inventory","Journal","Settings"]:
			var button: Button = shell.shell.utility[id]
			var touch := InputEventScreenTouch.new()
			touch.index = 77
			touch.position = root.get_final_transform() * (button.get_global_transform_with_canvas() * (button.size*.5))
			touch.pressed = true
			Input.parse_input_event(touch)
			await process_frame
			touch.pressed = false
			Input.parse_input_event(touch)
			await create_timer(.6).timeout
			check(menu.is_open(),id+" uses existing menu modal")
			check(menu._page == {"Inventory":FishingMenu.Page.EQUIP,"Journal":FishingMenu.Page.DATA,"Settings":FishingMenu.Page.OPTIONS}[id],id+" existing page")
			menu.close_menu()
			await create_timer(.6).timeout
		if not mobile:
			shell.passive.require_focus_confirmation = false
			shell.passive.focus_seconds = 120
			shell.set_mode(shell.Mode.PASSIVE)
			var deadline := Time.get_ticks_msec()+15000
			while shell.passive.state != shell.passive.State.FOCUS and Time.get_ticks_msec()<deadline: await process_frame
			check(shell.passive.state == shell.passive.State.FOCUS,"real Passive cast reaches focus")
			var scheduled: float = shell.passive.scheduled_at
			var bait_id: int = game.get_node("Game/Fishing").caster.active_bait.get_instance_id()
			for width in [900,899,1100,480]:
				root.size = Vector2i(width,900)
				await settle()
				check(shell.mode == shell.Mode.PASSIVE and shell.passive.scheduled_at == scheduled,"breakpoint preserves Passive timer")
				check(game.get_node("Game/Fishing").caster.active_bait.get_instance_id() == bait_id,"breakpoint preserves physical bait")
			shell.set_mode(shell.Mode.ACTIVE)
			check(not shell.passive.timer_entry.visible,"Active removes conditional timer")
			if shell.platform.supported() and DisplayServer.get_name() != "headless":
				shell.toggle_shell_fullscreen()
				await settle()
				check(root.mode == Window.MODE_FULLSCREEN,"reference maximize uses fullscreen")
				shell.dock_from_shell(shell.WindowState.DOCK_LEFT)
				var dock_deadline := Time.get_ticks_msec()+8000
				while (not shell.platform.read_status().get("registered",false) or shell._request_pending) and Time.get_ticks_msec()<dock_deadline: await process_frame
				check(shell.docked and root.mode == Window.MODE_WINDOWED,"fullscreen can dock through existing platform path")
				shell.toggle_shell_fullscreen()
				dock_deadline = Time.get_ticks_msec()+8000
				while root.mode != Window.MODE_FULLSCREEN and Time.get_ticks_msec()<dock_deadline: await process_frame
				check(root.mode == Window.MODE_FULLSCREEN and not shell.platform.read_status().get("registered",false),"maximize from dock releases AppBar first")
				shell.toggle_shell_fullscreen()
		shell.queue_free()
		await settle()
	var owned_session := root.get_node_or_null("FishingSessionServices")
	if owned_session != null: owned_session.queue_free()
	await settle()
	print("SEASIDE SHELL QA: ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
