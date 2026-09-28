extends Node

## Cross-save integrity audit for the fishing vertical slice.
##
## Persistent ownership stays with each domain service. This coordinator only
## checks/repairs derived or structurally recoverable state and provides one
## explicit save barrier for the full fishing slice.

signal integrity_checked(report: Dictionary)

var progress = null
var inventory = null
var catch_repository = null
var reward_service = null
var unlock_state = null
var modifier_service = null
var content_catalog = null
var tackle_catalog = null
var loadout = null

var last_report: Dictionary = {}


func configure(
	new_progress,
	new_inventory,
	new_catch_repository,
	new_reward_service,
	new_unlock_state,
	new_modifier_service,
	new_content_catalog,
	new_tackle_catalog,
	persist_repairs: bool = true
) -> void:
	progress = new_progress
	inventory = new_inventory
	catch_repository = new_catch_repository
	reward_service = new_reward_service
	unlock_state = new_unlock_state
	modifier_service = new_modifier_service
	content_catalog = new_content_catalog
	tackle_catalog = new_tackle_catalog
	last_report = audit_and_repair(true, persist_repairs)


func bind_loadout(new_loadout) -> Dictionary:
	loadout = new_loadout
	if loadout != null and loadout.has_method("repair_selection"):
		loadout.repair_selection(true)
	last_report = audit_and_repair(true)
	return last_report.duplicate(true)


func audit_and_repair(
	repair: bool = true,
	persist_repairs: bool = true
) -> Dictionary:
	var errors = PackedStringArray()
	var warnings = PackedStringArray()
	var repairs = PackedStringArray()

	if progress == null:
		errors.append("progress service missing")
	if inventory == null:
		errors.append("inventory service missing")
	if content_catalog == null:
		errors.append("content catalog missing")
	if tackle_catalog == null:
		errors.append("tackle catalog missing")

	if not errors.is_empty():
		last_report = _report(errors, warnings, repairs)
		integrity_checked.emit(last_report.duplicate(true))
		return last_report

	if catch_repository != null and catch_repository.has_pending_transaction():
		var recovery: Dictionary = catch_repository.recover_pending_transaction()
		if bool(recovery.get("recovered", false)):
			repairs.append("recovered pending catch transaction")
		elif str(recovery.get("reason", "")) != "nothing_pending":
			errors.append("pending catch recovery failed: %s" % str(recovery.get("reason", "unknown")))

	_audit_progress(errors, warnings, repairs, repair, persist_repairs)
	_audit_inventory(errors, warnings, repairs, repair, persist_repairs)
	_audit_loadout(errors, warnings, repairs, repair)
	_audit_modifiers(errors, warnings)
	_audit_rewards(errors, warnings)

	last_report = _report(errors, warnings, repairs)
	integrity_checked.emit(last_report.duplicate(true))
	return last_report


func save_all() -> Dictionary:
	var results: Dictionary = {
		"progress": true,
		"inventory": true,
		"rewards": true,
		"unlocks": true,
		"modifiers": true,
		"loadout": true,
	}
	if progress != null:
		results["progress"] = progress.commit_changes()
	if inventory != null:
		results["inventory"] = inventory.commit_changes()
	if reward_service != null:
		results["rewards"] = reward_service.save_to_disk()
	if unlock_state != null:
		results["unlocks"] = unlock_state.save_to_disk()
	if modifier_service != null and modifier_service.has_method("commit_changes"):
		results["modifiers"] = modifier_service.commit_changes()
	if loadout != null and loadout.has_method("save_to_disk"):
		results["loadout"] = loadout.save_to_disk()

	var durable: bool = true
	for value in results.values():
		if not bool(value):
			durable = false
			break
	results["durable"] = durable
	return results


func get_last_report() -> Dictionary:
	return last_report.duplicate(true)


func _audit_progress(
	errors: PackedStringArray,
	warnings: PackedStringArray,
	repairs: PackedStringArray,
	repair: bool,
	persist_repairs: bool
) -> void:
	var expected_points: int = 0
	var records: Dictionary = progress.get_all_records()
	for raw_species_id in records.keys():
		var species_id: String = str(raw_species_id)
		if content_catalog.get_fish_by_id(StringName(species_id)) == null:
			warnings.append("progress has unknown species: %s" % species_id)
		var record: Dictionary = records[raw_species_id]
		expected_points += maxi(int(record.get("best_points", 0)), 0)

	expected_points = mini(expected_points, progress.get_max_fishing_points())
	if progress.get_fishing_points() != expected_points:
		if repair and progress.has_method("repair_derived_totals"):
			progress.repair_derived_totals(persist_repairs)
			repairs.append("recalculated fishing points/total catches")
		else:
			errors.append("fishing point total does not match species records")


