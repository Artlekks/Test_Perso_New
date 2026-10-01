extends RefCounted

signal changed(snapshot: Dictionary)

const SAVE_PATH := "user://triple_triad_competitions.cfg"
const SAVE_VERSION := 3

var _catalog = null
var _persistence_enabled: bool = true
var _active_competition_id: StringName = &""
var _active_round_index: int = 0
var _locked_deck_ids := PackedStringArray()
var _pending_reward: Dictionary = {}
var _attempts: Dictionary = {}
var _clears: Dictionary = {}
var _failures: Dictionary = {}
var _abandons: Dictionary = {}


func initialize(
	catalog,
	persistence_enabled: bool = true
) -> void:
	_catalog = catalog
	_persistence_enabled = persistence_enabled
	_active_competition_id = &""
	_active_round_index = 0
	_locked_deck_ids = PackedStringArray()
	_pending_reward.clear()
	_attempts.clear()
	_clears.clear()
	_failures.clear()
	_abandons.clear()

	if _persistence_enabled:
		_load()
		_save()


func get_snapshot(
	player_rank: int,
	beaten_opponent_ids
) -> Dictionary:
	var circuits: Array = []
	if _catalog != null:
		for circuit in _catalog.call("get_all_circuits"):
			circuits.append(
				get_circuit_snapshot(
					StringName(
						str(circuit.get("circuit_id", ""))
					),
					player_rank,
					beaten_opponent_ids
				)
			)

	var competitions: Array = []
	if _catalog != null:
		for competition in _catalog.call(
			"get_all_competitions"
		):
			competitions.append(
				get_competition_snapshot(
					StringName(
						str(
							competition.get(
								"competition_id",
								""
							)
						)
					),
					player_rank,
					beaten_opponent_ids
				)
			)

	return {
		"circuits": circuits,
		"competitions": competitions,
		"active": get_active_snapshot(),
		"pending_reward": get_pending_reward(),
		"earned_titles": get_earned_titles(),
		"regional_champion": get_clear_count(
			&"regional_championship"
		) > 0,
		"card_master": get_clear_count(
			&"masters_cup"
		) > 0,
		"card_game_completed": get_clear_count(
			&"masters_cup"
		) > 0,
	}


func get_circuit_snapshot(
	circuit_id: StringName,
	player_rank: int,
	beaten_opponent_ids
) -> Dictionary:
	if _catalog == null:
		return {}
	var circuit: Dictionary = _catalog.call(
		"get_circuit",
		circuit_id
	)
	if circuit.is_empty():
		return {}

	var beaten: Dictionary = _id_set(
		beaten_opponent_ids
	)
	var required: Array = circuit.get(
		"opponent_ids",
		[]
	)
	var completed_ids := PackedStringArray()
	var remaining_ids := PackedStringArray()
	for raw_id in required:
		var opponent_id: String = str(raw_id)
		if beaten.has(opponent_id):
			completed_ids.append(opponent_id)
		else:
			remaining_ids.append(opponent_id)

	var required_rank: int = maxi(
		1,
		int(circuit.get("required_duel_rank", 1))
	)
	var complete: bool = (
		remaining_ids.is_empty()
		and not required.is_empty()
	)

	return {
		"circuit_id": String(circuit_id),
		"display_name": str(
			circuit.get("display_name", String(circuit_id))
		),
		"description": str(
			circuit.get("description", "")
		),
		"required_duel_rank": required_rank,
		"rank_requirement_met": player_rank >= required_rank,
		"complete": complete,
		"wins_completed": completed_ids.size(),
		"wins_required": required.size(),
		"completed_opponent_ids": completed_ids,
		"remaining_opponent_ids": remaining_ids,
	}


