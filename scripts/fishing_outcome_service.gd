extends RefCounted

## Single authority for the gameplay consequences of a fishing outcome.
## Encounter decides *what happened*. This service decides *what that outcome
## changes*: records/inventory, lure loss and reward evaluation.

const OUTCOME_NONE: StringName = &"none"
const OUTCOME_MISS: StringName = &"miss"
const OUTCOME_HOOK_OFF: StringName = &"hook_off"
const OUTCOME_LINE_BREAK: StringName = &"line_break"
const OUTCOME_CATCH: StringName = &"catch"
const OUTCOME_CANCELLED: StringName = &"cancelled"

var policy: Resource = null
var catch_repository = null
var loadout = null
var reward_service = null

var _cast_serial: int = 0
var _miss_count: int = 0
var _terminal_resolved: bool = false
var _last_result: Dictionary = {}


func configure(
	new_catch_repository,
	new_loadout,
	new_reward_service,
	new_policy: Resource
) -> void:
	catch_repository = new_catch_repository
	loadout = new_loadout
	reward_service = new_reward_service
	policy = new_policy


func begin_cast() -> int:
	_cast_serial += 1
	_miss_count = 0
	_terminal_resolved = false
	_last_result = {}
	return _cast_serial


func reset_session() -> void:
	_miss_count = 0
	_terminal_resolved = false
	_last_result = {}


func resolve_miss() -> Dictionary:
	if _terminal_resolved:
		return _duplicate_rejection(OUTCOME_MISS)

	_miss_count += 1
	var result := _make_base_result(OUTCOME_MISS, false)
	result["miss_count"] = _miss_count
	result["rule"] = _get_rule(OUTCOME_MISS)
	_last_result = result.duplicate(true)
	return result


func resolve_hook_off() -> Dictionary:
	return _resolve_failure(OUTCOME_HOOK_OFF)


func resolve_line_break() -> Dictionary:
	return _resolve_failure(OUTCOME_LINE_BREAK)


func resolve_cancelled() -> Dictionary:
	if _terminal_resolved:
		return _duplicate_rejection(OUTCOME_CANCELLED)

	_terminal_resolved = true
	var result := _make_base_result(OUTCOME_CANCELLED, true)
	var rule := _get_rule(OUTCOME_CANCELLED)
	result["rule"] = rule
	result["lure_loss"] = _apply_lure_rule(
		OUTCOME_CANCELLED,
		bool(rule.get("consume_lure", false))
	)
	_last_result = result.duplicate(true)
	return result


func resolve_catch(
	fish,
	catch_context: Dictionary,
	should_record: bool
) -> Dictionary:
	if _terminal_resolved:
		return _duplicate_rejection(OUTCOME_CATCH)

	if fish == null or fish.species == null:
		return {
			"applied": false,
			"duplicate": false,
			"terminal": false,
			"outcome": str(OUTCOME_CATCH),
			"reason": "invalid_fish",
			"cast_serial": _cast_serial,
		}

	_terminal_resolved = true
	var rule := _get_rule(OUTCOME_CATCH)
	var result := _make_base_result(OUTCOME_CATCH, true)
	result["rule"] = rule
	result["is_king"] = bool(fish.is_king)
	result["species_id"] = str(fish.species.get_stable_species_id())
	result["fish_name"] = fish.species.fish_name
	result["size"] = float(fish.size)
	result["points"] = int(fish.points)

	var rewards_before := _capture_reward_states()
	var catch_result: Dictionary = {}

	if not should_record:
		catch_result = {
			"committed": false,
			"durable": false,
			"recording_skipped": true,
			"reason": "debug_recording_disabled",
		}
	elif not bool(rule.get("record_catch", true)):
		catch_result = {
			"committed": false,
			"durable": false,
			"recording_skipped": true,
			"reason": "recording_disabled_by_policy",
		}
	elif catch_repository == null:
		catch_result = {
			"committed": false,
			"durable": false,
			"recording_skipped": false,
			"reason": "repository_unavailable",
		}
	else:
		catch_result = catch_repository.commit_catch(
			fish,
			catch_context
		)

	result["catch_result"] = catch_result.duplicate(true)
	result["catch_committed"] = bool(catch_result.get("committed", false))
	result["catch_durable"] = bool(catch_result.get("durable", false))
	result["recording_skipped"] = bool(
		catch_result.get("recording_skipped", false)
	)
	result["backend_ok"] = (
		bool(result["catch_committed"])
		or bool(result["recording_skipped"])
	)
	result["progression_change"] = _build_progression_change(catch_result)

	if (
		bool(rule.get("evaluate_rewards", true))
		and reward_service != null
		and bool(result["catch_committed"])
	):
		# Progress emits synchronously, but this call is intentionally idempotent
		# and makes outcome finalization independent of signal connection order.
		reward_service.evaluate_rewards()

	var rewards_after := _capture_reward_states()
	result["reward_changes"] = _diff_reward_states(
		rewards_before,
		rewards_after
	)
	result["lure_loss"] = _apply_lure_rule(
		OUTCOME_CATCH,
		bool(rule.get("consume_lure", false))
	)

	_last_result = result.duplicate(true)
	return result


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func get_debug_snapshot() -> Dictionary:
	return {
		"cast_serial": _cast_serial,
		"miss_count": _miss_count,
		"terminal_resolved": _terminal_resolved,
		"last_result": _last_result.duplicate(true),
	}


func _resolve_failure(outcome: StringName) -> Dictionary:
	if _terminal_resolved:
		return _duplicate_rejection(outcome)

	_terminal_resolved = true
	var rule := _get_rule(outcome)
	var result := _make_base_result(outcome, true)
	result["rule"] = rule
	result["lure_loss"] = _apply_lure_rule(
		outcome,
		bool(rule.get("consume_lure", false))
	)
	_last_result = result.duplicate(true)
	return result


