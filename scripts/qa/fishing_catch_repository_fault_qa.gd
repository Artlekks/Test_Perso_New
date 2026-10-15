extends RefCounted

const Progress = preload("res://scripts/fishing_progress.gd")
const Inventory = preload("res://scripts/fishing_inventory.gd")
const Repository = preload("res://scripts/fishing_catch_repository.gd")
const Evaluator = preload("res://scripts/fishing_catch_evaluator.gd")
const Catalog = preload("res://data/bof4/catalogs/all_content.tres")
const ROOT := "user://fishing_catch_repository_fault_qa"

class FailingCleanupRepository:
	extends "res://scripts/fishing_catch_repository.gd"
	var fail_temp_removal: bool = true

	func _remove_journal_file(path: String) -> bool:
		if fail_temp_removal and path == _pending_temp_path:
			return false
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

static func isolation_paths() -> Array:
	return [ROOT]

static func run() -> Dictionary:
	var report := {"passed": 0, "total": 0, "failures": PackedStringArray()}
	var species = Catalog.fish[0]
	var species_id: String = species.get_stable_species_id()
	for kind in ["progress", "inventory", "repeat", "overwrite"]:
		var base: String = ROOT + "/" + kind
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
		var block: String = base + "/block"
		var blocker := FileAccess.open(block, FileAccess.WRITE)
		if blocker == null:
			_check(report, kind + " blocker created", false)
			continue
		blocker.store_string("deliberate parent-directory blocker")
		blocker.close()
		var progress_blocked: bool = kind == "progress"
		var state: Dictionary = _open(base, progress_blocked, not progress_blocked)
		var first_id: String = "qa-" + kind + "-1"
		var first: Dictionary = _snapshot(species, first_id)
		var result: Dictionary = state.repo.commit_snapshot(first)
		_check(report, kind + " initial commit remains pending", bool(result.get("committed", false)) and not bool(result.get("durable", true)) and state.repo.has_pending_transaction())
		if kind == "progress" or kind == "inventory":
			var retry: Dictionary = state.repo.recover_pending_transaction()
			_check(report, kind + " blocked same-object retry retains journal", not bool(retry.get("recovered", false)) and state.repo.has_pending_transaction())
		if kind == "repeat":
			_close(state)
			state = _open(base, false, true)
			var retry: Dictionary = state.repo.recover_pending_transaction()
			_check(report, "repeated blocked recovery retains journal", not bool(retry.get("recovered", false)) and state.repo.has_pending_transaction())
		if kind == "overwrite":
			var second: Dictionary = state.repo.commit_snapshot(_snapshot(species, "qa-overwrite-2"))
			var pending: Dictionary = state.repo.get_pending_debug_snapshot()
			_check(report, "second catch cannot overwrite unresolved journal", not bool(second.get("committed", true)) and str(pending.get("transaction_id", "")) == first_id)
		_close(state)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(block))
		state = _open(base, false, false)
		_check(report, kind + " restart repairs both durable sides", not state.repo.has_pending_transaction() and state.progress.has_catch_transaction(first_id) and state.inventory.has_catch_transaction(first_id) and state.progress.get_total_catches() == 1 and state.inventory.get_fish_count(species_id) == 1)
		_close(state)
		state = _open(base, false, false)
		_check(report, kind + " second restart has no duplicate reward", not state.repo.has_pending_transaction() and state.progress.get_total_catches() == 1 and state.inventory.get_fish_count(species_id) == 1)
		_close(state)
	for kind in ["malformed", "forward_version"]:
		var base: String = ROOT + "/" + kind
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
		var pending_path: String = base + "/pending.json"
		var payload: String = JSON.stringify({"version": 99, "snapshot": _snapshot(species, "qa-forward-1")})
		if kind == "malformed":
			payload = "{broken" if OS.get_environment("FISHING_QA_BAD_JSON") == "1" else "{}"
		var pending := FileAccess.open(pending_path, FileAccess.WRITE)
		pending.store_string(payload)
		pending.close()
		var state: Dictionary = _open(base, false, false)
		var attempt: Dictionary = state.repo.commit_snapshot(_snapshot(species, "qa-new-1"))
		var retained := FileAccess.open(pending_path, FileAccess.READ)
		var retained_text: String = retained.get_as_text() if retained != null else ""
		if retained != null:
			retained.close()
		var debug: Dictionary = state.repo.get_pending_debug_snapshot()
		_check(report, kind + " journal is preserved and new catch refused", not bool(attempt.get("committed", true)) and retained_text == payload and state.progress.get_total_catches() == 0 and state.inventory.get_fish_count(species_id) == 0)
		_check(report, kind + " debug state reports invalid pending journal", bool(debug.get("pending", false)) and not bool(debug.get("valid", true)) and str(debug.get("reason", "")) == "invalid_pending_journal")
		_close(state)
	_test_partial_journal_cleanup(report, species, species_id)
	_test_process_restarts(report)
	return report