func get_competition_snapshot(
	competition_id: StringName,
	player_rank: int,
	beaten_opponent_ids
) -> Dictionary:
	if _catalog == null:
		return {}
	var competition: Dictionary = _catalog.call(
		"get_competition",
		competition_id
	)
	if competition.is_empty():
		return {}

	var availability: Dictionary = _competition_availability(
		competition,
		player_rank,
		beaten_opponent_ids
	)
	var rounds: Array = competition.get(
		"opponent_ids",
		[]
	)
	var active_here: bool = (
		_active_competition_id == competition_id
	)

	return {
		"competition_id": String(competition_id),
		"display_name": str(
			competition.get(
				"display_name",
				String(competition_id)
			)
		),
		"description": str(
			competition.get("description", "")
		),
		"required_duel_rank": maxi(
			1,
			int(
				competition.get(
					"required_duel_rank",
					1
				)
			)
		),
		"available": bool(
			availability.get("available", false)
		),
		"reason": str(
			availability.get("reason", "")
		),
		"round_count": rounds.size(),
		"round_opponent_ids": PackedStringArray(rounds),
		"reward_source_id": str(
			competition.get("reward_source_id", "")
		),
		"repeatable": bool(
			competition.get("repeatable", false)
		),
		"is_endgame": bool(
			competition.get("is_endgame", false)
		),
		"title_on_first_clear": str(
			competition.get(
				"title_on_first_clear",
				""
			)
		),
		"attempts": get_attempt_count(competition_id),
		"clears": get_clear_count(competition_id),
		"failures": get_failure_count(competition_id),
		"abandons": get_abandon_count(competition_id),
		"active": active_here,
		"active_round_index": (
			_active_round_index
			if active_here
			else -1
		),
		"next_opponent_id": (
			String(get_active_opponent_id())
			if active_here
			else ""
		),
	}


func start_competition(
	competition_id: StringName,
	player_rank: int,
	beaten_opponent_ids
) -> Dictionary:
	if _catalog == null:
		return {
			"success": false,
			"reason": "competition_catalog_unavailable",
		}

	if not _pending_reward.is_empty():
		return {
			"success": false,
			"reason": "pending_competition_reward",
			"pending_reward": _pending_reward.duplicate(true),
		}

	if _active_competition_id != &"":
		if _active_competition_id == competition_id:
			return {
				"success": true,
				"already_active": true,
				"competition_id": String(
					competition_id
				),
				"round_index": _active_round_index,
				"next_opponent_id": String(
					get_active_opponent_id()
				),
			}
		return {
			"success": false,
			"reason": "another_competition_active",
			"active_competition_id": String(
				_active_competition_id
			),
		}

	var competition: Dictionary = _catalog.call(
		"get_competition",
		competition_id
	)
	if competition.is_empty():
		return {
			"success": false,
			"reason": "unknown_competition",
		}

	var availability: Dictionary = _competition_availability(
		competition,
		player_rank,
		beaten_opponent_ids
	)
	if not bool(availability.get("available", false)):
		return {
			"success": false,
			"reason": str(
				availability.get(
					"reason",
					"competition_locked"
				)
			),
		}

	_active_competition_id = competition_id
	_active_round_index = 0
	_locked_deck_ids = PackedStringArray()
	_attempts[String(competition_id)] = (
		get_attempt_count(competition_id) + 1
	)
	_save()
	_emit_changed(player_rank, beaten_opponent_ids)

	return {
		"success": true,
		"competition_id": String(competition_id),
		"round_index": 0,
		"next_opponent_id": String(
			get_active_opponent_id()
		),
	}


