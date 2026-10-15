extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const ROOT := "user://mixed_exchange_qa"
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
	print("MIXED_CHECK %s %s" % [label, "PASS" if condition else "FAIL"])

func _clear_marker() -> void:
	var path := ROOT + "/fault.marker"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _write_text(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return FileAccess.get_file_as_string(path) == content

func _parsed(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return {}
	var value: Variant = parser.data
	return value if value is Dictionary else {}

func _state(folder: String) -> Dictionary:
	var root := ROOT + "/" + folder + "/"
	var items := _parsed(root + "items.json")
	var fish := _parsed(root + "fish.json")
	var journal := _parsed(root + "pending.json")
	if journal.is_empty():
		journal = _parsed(root + "pending.json.tmp")
	var ids := []
	for entry in fish.get("fish_specimens", {}).get("sea_bass", []):
		ids.append(int(entry.get("specimen_id", -1)))
	ids.sort()
	return {"herbs": int(items.get("counts", {}).get("player/coastal_herb", 0)),
		"bait": int(items.get("counts", {}).get("player/prepared_bait", 0)),
		"ids": ids, "id": str(journal.get("transaction_id", ""))}

func _matches(folder: String, herbs: int, bait: int, ids: Array,
		has_journal: bool) -> bool:
	var state := _state(folder)
	return state.herbs == herbs and state.bait == bait and state.ids == ids and (not state.id.is_empty()) == has_journal

func _change_fish_balance(folder: String, balance: int) -> bool:
	var path := ROOT + "/" + folder + "/fish.json"
	var data := _parsed(path)
	if data.is_empty():
		return false
	data["zenny_balance"] = balance
	return _write_text(path, JSON.stringify(data))

func _child(action: String, folder: String, kill_at_marker: bool = false) -> bool:
	var result_path := ROOT + "/" + folder + "/result.marker"
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/qa/fishing_mixed_exchange_child.gd", "--", action, folder])
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		return false
	for i in range(500):
		if kill_at_marker and FileAccess.file_exists(ROOT + "/fault.marker"):
			OS.kill(pid)
			return true
		if not OS.is_process_running(pid):
			return not kill_at_marker and FileAccess.get_file_as_string(result_path) == "ok"
		OS.delay_msec(20)
	OS.kill(pid)
	return false

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	_check("normal setup", _child("setup", "normal"))
	_check("normal completed once", _child("sale", "normal") and _child("verify_completed", "normal") and _child("verify_completed", "normal"))
	_check("pending catch setup", _child("setup", "pending_catch"))
	_check("pending catch blocks exchange", _child("pending_catch_blocks", "pending_catch") and _child("verify_before", "pending_catch"))
	_check("prior sale setup", _child("setup", "prior_sale"))
	_check("prior sale finishes without exchange", _child("pending_sale_then_exchange", "prior_sale") and _child("verify_sale_only", "prior_sale") and _child("verify_sale_only", "prior_sale"))
	_check("intent promotion failure setup", _child("setup", "intent_promotion"))
	_check("intent promotion failure retains staged identity", _child("fail_intent_promotion", "intent_promotion") and _matches("intent_promotion", 2, 0, [1, 2], true))
	_check("staged intent completes after two restarts", _child("verify_completed", "intent_promotion") and _child("verify_completed", "intent_promotion"))
	_check("early guard setup", _child("setup", "early_guard"))
	_clear_marker()
	_check("early guard crash", _child("fault_after_item_commit", "early_guard", true))
	_check("early guard blocks startup write", _child("early_guard", "early_guard") and _child("verify_completed", "early_guard") and _child("verify_completed", "early_guard"))
	for stage in ["before_intent", "after_intent", "after_item_commit", "after_fish_commit", "before_cleanup"]:
		var folder: String = "crash_" + stage
		_check(stage + " setup", _child("setup", folder))
		_clear_marker()
		_check(stage + " killed", _child("fault_" + stage, folder, true))
		var before_items: bool = stage in ["before_intent", "after_intent"]
		var before_fish: bool = stage in ["before_intent", "after_intent", "after_item_commit"]
		_check(stage + " exact disk state", _matches(folder, 2 if before_items else 0, 0 if before_items else 3, [1, 2] if before_fish else [2], stage != "before_intent"))
		_check(stage + " two restarts", (_child("verify_before", folder) and _child("verify_before", folder)) if stage == "before_intent" else (_child("verify_completed", folder) and _child("verify_completed", folder)))
	for failure in ["fail_item_commit", "fail_fish_commit", "fail_cleanup"]:
		var folder: String = "failure_" + failure
		_check(failure + " setup", _child("setup", folder))
		_check(failure + " reported", _child(failure, folder))
		_check(failure + " exact pending state", _matches(folder, 2 if failure == "fail_item_commit" else 0, 0 if failure == "fail_item_commit" else 3, [2] if failure == "fail_cleanup" else [1, 2], true))
		_check(failure + " two restarts", _child("verify_completed", folder) and _child("verify_completed", folder))
	_check("retry setup", _child("setup", "retry"))
	_check("retry resolves once", _child("retry_after_fail", "retry") and _child("verify_completed", "retry") and _child("verify_completed", "retry"))
	_check("unresolved setup", _child("setup", "unresolved"))
	_clear_marker()
	_check("unresolved crash", _child("fault_after_item_commit", "unresolved", true))
	var pending_id := str(_state("unresolved").id)
	_check("repeated failed recovery retains identity", not pending_id.is_empty() and _child("recover_fail_fish", "unresolved") and _child("recover_fail_fish", "unresolved") and _state("unresolved").id == pending_id)
	_check("conflicting exchange blocked", _child("pending_exchange", "unresolved") and _state("unresolved").id == pending_id)
	_check("conflicting sale blocked", _child("blocked_sale", "unresolved") and _state("unresolved").id == pending_id)
	_check("conflicting catch blocked", _child("catch_conflict", "unresolved") and _state("unresolved").id == pending_id)
	_check("cooking caller reports pending", _child("cook_pending", "unresolved") and _state("unresolved").id == pending_id)
	_check("direct item write blocked", _child("direct_write_blocked", "unresolved") and _matches("unresolved", 0, 3, [1, 2], true))
	_check("unresolved later completes once", _child("verify_completed", "unresolved") and _child("verify_completed", "unresolved"))
	_check("ambiguous setup", _child("setup", "ambiguous"))
	_clear_marker()
	_check("ambiguous crash", _child("fault_after_item_commit", "ambiguous", true))
	var ambiguous_id := str(_state("ambiguous").id)
	_check("ambiguous disk remains untouched", _change_fish_balance("ambiguous", 99) and _child("ambiguous_exchange", "ambiguous") and _child("ambiguous_exchange", "ambiguous") and _state("ambiguous").id == ambiguous_id and _matches("ambiguous", 0, 3, [1, 2], true))
	for kind in ["malformed", "future"]:
		var folder: String = "journal_" + kind
		_check(kind + " setup", _child("setup", folder))
		var path := ROOT + "/" + folder + "/pending.json"
		var raw := "{" if kind == "malformed" else '{"version":999,"transaction_id":"future"}'
		var blocked := _write_text(path, raw) and _child("pending_exchange", folder)
		var state := _state(folder)
		_check(kind + " journal blocks exchange", blocked and FileAccess.get_file_as_string(path) == raw and state.herbs == 2 and state.bait == 0 and state.ids == [1, 2])
	Isolation.emit_result("fishing_mixed_exchange_runner", passed, total, total - passed, 0)
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
