extends Node
class_name FishingRewardService

signal reward_available(
	reward: FishingRewardDefinition
)
signal reward_claimed(
	reward: FishingRewardDefinition,
	result: Dictionary
)
signal changed

enum RewardState {
	LOCKED,
	AVAILABLE,
	CLAIMED,
}

const SAVE_VERSION: int = 2
const SAVE_PATH: String = "user://fishing_rewards.json"

var progress: FishingProgress = null
var inventory: FishingInventory = null
var tackle_catalog: FishingTackleCatalog = null
var unlock_state: FishingUnlockState = null
var reward_catalog: FishingRewardCatalog = null

var _claimed_reward_keys: Dictionary = {}
var _known_available_keys: Dictionary = {}
var _claims_in_progress: Dictionary = {}
var _initialized: bool = false


func _ready() -> void:
	initialize()


func initialize() -> void:
	if _initialized:
		return

	_initialized = true
	load_from_disk()


func configure(
	new_progress: FishingProgress,
	new_inventory: FishingInventory,
	new_tackle_catalog: FishingTackleCatalog,
	new_unlock_state: FishingUnlockState,
	new_reward_catalog: FishingRewardCatalog
) -> void:
	initialize()
	_disconnect_sources()

	progress = new_progress
	inventory = new_inventory
	tackle_catalog = new_tackle_catalog
	unlock_state = new_unlock_state
	reward_catalog = new_reward_catalog

	_connect_sources()
	_reconcile_claimed_unique_rewards()
	call_deferred("evaluate_rewards")


func evaluate_rewards() -> Array[FishingRewardDefinition]:
	var available: Array[FishingRewardDefinition] = (
		get_available_unclaimed_rewards()
	)
	var availability_changed: bool = false
	var current_available: Dictionary = {}

	for reward in available:
		var key: String = str(reward.reward_key)
		current_available[key] = true

		if not _known_available_keys.has(key):
			_known_available_keys[key] = true
			availability_changed = true
			reward_available.emit(reward)

		if reward.auto_claim:
			claim_reward(reward.reward_key)

	# Conditions currently only move forward in normal gameplay, but keeping
	# this cache accurate makes QA resets / save migration deterministic.
	for raw_key in _known_available_keys.keys():
		var key: String = str(raw_key)

		if (
			not current_available.has(key)
			and not is_claimed(StringName(key))
		):
			_known_available_keys.erase(key)
			availability_changed = true

	if availability_changed:
		changed.emit()

	return available


func get_available_unclaimed_rewards() -> Array[FishingRewardDefinition]:
	var result: Array[FishingRewardDefinition] = []

	if reward_catalog == null:
		return result

	for reward in reward_catalog.get_all_rewards():
		if is_claimed(reward.reward_key):
			continue

		if _is_condition_met(reward):
			result.append(reward)

	return result


func get_reward_state(
	reward_key: StringName
) -> RewardState:
	if is_claimed(reward_key):
		return RewardState.CLAIMED

	if reward_catalog == null:
		return RewardState.LOCKED

	var reward: FishingRewardDefinition = (
		reward_catalog.get_reward_by_key(
			reward_key
		)
	)

	if reward == null:
		return RewardState.LOCKED

	if _is_condition_met(reward):
		return RewardState.AVAILABLE

	return RewardState.LOCKED


func get_reward_status(
	reward_key: StringName
) -> Dictionary:
	if reward_catalog == null:
		return {}

	var reward: FishingRewardDefinition = (
		reward_catalog.get_reward_by_key(
			reward_key
		)
	)

	if reward == null:
		return {}

	var condition: Dictionary = (
		_get_condition_progress(reward)
	)
	var state: RewardState = get_reward_state(
		reward_key
	)

	return {
		"reward_key": str(reward.reward_key),
		"display_name": reward.display_name,
		"source_description": reward.source_description,
		"claim_source_id": str(
			reward.claim_source_id
		),
		"claim_source_name": reward.claim_source_name,
		"sort_order": reward.sort_order,
		"trigger_type": reward.trigger_type,
		"threshold": reward.threshold,
		"reward_type": reward.reward_type,
		"reward_item_id": str(
			reward.reward_item_id
		),
		"quantity": reward.quantity,
		"auto_claim": reward.auto_claim,
		"state": state,
		"state_label": _get_state_label(state),
		"claimed": state == RewardState.CLAIMED,
		"available": state == RewardState.AVAILABLE,
		"can_claim": can_claim(reward_key),
		"condition": condition,
	}


