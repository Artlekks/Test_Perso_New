extends SceneTree

## Executable, isolated recovery suite with strict fixture ownership teardown.
const Recovery = preload("res://scripts/qa/fishing_save_recovery_interruption_qa.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

func _initialize() -> void:
	if not Isolation.verify(Recovery.isolation_paths()):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	for frame in range(2):
		await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
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
	Isolation.emit_result("fishing_save_recovery_runner", report.passed_count,
		report.test_count, report.failures.size(), orphan_ids.size())
	quit(0 if report.valid and orphan_ids.is_empty() else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
