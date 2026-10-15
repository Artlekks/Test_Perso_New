extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Storage = preload("res://scripts/fishing_save_storage.gd")
const Inventory = preload("res://scripts/fishing_inventory.gd")
const Progress = preload("res://scripts/fishing_progress.gd")
const Rewards = preload("res://scripts/fishing_reward_service.gd")
const ROOT := "user://durability_focus"
var passed := 0
var total := 0

func _initialize() -> void:
	if not Isolation.verify([ROOT, ROOT + "/fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func _check(label: String, condition: bool) -> void:
	total += 1
	passed += int(condition)
	print("DURABILITY_CHECK %s %s" % [label, "PASS" if condition else "FAIL"])

func _child(action: String, folder: String, kill_at_marker: bool = false) -> bool:
	var result_path := ROOT + "/" + folder + "/result.marker"
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/qa/fishing_durability_child.gd", "--", action, folder])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		return false
	var marker := ROOT + "/fault.marker"
	for i in range(400):
		if kill_at_marker and FileAccess.file_exists(marker):
			OS.kill(pid)
			return true
		if not OS.is_process_running(pid):
			return not kill_at_marker and FileAccess.get_file_as_string(result_path) == "ok"
		OS.delay_msec(20)
	OS.kill(pid)
	return false

func _data(folder: String, name: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/" + folder + "/" + name + ".json"))
	return parsed if parsed is Dictionary else {}

func _write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return FileAccess.get_file_as_string(path) == value

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	_check("first process saves", _child("first", "base") and int(_data("base", "inventory").get("zenny_balance", -1)) == 100)
	_check("second process updates", _child("update", "base") and int(_data("base", "inventory").get("zenny_balance", -1)) == 200)
	_check("backup is prior complete save", int(JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/base/inventory.json.bak")).get("zenny_balance", -1)) == 200)
	# Each interruption uses an independent seeded fixture.
	for stage in ["fault_open", "fault_pre"]:
		_child("first", stage)
		var marker := ROOT + "/fault.marker"
		if FileAccess.file_exists(marker):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
		var killed := _child(stage, stage, true)
		_check(stage + " process terminated", killed)
		_check(stage + " primary survives", int(_data(stage, "inventory").get("zenny_balance", -1)) == 100)
		_check(stage + " restart stable", _child("inspect", stage) and _child("inspect", stage))
	_child("first", "promotion")
	_child("update", "promotion")
	_child("fault_promote", "promotion")
	_check("failed promotion leaves valid backup", int(JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/promotion/inventory.json.bak")).get("zenny_balance", -1)) == 200)
	var corrupt := ROOT + "/promotion/inventory.json"
	var f := FileAccess.open(corrupt, FileAccess.WRITE)
	f.store_string("{" )
	f.close()
	_check("corrupt primary falls back to backup", _child("inspect200", "promotion"))
	_check("recovered save promotes without overwriting corrupt bytes", _child("recover_save", "promotion") and FileAccess.get_file_as_string(corrupt + ".invalid.0001") == "{" and int(_data("promotion", "inventory").get("zenny_balance", -1)) == 250)
	# Preserve unreadable bytes and reject a new write when no valid copy remains.
	var bak := ROOT + "/promotion/inventory.json.bak"
	var temp := ROOT + "/promotion/inventory.json.tmp"
	if FileAccess.file_exists(temp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	f = FileAccess.open(corrupt, FileAccess.WRITE)
	f.store_string("{")
	f.close()
	f = FileAccess.open(bak, FileAccess.WRITE)
	f.store_string("{")
	f.close()
	_check("both corrupt block save", _child("blocked", "promotion") and FileAccess.get_file_as_string(corrupt) == "{")
	var future := ROOT + "/future"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(future))
	f = FileAccess.open(future + "/inventory.json", FileAccess.WRITE)
	f.store_string('{"version":999,"progress_migrated":true,"zenny_balance":900}')
	f.close()
	_check("future version blocked", _child("blocked", "future"))
	var legacy := ROOT + "/legacy"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(legacy))
	f = FileAccess.open(legacy + "/inventory.json", FileAccess.WRITE)
	f.store_string('{"version":1,"progress_migrated":true,"fish_counts":{"qa":2},"zenny_balance":75,"lure_counts":{"straight":1},"rod_counts":{"wooden_rod":1}}')
	f.close()
	_check("legacy save migrates", _child("legacy", "legacy") and int(_data("legacy", "inventory").get("version", -1)) == 6)
	_check("reward claim reloads across processes", _child("reward_write", "reward") and _child("reward_check", "reward"))
	_child("first", "temp_only")
	var temp_primary := ROOT + "/temp_only/inventory.json"
	var temp_backup := temp_primary + ".bak"
	var temp_staged := temp_primary + ".tmp"
	if FileAccess.file_exists(temp_backup):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_backup))
	var temp_prepared := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_primary), ProjectSettings.globalize_path(temp_staged)) == OK
	var previous_temp_bytes := FileAccess.get_file_as_string(temp_staged)
	_check("temporary-only save loads", temp_prepared and previous_temp_bytes.length() > 0 and _child("inspect", "temp_only"))
	var marker := ROOT + "/fault.marker"
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	var killed_temp_writer := _child("fault_open", "temp_only", true)
	_check("temporary-only save survives interrupted restaging", killed_temp_writer and FileAccess.get_file_as_string(temp_staged) == previous_temp_bytes and _child("inspect", "temp_only"))
	_check("temporary-only repeated recovery", _child("inspect", "temp_only") and _child("inspect", "temp_only"))
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	_check("repeated interrupted restaging keeps selected temporary", _child("fault_open", "temp_only", true) and FileAccess.get_file_as_string(temp_staged) == previous_temp_bytes and _child("inspect", "temp_only"))
	_child("first", "temp_success")
	var success_primary := ROOT + "/temp_success/inventory.json"
	var success_backup := success_primary + ".bak"
	var success_temp := success_primary + ".tmp"
	if FileAccess.file_exists(success_backup):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(success_backup))
	var success_ready := DirAccess.rename_absolute(ProjectSettings.globalize_path(success_primary), ProjectSettings.globalize_path(success_temp)) == OK
	_check("temporary-only successful recovery", success_ready and _child("recover_temp_save", "temp_success") and int(_data("temp_success", "inventory").get("zenny_balance", -1)) == 150 and _child("inspect150", "temp_success") and _child("inspect150", "temp_success"))
	_child("first", "temp_corrupt")
	var corrupt_temp_primary := ROOT + "/temp_corrupt/inventory.json"
	var corrupt_temp_backup := corrupt_temp_primary + ".bak"
	var corrupt_temp := corrupt_temp_primary + ".tmp"
	if FileAccess.file_exists(corrupt_temp_backup):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(corrupt_temp_backup))
	var corrupt_temp_ready := DirAccess.rename_absolute(ProjectSettings.globalize_path(corrupt_temp_primary), ProjectSettings.globalize_path(corrupt_temp)) == OK
	var corrupt_temp_bytes := FileAccess.get_file_as_string(corrupt_temp)
	_write_text(corrupt_temp_primary, "{")
	_check("valid temporary beats corrupt primary without backup", corrupt_temp_ready and _child("inspect", "temp_corrupt") and FileAccess.get_file_as_string(corrupt_temp_primary) == "{")
	_write_text(corrupt_temp_backup, "{")
	_check("valid temporary beats corrupt primary and backup", _child("inspect", "temp_corrupt") and FileAccess.get_file_as_string(corrupt_temp) == corrupt_temp_bytes and FileAccess.get_file_as_string(corrupt_temp_backup) == "{")
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))
	_check("corrupt neighbors do not expose temporary during staging", _child("fault_open", "temp_corrupt", true) and FileAccess.get_file_as_string(corrupt_temp) == corrupt_temp_bytes and FileAccess.get_file_as_string(corrupt_temp_primary) == "{" and FileAccess.get_file_as_string(corrupt_temp_backup) == "{" and _child("inspect", "temp_corrupt") and _child("inspect", "temp_corrupt"))
	_check("successful recovery preserves invalid bytes", _child("recover_temp_save", "temp_corrupt") and _child("inspect150", "temp_corrupt") and FileAccess.get_file_as_string(corrupt_temp_primary + ".invalid.0001") == "{" and FileAccess.get_file_as_string(corrupt_temp_backup + ".invalid.0001") == "{")
	_child("first", "nested_inventory")
	var nested_inventory_path := ROOT + "/nested_inventory/inventory.json"
	var healthy_inventory := FileAccess.get_file_as_string(nested_inventory_path)
	var malformed_inventory: Dictionary = JSON.parse_string(healthy_inventory)
	malformed_inventory["fish_specimens"]["qa"] = ["not_a_specimen"]
	var malformed_inventory_bytes := JSON.stringify(malformed_inventory)
	_write_text(nested_inventory_path + ".bak", healthy_inventory)
	_write_text(nested_inventory_path, malformed_inventory_bytes)
	_check("malformed specimens use healthy backup", Storage.read(nested_inventory_path, Inventory.SAVE_VERSION, Inventory.SAVE_KEYS).get("source", "") == "backup" and _child("inspect", "nested_inventory") and FileAccess.get_file_as_string(nested_inventory_path) == malformed_inventory_bytes)
	var malformed_specimen_value: Dictionary = JSON.parse_string(healthy_inventory)
	malformed_specimen_value["fish_specimens"]["qa"][0]["points"] = "many"
	var malformed_specimen_value_bytes := JSON.stringify(malformed_specimen_value)
	_write_text(nested_inventory_path, malformed_specimen_value_bytes)
	_check("malformed specimen field uses healthy backup", Storage.read(nested_inventory_path, Inventory.SAVE_VERSION, Inventory.SAVE_KEYS).get("source", "") == "backup" and _child("inspect", "nested_inventory") and FileAccess.get_file_as_string(nested_inventory_path) == malformed_specimen_value_bytes)
	var malformed_count: Dictionary = JSON.parse_string(healthy_inventory)
	malformed_count["lure_counts"]["straight"] = "many"
	var malformed_count_bytes := JSON.stringify(malformed_count)
	_write_text(nested_inventory_path, malformed_count_bytes)
	_check("malformed tackle count uses healthy backup", Storage.read(nested_inventory_path, Inventory.SAVE_VERSION, Inventory.SAVE_KEYS).get("source", "") == "backup" and _child("inspect", "nested_inventory") and FileAccess.get_file_as_string(nested_inventory_path) == malformed_count_bytes)
	_child("seed_progress", "nested_progress")
	var nested_progress_path := ROOT + "/nested_progress/progress.json"
	var healthy_progress := FileAccess.get_file_as_string(nested_progress_path)
	var malformed_progress: Dictionary = JSON.parse_string(healthy_progress)
	malformed_progress["species_records"]["qa"] = "not_a_record"
	var malformed_progress_bytes := JSON.stringify(malformed_progress)
	_write_text(nested_progress_path + ".bak", healthy_progress)
	_write_text(nested_progress_path, malformed_progress_bytes)
	_check("malformed progress record uses healthy backup", Storage.read(nested_progress_path, Progress.SAVE_VERSION, Progress.SAVE_KEYS).get("source", "") == "backup" and _child("inspect_progress", "nested_progress") and FileAccess.get_file_as_string(nested_progress_path) == malformed_progress_bytes)
	var malformed_record_value: Dictionary = JSON.parse_string(healthy_progress)
	malformed_record_value["species_records"]["qa"]["caught_count"] = "two"
	var malformed_record_value_bytes := JSON.stringify(malformed_record_value)
	_write_text(nested_progress_path, malformed_record_value_bytes)
	_check("malformed record field uses healthy backup", Storage.read(nested_progress_path, Progress.SAVE_VERSION, Progress.SAVE_KEYS).get("source", "") == "backup" and _child("inspect_progress", "nested_progress") and FileAccess.get_file_as_string(nested_progress_path) == malformed_record_value_bytes)
	var malformed_transactions: Dictionary = JSON.parse_string(healthy_progress)
	malformed_transactions["recent_catch_transaction_ids"] = [123]
	var malformed_transaction_bytes := JSON.stringify(malformed_transactions)
	_write_text(nested_progress_path, malformed_transaction_bytes)
	_check("malformed transaction IDs use healthy backup", Storage.read(nested_progress_path, Progress.SAVE_VERSION, Progress.SAVE_KEYS).get("source", "") == "backup" and _child("inspect_progress", "nested_progress") and FileAccess.get_file_as_string(nested_progress_path) == malformed_transaction_bytes)
	var reward_path := Rewards.SAVE_PATH
	var healthy_rewards := FileAccess.get_file_as_string(reward_path)
	var malformed_rewards: Dictionary = JSON.parse_string(healthy_rewards)
	malformed_rewards["claimed_reward_keys"]["qa_reward"] = "false"
	var malformed_reward_bytes := JSON.stringify(malformed_rewards)
	_write_text(reward_path + ".bak", healthy_rewards)
	_write_text(reward_path, malformed_reward_bytes)
	_check("malformed claim value uses healthy backup", Storage.read(reward_path, Rewards.SAVE_VERSION, Rewards.SAVE_KEYS).get("source", "") == "backup" and _child("reward_check", "reward") and FileAccess.get_file_as_string(reward_path) == malformed_reward_bytes)
	var legacy_progress_path := ROOT + "/legacy_progress/progress.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "/legacy_progress"))
	_write_text(legacy_progress_path, '{"version":1,"species_records":{"qa":{"fish_name":"QA","caught_count":2}},"total_catches":2}')
	_check("legacy progress reader migrates", _child("legacy_progress", "legacy_progress") and int(_data("legacy_progress", "progress").get("version", -1)) == 7 and _child("inspect_progress", "legacy_progress"))
	Isolation.emit_result("fishing_durability_runner", passed, total, total - passed, 0)
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