func get_all_reward_statuses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if reward_catalog == null:
		return result

	for reward in reward_catalog.get_all_rewards():
		var status: Dictionary = get_reward_status(
			reward.reward_key
		)

		if not status.is_empty():
			result.append(status)

	return result


func get_available_reward_count() -> int:
	return get_available_unclaimed_rewards().size()


func get_next_unclaimed_point_reward_status() -> Dictionary:
	if reward_catalog == null:
		return {}

	var best_reward: FishingRewardDefinition = null

	for reward in reward_catalog.get_all_rewards():
		if (
			reward.trigger_type
			!= FishingRewardDefinition.TriggerType.FISHING_POINTS
		):
			continue

		if is_claimed(reward.reward_key):
			continue

		if (
			best_reward == null
			or reward.threshold < best_reward.threshold
		):
			best_reward = reward

	if best_reward == null:
		return {}

	return get_reward_status(
		best_reward.reward_key
	)


func can_claim(
	reward_key: StringName
) -> bool:
	if (
		reward_catalog == null
		or is_claimed(reward_key)
	):
		return false

	var reward: FishingRewardDefinition = (
		reward_catalog.get_reward_by_key(
			reward_key
		)
	)

	return (
		reward != null
		and _is_condition_met(reward)
		and _can_grant_reward(reward)
	)


func claim_reward(
	reward_key: StringName
) -> Dictionary:
	var result: Dictionary = {
		"claimed": false,
		"reason": "",
		"reward_key": reward_key,
		"reward_type": -1,
		"reward_item_id": &"",
		"quantity": 0,
	}

	if reward_catalog == null:
		result["reason"] = "catalog_unavailable"
		return result

	var reward: FishingRewardDefinition = (
		reward_catalog.get_reward_by_key(
			reward_key
		)
	)

	if (
		reward == null
		or not reward.is_valid_definition()
	):
		result["reason"] = "unknown_reward"
		return result

	if is_claimed(reward_key):
		result["reason"] = "already_claimed"
		return result

	var key: String = str(reward.reward_key)

	if bool(_claims_in_progress.get(key, false)):
		result["reason"] = "claim_in_progress"
		return result

	if not _is_condition_met(reward):
		result["reason"] = "condition_not_met"
		return result

	if not _can_grant_reward(reward):
		result["reason"] = "reward_unavailable"
		return result

	_claims_in_progress[key] = true
	var grant_result: Dictionary = _grant_reward(
		reward
	)
	_claims_in_progress.erase(key)

	if not bool(grant_result.get("granted", false)):
		result["reason"] = str(
			grant_result.get(
				"reason",
				"grant_failed"
			)
		)
		return result

	_claimed_reward_keys[key] = true

	if not save_to_disk():
		# Unique rod grants are duplicate-safe, so a future retry can safely
		# repair the claim without creating a second rod.
		result["reason"] = "claim_save_failed"
		return result

	_known_available_keys.erase(key)

	result["claimed"] = true
	result["reason"] = "ok"
	result["reward_type"] = reward.reward_type
	result["reward_item_id"] = reward.reward_item_id
	result["quantity"] = reward.quantity
	result["grant_result"] = grant_result

	reward_claimed.emit(
		reward,
		result.duplicate(true)
	)
	changed.emit()

	return result


func claim_all_available() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var available: Array[FishingRewardDefinition] = (
		get_available_unclaimed_rewards()
	)

	for reward in available:
		results.append(
			claim_reward(
				reward.reward_key
			)
		)

	return results


func is_claimed(
	reward_key: StringName
) -> bool:
	if reward_key == &"":
		return false

	return bool(
		_claimed_reward_keys.get(
			str(reward_key),
			false
		)
	)


func get_claimed_reward_keys() -> PackedStringArray:
	var result := PackedStringArray()

	for raw_key in _claimed_reward_keys.keys():
		if bool(_claimed_reward_keys[raw_key]):
			result.append(str(raw_key))

	result.sort()
	return result


