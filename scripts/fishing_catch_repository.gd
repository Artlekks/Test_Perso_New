extends Node
class_name FishingCatchRepository

signal catch_committed(result: Dictionary)
signal pending_recovery_completed(transaction_id: String)

const CatchEvaluator = preload(
	"res://scripts/fishing_catch_evaluator.gd"
)

const PENDING_PATH: String = "user://fishing_catch_pending.json"
const PENDING_TEMP_PATH: String = "user://fishing_catch_pending.tmp"
const JOURNAL_VERSION: int = 1

var progress: FishingProgress = null
var inventory: FishingInventory = null
var _transaction_counter: int = 0


func configure(
	new_progress: FishingProgress,
	new_inventory: FishingInventory
) -> void:
	progress = new_progress
	inventory = new_inventory
	recover_pending_transaction()


func commit_catch(
	fish: FishInstance,
	catch_context: Dictionary = {}
) -> Dictionary:
	if fish == null or fish.species == null:
		return {
			"committed": false,
			"reason": "invalid_fish",
		}

	var snapshot: Dictionary = CatchEvaluator.create_snapshot(
		fish,
		catch_context
	)
	return commit_snapshot(snapshot)


func commit_snapshot(input_snapshot: Dictionary) -> Dictionary:
	if progress == null or inventory == null:
		return {
			"committed": false,
			"reason": "repository_unconfigured",
		}

	if input_snapshot.is_empty():
		return {
			"committed": false,
			"reason": "empty_snapshot",
		}

	var snapshot: Dictionary = input_snapshot.duplicate(true)
	var transaction_id: String = str(
		snapshot.get("transaction_id", "")
	).strip_edges()

	if transaction_id.is_empty():
		transaction_id = _create_transaction_id()
		snapshot["transaction_id"] = transaction_id

	if not _write_pending_snapshot(snapshot):
		return {
			"committed": false,
			"reason": "pending_journal_write_failed",
			"transaction_id": transaction_id,
		}

	var progress_before: Dictionary = progress.create_transaction_snapshot()
	var inventory_before: Dictionary = inventory.create_transaction_snapshot()

	var progress_result: Dictionary = progress.record_catch_snapshot(
		snapshot,
		false,
		false
	)

	if progress_result.is_empty():
		progress.restore_transaction_snapshot(progress_before, false)
		inventory.restore_transaction_snapshot(inventory_before)
		_clear_pending_file()
		return {
			"committed": false,
			"reason": "progress_apply_failed",
			"transaction_id": transaction_id,
		}

	if bool(
		progress_result.get(
			"transaction_already_applied",
			false
		)
	):
		progress.restore_transaction_snapshot(progress_before, false)
		inventory.restore_transaction_snapshot(inventory_before)
		_clear_pending_file()
		return {
			"committed": false,
			"reason": "duplicate_transaction",
			"transaction_id": transaction_id,
		}

	var specimen: FishingFishSpecimen = _add_snapshot_to_inventory(
		snapshot,
		false
	)

	if specimen == null:
		progress.restore_transaction_snapshot(progress_before, false)
		inventory.restore_transaction_snapshot(inventory_before)
		_clear_pending_file()
		return {
			"committed": false,
			"reason": "inventory_apply_failed",
			"transaction_id": transaction_id,
		}

	# Both runtime states are now consistent. The journal remains until both
	# independent save files are durable.
	var progress_saved: bool = progress.commit_changes()
	var inventory_saved: bool = inventory.commit_changes()
	var durable: bool = progress_saved and inventory_saved

	if durable:
		_clear_pending_file()

	inventory.emit_specimen_commit(
		str(snapshot.get("species_id", "")),
		specimen
	)
	progress.emit_catch_commit(progress_result)

	var result: Dictionary = progress_result.duplicate(true)
	result["committed"] = true
	result["durable"] = durable
	result["pending_recovery"] = not durable
	result["transaction_id"] = transaction_id
	result["inventory_specimen"] = specimen.to_dictionary()
	result["reason"] = (
		"ok"
		if durable
		else "committed_pending_recovery"
	)

	catch_committed.emit(result.duplicate(true))
	return result


