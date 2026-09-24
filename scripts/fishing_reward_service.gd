extends Node
class_name FishingRewardService

signal reward_available(reward: FishingRewardDefinition)
signal reward_claimed(reward: FishingRewardDefinition, result: Dictionary)

const SAVE_VERSION: int = 1
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
	call_deferred("evaluate_rewards")


func evaluate_rewards() -> Array[FishingRewardDefinition]:
	var available := get_available_unclaimed_rewards()

	for reward in available:
		var key := str(reward.reward_key)
		if not _known_available_keys.has(key):
			_known_available_keys[key] = true
			reward_available.emit(reward)

		if reward.auto_claim:
			claim_reward(reward.reward_key)

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


func can_claim(reward_key: StringName) -> bool:
	if reward_catalog == null or is_claimed(reward_key):
		return false
	var reward := reward_catalog.get_reward_by_key(reward_key)
	return reward != null and _is_condition_met(reward) and _can_grant_reward(reward)


func claim_reward(reward_key: StringName) -> Dictionary:
	var result := {
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

	var reward := reward_catalog.get_reward_by_key(reward_key)
	if reward == null or not reward.is_valid_definition():
		result["reason"] = "unknown_reward"
		return result

	if is_claimed(reward_key):
		result["reason"] = "already_claimed"
		return result

	if bool(_claims_in_progress.get(str(reward_key), false)):
		result["reason"] = "claim_in_progress"
		return result

	if not _is_condition_met(reward):
		result["reason"] = "condition_not_met"
		return result

	if not _can_grant_reward(reward):
		result["reason"] = "reward_unavailable"
		return result

	_claims_in_progress[str(reward.reward_key)] = true
	var grant_result := _grant_reward(reward)
	_claims_in_progress.erase(str(reward.reward_key))

	if not bool(grant_result.get("granted", false)):
		result["reason"] = str(grant_result.get("reason", "grant_failed"))
		return result

	_claimed_reward_keys[str(reward.reward_key)] = true
	save_to_disk()

	result["claimed"] = true
	result["reason"] = "ok"
	result["reward_type"] = reward.reward_type
	result["reward_item_id"] = reward.reward_item_id
	result["quantity"] = reward.quantity
	result["grant_result"] = grant_result
	reward_claimed.emit(reward, result.duplicate(true))
	return result


func is_claimed(reward_key: StringName) -> bool:
	if reward_key == &"":
		return false
	return bool(_claimed_reward_keys.get(str(reward_key), false))


func get_claimed_reward_keys() -> PackedStringArray:
	var result := PackedStringArray()
	for raw_key in _claimed_reward_keys.keys():
		if bool(_claimed_reward_keys[raw_key]):
			result.append(str(raw_key))
	result.sort()
	return result


func _is_condition_met(reward: FishingRewardDefinition) -> bool:
	if reward == null or progress == null:
		return false

	match reward.trigger_type:
		FishingRewardDefinition.TriggerType.FISHING_POINTS:
			return progress.get_fishing_points() >= reward.threshold
		FishingRewardDefinition.TriggerType.RANK_INDEX:
			return progress.get_rank_index() >= reward.threshold
		FishingRewardDefinition.TriggerType.TOTAL_CATCHES:
			return progress.get_total_catches() >= reward.threshold
		FishingRewardDefinition.TriggerType.SPECIES_CATCH_COUNT:
			var record := progress.get_species_record_by_key(reward.species_id)
			return int(record.get("caught_count", 0)) >= maxi(reward.threshold, 1)
		FishingRewardDefinition.TriggerType.KING_CAUGHT:
			var record := progress.get_species_record_by_key(reward.species_id)
			return bool(record.get("king_caught", false))
		FishingRewardDefinition.TriggerType.UNLOCK_FLAG:
			return unlock_state != null and unlock_state.has_flag(reward.required_flag)
		_:
			return false


func _can_grant_reward(reward: FishingRewardDefinition) -> bool:
	if inventory == null:
		return false

	match reward.reward_type:
		FishingRewardDefinition.RewardType.LURE:
			return tackle_catalog != null and tackle_catalog.has_lure(reward.reward_item_id)
		FishingRewardDefinition.RewardType.ROD:
			return tackle_catalog != null and tackle_catalog.has_rod(reward.reward_item_id)
		FishingRewardDefinition.RewardType.UNLOCK_FLAG:
			return unlock_state != null and reward.reward_item_id != &""
		_:
			return false


func _grant_reward(reward: FishingRewardDefinition) -> Dictionary:
	var result := {"granted": false, "reason": ""}

	match reward.reward_type:
		FishingRewardDefinition.RewardType.LURE:
			var count_after := inventory.grant_lure(reward.reward_item_id, reward.quantity, true)
			result["granted"] = count_after > 0
			result["count_after"] = count_after
		FishingRewardDefinition.RewardType.ROD:
			var count_after := inventory.grant_rod(reward.reward_item_id, reward.quantity, true)
			result["granted"] = count_after > 0
			result["count_after"] = count_after
		FishingRewardDefinition.RewardType.UNLOCK_FLAG:
			# A duplicate flag is still a valid completed reward; the reward key itself
			# prevents the reward from being processed again.
			unlock_state.grant_flag(reward.reward_item_id, true)
			result["granted"] = unlock_state.has_flag(reward.reward_item_id)
		_:
			result["reason"] = "unsupported_reward_type"

	if not bool(result.get("granted", false)) and str(result.get("reason", "")).is_empty():
		result["reason"] = "grant_failed"
	return result


func _connect_sources() -> void:
	if is_instance_valid(progress):
		var progress_callback := Callable(self, "_on_source_changed")
		if not progress.changed.is_connected(progress_callback):
			progress.changed.connect(progress_callback)

	if is_instance_valid(unlock_state):
		var unlock_callback := Callable(self, "_on_source_changed")
		if not unlock_state.changed.is_connected(unlock_callback):
			unlock_state.changed.connect(unlock_callback)


func _disconnect_sources() -> void:
	var callback := Callable(self, "_on_source_changed")
	if is_instance_valid(progress) and progress.changed.is_connected(callback):
		progress.changed.disconnect(callback)
	if is_instance_valid(unlock_state) and unlock_state.changed.is_connected(callback):
		unlock_state.changed.disconnect(callback)


func _on_source_changed() -> void:
	evaluate_rewards()


func save_to_disk() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"claimed_reward_keys": _claimed_reward_keys,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("FishingRewardService: could not open save file for writing.")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func load_from_disk() -> bool:
	_claimed_reward_keys.clear()
	_known_available_keys.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return true

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("FishingRewardService: could not open save file for reading.")
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		push_warning("FishingRewardService: invalid save; starting with no claimed rewards.")
		return false

	var data: Dictionary = parsed
	if int(data.get("version", 0)) > SAVE_VERSION:
		push_warning("FishingRewardService: save version is newer than this build.")
		return false
	var loaded = data.get("claimed_reward_keys", {})
	if loaded is Dictionary:
		for raw_key in (loaded as Dictionary).keys():
			if bool((loaded as Dictionary)[raw_key]):
				_claimed_reward_keys[str(raw_key)] = true
	return true


func reset_rewards(delete_save: bool = true) -> void:
	_claimed_reward_keys.clear()
	_known_available_keys.clear()
	_claims_in_progress.clear()
	if delete_save and FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	elif not delete_save:
		save_to_disk()
	evaluate_rewards()