func _audit_inventory(
	errors: PackedStringArray,
	warnings: PackedStringArray,
	repairs: PackedStringArray,
	repair: bool,
	persist_repairs: bool
) -> void:
	var seen_specimen_ids: Dictionary = {}
	var seen_transactions: Dictionary = {}
	var duplicate_specimen_ids: int = 0

	var all_specimens: Dictionary = inventory.get_all_fish_specimens()
	for raw_species_id in all_specimens.keys():
		var species_id: String = str(raw_species_id)
		if content_catalog.get_fish_by_id(StringName(species_id)) == null:
			warnings.append("inventory has unknown species: %s" % species_id)
		var entries: Array = all_specimens[raw_species_id]
		for raw_entry in entries:
			if not (raw_entry is Dictionary):
				continue
			var entry: Dictionary = raw_entry
			var specimen_id: int = int(entry.get("specimen_id", 0))
			if specimen_id <= 0 or seen_specimen_ids.has(specimen_id):
				duplicate_specimen_ids += 1
			seen_specimen_ids[specimen_id] = true
			var transaction_id: String = str(entry.get("catch_transaction_id", "")).strip_edges()
			if not transaction_id.is_empty():
				if seen_transactions.has(transaction_id):
					warnings.append("duplicate inventory catch transaction: %s" % transaction_id)
				seen_transactions[transaction_id] = true

	if duplicate_specimen_ids > 0:
		if repair and inventory.has_method("repair_specimen_ids"):
			var fixed: int = int(inventory.repair_specimen_ids(persist_repairs))
			repairs.append("repaired %d specimen ids" % fixed)
		else:
			errors.append("inventory contains duplicate/invalid specimen ids")

	for lure_id in inventory.get_owned_lure_ids():
		if not tackle_catalog.has_lure(StringName(lure_id)):
			warnings.append("inventory has unknown lure: %s" % lure_id)
	for rod_id in inventory.get_owned_rod_ids():
		if not tackle_catalog.has_rod(StringName(rod_id)):
			warnings.append("inventory has unknown rod: %s" % rod_id)


func _audit_loadout(
	errors: PackedStringArray,
	_warnings: PackedStringArray,
	repairs: PackedStringArray,
	repair: bool
) -> void:
	if loadout == null:
		return
	var lure = loadout.get_selected_lure()
	var rod = loadout.get_selected_rod()
	var invalid: bool = (
		lure == null
		or rod == null
		or not inventory.owns_lure(lure)
		or not inventory.owns_rod(rod)
	)
	if not invalid:
		return
	if repair and loadout.has_method("repair_selection"):
		loadout.repair_selection(true)
		var repaired_lure = loadout.get_selected_lure()
		var repaired_rod = loadout.get_selected_rod()
		var repair_valid: bool = (
			repaired_lure != null
			and repaired_rod != null
			and inventory.owns_lure(repaired_lure)
			and inventory.owns_rod(repaired_rod)
		)
		if repair_valid:
			repairs.append("repaired equipped tackle selection")
		else:
			errors.append("no valid owned tackle is available for loadout repair")
	else:
		errors.append("equipped tackle is not owned")


func _audit_modifiers(
	_errors: PackedStringArray,
	warnings: PackedStringArray
) -> void:
	if modifier_service == null:
		return
	for effect in modifier_service.get_active_effects():
		if float(effect.get("remaining_seconds", 0.0)) <= 0.0:
			warnings.append("expired session modifier remained active")


func _audit_rewards(
	_errors: PackedStringArray,
	warnings: PackedStringArray
) -> void:
	if reward_service == null:
		return
	for status in reward_service.get_all_reward_statuses():
		if bool(status.get("claimed", false)) and not bool(status.get("reward_resolvable", true)):
			warnings.append("claimed reward no longer resolves: %s" % str(status.get("reward_key", "")))


func _report(
	errors: PackedStringArray,
	warnings: PackedStringArray,
	repairs: PackedStringArray
) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"error_count": errors.size(),
		"warning_count": warnings.size(),
		"repair_count": repairs.size(),
		"errors": errors,
		"warnings": warnings,
		"repairs": repairs,
	}