func recover_pending_transaction() -> Dictionary:
	if progress == null or inventory == null:
		return {
			"recovered": false,
			"reason": "repository_unconfigured",
		}

	var snapshot: Dictionary = _read_pending_snapshot()

	if snapshot.is_empty():
		return {
			"recovered": false,
			"reason": "nothing_pending",
		}

	var transaction_id: String = str(
		snapshot.get("transaction_id", "")
	).strip_edges()

	if transaction_id.is_empty():
		_clear_pending_file()
		return {
			"recovered": false,
			"reason": "invalid_pending_transaction",
		}

	var progress_changed: bool = false
	var inventory_changed: bool = false

	if not progress.has_catch_transaction(transaction_id):
		var progress_result: Dictionary = progress.record_catch_snapshot(
			snapshot,
			false,
			false
		)
		if progress_result.is_empty():
			return {
				"recovered": false,
				"reason": "progress_recovery_apply_failed",
				"transaction_id": transaction_id,
			}
		progress_changed = true

	if not inventory.has_catch_transaction(transaction_id):
		var specimen: FishingFishSpecimen = _add_snapshot_to_inventory(
			snapshot,
			false
		)
		if specimen == null:
			return {
				"recovered": false,
				"reason": "inventory_recovery_apply_failed",
				"transaction_id": transaction_id,
			}
		inventory_changed = true

	var progress_saved: bool = (
		progress.commit_changes()
		if progress_changed
		else true
	)
	var inventory_saved: bool = (
		inventory.commit_changes()
		if inventory_changed
		else true
	)

	if not (progress_saved and inventory_saved):
		return {
			"recovered": false,
			"reason": "recovery_save_failed",
			"transaction_id": transaction_id,
			"progress_changed": progress_changed,
			"inventory_changed": inventory_changed,
		}

	_clear_pending_file()
	pending_recovery_completed.emit(transaction_id)

	return {
		"recovered": true,
		"reason": "ok",
		"transaction_id": transaction_id,
		"progress_changed": progress_changed,
		"inventory_changed": inventory_changed,
	}


func has_pending_transaction() -> bool:
	return FileAccess.file_exists(PENDING_PATH)


func get_pending_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = _read_pending_snapshot()

	if snapshot.is_empty():
		return {
			"pending": false,
		}

	return {
		"pending": true,
		"transaction_id": str(snapshot.get("transaction_id", "")),
		"species_id": str(snapshot.get("species_id", "")),
		"size": float(snapshot.get("size", 0.0)),
		"points": int(snapshot.get("points", 0)),
	}


func _add_snapshot_to_inventory(
	snapshot: Dictionary,
	emit_events: bool
) -> FishingFishSpecimen:
	var context: Dictionary = (
		snapshot.get("catch_context", {}) as Dictionary
	)

	return inventory.add_fish_specimen(
		str(snapshot.get("species_id", "")),
		str(snapshot.get("fish_name", "")),
		float(snapshot.get("size", 0.0)),
		int(snapshot.get("points", 0)),
		bool(snapshot.get("is_king", false)),
		false,
		false,
		context,
		str(snapshot.get("transaction_id", "")),
		emit_events
	)


func _create_transaction_id() -> String:
	_transaction_counter += 1
	return "%d-%d-%d" % [
		int(Time.get_unix_time_from_system()),
		Time.get_ticks_usec(),
		_transaction_counter,
	]


func _write_pending_snapshot(snapshot: Dictionary) -> bool:
	var payload: Dictionary = {
		"version": JOURNAL_VERSION,
		"snapshot": snapshot,
	}

	var file := FileAccess.open(
		PENDING_TEMP_PATH,
		FileAccess.WRITE
	)
	if file == null:
		push_warning(
			"FishingCatchRepository: could not open pending temp journal."
		)
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	var temp_absolute: String = ProjectSettings.globalize_path(
		PENDING_TEMP_PATH
	)
	var final_absolute: String = ProjectSettings.globalize_path(
		PENDING_PATH
	)

	if FileAccess.file_exists(PENDING_PATH):
		DirAccess.remove_absolute(final_absolute)

	var rename_error: Error = DirAccess.rename_absolute(
		temp_absolute,
		final_absolute
	)

	if rename_error != OK:
		push_warning(
			"FishingCatchRepository: could not promote pending journal."
		)
		return false

	return true


func _read_pending_snapshot() -> Dictionary:
	if not FileAccess.file_exists(PENDING_PATH):
		return {}

	var file := FileAccess.open(
		PENDING_PATH,
		FileAccess.READ
	)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()

	if not (parsed is Dictionary):
		return {}

	var payload: Dictionary = parsed
	if int(payload.get("version", 0)) > JOURNAL_VERSION:
		return {}

	var raw_snapshot: Variant = payload.get("snapshot", {})
	if not (raw_snapshot is Dictionary):
		return {}

	return (raw_snapshot as Dictionary).duplicate(true)


func _clear_pending_file() -> void:
	for path in [PENDING_PATH, PENDING_TEMP_PATH]:
		if not FileAccess.file_exists(path):
			continue

		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path)
		)
