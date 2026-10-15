extends SceneTree

const Faults = preload("res://scripts/qa/fishing_catch_repository_fault_qa.gd")
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

func _initialize() -> void:
	if not Isolation.verify(Faults.isolation_paths()):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	for frame in range(2):
		await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var report: Dictionary = Faults.run()
	for frame in range(2):
		await process_frame
	var orphans: int = Node.get_orphan_node_ids().size()
	print("Catch repository fault QA: %d/%d failures=%s" % [report.passed, report.total, report.failures])
	Isolation.emit_result("fishing_catch_repository_fault_runner", report.passed, report.total, report.failures.size(), orphans)
	quit(0 if report.passed == report.total and orphans == 0 else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