func record_match_result(
	opponent_id: StringName,
	winner: int,
	player_owner: int
) -> Dictionary:
	if _active_competition_id == &"":
		return {
			"handled": false,
			"reason": "no_active_competition",
		}

	var expected_opponent: StringName = (
		get_active_opponent_id()
	)
	if opponent_id != expected_opponent:
		return {
			"handled": false,
			"reason": "unexpected_opponent",
			"expected_opponent_id": String(
				expected_opponent
			),
		}

	var competition_id: StringName = (
		_active_competition_id
	)
	var competition: Dictionary = _catalog.call(
		"get_competition",
		competition_id
	)
	if competition.is_empty():
		_clear_active()
		_save()
		return {
			"handled": false,
			"reason": "active_competition_missing",
		}

	if winner == 0:
		return {
			"handled": true,
			"draw_replay": true,
			"competition_id": String(
				competition_id
			),
			"round_index": _active_round_index,
			"opponent_id": String(opponent_id),
		}

	if winner != player_owner:
		_failures[String(competition_id)] = (
			get_failure_count(competition_id) + 1
		)
		var failed_round: int = _active_round_index
		_clear_active()
		_save()
		return {
			"handled": true,
			"failed": true,
			"competition_id": String(
				competition_id
			),
			"round_index": failed_round,
			"opponent_id": String(opponent_id),
		}

	_active_round_index += 1
	var rounds: Array = competition.get(
		"opponent_ids",
		[]
	)
	if _active_round_index < rounds.size():
		_save()
		return {
			"handled": true,
			"round_won": true,
			"competition_id": String(
				competition_id
			),
			"round_index": _active_round_index - 1,
			"next_round_index": _active_round_index,
			"next_opponent_id": String(
				get_active_opponent_id()
			),
		}

	var clear_number: int = (
		get_clear_count(competition_id) + 1
	)
	_clears[String(competition_id)] = clear_number
	var reward_source_id: String = str(
		competition.get("reward_source_id", "")
	)
	var title_awarded: String = ""
	if clear_number == 1:
		title_awarded = str(
			competition.get(
				"title_on_first_clear",
				""
			)
		)
	var endgame_clear: bool = bool(
		competition.get("is_endgame", false)
	)
	var reward_event_id: String = (
		"competition_%s_clear_%03d"
		% [String(competition_id), clear_number]
	)

	_pending_reward = {
		"competition_id": String(competition_id),
		"clear_number": clear_number,
		"reward_source_id": reward_source_id,
		"reward_event_id": reward_event_id,
		"title_awarded": title_awarded,
		"card_game_completed": endgame_clear,
	}
	_clear_active()
	_save()

	return {
		"handled": true,
		"completed": true,
		"competition_id": String(competition_id),
		"clear_number": clear_number,
		"reward_source_id": reward_source_id,
		"reward_event_id": reward_event_id,
		"title_awarded": title_awarded,
		"card_game_completed": endgame_clear,
	}


func get_pending_reward() -> Dictionary:
	return _pending_reward.duplicate(true)


func has_pending_reward() -> bool:
	return not _pending_reward.is_empty()


func acknowledge_pending_reward(
	reward_event_id: StringName
) -> bool:
	if _pending_reward.is_empty():
		return true
	var pending_id: String = str(
		_pending_reward.get("reward_event_id", "")
	)
	if (
		not pending_id.is_empty()
		and pending_id != String(reward_event_id)
	):
		return false
	_pending_reward.clear()
	return _save() == OK


func abandon_active_competition() -> Dictionary:
	if _active_competition_id == &"":
		return {
			"success": false,
			"reason": "no_active_competition",
		}

	var competition_id: StringName = (
		_active_competition_id
	)
	_abandons[String(competition_id)] = (
		get_abandon_count(competition_id) + 1
	)
	_clear_active()
	_save()

	return {
		"success": true,
		"competition_id": String(competition_id),
	}


func get_active_snapshot() -> Dictionary:
	if _active_competition_id == &"":
		return {
			"active": false,
			"competition_id": "",
			"round_index": -1,
			"next_opponent_id": "",
		}
	var competition: Dictionary = _catalog.call(
		"get_competition",
		_active_competition_id
	)
	return {
		"active": true,
		"competition_id": String(
			_active_competition_id
		),
		"display_name": str(
			competition.get("display_name", "")
		),
		"round_index": _active_round_index,
		"round_count": (
			competition.get("opponent_ids", [])
			as Array
		).size(),
		"next_opponent_id": String(
			get_active_opponent_id()
		),
		"deck_locked": _locked_deck_ids.size() == 5,
		"locked_deck_ids": _locked_deck_ids.duplicate(),
	}


func set_locked_deck_ids(card_ids) -> bool:
	if _active_competition_id == &"":
		return false
	if not (card_ids is PackedStringArray or card_ids is Array):
		return false

	var clean := PackedStringArray()
	for raw_id in card_ids:
		var card_id: String = str(raw_id).strip_edges()
		if card_id.is_empty() or clean.has(card_id):
			return false
		clean.append(card_id)

	if clean.size() != 5:
		return false

	_locked_deck_ids = clean
	_save()
	return true


func get_locked_deck_ids() -> PackedStringArray:
	return _locked_deck_ids.duplicate()


func has_locked_deck() -> bool:
	return (
		_active_competition_id != &""
		and _locked_deck_ids.size() == 5
	)


func get_active_competition_id() -> StringName:
	return _active_competition_id


func get_active_opponent_id() -> StringName:
	if _active_competition_id == &"" or _catalog == null:
		return &""
	var competition: Dictionary = _catalog.call(
		"get_competition",
		_active_competition_id
	)
	var rounds: Array = competition.get(
		"opponent_ids",
		[]
	)
	if (
		_active_round_index < 0
		or _active_round_index >= rounds.size()
	):
		return &""
	return StringName(str(rounds[_active_round_index]))


