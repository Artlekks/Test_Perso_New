extends RefCounted

const DATA_PATH := "res://data/triple_triad/competition/competition_catalog.json"

var _opponent_registry = null
var _world_acquisition_catalog = null
var _circuits: Dictionary = {}
var _competitions: Dictionary = {}
var _load_errors := PackedStringArray()


func initialize(
	opponent_registry,
	world_acquisition_catalog
) -> Dictionary:
	_opponent_registry = opponent_registry
	_world_acquisition_catalog = world_acquisition_catalog
	_circuits.clear()
	_competitions.clear()
	_load_errors.clear()
	_load_data()
	return validate_catalog()


func validate_catalog() -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	for error_text in _load_errors:
		errors.append(error_text)

	if _circuits.is_empty():
		errors.append("No competitive circuits are authored.")
	if _competitions.is_empty():
		errors.append("No tournaments are authored.")

	for raw_circuit in _circuits.values():
		if not (raw_circuit is Dictionary):
			errors.append("Competition catalog contains an invalid circuit entry.")
			continue
		var circuit: Dictionary = raw_circuit
		var circuit_id: String = str(circuit.get("circuit_id", ""))
		var opponents: Array = circuit.get("opponent_ids", [])
		if opponents.is_empty():
			errors.append("%s: circuit has no opponents" % circuit_id)
		for raw_opponent_id in opponents:
			var opponent_id := StringName(str(raw_opponent_id))
			if not _has_opponent(opponent_id):
				errors.append(
					"%s: unknown opponent '%s'"
					% [circuit_id, String(opponent_id)]
				)

	for raw_competition in _competitions.values():
		if not (raw_competition is Dictionary):
			errors.append("Competition catalog contains an invalid tournament entry.")
			continue
		var competition: Dictionary = raw_competition
		var competition_id: String = str(
			competition.get("competition_id", "")
		)
		var rounds: Array = competition.get("opponent_ids", [])
		if rounds.is_empty():
			errors.append("%s: tournament has no rounds" % competition_id)
		for raw_opponent_id in rounds:
			var opponent_id := StringName(str(raw_opponent_id))
			if not _has_opponent(opponent_id):
				errors.append(
					"%s: unknown round opponent '%s'"
					% [competition_id, String(opponent_id)]
				)

		for raw_circuit_id in competition.get("required_circuit_ids", []):
			if not _circuits.has(str(raw_circuit_id)):
				errors.append(
					"%s: unknown required circuit '%s'"
					% [competition_id, str(raw_circuit_id)]
				)

		var required_clears = competition.get("required_competition_clears", {})
		if required_clears is Dictionary:
			for raw_required_id in required_clears.keys():
				var required_id: String = str(raw_required_id)
				if required_id == competition_id:
					errors.append(
						"%s: tournament cannot require itself" % competition_id
					)
				elif not _competitions.has(required_id):
					errors.append(
						"%s: unknown prerequisite tournament '%s'"
						% [competition_id, required_id]
					)
				elif int(required_clears[raw_required_id]) < 1:
					errors.append(
						"%s: prerequisite clear count must be positive"
						% competition_id
					)

		var reward_source_id: String = str(competition.get("reward_source_id", ""))
		if reward_source_id.is_empty():
			warnings.append("%s: tournament has no card reward source" % competition_id)
		elif not _has_tournament_reward_source(StringName(reward_source_id)):
			errors.append(
				"%s: tournament reward source '%s' is missing"
				% [competition_id, reward_source_id]
			)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"circuit_count": _circuits.size(),
		"competition_count": _competitions.size(),
	}


func get_circuit(circuit_id: StringName) -> Dictionary:
	var raw = _circuits.get(String(circuit_id), {})
	if raw is Dictionary:
		return raw.duplicate(true)
	return {}


func get_competition(competition_id: StringName) -> Dictionary:
	var raw = _competitions.get(String(competition_id), {})
	if raw is Dictionary:
		return raw.duplicate(true)
	return {}


func get_all_circuits() -> Array:
	var result: Array = []
	for raw_circuit in _circuits.values():
		if raw_circuit is Dictionary:
			result.append(raw_circuit.duplicate(true))
	result.sort_custom(func(a, b):
		return str(a.get("circuit_id", "")) < str(b.get("circuit_id", ""))
	)
	return result


func get_all_competitions() -> Array:
	var result: Array = []
	for raw_competition in _competitions.values():
		if raw_competition is Dictionary:
			result.append(raw_competition.duplicate(true))
	result.sort_custom(func(a, b):
		var rank_a: int = int(a.get("required_duel_rank", 1))
		var rank_b: int = int(b.get("required_duel_rank", 1))
		if rank_a == rank_b:
			return str(a.get("competition_id", "")) < str(b.get("competition_id", ""))
		return rank_a < rank_b
	)
	return result


func get_competition_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for raw_id in _competitions.keys():
		result.append(str(raw_id))
	result.sort()
	return result


func _load_data() -> void:
	if not FileAccess.file_exists(DATA_PATH):
		_load_errors.append("Competition catalog is missing: %s" % DATA_PATH)
		return

	var raw_text: String = FileAccess.get_file_as_string(DATA_PATH)
	var parsed = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		_load_errors.append("Competition catalog JSON is invalid.")
		return

	var data: Dictionary = parsed
	for raw_circuit in data.get("circuits", []):
		if not (raw_circuit is Dictionary):
			_load_errors.append("Competition catalog contains an invalid circuit.")
			continue
		var circuit: Dictionary = raw_circuit.duplicate(true)
		var circuit_id: String = str(circuit.get("circuit_id", "")).strip_edges()
		if circuit_id.is_empty():
			_load_errors.append("Circuit has an empty id.")
		elif _circuits.has(circuit_id):
			_load_errors.append("Duplicate circuit id: %s" % circuit_id)
		else:
			_circuits[circuit_id] = circuit

	for raw_competition in data.get("competitions", []):
		if not (raw_competition is Dictionary):
			_load_errors.append("Competition catalog contains an invalid tournament.")
			continue
		var competition: Dictionary = raw_competition.duplicate(true)
		var competition_id: String = str(
			competition.get("competition_id", "")
		).strip_edges()
		if competition_id.is_empty():
			_load_errors.append("Tournament has an empty id.")
		elif _competitions.has(competition_id):
			_load_errors.append("Duplicate tournament id: %s" % competition_id)
		else:
			_competitions[competition_id] = competition


func _has_opponent(opponent_id: StringName) -> bool:
	return (
		_opponent_registry != null
		and _opponent_registry.has_method("has_opponent")
		and bool(_opponent_registry.call("has_opponent", opponent_id))
	)


func _has_tournament_reward_source(source_id: StringName) -> bool:
	if (
		_world_acquisition_catalog == null
		or not _world_acquisition_catalog.has_method("get_source_snapshot")
	):
		return false
	var source: Dictionary = _world_acquisition_catalog.call(
		"get_source_snapshot",
		&"tournament_reward",
		source_id
	)
	return not source.is_empty()
