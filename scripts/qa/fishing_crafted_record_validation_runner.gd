extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const SaveStorage = preload("res://scripts/fishing_save_storage.gd")
const SAVE_PATH := "user://beach_crafted_lures.json"
const ROOT := "user://beach_craft_qa"
var passed := 0
var total := 0

func _initialize() -> void:
	if not Isolation.verify([ROOT, SAVE_PATH]):
		quit(1)
		return
	call_deferred("run")

func _check(label: String, good: bool) -> void:
	total += 1
	passed += int(good)
	print("CRAFT_RECORD_CHECK %s %s" % [label, "PASS" if good else "FAIL"])

func _write(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return FileAccess.get_file_as_string(path) == content

func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _child(action: String) -> Dictionary:
	var result_path := ROOT + "/child_result.json"
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/qa/fishing_beach_craft_child.gd", "--", action]))
	if pid <= 0:
		return {}
	for index in range(1000):
		if not OS.is_process_running(pid):
			return _read(result_path) if FileAccess.file_exists(result_path) else {}
		OS.delay_msec(20)
	OS.kill(pid)
	return {}

func _has_damaged_bytes(expected: String) -> bool:
	if FileAccess.file_exists(SAVE_PATH) and FileAccess.get_file_as_string(SAVE_PATH) == expected:
		return true
	var directory := DirAccess.open("user://")
	if directory == null:
		return false
	for name in directory.get_files():
		if name.begins_with("beach_crafted_lures.json.invalid.") and FileAccess.get_file_as_string("user://" + name) == expected:
			return true
	return false

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var before := OS.get_environment("FISHING_QA_RECORD_PHASE") == "before"
	_check("valid version-one setup", bool(_child("setup").get("success", false)))
	var first := _child("craft")
	_check("first craft", bool(first.get("success", false)) and first.get("lure_id", "") == "crafted_beach_minnow_001")
	var healthy_text := FileAccess.get_file_as_string(SAVE_PATH)
	var healthy := _read(SAVE_PATH)
	var records: Array = healthy.get("records", [])
	_check("valid primary identity and next number", healthy.get("version", 0) == 1 and records.size() == 1
		and records[0] is Dictionary and records[0].get("lure_id", "") == "crafted_beach_minnow_001"
		and healthy.get("next_instance_number", 0) == 2)
	_check("healthy backup copied", _write(SAVE_PATH + ".bak", healthy_text))
	var damaged := healthy.duplicate(true)
	damaged["records"] = [[]]
	var damaged_text := JSON.stringify(damaged)
	_check("syntactically valid damaged primary", _write(SAVE_PATH, damaged_text)
		and JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH)) is Dictionary)
	var selected := SaveStorage.read(SAVE_PATH, BeachCraftingService.SAVE_VERSION, BeachCraftingService.RECORD_KEYS)
	if before:
		_check("old validator selects damaged primary", selected.status == "valid" and selected.source == "primary")
		var old_load := _child("inspect_records")
		_check("old loader silently loses crafted record", bool(old_load.get("success", false))
			and old_load.get("records", []).size() == 0
			and old_load.get("next_instance_number", 0) == 2
			and not bool(old_load.get("runtime_lure_present", true)))
	else:
		_check("validator selects healthy backup", selected.status == "valid" and selected.source == "backup")
		_check("backup holds exact record", selected.data.get("records", []) == records
			and selected.data.get("next_instance_number", 0) == 2)
		_check("damaged primary retained before load", FileAccess.get_file_as_string(SAVE_PATH) == damaged_text)
		var recovered := _child("inspect_records")
		var recovered_records: Array = recovered.get("records", [])
		_check("loader restores exact record and runtime lure", recovered_records == records
			and recovered.get("next_instance_number", 0) == 2
			and bool(recovered.get("runtime_lure_present", false)))
		_check("damaged bytes preserved after load", _has_damaged_bytes(damaged_text))
		var repeated := _child("craft")
		_check("repeat craft succeeds with distinct identity", bool(repeated.get("success", false))
			and repeated.get("lure_id", "") == "crafted_beach_minnow_002"
			and repeated.get("transaction_id", "") != first.get("transaction_id", ""))
		var after := _read(SAVE_PATH)
		var after_records: Array = after.get("records", [])
		var fish := _read("user://fishing_inventory.json")
		_check("repeat craft exact records and next number", after_records.size() == 2
			and after_records[0] == records[0]
			and after_records[1].get("lure_id", "") == "crafted_beach_minnow_002"
			and after.get("next_instance_number", 0) == 3)
		_check("exact equipment ownership", fish.get("lure_counts", {}).get("crafted_beach_minnow_001", 0) == 1
			and fish.get("lure_counts", {}).get("crafted_beach_minnow_002", 0) == 1)
		_check("damaged bytes preserved after repeat craft", _has_damaged_bytes(damaged_text))
		var legacy := healthy.duplicate(true)
		var legacy_record: Dictionary = legacy.records[0]
		for key in ["accent_id", "buoyancy", "handling", "attraction", "created_unix", "instance_number"]:
			legacy_record.erase(key)
		legacy_record["display_name_override"] = "Old beach lure"
		_check("version-one optional fields remain valid", _write("user://craft_record_probe.json", JSON.stringify(legacy))
			and SaveStorage.read("user://craft_record_probe.json", 1, BeachCraftingService.RECORD_KEYS).status == "valid")
		for bad_case in ["empty_lure_id", "typed_recipe", "typed_score", "non_object", "duplicate_id"]:
			var probe := healthy.duplicate(true)
			match bad_case:
				"empty_lure_id": probe.records[0]["lure_id"] = ""
				"typed_recipe": probe.records[0]["recipe_id"] = 42
				"typed_score": probe.records[0]["buoyancy"] = "invalid"
				"non_object": probe.records[0] = []
				"duplicate_id": probe.records.append(probe.records[0].duplicate(true))
			_check("reject " + bad_case, _write("user://craft_record_probe.json", JSON.stringify(probe))
				and SaveStorage.read("user://craft_record_probe.json", 1, BeachCraftingService.RECORD_KEYS).status == "blocked")
		var unbuildable := after.duplicate(true)
		unbuildable.records[0]["recipe_id"] = "missing_recipe"
		var unbuildable_text := JSON.stringify(unbuildable)
		_check("structurally valid unknown recipe", _write(SAVE_PATH, unbuildable_text)
			and SaveStorage.read(SAVE_PATH, 1, BeachCraftingService.RECORD_KEYS).source == "primary")
		var refused := _child("load_status")
		_check("loader reports unbuildable record failure", not bool(refused.get("success", true))
			and refused.get("records", []).is_empty())
		_check("unbuildable record retained", FileAccess.get_file_as_string(SAVE_PATH) == unbuildable_text)
		_check("older version-one primary written", _write(SAVE_PATH, JSON.stringify(legacy)))
		var legacy_loaded := _child("inspect_records")
		_check("older version-one record builds runtime lure", legacy_loaded.get("records", []) == legacy.records
			and legacy_loaded.get("next_instance_number", 0) == 2
			and bool(legacy_loaded.get("runtime_lure_present", false)))
		var card_service := FishingCardMakerService.new()
		card_service.configure_pending_journal_paths("user://craft_card_probe.json", "user://craft_card_probe.tmp")
		for card_case in ["malformed", "future_version"]:
			var pending_bytes := "[]" if card_case == "malformed" else '{"version":999,"transaction_id":"future-card"}'
			_check("card maker " + card_case + " journal written", _write("user://craft_card_probe.json", pending_bytes))
			var card_read: Dictionary = card_service.call("_read_pending")
			var card_recovery: Dictionary = card_service.recover_pending_transaction()
			_check("card maker " + card_case + " blocks recovery", card_read.get("status", "") == ("invalid" if card_case == "malformed" else "unsupported")
				and bool(card_recovery.get("blocked", false)))
			var replacement := {"version": 1, "transaction_id": "replacement-" + card_case}
			_check("card maker " + card_case + " cannot be overwritten", not bool(card_service.call("_write_pending", replacement))
				and FileAccess.get_file_as_string("user://craft_card_probe.json") == pending_bytes)
		card_service.free()
	Isolation.emit_result("fishing_crafted_record_validation_runner", passed, total, total - passed, Node.get_orphan_node_ids().size())
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
