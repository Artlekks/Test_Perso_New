extends SceneTree
## Render the real companion, including a production cast and native minimum dock.
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
var checks := 0
var failures: Array[String] = []
var measurements: Array[Dictionary] = []
var host: Control
var fishing: Node
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","DesktopResponsiveQA-%d" % Time.get_ticks_usec())
	OS.set_environment("FISHING_COMPANION_IPC",ProjectSettings.globalize_path("res://build/mobile-web/desktop-responsive/ipc"))
	DirAccess.make_dir_recursive_absolute("res://build/mobile-web/desktop-responsive")
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for i in range(30): await process_frame
func capture(label: String) -> void:
	await settle()
	var r: Dictionary = host.shell.regions
	var display: Rect2 = host.gameplay_display_rect()
	check(display == r.world,"uniform world fits layout "+label)
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(r.toolbar),"toolbar inside client "+label)
	check(not host.keyboard_strip.visible,"no permanent instructions "+label)
	if label.ends_with("fishing"):
		var power: Node = fishing.power_meter_view
		var bg: Sprite2D = power.get_node("Root/PowerBarBG")
		var bounds: Rect2 = bg.get_global_transform_with_canvas()*bg.get_rect()
		check(absf(bounds.position.x-power.fishing_stance_right_pixels()-bounds.size.y*power.character_to_bar_gap_ratio)<.01,"same player-relative HUD ratio "+label)
		check(absf(fishing.depth_meter_view.rest_position.x-power._rest_position.x-357)<.01,"approved gauge spacing "+label)
		check(power.root.scale == Vector2(.35,.35) and fishing.depth_meter_view.scale == Vector2(.36,.36),"HUD artwork scale unchanged "+label)
	check(not host.shell.utility.Inventory.visible and not host.shell.utility.Cards.visible,"menu remains J entry "+label)
	var row := {"case":label,"client":str(root.size),"header_height":r.info.size.y,"world":str(display),"resolution":str(host.gameplay_viewport.size),"client_game_percent":100*display.get_area()/(root.size.x*root.size.y),"toolbar":str(r.toolbar),"dashboard":str(r.dashboard),"native":native_geometry()}
	measurements.append(row)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mobile-web/desktop-responsive/"+label+".png")
func key(down: bool) -> void:
	var event := InputEventAction.new(); event.action=&"enter_fishing"; event.pressed=down
	fishing._unhandled_input(event)
