extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")

func _initialize() -> void:
	if not Isolation.verify([]):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	for frame in range(2):
		await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	Isolation.emit_result("fishing_qa_exit_probe", 1, 1, 0, 0)
	var mode: String = OS.get_environment("FISHING_QA_EXIT_PROBE")
	if mode == "nonzero":
		quit(7)
	elif mode == "killed":
		OS.kill(OS.get_process_id())
	else:
		quit(0)
