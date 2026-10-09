extends RefCounted

class_name TripleTriadMatchResolutionJournal
const Storage = preload("res://scripts/triple_triad/triple_triad_config_store.gd")

const DEFAULT_PATH := "user://triple_triad_match_resolution.cfg"
const SAVE_VERSION := 1

var _save_path: String = DEFAULT_PATH


func initialize(save_path: String = DEFAULT_PATH) -> void:
	_save_path = save_path


func has_pending() -> bool:
	return bool(get_snapshot().get("pending", false))


func get_snapshot() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(_save_path) != OK:
		return {}
	if not config.has_section("resolution"):
		return {}
	if not bool(config.get_value("resolution", "pending", false)):
		return {}

	var competition_change: Dictionary = {}
	var raw_competition = config.get_value("resolution", "competition_change", {})
	if raw_competition is Dictionary:
		competition_change = (raw_competition as Dictionary).duplicate(true)

	var transfer_state: Dictionary = {}
	var raw_transfer = config.get_value("resolution", "transfer_state", {})
	if raw_transfer is Dictionary:
		transfer_state = (raw_transfer as Dictionary).duplicate(true)

	return {
		"pending": true,
		"version": int(config.get_value("resolution", "version", SAVE_VERSION)),
		"created_unix": maxi(
			0,
			int(config.get_value("resolution", "created_unix", 0))
		),
		"opponent_id": str(config.get_value("resolution", "opponent_id", "")),
		"winner": int(config.get_value("resolution", "winner", 0)),
		"result_reason": str(
			config.get_value("resolution", "result_reason", "")
		),
		"surrendered": bool(
			config.get_value("resolution", "surrendered", false)
		),
		"player_card_ids": _string_array(
			config.get_value(
				"resolution",
				"player_card_ids",
				PackedStringArray()
			)
		),
		"opponent_card_ids": _string_array(
			config.get_value(
				"resolution",
				"opponent_card_ids",
				PackedStringArray()
			)
		),
		"eligible_reward_ids": _string_array(
			config.get_value(
				"resolution",
				"eligible_reward_ids",
				PackedStringArray()
			)
		),
		"forced_loss_card_id": str(
			config.get_value(
				"resolution",
				"forced_loss_card_id",
				""
			)
		),
		"competition_change": competition_change,
		"selected_card_id": str(
			config.get_value(
				"resolution",
				"selected_card_id",
				""
			)
		),
		"transfer_committed": bool(
			config.get_value(
				"resolution",
				"transfer_committed",
				false
			)
		),
		"metadata_committed": bool(
			config.get_value(
				"resolution",
				"metadata_committed",
				false
			)
		),
		"transfer_state": transfer_state,
	}


func begin_resolution(snapshot: Dictionary) -> bool:
	var opponent_id: String = str(snapshot.get("opponent_id", "")).strip_edges()
	var winner: int = int(snapshot.get("winner", 0))
	if opponent_id.is_empty() or winner not in [1, 2]:
		return false

	var player_ids := _string_array(
		snapshot.get("player_card_ids", PackedStringArray())
	)
	var opponent_ids := _string_array(
		snapshot.get("opponent_card_ids", PackedStringArray())
	)
	if player_ids.size() != 5 or opponent_ids.size() != 5:
		return false

	var config := ConfigFile.new()
	config.set_value("resolution", "version", SAVE_VERSION)
	config.set_value("resolution", "pending", true)
	config.set_value(
		"resolution",
		"created_unix",
		int(Time.get_unix_time_from_system())
	)
	config.set_value("resolution", "opponent_id", opponent_id)
	config.set_value("resolution", "winner", winner)
	config.set_value(
		"resolution",
		"result_reason",
		str(snapshot.get("result_reason", ""))
	)
	config.set_value(
		"resolution",
		"surrendered",
		bool(snapshot.get("surrendered", false))
	)
	config.set_value("resolution", "player_card_ids", player_ids)
	config.set_value("resolution", "opponent_card_ids", opponent_ids)
	config.set_value(
		"resolution",
		"eligible_reward_ids",
		_string_array(
			snapshot.get("eligible_reward_ids", PackedStringArray())
		)
	)
	config.set_value(
		"resolution",
		"forced_loss_card_id",
		str(snapshot.get("forced_loss_card_id", ""))
	)
	var competition_change: Dictionary = {}
	var raw_competition = snapshot.get("competition_change", {})
	if raw_competition is Dictionary:
		competition_change = (
			raw_competition as Dictionary
		).duplicate(true)
	config.set_value("resolution", "competition_change", competition_change)
	config.set_value("resolution", "selected_card_id", "")
	config.set_value("resolution", "transfer_committed", false)
	config.set_value("resolution", "metadata_committed", false)
	config.set_value("resolution", "transfer_state", {})
	return Storage.commit(config, _save_path) == OK


func record_selection(
	card_id: StringName,
	transfer_state: Dictionary
) -> bool:
	var config := ConfigFile.new()
	if config.load(_save_path) != OK:
		return false
	if not bool(config.get_value("resolution", "pending", false)):
		return false
	var clean_id: String = String(card_id).strip_edges()
	if clean_id.is_empty():
		return false

	var previous_id: String = str(config.get_value("resolution", "selected_card_id", ""))
	if not previous_id.is_empty():
		return previous_id == clean_id and config.get_value("resolution", "transfer_state", {}) == transfer_state

	config.set_value("resolution", "selected_card_id", clean_id)
	config.set_value(
		"resolution",
		"transfer_state",
		transfer_state.duplicate(true)
	)
	config.set_value("resolution", "transfer_committed", false)
	config.set_value("resolution", "metadata_committed", false)
	return Storage.commit(config, _save_path) == OK


func mark_transfer_committed() -> bool:
	return _set_flag("transfer_committed", true)


func mark_metadata_committed() -> bool:
	return _set_flag("metadata_committed", true)


func clear() -> bool:
	var config := ConfigFile.new()
	return Storage.commit(config, _save_path) == OK


func _set_flag(key: String, value: bool) -> bool:
	var config := ConfigFile.new()
	if config.load(_save_path) != OK:
		return false
	if not bool(config.get_value("resolution", "pending", false)):
		return false
	config.set_value("resolution", key, value)
	return Storage.commit(config, _save_path) == OK


func _string_array(value) -> PackedStringArray:
	var result := PackedStringArray()
	if value is PackedStringArray or value is Array:
		for raw_value in value:
			var clean: String = str(raw_value).strip_edges()
			if not clean.is_empty() and not result.has(clean):
				result.append(clean)
	return result
