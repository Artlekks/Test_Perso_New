extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const ROOT := "user://card_maker_journal_qa"
const INVENTORY := ROOT + "/inventory.json"
const JOURNAL := ROOT + "/pending.json"
const TEMP := ROOT + "/pending.tmp"
const CARD := ROOT + "/card.json"
const RESULT := ROOT + "/result.json"
var passed := 0
var total := 0

func _initialize() -> void:
	if not Isolation.verify([ROOT, INVENTORY, JOURNAL, TEMP, CARD, RESULT,
			"user://card_maker_fault.marker", "user://item_sale_pending.json"]):
		quit(1)
		return
	call_deferred("run")

func _check(label: String, good: bool) -> void:
	total += 1
	passed += int(good)
	print("CARD_JOURNAL_CHECK %s %s" % [label, "PASS" if good else "FAIL"])

func _write(path: String, value: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return FileAccess.get_file_as_string(path) == value

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _reset() -> void:
	for path in [INVENTORY, INVENTORY + ".bak", INVENTORY + ".tmp", INVENTORY + ".tmp.next",
			JOURNAL, TEMP, CARD, RESULT, "user://item_sale_pending.json",
			"user://fishing_catch_pending.json", "user://card_maker_fault.marker"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _child(action: String, pause: String = "", fault: String = "", kill_at_marker: bool = false) -> Dictionary:
	if FileAccess.file_exists(RESULT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RESULT))
	if FileAccess.file_exists("user://card_maker_fault.marker"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://card_maker_fault.marker"))
	OS.set_environment("FISHING_QA_CARD_PAUSE", pause)
	OS.set_environment("FISHING_QA_CARD_FAULT", fault)
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://scripts/qa/fishing_card_journal_child.gd", "--", action]))
	if pid <= 0:
		return {}
	for index in range(1000):
		if kill_at_marker and FileAccess.file_exists("user://card_maker_fault.marker"):
			OS.kill(pid)
			OS.set_environment("FISHING_QA_CARD_PAUSE", "")
			OS.set_environment("FISHING_QA_CARD_FAULT", "")
			return {"killed": true}
		if not OS.is_process_running(pid):
			OS.set_environment("FISHING_QA_CARD_PAUSE", "")
			OS.set_environment("FISHING_QA_CARD_FAULT", "")
			return _read(RESULT)
		OS.delay_msec(20)
	OS.kill(pid)
	return {}

func _fish_ids() -> String:
	return JSON.stringify(_read(INVENTORY).get("fish_specimens", {}))

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	for bad_case in ["malformed", "future"]:
		for location in ["primary", "temporary"]:
			_reset()
			var bytes := "[]" if bad_case == "malformed" else '{"version":999,"transaction_id":"future-card"}'
			var path := JOURNAL if location == "primary" else TEMP
			_check(bad_case + " " + location + " written", _write(path, bytes))
			var service := FishingCardMakerService.new()
			service.configure_pending_journal_paths(JOURNAL, TEMP)
			var recovery: Dictionary = service.recover_pending_transaction()
			_check(bad_case + " " + location + " blocks recovery", bool(recovery.get("blocked", false))
				and service.has_pending_transaction())
			_check(bad_case + " " + location + " bytes retained", FileAccess.get_file_as_string(path) == bytes)
			service.free()
			_check(bad_case + " " + location + " operation blocked", not bool(_child("make").get("success", true))
				and FileAccess.get_file_as_string(path) == bytes)
	_reset()
	var inaccessible_path := ProjectSettings.globalize_path(JOURNAL)
	_check("inaccessible journal path created", DirAccess.make_dir_absolute(inaccessible_path) == OK)
	var inaccessible_service := FishingCardMakerService.new()
	inaccessible_service.configure_pending_journal_paths(JOURNAL, TEMP)
	_check("inaccessible journal blocks recovery", bool(inaccessible_service.recover_pending_transaction().get("blocked", false))
		and inaccessible_service.has_pending_transaction())
	inaccessible_service.free()
	_check("inaccessible journal blocks inventory and catch", not bool(_child("direct_write").get("saved", true))
		and _child("conflict_catch").get("reason", "") == "pending_card_maker_transaction"
		and DirAccess.dir_exists_absolute(inaccessible_path))
	_check("inaccessible journal path retained", DirAccess.remove_absolute(inaccessible_path) == OK)
	_reset()
	_check("promotion failure setup", bool(_child("setup").get("success", false)))
	var baseline_ids := _fish_ids()
	var promoted := _child("make", "", "fail_promotion")
	_check("failed promotion leaves staged intent", not bool(promoted.get("success", true))
		and FileAccess.file_exists(TEMP) and not FileAccess.file_exists(JOURNAL)
		and promoted.get("fish", -1) == 1 and promoted.get("card_quantity", -1) == 0)
	_check("staged intent restart recovery", _child("recover").get("recovered", false)
		and not FileAccess.file_exists(TEMP) and _fish_ids() == baseline_ids)
	_reset()
	_check("post-intent interruption setup", bool(_child("setup").get("success", false)))
	baseline_ids = _fish_ids()
	_check("kill after promoted intent before spend", bool(_child("make", "after_intent", "", true).get("killed", false))
		and FileAccess.file_exists(JOURNAL) and _fish_ids() == baseline_ids
		and _read(CARD).get("quantity", 0) == 0)
	_check("post-intent restart keeps exact baseline", _child("recover").get("reason", "") == "rolled_back_unfinished_transaction"
		and _fish_ids() == baseline_ids and not FileAccess.file_exists(JOURNAL))
	_check("post-intent second restart is inert", _child("recover").get("reason", "") == "nothing_pending"
		and _fish_ids() == baseline_ids and _read(CARD).get("quantity", 0) == 0)
	_reset()
	_check("interrupted spend setup", bool(_child("setup").get("success", false)))
	baseline_ids = _fish_ids()
	_check("kill after inventory commit", bool(_child("make", "after_inventory_commit", "", true).get("killed", false))
		and FileAccess.file_exists(JOURNAL) and _read(CARD).get("quantity", 0) == 0)
	var original_pending := FileAccess.get_file_as_string(JOURNAL)
	var other_intent := _read(JOURNAL)
	other_intent.transaction_id = "replacement-must-fail"
	var replacement_service := FishingCardMakerService.new()
	replacement_service.configure_pending_journal_paths(JOURNAL, TEMP)
	_check("pending intent resists replacement", not bool(replacement_service.call("_write_pending", other_intent))
		and FileAccess.get_file_as_string(JOURNAL) == original_pending)
	replacement_service.free()
	_check("pending intent blocks direct fishing write", not bool(_child("direct_write").get("saved", true)))
	_check("pending intent blocks new catch", _child("conflict_catch").get("reason", "") == "pending_card_maker_transaction")
	var rolled := _child("recover")
	_check("restart one restores exact fish and zenny", rolled.get("reason", "") == "rolled_back_unfinished_transaction"
		and rolled.get("fish", -1) == 1 and rolled.get("zenny", -1) == 275
		and rolled.get("card_quantity", -1) == 0 and _fish_ids() == baseline_ids and not FileAccess.file_exists(JOURNAL))
	_check("restart two does not refund twice", _child("recover").get("reason", "") == "nothing_pending"
		and _fish_ids() == baseline_ids and _read(CARD).get("quantity", 0) == 0)
	_reset()
	_check("pending operation setup", bool(_child("setup").get("success", false)))
	_check("pending operation interrupted", bool(_child("make", "after_inventory_commit", "", true).get("killed", false)))
	var next_make := _child("make")
	_check("next operation only recovers", not bool(next_make.get("success", true))
		and next_make.get("reason", "") == "pending_transaction_recovered"
		and next_make.get("fish", -1) == 1 and next_make.get("zenny", -1) == 275
		and next_make.get("card_quantity", -1) == 0 and not FileAccess.file_exists(JOURNAL))
	_reset()
	_check("ambiguous journal setup", bool(_child("setup").get("success", false)))
	_check("ambiguous journal interrupted", bool(_child("make", "after_inventory_commit", "", true).get("killed", false)))
	var primary_bytes := FileAccess.get_file_as_string(JOURNAL)
	var conflicting := _read(JOURNAL)
	conflicting.transaction_id = "different-pending-intent"
	var staged_bytes := JSON.stringify(conflicting)
	_check("conflicting staged intent written", _write(TEMP, staged_bytes))
	_check("ambiguous journals block without guessing", _child("recover").get("reason", "") == "ambiguous_pending_journal"
		and FileAccess.get_file_as_string(JOURNAL) == primary_bytes
		and FileAccess.get_file_as_string(TEMP) == staged_bytes)
	_reset()
	_check("interrupted grant setup", bool(_child("setup").get("success", false)))
	_check("kill after card grant", bool(_child("make", "before_cleanup", "", true).get("killed", false))
		and FileAccess.file_exists(JOURNAL) and _read(CARD).get("quantity", 0) == 1)
	var committed := _child("recover")
	_check("restart one keeps exactly one reward", committed.get("reason", "") == "commit_already_completed"
		and committed.get("fish", -1) == 0 and committed.get("zenny", -1) == 200
		and committed.get("card_quantity", -1) == 1 and not FileAccess.file_exists(JOURNAL))
	_check("restart two leaves reward unchanged", _child("recover").get("reason", "") == "nothing_pending"
		and _read(CARD).get("quantity", 0) == 1)
	_reset()
	_check("repeat recipe setup", bool(_child("setup").get("success", false)))
	var first_card := _child("make")
	var second_card := _child("make")
	_check("first and duplicate costs and ownership", first_card.get("success", false)
		and first_card.get("fish", -1) == 0 and first_card.get("zenny", -1) == 200
		and first_card.get("card_quantity", -1) == 1 and second_card.get("success", false)
		and second_card.get("fish", -1) == 0 and second_card.get("zenny", -1) == 50
		and second_card.get("card_quantity", -1) == 2)
	_check("repeat transactions distinct and durable", str(first_card.get("transaction_id", "")) != ""
		and str(second_card.get("transaction_id", "")) != ""
		and first_card.transaction_id != second_card.transaction_id
		and _child("recover").get("reason", "") == "nothing_pending"
		and _child("recover").get("card_quantity", -1) == 2)
	_reset()
	_check("cleanup fault setup", bool(_child("setup").get("success", false)))
	var made := _child("make", "", "fail_cleanup")
	_check("failed cleanup retains completed intent", made.get("success", false)
		and made.get("journal_cleanup_pending", false) and FileAccess.file_exists(JOURNAL))
	var failed_again := _child("recover", "", "fail_cleanup")
	_check("repeated cleanup failure blocks", failed_again.get("blocked", false)
		and FileAccess.file_exists(JOURNAL) and failed_again.get("card_quantity", -1) == 1)
	_check("later recovery clears once", _child("recover").get("reason", "") == "commit_already_completed"
		and _child("recover").get("reason", "") == "nothing_pending" and _read(CARD).get("quantity", 0) == 1)
	_reset()
	_check("shared journal setup", bool(_child("setup").get("success", false)))
	var future_cross := '{"version":999,"transaction_id":"future-cross"}'
	_check("shared journal written", _write("user://item_sale_pending.json", future_cross))
	_check("shared journal blocks card maker", _child("make").get("reason", "") == "pending_cross_store_transaction"
		and FileAccess.get_file_as_string("user://item_sale_pending.json") == future_cross
		and not FileAccess.file_exists(JOURNAL))
	_reset()
	_check("catch journal setup", bool(_child("setup").get("success", false)))
	var catch_pending := '{"version":999,"transaction_id":"future-catch"}'
	_check("catch journal written", _write("user://fishing_catch_pending.json", catch_pending))
	_check("catch journal blocks card maker", _child("make").get("reason", "") == "pending_catch_transaction"
		and FileAccess.get_file_as_string("user://fishing_catch_pending.json") == catch_pending)
	Isolation.emit_result("fishing_card_journal_runner", passed, total, total - passed, Node.get_orphan_node_ids().size())
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