func get_attempt_count(
	competition_id: StringName
) -> int:
	return maxi(
		0,
		int(
			_attempts.get(
				String(competition_id),
				0
			)
		)
	)


func get_clear_count(
	competition_id: StringName
) -> int:
	return maxi(
		0,
		int(
			_clears.get(
				String(competition_id),
				0
			)
		)
	)


func get_failure_count(
	competition_id: StringName
) -> int:
	return maxi(
		0,
		int(
			_failures.get(
				String(competition_id),
				0
			)
		)
	)


func get_abandon_count(
	competition_id: StringName
) -> int:
	return maxi(
		0,
		int(
			_abandons.get(
				String(competition_id),
				0
			)
		)
	)


func get_earned_titles() -> PackedStringArray:
	var result := PackedStringArray()
	if _catalog == null:
		return result
	for competition in _catalog.call(
		"get_all_competitions"
	):
		var competition_id := StringName(
			str(
				competition.get(
					"competition_id",
					""
				)
			)
		)
		if get_clear_count(competition_id) <= 0:
			continue
		var title: String = str(
			competition.get(
				"title_on_first_clear",
				""
			)
		)
		if not title.is_empty():
			result.append(title)
	return result


func _competition_availability(
	competition: Dictionary,
	player_rank: int,
	beaten_opponent_ids
) -> Dictionary:
	var competition_id := StringName(
		str(competition.get("competition_id", ""))
	)
	if not _pending_reward.is_empty():
		return {
			"available": false,
			"reason": "Collect the previous tournament reward first.",
		}
	var required_rank: int = maxi(
		1,
		int(
			competition.get(
				"required_duel_rank",
				1
			)
		)
	)
	if player_rank < required_rank:
		return {
			"available": false,
			"reason": "Requires Duel Rank %d."
				% required_rank,
		}

	for raw_circuit_id in competition.get(
		"required_circuit_ids",
		[]
	):
		var circuit_snapshot: Dictionary = (
			get_circuit_snapshot(
				StringName(str(raw_circuit_id)),
				player_rank,
				beaten_opponent_ids
			)
		)
		if not bool(
			circuit_snapshot.get("complete", false)
		):
			return {
				"available": false,
				"reason": "Complete %s first."
					% str(
						circuit_snapshot.get(
							"display_name",
							raw_circuit_id
						)
					),
			}

	var required_clears = competition.get(
		"required_competition_clears",
		{}
	)
	if required_clears is Dictionary:
		for raw_required_id in required_clears.keys():
			var required_id := StringName(
				str(raw_required_id)
			)
			var required_count: int = maxi(
				1,
				int(required_clears[raw_required_id])
			)
			if get_clear_count(
				required_id
			) < required_count:
				var prerequisite: Dictionary = (
					_catalog.call(
						"get_competition",
						required_id
					)
				)
				return {
					"available": false,
					"reason": "Clear %s first."
						% str(
							prerequisite.get(
								"display_name",
								String(required_id)
							)
						),
				}

	if (
		_active_competition_id != &""
		and _active_competition_id
		!= competition_id
	):
		return {
			"available": false,
			"reason": "Another competition is active.",
		}

	return {
		"available": true,
		"reason": "",
	}


func _emit_changed(
	player_rank: int,
	beaten_opponent_ids
) -> void:
	changed.emit(
		get_snapshot(
			player_rank,
			beaten_opponent_ids
		)
	)


func _id_set(values) -> Dictionary:
	var result: Dictionary = {}
	if values is PackedStringArray or values is Array:
		for raw_value in values:
			result[str(raw_value)] = true
	return result


