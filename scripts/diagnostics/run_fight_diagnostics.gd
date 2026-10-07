extends SceneTree

var _orphan_before: Array[int] = []

## Rendered normal-play launcher. Isolates saves, does not grant or force fish,
## change positions, inject inputs, or modify fight/camera settings.
func _initialize() -> void:
	_orphan_before.assign(Node.get_orphan_node_ids())
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	var isolated_name := "CodexFightRuntime-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated_name)
	if not OS.get_user_data_dir().ends_with(isolated_name) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Cannot isolate diagnostic saves; refusing to start")
		quit(1)
		return
	print("DIAGNOSTIC USERDATA: ", OS.get_user_data_dir())
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	scene.get_node("Game/Fishing").debug_fight_telemetry = true
	root.add_child(scene)
	current_scene = scene

func _finalize() -> void:
	# The existing startup QA builds detached Node-based fixtures. Release the
	# isolated session and its fixtures when this diagnostic window closes.
	if is_instance_valid(current_scene):
		current_scene.free()
	var session: Node = root.get_node_or_null("FishingSessionServices") if is_instance_valid(root) else null
	if is_instance_valid(session):
		session.free()
	for id in Node.get_orphan_node_ids():
		if not _orphan_before.has(id):
			var orphan = instance_from_id(id)
			if is_instance_valid(orphan):
				orphan.free()