func run() -> void:
	check(Layout.desktop(Vector2(1200,740)).resolution.x == 960,"wide available area selects 2:1")
	check(Layout.desktop(Vector2(800,560)).resolution.x == 640,"regular area selects 4:3")
	check(Layout.desktop(Vector2(1200,740),Vector2i(640,480),true).resolution.x == 640,"docking selects canonical world")
	check(Layout.desktop(Vector2(1200,740),Vector2i(640,480),false,true).resolution.x == 640,"fishing locks shape")
	# A 1.7 available ratio retains either previous shape (hysteresis).
	for prior in [Vector2i(640,480),Vector2i(960,480)]:
		check(Layout.desktop(Vector2(828,574),prior).resolution == prior,"shape retained in hysteresis band")
	for dimensions in [Vector2i(1280,760),Vector2i(800,560),Vector2i(1268,1494),Vector2i(320,400)]:
		root.mode=Window.MODE_WINDOWED
		host=load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
		root.add_child(host); current_scene=host; await settle()
		root.size=dimensions
		if dimensions.x == 1280: root.mode=Window.MODE_MAXIMIZED
		if dimensions.x == 1268 and host.platform.supported():
			var geometry := native_geometry()
			var outer: Array = geometry.window
			var client: Array = geometry.client
			var work: Array = geometry.work_area
			var chrome := Vector2i(int(outer[2]-outer[0]-client[2]),int(outer[3]-outer[1]-client[3]))
			root.size=Vector2i(int((work[2]-work[0])/2),int(work[3]-work[1]))-chrome
			root.position += Vector2i(int(work[0]-outer[0]),int(work[1]-outer[1]))
		var narrow: bool = dimensions.x == 320
		if narrow and DisplayServer.get_name() != "headless":
			host.set_dock_width(320); host.set_window_state(host.WindowState.DOCK_LEFT)
			var deadline := Time.get_ticks_msec()+8000
			while Time.get_ticks_msec()<deadline:
				var state: Dictionary = host.platform.read_status()
				if state.get("registered",false) and state.get("sequence",-1) == host.platform.sequence: break
				await process_frame
			check(host.docked and host.platform.read_status().get("registered",false),"minimum dock actually owns AppBar")
		await settle(); host._layout()
		var label := "expanded" if dimensions.x == 1280 else "half-screen" if dimensions.x == 1268 else "regular" if not narrow else "minimum-dock"
		await capture(label+"-exploration")
		check((host.shell.utility.Window as MenuButton).get_popup().item_count == 4,"window actions grouped without native caption duplicates")
		if host.shell.dashboard.visible:
			var world_before: Rect2 = host.gameplay_display_rect()
			var body: Label = host.shell.dashboard.records
			body.get_parent().get_child(0).pressed.emit(); await settle()
			check(not body.visible and host.gameplay_display_rect() == world_before,"dashboard folds without resizing gameplay")
			body.get_parent().get_child(0).pressed.emit()
		var game_id: int = host.game.get_instance_id()
		var camera: Camera3D = host.gameplay_viewport.get_camera_3d()
		var camera_pose: Transform3D = camera.global_transform
		host.shell._activate("Equipment"); await settle()
		check(host.shell.equipment_drawer.visible,"shared drawer opens "+label)
		host.shell._equipment_action("Pin / unpin")
		check(host.shell.equipment_pinned,"drawer pins")
		check(camera.global_transform == camera_pose,"drawer leaves camera untouched")
		host.shell._equipment_action("Close")
		check(host.shell.environment_strip.state.wind == "N/A" and not host.shell.snapshot.time.contains(":"),"no fabricated clock or wind")
		fishing=host.game.get_node("Game/Fishing")
		fishing.player.global_basis=host.game.get_node("World/FishZone_V2/WaterFacing").global_basis
		fishing.game_mode.enter_fishing(host.game.get_node("World/FishZone_V2"))
		for frame in range(600):
			if fishing.phase == fishing.Phase.AIM: break
			await process_frame
		for attempt in range(6):
			if fishing.phase == fishing.Phase.IN_WATER: break
			key(true); await process_frame; key(false); await create_timer(.8).timeout
			if fishing.phase in [fishing.Phase.THROW,fishing.Phase.BAIT_FLYING]: await create_timer(2).timeout
		check(fishing.phase == fishing.Phase.IN_WATER,"normal cast reaches water "+label)
		fishing.encounter.bite_timer.stop(); fishing.encounter.bite_window_timer.stop()
		await capture(label+"-fishing")
		if OS.get_cmdline_user_args().has("--tall-experiment") and label == "regular": await tall_experiment()
		var resolution: Vector2i = host.gameplay_viewport.size
		var bait_id: int = fishing.caster.active_bait.get_instance_id()
		if not narrow:
			fishing.camera_rig.set_process(false)
			fishing.caster.active_bait.set_physics_process(false)
			var pose: Transform3D = camera.global_transform
			root.mode=Window.MODE_WINDOWED
			root.size=Vector2i(800,560) if dimensions.x == 1280 else Vector2i(1280,760)
			await settle()
			check(host.gameplay_viewport.size == resolution,"resize defers world shape during fishing")
			check(host.game.get_instance_id() == game_id and fishing.caster.active_bait.get_instance_id() == bait_id,"resize keeps physical session")
			check(host.mode == host.Mode.ACTIVE,"resize leaves activity mode")
			check(camera.global_transform == pose,"resizing introduces no camera transform")
			fishing.camera_rig.set_process(true)
			fishing.caster.active_bait.set_physics_process(true)
			fishing._cancel_water_cast_to_aim()
			await create_timer(.5).timeout
			var cancel := InputEventAction.new(); cancel.action=&"cancel_fishing"; cancel.pressed=true
			fishing._unhandled_input(cancel)
			var deadline := Time.get_ticks_msec()+15000
			while not fishing.game_mode.is_exploration() and Time.get_ticks_msec()<deadline: await process_frame
			await settle()
			check(fishing.game_mode.is_exploration(),"normal fishing exit completes")
			check(host.gameplay_viewport.size == Layout.desktop(Vector2(root.size),resolution).resolution,"deferred shape applies after safe exit")
		var session := root.get_node_or_null("FishingSessionServices")
		host.queue_free(); await settle()
		if session != null: session.queue_free()
		await settle()
	FileAccess.open("res://build/mobile-web/desktop-responsive/measurements.json",FileAccess.WRITE).store_string(JSON.stringify(measurements,"\t"))
	print("RESPONSIVE DESKTOP UI QA: ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)


func tall_experiment() -> void:
	# Disposable projection experiment only. Never called by production.
	var camera: Camera3D = host.gameplay_viewport.get_camera_3d()
	var previous: Vector2i = host.gameplay_viewport.size
	var fov := camera.fov
	var aspect := camera.keep_aspect
	var pose := camera.global_transform
	fishing.camera_rig.set_process(false)
	fishing.caster.active_bait.set_physics_process(false)
	var point: Vector3 = fishing.player.global_position
	var before := camera.unproject_position(point)
	var before_scale := camera.unproject_position(point+camera.global_basis.x*.01).distance_to(before)
	camera.keep_aspect=Camera3D.KEEP_WIDTH
	camera.fov=rad_to_deg(2*atan(tan(deg_to_rad(fov)*.5)*float(previous.x)/previous.y))
	host.gameplay_viewport.size=Vector2i(640,864)
	host._layout(); await settle()
	var after := camera.unproject_position(point)
	var after_scale := camera.unproject_position(point+camera.global_basis.x*.01).distance_to(after)
	var data := {"before_foot":str(before),"tall_foot":str(after),"before_pixel_scale":before_scale,"tall_pixel_scale":after_scale,"power_y":fishing.power_meter_view._rest_position.y,"camera_pose_unchanged":camera.global_transform == pose,"decision":"Reject: fixed pixel scale reveals vertical world but shifts physical foot relative to the approved HUD/composition"}
	check(absf(before_scale-after_scale)<.001,"tall experiment preserves apparent player pixel scale")
	check(camera.global_transform == pose,"tall experiment uses no camera translation")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/mobile-web/desktop-responsive/tall-experiment.png")
	FileAccess.open("res://build/mobile-web/desktop-responsive/tall-experiment.json",FileAccess.WRITE).store_string(JSON.stringify(data,"\t"))
	camera.keep_aspect=aspect; camera.fov=fov
	host.gameplay_viewport.size=previous; host._layout()
	fishing.camera_rig.set_process(true); fishing.caster.active_bait.set_physics_process(true)

func native_geometry() -> Dictionary:
	if DisplayServer.get_name() == "headless": return {}
	var python := OS.get_environment("USERPROFILE").path_join(".cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe")
	var output: Array = []
	var result := OS.execute(python,[ProjectSettings.globalize_path("res://tools/desktop/inspect_window.py"),str(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE))],output)
	check(result == 0,"read-only native geometry witness succeeds")
	var parsed = JSON.parse_string("".join(output))
	return parsed if parsed is Dictionary else {}