func _get_condition_progress(
	reward: FishingRewardDefinition
) -> Dictionary:
	var current: int = 0
	var target: int = maxi(
		reward.threshold,
		0
	)
	var binary_condition: bool = false

	if reward == null or progress == null:
		return {
			"current": current,
			"target": target,
			"remaining": target,
			"ratio": 0.0,
			"met": false,
		}

	match reward.trigger_type:
		FishingRewardDefinition.TriggerType.FISHING_POINTS:
			current = progress.get_fishing_points()

		FishingRewardDefinition.TriggerType.RANK_INDEX:
			current = progress.get_rank_index()

		FishingRewardDefinition.TriggerType.TOTAL_CATCHES:
			current = progress.get_total_catches()

		FishingRewardDefinition.TriggerType.SPECIES_CATCH_COUNT:
			var record: Dictionary = (
				progress.get_species_record_by_key(
					reward.species_id
				)
			)
			current = int(
				record.get(
					"caught_count",
					0
				)
			)
			target = maxi(target, 1)

		FishingRewardDefinition.TriggerType.KING_CAUGHT:
			var record: Dictionary = (
				progress.get_species_record_by_key(
					reward.species_id
				)
			)
			current = (
				1
				if bool(
					record.get(
						"king_caught",
						false
					)
				)
				else 0
			)
			target = 1
			binary_condition = true

		FishingRewardDefinition.TriggerType.UNLOCK_FLAG:
			current = (
				1
				if (
					unlock_state != null
					and unlock_state.has_flag(
						reward.required_flag
					)
				)
				else 0
			)
			target = 1
			binary_condition = true

	var met: bool = current >= target
	var ratio: float = (
		1.0
		if binary_condition and met
		else (
			0.0
			if binary_condition
			else (
				clampf(
					float(current) / float(maxi(target, 1)),
					0.0,
					1.0
				)
			)
		)
	)

	return {
		"current": current,
		"target": target,
		"remaining": maxi(
			target - current,
			0
		),
		"ratio": ratio,
		"met": met,
	}


func _is_condition_met(
	reward: FishingRewardDefinition
) -> bool:
	return bool(
		_get_condition_progress(reward).get(
			"met",
			false
		)
	)


func _can_grant_reward(
	reward: FishingRewardDefinition
) -> bool:
	if reward == null:
		return false

	match reward.reward_type:
		FishingRewardDefinition.RewardType.LURE:
			return (
				inventory != null
				and tackle_catalog != null
				and tackle_catalog.has_lure(
					reward.reward_item_id
				)
			)

		FishingRewardDefinition.RewardType.ROD:
			return (
				inventory != null
				and tackle_catalog != null
				and tackle_catalog.has_rod(
					reward.reward_item_id
				)
			)

		FishingRewardDefinition.RewardType.UNLOCK_FLAG:
			return (
				unlock_state != null
				and reward.reward_item_id != &""
			)

		_:
			return false


func _grant_reward(
	reward: FishingRewardDefinition
) -> Dictionary:
	var result: Dictionary = {
		"granted": false,
		"reason": "",
		"already_owned": false,
	}

	match reward.reward_type:
		FishingRewardDefinition.RewardType.LURE:
			var count_after: int = inventory.grant_lure(
				reward.reward_item_id,
				reward.quantity,
				true
			)
			result["granted"] = count_after > 0
			result["count_after"] = count_after

		FishingRewardDefinition.RewardType.ROD:
			# Rods are unique equipment. If QA, migration or an old save already
			# owns the rod, complete the milestone without creating duplicates.
			if inventory.owns_rod(
				reward.reward_item_id
			):
				result["granted"] = true
				result["already_owned"] = true
				result["count_after"] = (
					inventory.get_rod_count(
						reward.reward_item_id
					)
				)
			else:
				var count_after: int = (
					inventory.grant_rod(
						reward.reward_item_id,
						1,
						true
					)
				)
				result["granted"] = count_after > 0
				result["count_after"] = count_after

		FishingRewardDefinition.RewardType.UNLOCK_FLAG:
			unlock_state.grant_flag(
				reward.reward_item_id,
				true
			)
			result["granted"] = (
				unlock_state.has_flag(
					reward.reward_item_id
				)
			)

		_:
			result["reason"] = "unsupported_reward_type"

	if (
		not bool(result.get("granted", false))
		and str(result.get("reason", "")).is_empty()
	):
		result["reason"] = "grant_failed"

	return result


