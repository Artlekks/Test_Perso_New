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
		if state.get("sequence",-1) == shell.platform.sequence and state.get("registered",false) == registered: return state
		if not str(state.get("error","")).is_empty(): print("APPBAR ERROR: ",state); break
		await process_frame
	check(false,"native helper acknowledges request")
	return {}
func run() -> void:
	shell = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	current_scene = shell
	await settle()
	check(shell.platform.supported(),"native Windows adapter available")
	var session_id := root.get_node("FishingSessionServices").get_instance_id()
	var game_id: int = shell.game.get_instance_id()
	var camera: Transform3D = shell.gameplay_viewport.get_camera_3d().global_transform
	var floating := Rect2i(root.position,root.size)
	shell.set_docked(true)
	var initial := await status_ready(true)
	if initial.is_empty(): shell.set_docked(false); shell.platform.close(); quit(1); return
	var baseline: Array = initial.baseline
	FileAccess.open("res://build/desktop-docking/native-fixture.json",FileAccess.WRITE).store_string(JSON.stringify({"command":shell.platform.command_path,"status":shell.platform.status_path,"baseline":baseline,"pid":OS.get_process_id()}))
	for mode in [shell.Mode.ACTIVE,shell.Mode.PASSIVE,shell.Mode.COLLAPSED,shell.Mode.ACTIVE]:
		shell.set_mode(mode)
		var state := await status_ready(true)
		if state.is_empty(): continue
		print("NATIVE APPBAR SAMPLE: ",JSON.stringify(state))
		var width: int = [shell.dock_active_width,shell.dock_passive_width,shell.dock_collapsed_width][mode]
		check(state.reservation[2]-state.reservation[0] == width,"mode reserved width %d" % width)
		check(state.work_area[2] == state.reservation[0],"ordinary desktop excludes reservation")
		check(state.window[0] == state.reservation[0] and state.window[2] == state.reservation[2],"companion flush inside reserved strip")
		check(state.reservation[1] == baseline[1] and state.reservation[3] == baseline[3],"taskbar vertical clearance respected")
		check(shell.game.get_instance_id() == game_id and root.get_node("FishingSessionServices").get_instance_id() == session_id,"same game/session survives docking mode")
		check(shell.gameplay_viewport.size == Vector2i(640,864) and not paused,"canonical running session retained")
		check(shell.gameplay_viewport.get_camera_3d().global_transform == camera,"docking leaves camera unchanged")
		await create_timer(.3).timeout
	if OS.get_cmdline_user_args().has("--hold-docked"):
		print("DOCK QA HOLD READY")
		await create_timer(30).timeout
	shell.set_docked(false)
	var released := await status_ready(false)
	await settle()
	check(released.get("work_area",[]) == baseline,"Undock restores native work area exactly")
	check(Rect2i(root.position,root.size) == floating,"Undock restores floating geometry")
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
