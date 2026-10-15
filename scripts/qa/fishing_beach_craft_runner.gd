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
	print("CRAFT_TX_CHECK %s %s" % [label, "PASS" if good else "FAIL"])

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _write(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return FileAccess.get_file_as_string(path) == content

func _clear(path: String) -> void:
	for suffix in ["", ".bak", ".tmp", ".tmp.next"]:
		var candidate: String = path + str(suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))

func _reset() -> void:
	for path in ["user://item_sale_pending.json", "user://player_item_inventory.json",
		"user://fishing_inventory.json", "user://beach_crafted_lures.json",
		"user://fishing_catch_pending.json", "user://fishing_card_maker_pending.json",
		"user://craft_fault.marker"]:
		_clear(path)
	_clear(ROOT + "/child_result.json")

func _child(action: String, pause: String = "", fault: String = "", kill_at_marker: bool = false) -> bool:
	_clear(ROOT + "/child_result.json")
	_clear("user://craft_fault.marker")
	OS.set_environment("FISHING_QA_CRAFT_PAUSE", pause)
	OS.set_environment("FISHING_QA_CRAFT_FAULT", fault)
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/qa/fishing_beach_craft_child.gd", "--", action]))
	if pid <= 0:
		return false
	for index in range(1000):
		if kill_at_marker and FileAccess.file_exists("user://craft_fault.marker"):
			OS.kill(pid)
			OS.set_environment("FISHING_QA_CRAFT_PAUSE", "")
			OS.set_environment("FISHING_QA_CRAFT_FAULT", "")
			return true
		if not OS.is_process_running(pid):
			OS.set_environment("FISHING_QA_CRAFT_PAUSE", "")
			OS.set_environment("FISHING_QA_CRAFT_FAULT", "")
			return not kill_at_marker and FileAccess.file_exists(ROOT + "/child_result.json")
		OS.delay_msec(20)
	OS.kill(pid)
	return false