func _clear_active() -> void:
	_active_competition_id = &""
	_active_round_index = 0
	_locked_deck_ids = PackedStringArray()


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return

	if int(
		config.get_value(
			"meta",
			"version",
			0
		)
	) <= 0:
		return

	if _catalog != null:
		for raw_id in _catalog.call(
			"get_competition_ids"
		):
			var key: String = str(raw_id)
			_attempts[key] = maxi(
				0,
				int(
					config.get_value(
						"attempts",
						key,
						0
					)
				)
			)
			_clears[key] = maxi(
				0,
				int(
					config.get_value(
						"clears",
						key,
						0
					)
				)
			)
			_failures[key] = maxi(
				0,
				int(
					config.get_value(
						"failures",
						key,
						0
					)
				)
			)
			_abandons[key] = maxi(
				0,
				int(
					config.get_value(
						"abandons",
						key,
						0
					)
				)
			)

	var pending_event_id: String = str(
		config.get_value("pending_reward", "reward_event_id", "")
	).strip_edges()
	if not pending_event_id.is_empty():
		_pending_reward = {
			"competition_id": str(
				config.get_value(
					"pending_reward",
					"competition_id",
					""
				)
			),
			"clear_number": maxi(
				0,
				int(
					config.get_value(
						"pending_reward",
						"clear_number",
						0
					)
				)
			),
			"reward_source_id": str(
				config.get_value(
					"pending_reward",
					"reward_source_id",
					""
				)
			),
			"reward_event_id": pending_event_id,
			"title_awarded": str(
				config.get_value(
					"pending_reward",
					"title_awarded",
					""
				)
			),
			"card_game_completed": bool(
				config.get_value(
					"pending_reward",
					"card_game_completed",
					false
				)
			),
		}

	var raw_active: String = str(
		config.get_value(
			"active",
			"competition_id",
			""
		)
	)
	var active_definition: Dictionary = {}
	if not raw_active.is_empty() and _catalog != null:
		active_definition = _catalog.call(
			"get_competition",
			StringName(raw_active)
		)
	if not raw_active.is_empty() and not active_definition.is_empty():
		_active_competition_id = StringName(raw_active)
		_active_round_index = maxi(
			0,
			int(
				config.get_value(
					"active",
					"round_index",
					0
				)
			)
		)
		if get_active_opponent_id() == &"":
			_clear_active()
		else:
			var raw_locked = config.get_value(
				"active",
				"locked_deck_ids",
				PackedStringArray()
			)
			var clean_locked := PackedStringArray()
			if raw_locked is PackedStringArray or raw_locked is Array:
				for raw_card_id in raw_locked:
					var card_id: String = str(raw_card_id).strip_edges()
					if (
						not card_id.is_empty()
						and not clean_locked.has(card_id)
					):
						clean_locked.append(card_id)
			if clean_locked.size() == 5:
				_locked_deck_ids = clean_locked


func _save() -> Error:
	if not _persistence_enabled:
		return OK

	var config := ConfigFile.new()
	config.set_value(
		"meta",
		"version",
		SAVE_VERSION
	)

	if _catalog != null:
		for raw_id in _catalog.call(
			"get_competition_ids"
		):
			var key: String = str(raw_id)
			config.set_value(
				"attempts",
				key,
				maxi(
					0,
					int(_attempts.get(key, 0))
				)
			)
			config.set_value(
				"clears",
				key,
				maxi(
					0,
					int(_clears.get(key, 0))
				)
			)
			config.set_value(
				"failures",
				key,
				maxi(
					0,
					int(_failures.get(key, 0))
				)
			)
			config.set_value(
				"abandons",
				key,
				maxi(
					0,
					int(_abandons.get(key, 0))
				)
			)

	config.set_value(
		"pending_reward",
		"competition_id",
		str(_pending_reward.get("competition_id", ""))
	)
	config.set_value(
		"pending_reward",
		"clear_number",
		maxi(0, int(_pending_reward.get("clear_number", 0)))
	)
	config.set_value(
		"pending_reward",
		"reward_source_id",
		str(_pending_reward.get("reward_source_id", ""))
	)
	config.set_value(
		"pending_reward",
		"reward_event_id",
		str(_pending_reward.get("reward_event_id", ""))
	)
	config.set_value(
		"pending_reward",
		"title_awarded",
		str(_pending_reward.get("title_awarded", ""))
	)
	config.set_value(
		"pending_reward",
		"card_game_completed",
		bool(_pending_reward.get("card_game_completed", false))
	)

	config.set_value(
		"active",
		"competition_id",
		String(_active_competition_id)
	)
	config.set_value(
		"active",
		"round_index",
		_active_round_index
	)
	config.set_value(
		"active",
		"locked_deck_ids",
		_locked_deck_ids
	)

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadCompetitionService: "
			+ "could not save competition state (%s)."
			% error_string(save_error)
		)
	return save_error