func _make_base_result(
	outcome: StringName,
	terminal: bool
) -> Dictionary:
	return {
		"applied": true,
		"duplicate": false,
		"terminal": terminal,
		"outcome": str(outcome),
		"reason": "ok",
		"cast_serial": _cast_serial,
		"miss_count": _miss_count,
	}


func _duplicate_rejection(outcome: StringName) -> Dictionary:
	return {
		"applied": false,
		"duplicate": true,
		"terminal": true,
		"outcome": str(outcome),
		"reason": "terminal_outcome_already_resolved",
		"cast_serial": _cast_serial,
		"previous_result": _last_result.duplicate(true),
	}


func _get_rule(outcome: StringName) -> Dictionary:
	if policy != null and policy.has_method("get_rule"):
		return policy.get_rule(outcome)

	# Safe fallback mirrors the authored default policy.
	return {
		"terminal": outcome != OUTCOME_MISS,
		"consume_lure": outcome == OUTCOME_LINE_BREAK,
		"record_catch": outcome == OUTCOME_CATCH,
		"evaluate_rewards": outcome == OUTCOME_CATCH,
	}


func _apply_lure_rule(
	outcome: StringName,
	consume_lure: bool
) -> Dictionary:
	if not consume_lure:
		return {
			"consumed": false,
			"reason": "kept_by_outcome_policy",
			"outcome": str(outcome),
		}

	if loadout == null or not loadout.has_method("consume_equipped_lure"):
		return {
			"consumed": false,
			"reason": "loadout_unavailable",
			"outcome": str(outcome),
		}

	if _should_protect_last_owned_lure():
		return {
			"consumed": false,
			"reason": "last_owned_lure_protected",
			"outcome": str(outcome),
		}

	var loss_result = loadout.consume_equipped_lure(outcome)
	if loss_result is Dictionary:
		var typed_result := (loss_result as Dictionary).duplicate(true)
		typed_result["outcome"] = str(outcome)
		return typed_result

	return {
		"consumed": false,
		"reason": "invalid_lure_loss_result",
		"outcome": str(outcome),
	}


static func should_protect_last_lure(
	protection_enabled: bool,
	total_owned_units: int
) -> bool:
	return protection_enabled and total_owned_units == 1


func _should_protect_last_owned_lure() -> bool:
	if policy == null:
		return false

	if not bool(policy.get("protect_last_owned_lure")):
		return false

	if loadout == null or not loadout.has_method("get_inventory"):
		return false

	var inventory = loadout.get_inventory()
	if inventory == null:
		return false

	if (
		not inventory.has_method("get_owned_lure_ids")
		or not inventory.has_method("get_lure_count")
	):
		return false

	var total_units: int = 0
	for lure_id in inventory.get_owned_lure_ids():
		total_units += maxi(
			int(inventory.get_lure_count(StringName(str(lure_id)))),
			0
		)
		if total_units > 1:
			return false

	return should_protect_last_lure(true, total_units)


func _build_progression_change(catch_result: Dictionary) -> Dictionary:
	if not bool(catch_result.get("committed", false)):
		return {}

	var progress_result: Dictionary = (
		catch_result.get("progress_result", {}) as Dictionary
	)
	if progress_result.is_empty():
		# Older repository snapshots may expose the progression fields directly.
		progress_result = catch_result

	return {
		"points_before": int(progress_result.get("fishing_points_before", 0)),
		"points_after": int(progress_result.get("fishing_points", 0)),
		"points_gained": int(progress_result.get("fishing_points_gained", 0)),
		"rank_before": str(progress_result.get("rank_before", "")),
		"rank_after": str(progress_result.get("rank_name", "")),
		"rank_id": str(progress_result.get("rank_id", "")),
		"rank_index": int(progress_result.get("rank_index", 0)),
		"rank_up": bool(progress_result.get("rank_up", false)),
		"rank_changes": (progress_result.get("rank_changes", []) as Array).duplicate(true),
		"rank_progress": (progress_result.get("rank_progress", {}) as Dictionary).duplicate(true),
		"next_rank_points": int(progress_result.get("next_rank_points", 0)),
		"points_to_next_rank": int(progress_result.get("points_to_next_rank", 0)),
		"new_species": bool(progress_result.get("new_species", false)),
		"new_best_size": bool(progress_result.get("new_best_size", false)),
		"new_best_points": bool(progress_result.get("new_best_points", false)),
		"first_king": bool(progress_result.get("first_king", false)),
	}


func _capture_reward_states() -> Dictionary:
	var result: Dictionary = {}
	if reward_service == null or not reward_service.has_method("get_all_reward_statuses"):
		return result

	for status in reward_service.get_all_reward_statuses():
		if not (status is Dictionary):
			continue
		var reward_key := str(status.get("reward_key", ""))
		if reward_key.is_empty():
			continue
		result[reward_key] = str(status.get("state_label", "UNKNOWN"))

	return result


func _diff_reward_states(
	before: Dictionary,
	after: Dictionary
) -> Dictionary:
	var newly_available := PackedStringArray()
	var newly_claimed := PackedStringArray()

	for raw_key in after.keys():
		var key := str(raw_key)
		var old_state := str(before.get(key, "LOCKED"))
		var new_state := str(after.get(key, "LOCKED"))

		if new_state == "AVAILABLE" and old_state != "AVAILABLE":
			newly_available.append(key)
		elif new_state == "CLAIMED" and old_state != "CLAIMED":
			newly_claimed.append(key)

	newly_available.sort()
	newly_claimed.sort()
	return {
		"newly_available": newly_available,
		"newly_claimed": newly_claimed,
	}
