extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const ROOT := "user://beach_craft_qa"
var passed := 0
var total := 0

func _initialize() -> void:
	if not Isolation.verify([ROOT, "user://craft_fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func _check(label: String, good: bool) -> void:
	total += 1
	passed += int(good)
	print("PREFIX_CRAFT_CHECK %s %s" % [label, "PASS" if good else "FAIL"])

func _data(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _child(action: String, kill: bool = false) -> bool:
	var result_path := ROOT + "/child_result.json"
	for path in [result_path, "user://craft_fault.marker"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	OS.set_environment("FISHING_QA_CRAFT_PAUSE", "after_item_commit" if kill else "")
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/qa/fishing_beach_craft_child.gd", "--", action]))
	if pid <= 0:
		return false
	for index in range(1000):
		if kill and FileAccess.file_exists("user://craft_fault.marker"):
			OS.kill(pid)
			OS.set_environment("FISHING_QA_CRAFT_PAUSE", "")
			return true
		if not OS.is_process_running(pid):
			OS.set_environment("FISHING_QA_CRAFT_PAUSE", "")
			return not kill and FileAccess.file_exists(result_path)
		OS.delay_msec(20)
	OS.kill(pid)
	return false

func _state() -> Dictionary:
	var items := _data("user://player_item_inventory.json")
	var fish := _data("user://fishing_inventory.json")
	var records := _data("user://beach_crafted_lures.json")
	return {"wood": int(items.get("counts", {}).get("player/driftwood", 0)),
		"lure_count": int(fish.get("lure_counts", {}).get("crafted_beach_minnow_001", 0)),
		"records": records.get("records", []).size()}

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	_check("setup", _child("setup"))
	_check("initial materials", _state().wood == 3)
	_check("process killed after material commit", _child("craft", true))
	var partial := _state()
	_check("partial commit reproduced", partial.wood == 2 and partial.records == 1 and partial.lure_count == 0)
	_check("restart one", _child("load"))
	_check("restart two", _child("load"))
	var final := _state()
	_check("partial commit persists", final.wood == 2 and final.records == 1 and final.lure_count == 0)
	Isolation.emit_result("fishing_beach_craft_prefix_runner", passed, total, total - passed, Node.get_orphan_node_ids().size())
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
