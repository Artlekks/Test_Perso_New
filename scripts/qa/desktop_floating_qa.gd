extends SceneTree
var shell: Node
var checks := 0
var failures: Array[String] = []
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","FloatingOwnershipQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute("res://build/mobile-web/safe-rectangle")
	OS.set_environment("FISHING_COMPANION_IPC",ProjectSettings.globalize_path("res://build/mobile-web/safe-rectangle/ipc"))
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle() -> void:
	await create_timer(.5).timeout
func released(expected: bool) -> void:
	var deadline := Time.get_ticks_msec()+8000
	while Time.get_ticks_msec()<deadline:
		var status: Dictionary = shell.platform.read_status()
		if status.get("sequence",-1) == shell.platform.sequence and status.get("registered",false) == expected and not shell._pending_float_decoration and not shell._request_pending: return
		await process_frame
	check(false,"AppBar acknowledges ownership transition")
func run() -> void:
	shell = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	current_scene = shell
	await settle()
	var ids := [shell.game.get_instance_id(),root.get_node("FishingSessionServices").get_instance_id()]
	for edge in [shell.WindowState.DOCK_LEFT,shell.WindowState.DOCK_RIGHT]:
		shell.set_window_state(edge)
		await released(true)
		check(shell.platform.read_status().get("registered",false),"dock owns AppBar")
		shell.set_window_state(shell.WindowState.FLOATING)
		await released(false)
		check(not root.borderless and not root.unresizable,"Float is decorated and resizable")
		check(not shell.platform.read_status().get("registered",true),"Float releases reservation")
		var rectangle := Rect2i(root.position,root.size)
		root.position += Vector2i(-35,20)
		root.size += Vector2i(25,20)
		var manual := Rect2i(root.position,root.size)
		await settle()
		check(Rect2i(root.position,root.size) == manual,"manual Float move/resize survives geometry polling")
		shell.toggle_shell_fullscreen()
		await settle()
		check(root.mode == Window.MODE_MAXIMIZED and not root.borderless,"normal maximization retains Windows title bar")
		shell.toggle_shell_fullscreen()
		await settle()
		check(root.mode == Window.MODE_WINDOWED,"normal restore")
		check([shell.game.get_instance_id(),root.get_node("FishingSessionServices").get_instance_id()] == ids,"window transitions preserve scene/session")
		root.position = rectangle.position
		root.size = rectangle.size
	if OS.get_cmdline_user_args().has("--witness"):
		FileAccess.open("res://build/mobile-web/safe-rectangle/floating-witness.json",FileAccess.WRITE).store_string(JSON.stringify({"hwnd":DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE),"pid":OS.get_process_id(),"command":shell.platform.command_path,"status":shell.platform.status_path}))
		var deadline := Time.get_ticks_msec()+30000
		while not FileAccess.file_exists("res://build/mobile-web/safe-rectangle/floating-witness.done") and Time.get_ticks_msec()<deadline: await process_frame
		check(FileAccess.file_exists("res://build/mobile-web/safe-rectangle/floating-witness.done"),"native witness completed")
	print("DESKTOP FLOATING QA: ",checks-failures.size(),"/",checks," failures=",failures)
	shell.queue_free()
	var session := root.get_node_or_null("FishingSessionServices")
	if session != null: session.queue_free()
	await settle()
	quit(0 if failures.is_empty() else 1)