static func _test_partial_journal_cleanup(report: Dictionary, species, species_id: String) -> void:
	var base: String = ROOT + "/partial_cleanup"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var block: String = base + "/block"
	var blocker := FileAccess.open(block, FileAccess.WRITE)
	if blocker == null:
		_check(report, "partial cleanup blocker created", false)
		return
	blocker.store_string("deliberate blocker")
	blocker.close()
	var state: Dictionary = _open(base, false, true)
	var transaction_id: String = "qa-partial-cleanup-1"
	var result: Dictionary = state.repo.commit_snapshot(_snapshot(species, transaction_id))
	_check(report, "partial cleanup setup retains primary", bool(result.get("committed", false)) and not bool(result.get("durable", true)) and state.repo.has_pending_transaction())
	_close(state)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(block))
	var temp_path: String = base + "/pending.tmp"
	var temp := FileAccess.open(temp_path, FileAccess.WRITE)
	if temp == null:
		_check(report, "partial cleanup temp created", false)
		return
	temp.store_string("orphan temporary journal")
	temp.close()
	var progress = Progress.new()
	progress.configure_save_path(base + "/progress.json")
	progress.initialize()
	var inventory = Inventory.new()
	inventory.configure_save_path(base + "/inventory.json")
	inventory.initialize()
	var repo := FailingCleanupRepository.new()
	repo.configure_pending_journal_paths(base + "/pending.json", temp_path)
	repo.configure(progress, inventory)
	var retry: Dictionary = repo.recover_pending_transaction()
	var debug: Dictionary = repo.get_pending_debug_snapshot()
	_check(report, "failed auxiliary cleanup retains primary journal", not bool(retry.get("recovered", false)) and str(retry.get("reason", "")) == "pending_journal_clear_failed" and FileAccess.file_exists(temp_path) and repo.has_pending_transaction() and str(debug.get("transaction_id", "")) == transaction_id)
	repo.fail_temp_removal = false
	var recovered: Dictionary = repo.recover_pending_transaction()
	_check(report, "cleanup retry removes temp then primary", bool(recovered.get("recovered", false)) and not FileAccess.file_exists(temp_path) and not repo.has_pending_transaction() and progress.get_total_catches() == 1 and inventory.get_fish_count(species_id) == 1)
	repo.free()
	progress.free()
	inventory.free()
	state = _open(base, false, false)
	_check(report, "partial cleanup restart has no duplicate catch", not state.repo.has_pending_transaction() and state.progress.get_total_catches() == 1 and state.inventory.get_fish_count(species_id) == 1)
	_close(state)

static func _test_process_restarts(report: Dictionary) -> void:
	var base: String = ROOT + "/process_restart"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base))
	var block: String = base + "/block"
	var blocker := FileAccess.open(block, FileAccess.WRITE)
	if blocker == null:
		_check(report, "process restart blocker created", false)
		return
	blocker.store_string("deliberate blocker")
	blocker.close()
	for stage in ["commit", "blocked", "repair", "verify"]:
		if stage == "repair":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(block))
		var stage_file := FileAccess.open(base + "/stage.txt", FileAccess.WRITE)
		stage_file.store_string(stage)
		stage_file.close()
		var output: Array = []
		var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://scripts/qa/fishing_catch_repository_process_stage.gd"], output, true)
		var result_present: bool = str(output).contains("QA_CHILD_RESULT stage=" + stage + " pass=true")
		print("QA_CHILD_STAGE stage=%s exit=%d result_present=%s" % [stage, code, str(result_present)])
		_check(report, "actual process restart " + stage, code == 0 and result_present)

static func _open(base: String, block_progress: bool, block_inventory: bool) -> Dictionary:
	var progress = Progress.new()
	progress.configure_save_path(base + ("/block/progress.json" if block_progress else "/progress.json"))
	progress.initialize()
	var inventory = Inventory.new()
	inventory.configure_save_path(base + ("/block/inventory.json" if block_inventory else "/inventory.json"))
	inventory.initialize()
	var repo = Repository.new()
	repo.configure_pending_journal_paths(base + "/pending.json", base + "/pending.tmp")
	repo.configure(progress, inventory)
	return {"progress": progress, "inventory": inventory, "repo": repo}

static func _close(state: Dictionary) -> void:
	state.repo.free()
	state.progress.free()
	state.inventory.free()

static func _snapshot(species, transaction_id: String) -> Dictionary:
	var snapshot: Dictionary = Evaluator.create_snapshot_from_values(species, 12.0)
	snapshot["transaction_id"] = transaction_id
	return snapshot

static func _check(report: Dictionary, label: String, condition: bool) -> void:
	report.total += 1
	if condition:
		report.passed += 1
	else:
		report.failures.append(label)
