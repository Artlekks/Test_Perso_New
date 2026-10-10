extends SceneTree
## Native work-area verification. A separate Win32 witness checks maximization.
var shell: Node
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	OS.set_environment("FISHING_COMPANION_IPC",ProjectSettings.globalize_path("res://build/desktop-docking"))
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","CompanionDockQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	for i in range(20): await process_frame
func status_ready(registered: bool) -> Dictionary:
	var until := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<until:
		var state: Dictionary = shell.platform.read_status()
		if not shell._request_pending and state.get("sequence",-1) == shell.platform.sequence and state.get("registered",false) == registered:
			if not registered or state.get("reservation",[0,0,0,0])[2]-state.get("reservation",[0,0,0,0])[0] == (shell.collapsed_width if shell.window_state==shell.WindowState.COLLAPSED else shell.dock_width): return state
		if not str(state.get("error","")).is_empty(): print("APPBAR ERROR: ",state); break
		await process_frame
	check(false,"native helper acknowledges request")
	return {}
func check_result_center(label: String) -> void:
	var view: Node = shell.game.get_node("Game/Fishing").fishing_catch_view
	var specimen := FishInstance.new()
	specimen.species = load("res://data/bof4/fish/sea_bream.tres")
	view.show_catch(specimen,{"fishing_points":120,"rank_id":"novice"})
	await create_timer(view.slide_time + 0.1).timeout
	var display: Rect2 = shell.gameplay_display_rect()
	var logical: Vector2 = view.root.position + view.composed_result_rect().get_center()
	var physical: Vector2 = display.position + logical * display.size / Vector2(shell.SURFACE)
	check(physical.distance_to(display.get_center()) < 0.01,label+" catch group centered excluding chrome/letterbox")
	if label.ends_with("360") or label.ends_with("620"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/desktop-docking/catch-"+label+".png")
	view.hide_catch()
func run() -> void:
	shell = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	shell.passive.require_focus_confirmation = false
	current_scene = shell
	await settle()
	check(shell.platform.supported(),"native Windows adapter available")
	var session_id := root.get_node("FishingSessionServices").get_instance_id()
	var game_id: int = shell.game.get_instance_id()
	var camera: Transform3D = shell.gameplay_viewport.get_camera_3d().global_transform
	var floating := Rect2i(root.position,root.size)
	await check_result_center("floating")
	shell.set_docked(true)
	var initial := await status_ready(true)
	if initial.is_empty(): shell.set_docked(false); shell.platform.close(); quit(1); return
	var baseline: Array = initial.baseline
	FileAccess.open("res://build/desktop-docking/native-fixture.json",FileAccess.WRITE).store_string(JSON.stringify({"command":shell.platform.command_path,"status":shell.platform.status_path,"baseline":baseline,"pid":OS.get_process_id()}))
	for edge in [shell.WindowState.DOCK_RIGHT,shell.WindowState.DOCK_LEFT,shell.WindowState.DOCK_RIGHT]:
		shell.set_window_state(edge)
		for width in [480,620,360,540,480]:
			shell.set_dock_width(width)
			await settle()
			var state := await status_ready(true)
			if state.is_empty(): continue
			print("NATIVE APPBAR SAMPLE: ",JSON.stringify(state))
			check(state.reservation[2]-state.reservation[0] == width,"live dock width %d" % width)
			check(state.work_area[0] == state.reservation[2] if edge == shell.WindowState.DOCK_LEFT else state.work_area[2] == state.reservation[0],"ordinary desktop excludes selected edge")
			check(state.window[0] == state.reservation[0] and state.window[2] == state.reservation[2],"companion remains attached")
			check(shell.game.get_instance_id() == game_id and root.get_node("FishingSessionServices").get_instance_id() == session_id,"same session through resizing")
			check(shell.gameplay_viewport.size == Vector2i(640,480) and not paused,"canonical session retained")
			check(shell.gameplay_viewport.get_camera_3d().global_transform == camera,"windowing leaves camera unchanged")
			await check_result_center(("left-" if edge == shell.WindowState.DOCK_LEFT else "right-")+str(width))
		# Sample every engine frame during continuous commanded resize, not just
		# the final acknowledgement. Physical outer edge must never flip sides.
		var monitor: Array = shell.platform.read_status().monitor
		for frame in range(150):
			if frame % 3 == 0: shell.set_dock_width(roundi(480+140*sin(frame*.09)))
			await process_frame
			var edge_x := root.position.x if edge == shell.WindowState.DOCK_LEFT else root.position.x+root.size.x
			check(shell.docked and shell.window_state == edge,"resize keeps exclusive native geometry ownership on frame %d" % frame)
			# Window position/size are separate cached WM_MOVE/WM_SIZE fields.
			# Physical per-frame edge is sampled atomically with GetWindowRect
			# by verify_companion_docking.py, not by combining stale cached fields.
		shell.set_dock_width(480)
		await status_ready(true)
		var before := Rect2i(root.position,root.size)
		shell.set_mode(99)
		check(Rect2i(root.position,root.size)==before and shell.mode==shell.Mode.ACTIVE,"invalid legacy mode recovers without shrinking")
		shell.toggle_collapse()
		await settle()
		var collapsed := await status_ready(false)
		if collapsed.is_empty(): shell.queue_free(); quit(1); return
		check(collapsed.work_area == baseline and not collapsed.registered,"collapse releases full work area")
		check(collapsed.window[2]-collapsed.window[0] == shell.collapsed_width and collapsed.window[3]-collapsed.window[1] == shell.WIDGET_HEIGHT,"collapse leaves only tiny edge widget")
		check(shell.effective_window_state()==edge,"collapse remembers edge")
		shell.toggle_collapse()
		await settle()
		var expanded := await status_ready(true)
		if expanded.is_empty(): shell.queue_free(); quit(1); return
		check(expanded.reservation[2]-expanded.reservation[0]==480 and shell.dock_width==480,"expand restores exact previous width")
	# Real Passive entry/cast while docked. Activity never writes geometry or
	# drops the native reservation, including across a left/right presentation.
	for edge in [shell.WindowState.DOCK_LEFT,shell.WindowState.DOCK_RIGHT]:
		shell.set_window_state(edge)
		await status_ready(true)
		await settle()
		var activity_rect := Rect2i(root.position,root.size)
		shell.passive.focus_seconds=100
		shell.set_mode(shell.Mode.PASSIVE)
		check(shell.mode==shell.Mode.PASSIVE,"docked Passive accepted")
		var deadline := Time.get_ticks_msec()+15000
		while shell.passive.state!=shell.passive.State.FOCUS and Time.get_ticks_msec()<deadline: await process_frame
		check(shell.passive.state==shell.passive.State.FOCUS,"docked passive production cast reaches water")
		check(Rect2i(root.position,root.size)==activity_rect,"Passive preserves dock geometry")
		shell.set_mode(shell.Mode.ACTIVE)
		check(Rect2i(root.position,root.size)==activity_rect,"Active preserves dock geometry")
		check(shell.window_state==edge and shell.platform.read_status().get("registered",false),"activity keeps edge and reservation")
		var fishing: Node = shell.game.get_node("Game/Fishing")
		if fishing.phase==fishing.Phase.IN_WATER: fishing._cancel_water_cast_to_aim()
		await create_timer(.3).timeout
	var fishing_after: Node = shell.game.get_node("Game/Fishing")
	var cancel := InputEventAction.new()
	cancel.action=&"cancel_fishing"; cancel.pressed=true
	fishing_after._unhandled_input(cancel)
	var exit_deadline := Time.get_ticks_msec()+15000
	while not fishing_after.game_mode.is_exploration() and Time.get_ticks_msec()<exit_deadline: await process_frame
	check(fishing_after.game_mode.is_exploration(),"docked passive returns through normal fishing exit")
	if OS.get_cmdline_user_args().has("--hold-docked"):
		print("DOCK QA HOLD READY")
		await create_timer(30).timeout
	var dock_geometry := Rect2i(root.position,root.size)
	shell.set_docked(false)
	var released := await status_ready(false)
	await settle()
	check(released.get("work_area",[]) == baseline,"Undock restores native work area exactly")
	check(Rect2i(root.position,root.size) == dock_geometry,"Float preserves current dock geometry")
	# Prove a live remapping updates only the reminder, not a fake gameplay path.
	var original := InputMap.action_get_events(&"world_card_challenge")
	InputMap.action_erase_events(&"world_card_challenge")
	var binding := InputEventKey.new()
	binding.physical_keycode = KEY_V
	InputMap.action_add_event(&"world_card_challenge",binding)
	await settle()
	check(shell.keyboard_strip.text.contains("V  Cards"),"strip follows live InputMap")
	InputMap.action_erase_events(&"world_card_challenge")
	for event in original: InputMap.action_add_event(&"world_card_challenge",event)
	check(shell.find_children("TouchControls","",true,false).is_empty(),"desktop has no touch buttons")
	shell.set_docked(true)
	await status_ready(true)
	shell.queue_free()
	await create_timer(.7).timeout
	print("Desktop Companion Docking QA: %d/%d; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
