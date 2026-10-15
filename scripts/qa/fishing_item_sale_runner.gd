extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const ROOT := "user://sale_fault_qa"
var passed := 0
var total := 0

func _initialize() -> void:
	if not Isolation.verify([ROOT, ROOT + "/fault.marker"]):
		quit(1)
		return
	call_deferred("run")

func _check(label: String, success: bool) -> void:
	total += 1
	passed += int(success)
	print("ITEM_SALE_CHECK %s %s" % [label, "PASS" if success else "FAIL"])

func _clear_fault_marker() -> void:
	var marker := ROOT + "/fault.marker"
	if FileAccess.file_exists(marker):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(marker))

func _balances(folder: String) -> Dictionary:
	var item_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/" + folder + "/items.json"))
	var wallet_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/" + folder + "/wallet.json"))
	if not item_data is Dictionary or not wallet_data is Dictionary:
		return {"items": -1, "zenny": -1}
	return {"items": int(item_data.get("counts", {}).get("player/driftwood", 0)),
		"zenny": int(wallet_data.get("zenny_balance", -1))}

func _journal_id(folder: String) -> String:
	var path := ROOT + "/" + folder + "/pending.json"
	if not FileAccess.file_exists(path):
		return ""
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		return ""
	var parsed: Variant = JSON.parse_string(raw)
	return str(parsed.get("transaction_id", "")) if parsed is Dictionary else ""

func _write_text(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return FileAccess.get_file_as_string(path) == value

func _change_wallet_balance(folder: String, balance: int) -> bool:
	var path := ROOT + "/" + folder + "/wallet.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	parsed["zenny_balance"] = balance
	return _write_text(path, JSON.stringify(parsed))

func _make_item_tmp_only(folder: String) -> bool:
	var primary := ROOT + "/" + folder + "/items.json"
	var raw := FileAccess.get_file_as_string(primary)
	if raw.is_empty() or not _write_text(primary + ".tmp", raw):
		return false
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(primary)) != OK:
		return false
	var backup := primary + ".bak"
	if FileAccess.file_exists(backup) and DirAccess.remove_absolute(ProjectSettings.globalize_path(backup)) != OK:
		return false
	return FileAccess.file_exists(primary + ".tmp") and not FileAccess.file_exists(primary)

func _child(action: String, folder: String, kill_at_marker: bool = false) -> bool:
	var result_path := ROOT + "/" + folder + "/result.marker"
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/qa/fishing_item_sale_child.gd", "--", action, folder])
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
	_check("normal sale", _child("sale", "normal") and _child("verify_completed", "normal"))
	_check("item staging setup", _child("setup", "item_staging"))
	_check("item staging only temporary copy", _make_item_tmp_only("item_staging"))
	_clear_fault_marker()
	_check("item staging killed on alternate open", _child("item_staging_crash", "item_staging", true))
	_check("item staging previous data survives two restarts", _child("verify_item_only_tmp", "item_staging") and _child("verify_item_only_tmp", "item_staging"))
	_check("crash fixture setup", _child("setup", "baseline"))
	_clear_fault_marker()
	_check("killed after item commit", _child("baseline_interrupt", "baseline", true))
	_check("sale repaired after two restarts", _child("verify_completed", "baseline") and _child("verify_completed", "baseline"))
	for stage in ["before_intent", "after_intent", "after_item_commit", "after_wallet_commit", "before_cleanup"]:
		var folder: String = "crash_" + stage
		_check(stage + " setup", _child("setup", folder))
		_clear_fault_marker()
		_check(stage + " process killed", _child("fault_" + stage, folder, true))
		var balances := _balances(folder)
		var expected_items := 1 if stage in ["after_item_commit", "after_wallet_commit", "before_cleanup"] else 2
		var expected_zenny := 13 if stage in ["after_wallet_commit", "before_cleanup"] else 10
		_check(stage + " exact crash state", int(balances.items) == expected_items and int(balances.zenny) == expected_zenny and (_journal_id(folder).is_empty() if stage == "before_intent" else not _journal_id(folder).is_empty()))
		_check(stage + " two restarts", (_child("verify_before", folder) and _child("verify_before", folder)) if stage == "before_intent" else (_child("verify_completed", folder) and _child("verify_completed", folder)))
	for failure in ["fail_item_commit", "fail_wallet_commit", "fail_cleanup"]:
		var folder: String = "failure_" + failure
		_check(failure + " setup", _child("setup", folder))
		_check(failure + " reported", _child(failure, folder))
		var balances := _balances(folder)
		var expected_items := 2 if failure == "fail_item_commit" else 1
		var expected_zenny := 13 if failure == "fail_cleanup" else 10
		_check(failure + " journal retained", int(balances.items) == expected_items and int(balances.zenny) == expected_zenny and not _journal_id(folder).is_empty())
		_check(failure + " recovers once", _child("verify_completed", folder) and _child("verify_completed", folder))
	_check("repeated failure setup", _child("setup", "repeated_failure"))
	_clear_fault_marker()
	_check("repeated failure crash", _child("fault_after_item_commit", "repeated_failure", true))
	var pending_id := _journal_id("repeated_failure")
	_check("repeated failed recovery keeps identity", not pending_id.is_empty() and _child("recover_fail_wallet", "repeated_failure") and _child("recover_fail_wallet", "repeated_failure") and _journal_id("repeated_failure") == pending_id and int(_balances("repeated_failure").items) == 1 and int(_balances("repeated_failure").zenny) == 10)
	_check("conflicting sale blocked", _child("pending_sell", "repeated_failure") and _journal_id("repeated_failure") == pending_id and int(_balances("repeated_failure").items) == 1 and int(_balances("repeated_failure").zenny) == 10)
	_check("insufficient conflicting sale still reports pending", _child("blocked_sale_insufficient", "repeated_failure") and _journal_id("repeated_failure") == pending_id)
	_check("later recovery completes once", _child("verify_completed", "repeated_failure") and _child("verify_completed", "repeated_failure"))
	_check("immediate retry setup", _child("setup", "immediate_retry"))
	_check("immediate retry completes prior sale only", _child("retry_after_fail", "immediate_retry") and _child("verify_completed", "immediate_retry") and _child("verify_completed", "immediate_retry"))
	_check("ambiguous state setup", _child("setup", "ambiguous"))
	_clear_fault_marker()
	_check("ambiguous state crash", _child("fault_after_item_commit", "ambiguous", true))
	var ambiguous_id := _journal_id("ambiguous")
	_check("ambiguous state preserves evidence", _change_wallet_balance("ambiguous", 99) and _child("blocked_sale", "ambiguous") and _child("blocked_sale", "ambiguous") and _journal_id("ambiguous") == ambiguous_id and int(_balances("ambiguous").items) == 1 and int(_balances("ambiguous").zenny) == 99)
	for journal_kind in ["malformed", "future"]:
		var folder: String = "journal_" + journal_kind
		_check(journal_kind + " journal setup", _child("setup", folder))
		var journal_path: String = ROOT + "/" + folder + "/pending.json"
		var journal_bytes := "{" if journal_kind == "malformed" else '{"version":999,"transaction_id":"future"}'
		_check(journal_kind + " journal blocks sale", _write_text(journal_path, journal_bytes) and _child("blocked_sale", folder) and FileAccess.get_file_as_string(journal_path) == journal_bytes and int(_balances(folder).items) == 2 and int(_balances(folder).zenny) == 10)
	Isolation.emit_result("fishing_item_sale_runner", passed, total, total - passed, 0)
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