func _state() -> Dictionary:
	var items := _read("user://player_item_inventory.json")
	var fish := _read("user://fishing_inventory.json")
	var records := _read("user://beach_crafted_lures.json")
	var journal := _read("user://item_sale_pending.json")
	return {"wood": int(items.get("counts", {}).get("player/driftwood", 0)),
		"shell": int(items.get("counts", {}).get("player/shell", 0)),
		"fibre": int(items.get("counts", {}).get("player/seaweed_fibre", 0)),
		"lure_count": int(fish.get("lure_counts", {}).get("crafted_beach_minnow_001", 0)),
		"records": records.get("records", []).size(),
		"next": int(records.get("next_instance_number", 0)),
		"record_id": str(records.get("records", [{}])[0].get("lure_id", "")) if records.get("records", []).size() > 0 else "",
		"id": str(journal.get("transaction_id", ""))}

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	_reset()
	_check("ordinary craft setup", _child("setup"))
	_check("ordinary craft completes", _child("craft") and bool(_read(ROOT + "/child_result.json").get("success", false)))
	var first_id := str(_read(ROOT + "/child_result.json").get("transaction_id", ""))
	_check("ordinary craft exact state", _state().wood == 2 and _state().lure_count == 1
		and _state().records == 1 and _state().next == 2
		and _state().id.is_empty() and not first_id.is_empty())
	_check("repeat recipe creates distinct equipment", _child("craft")
		and bool(_read(ROOT + "/child_result.json").get("success", false))
		and str(_read(ROOT + "/child_result.json").get("lure_id", "")) == "crafted_beach_minnow_002"
		and str(_read(ROOT + "/child_result.json").get("transaction_id", "")) != first_id
		and int(_read("user://fishing_inventory.json").get("lure_counts", {}).get("crafted_beach_minnow_002", 0)) == 1
		and _state().lure_count == 1 and _state().records == 2 and _state().next == 3 and _state().wood == 1)
	for stage in ["after_intent", "after_record_commit", "after_item_commit", "after_fish_commit", "before_cleanup"]:
		_reset()
		_check(stage + " setup", _child("setup"))
		_check(stage + " kill", _child("craft", stage, "", true))
		var pending := _state()
		_check(stage + " journal", not pending.id.is_empty())
		var blocking_fault := "fail_record_recovery" if stage == "after_intent" else ("fail_item_recovery" if stage == "after_record_commit" else ("fail_fish_recovery" if stage == "after_item_commit" else "fail_cleanup"))
		_check(stage + " conflict", _child("conflict", "", blocking_fault) and not _read(ROOT + "/child_result.json").get("success", false) and _state().id == pending.id)
		if stage == "after_intent":
			_check("pending craft blocks catch", _child("conflict_catch", "", blocking_fault)
				and _read(ROOT + "/child_result.json").get("reason", "") == "pending_cross_store_transaction")
			_check("pending craft blocks card maker", _child("conflict_card_maker", "", blocking_fault)
				and _read(ROOT + "/child_result.json").get("reason", "") == "pending_cross_store_transaction")
			_check("pending craft blocks direct store writes", _child("direct_writes", "", blocking_fault)
				and not bool(_read(ROOT + "/child_result.json").get("item", true))
				and not bool(_read(ROOT + "/child_result.json").get("fish", true))
				and not bool(_read(ROOT + "/child_result.json").get("record", true)))
		_check(stage + " restart one", _child("recover"))
		_check(stage + " restart two", _child("recover"))
		var final := _state()
		_check(stage + " exact outcome", final.wood == 2 and final.shell == 2 and final.fibre == 2
			and final.lure_count == 1 and final.records == 1 and final.next == 2
			and final.record_id == "crafted_beach_minnow_001"
			and final.id.is_empty())
	for fault in ["fail_record_commit", "fail_item_commit", "fail_fish_commit", "fail_cleanup"]:
		_reset()
		_check(fault + " setup", _child("setup"))
		_check(fault + " craft", _child("craft", "", fault))
		_check(fault + " journal", not _state().id.is_empty())
		_check(fault + " restart", _child("recover") and _child("recover"))
		var final := _state()
		_check(fault + " exact outcome", final.wood == 2 and final.lure_count == 1 and final.records == 1 and final.next == 2 and final.id.is_empty())
	_reset()
	_check("failed intent setup", _child("setup"))
	_check("failed intent craft", _child("craft", "", "fail_intent")
		and not bool(_read(ROOT + "/child_result.json").get("success", false)))
	var uncommitted := _state()
	_check("failed intent changes no store", uncommitted.wood == 3 and uncommitted.shell == 3
		and uncommitted.fibre == 3 and uncommitted.lure_count == 0
		and uncommitted.records == 0 and uncommitted.id.is_empty())
	_reset()
	_check("repeated failed recovery setup", _child("setup"))
	_check("repeated failed recovery crash", _child("craft", "after_intent", "", true))
	var id := str(_state().id)
	_check("failed recovery one", _child("recover", "", "fail_record_recovery") and _state().id == id)
	_check("failed recovery two", _child("recover", "", "fail_record_recovery") and _state().id == id)
	_check("failed recovery completes", _child("recover") and _state().id.is_empty())
	_reset()
	_check("ambiguous setup", _child("setup") and _child("craft", "after_intent", "", true))
	var fish_path := "user://fishing_inventory.json"
	var altered := _read(fish_path)
	altered["zenny_balance"] = int(altered.get("zenny_balance", 0)) + 7
	var altered_text := JSON.stringify(altered)
	var pending_text := FileAccess.get_file_as_string("user://item_sale_pending.json")
	_check("ambiguous external edit", _write(fish_path, altered_text))
	_check("ambiguous recovery preserves evidence", _child("recover")
		and FileAccess.get_file_as_string(fish_path) == altered_text
		and FileAccess.get_file_as_string("user://item_sale_pending.json") == pending_text)
	_reset()
	_check("future journal setup", _child("setup"))
	var future := '{"version":999,"transaction_id":"future-craft"}'
	_check("future journal written", _write("user://item_sale_pending.json", future))
	_check("future journal blocks craft", _child("craft")
		and not bool(_read(ROOT + "/child_result.json").get("success", false))
		and FileAccess.get_file_as_string("user://item_sale_pending.json") == future)
	_reset()
	_check("pending catch setup", _child("setup"))
	var catch_evidence := "{unresolved catch evidence"
	_check("pending catch evidence written", _write("user://fishing_catch_pending.json", catch_evidence))
	_check("pending catch blocks craft", _child("craft")
		and _read(ROOT + "/child_result.json").get("reason", "") == "pending_catch_unresolved"
		and FileAccess.get_file_as_string("user://fishing_catch_pending.json") == catch_evidence
		and _state().wood == 3 and _state().records == 0)
	_reset()
	_check("pending card maker setup", _child("setup"))
	var card_evidence := "{unresolved card maker evidence"
	_check("pending card maker evidence written", _write("user://fishing_card_maker_pending.json", card_evidence))
	_check("pending card maker blocks craft", _child("craft")
		and _read(ROOT + "/child_result.json").get("reason", "") == "pending_card_maker_unresolved"
		and FileAccess.get_file_as_string("user://fishing_card_maker_pending.json") == card_evidence
		and _state().wood == 3 and _state().records == 0)
	Isolation.emit_result("fishing_beach_craft_runner", passed, total, total - passed, Node.get_orphan_node_ids().size())
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