func _reconcile_claimed_unique_rewards() -> void:
	if (
		reward_catalog == null
		or inventory == null
	):
		return

	var inventory_changed: bool = false

	for raw_key in _claimed_reward_keys.keys():
		if not bool(_claimed_reward_keys[raw_key]):
			continue

		var reward: FishingRewardDefinition = (
			reward_catalog.get_reward_by_key(
				StringName(str(raw_key))
			)
		)

		if (
			reward == null
			or not reward.is_unique_equipment_reward()
		):
			continue

		if not tackle_catalog.has_rod(
			reward.reward_item_id
		):
			continue

		if inventory.owns_rod(
			reward.reward_item_id
		):
			continue

		var count_after: int = inventory.grant_rod(
			reward.reward_item_id,
			1,
			false
		)

		if count_after > 0:
			inventory_changed = true

	if inventory_changed:
		inventory.commit_changes()


func _connect_sources() -> void:
	if is_instance_valid(progress):
		var progress_callback := Callable(
			self,
			"_on_source_changed"
		)

		if not progress.changed.is_connected(
			progress_callback
		):
			progress.changed.connect(
				progress_callback
			)

	if is_instance_valid(unlock_state):
		var unlock_callback := Callable(
			self,
			"_on_source_changed"
		)

		if not unlock_state.changed.is_connected(
			unlock_callback
		):
			unlock_state.changed.connect(
				unlock_callback
			)


func _disconnect_sources() -> void:
	var callback := Callable(
		self,
		"_on_source_changed"
	)

	if (
		is_instance_valid(progress)
		and progress.changed.is_connected(callback)
	):
		progress.changed.disconnect(callback)

	if (
		is_instance_valid(unlock_state)
		and unlock_state.changed.is_connected(callback)
	):
		unlock_state.changed.disconnect(callback)


func _on_source_changed() -> void:
	evaluate_rewards()


func _get_state_label(
	state: RewardState
) -> String:
	match state:
		RewardState.LOCKED:
			return "LOCKED"
		RewardState.AVAILABLE:
			return "AVAILABLE"
		RewardState.CLAIMED:
			return "CLAIMED"
		_:
			return "UNKNOWN"


func save_to_disk() -> bool:
	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"claimed_reward_keys": _claimed_reward_keys,
	}

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.WRITE
	)

	if file == null:
		push_warning(
			"FishingRewardService: could not open save file for writing."
		)
		return false

	file.store_string(
		JSON.stringify(
			payload,
			"\t"
		)
	)
	file.close()
	return true


func load_from_disk() -> bool:
	_claimed_reward_keys.clear()
	_known_available_keys.clear()

	if not FileAccess.file_exists(SAVE_PATH):
		return true

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.READ
	)

	if file == null:
		push_warning(
			"FishingRewardService: could not open save file for reading."
		)
		return false

	var parsed: Variant = JSON.parse_string(
		file.get_as_text()
	)
	file.close()

	if not (parsed is Dictionary):
		push_warning(
			"FishingRewardService: invalid save; starting with no claimed rewards."
		)
		return false

	var data: Dictionary = parsed

	if int(data.get("version", 0)) > SAVE_VERSION:
		push_warning(
			"FishingRewardService: save version is newer than this build."
		)
		return false

	var loaded: Variant = data.get(
		"claimed_reward_keys",
		{}
	)

	if loaded is Dictionary:
		for raw_key in (
			loaded as Dictionary
		).keys():
			if bool(
				(loaded as Dictionary)[raw_key]
			):
				_claimed_reward_keys[
					str(raw_key)
				] = true

	return true


func reset_rewards(
	delete_save: bool = true
) -> void:
	_claimed_reward_keys.clear()
	_known_available_keys.clear()
	_claims_in_progress.clear()

	if (
		delete_save
		and FileAccess.file_exists(SAVE_PATH)
	):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(
				SAVE_PATH
			)
		)
	elif not delete_save:
		save_to_disk()

	evaluate_rewards()
	changed.emit()
