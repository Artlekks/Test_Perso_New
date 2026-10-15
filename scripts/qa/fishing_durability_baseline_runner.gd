extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Inventory = preload("res://scripts/fishing_inventory.gd")
const PATH := "user://durability_baseline/inventory.json"

func _initialize() -> void:
	if not Isolation.verify([PATH, PATH + ".marker"]):
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://durability_baseline"))
	var inventory: FishingInventory = Inventory.new()
	inventory.configure_save_path(PATH)
	inventory.initialize()
	inventory.set_zenny(9876)
	var before := FileAccess.get_file_as_string(PATH)
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/qa/fishing_durability_baseline_child.gd"])
	var pid := OS.create_process(OS.get_executable_path(), args)
	var marker := PATH + ".marker"
	for i in range(200):
		if FileAccess.file_exists(marker):
			break
		OS.delay_msec(20)
	var marked := FileAccess.file_exists(marker)
	if pid > 0:
		OS.kill(pid)
	var after := FileAccess.get_file_as_string(PATH)
	var reproduced := marked and before.length() > 0 and after.length() == 0
	print("BASELINE_DIRECT_WRITE_TRUNCATION reproduced=%s before=%d after=%d" % [reproduced, before.length(), after.length()])
	inventory.free()
	Isolation.emit_result("fishing_durability_baseline_runner", int(reproduced), 1, int(not reproduced), 0)
	quit(0 if reproduced else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
