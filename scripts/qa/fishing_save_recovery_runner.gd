extends SceneTree

## Executable, isolated recovery suite with strict fixture ownership teardown.
const Recovery = preload("res://scripts/qa/fishing_save_recovery_interruption_qa.gd")

func _initialize() -> void:
	var isolated := "CodexArchitectureRecoveryQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Recovery QA requires isolated userdata")
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	var scene := preload("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in range(6):
		await process_frame
	var session := root.get_node("FishingSessionServices")
	var report := Recovery.run(session)
	print("Save Recovery Interruption QA: %d/%d; failures=%s" % [report.passed_count, report.test_count, report.failures])
	scene.queue_free()
	session.queue_free()
	for frame in range(4):
		await process_frame
	var orphan_ids := Node.get_orphan_node_ids()
	for id in orphan_ids:
		push_error("Recovery fixture leaked orphan node %d" % id)
	print("Recovery teardown orphan count: ", orphan_ids.size())
	quit(0 if report.valid and orphan_ids.is_empty() else 1)
