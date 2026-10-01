extends Resource
class_name TripleTriadOpponentRegistry

@export var opponents: Array[TripleTriadOpponentProfile] = []

var _cache: Dictionary = {}


func get_opponent(opponent_id: StringName) -> TripleTriadOpponentProfile:
	_ensure_cache()
	return _cache.get(opponent_id, null)


func has_opponent(opponent_id: StringName) -> bool:
	return get_opponent(opponent_id) != null


func get_all_opponents() -> Array[TripleTriadOpponentProfile]:
	var result: Array[TripleTriadOpponentProfile] = []
	for profile in opponents:
		if profile != null:
			result.append(profile)
	return result


func get_availability(
	opponent_id: StringName,
	player_rank: int,
	region_id: StringName = &"",
	required_tag: StringName = &""
) -> Dictionary:
	var profile: TripleTriadOpponentProfile = get_opponent(opponent_id)
	if profile == null:
		return {
			"available": false,
			"reason": "Unknown opponent.",
			"required_player_rank": 1,
		}

	var clean_rank: int = maxi(1, player_rank)
	if not profile.enabled_by_default:
		return {
			"available": false,
			"reason": "Opponent disabled.",
			"required_player_rank": profile.required_player_rank,
		}
	if clean_rank < profile.required_player_rank:
		return {
			"available": false,
			"reason": "Requires Duel Rank %d." % profile.required_player_rank,
			"required_player_rank": profile.required_player_rank,
		}
	if region_id != &"" and profile.get_region_id() != region_id:
		return {
			"available": false,
			"reason": "Opponent is not available in this region.",
			"required_player_rank": profile.required_player_rank,
		}
	if required_tag != &"" and not profile.has_tag(required_tag):
		return {
			"available": false,
			"reason": "Opponent does not match the required encounter type.",
			"required_player_rank": profile.required_player_rank,
		}
	return {
		"available": true,
		"reason": "",
		"required_player_rank": profile.required_player_rank,
	}


func get_available_opponents(
	player_rank: int,
	region_id: StringName = &"",
	required_tag: StringName = &""
) -> Array[TripleTriadOpponentProfile]:
	var result: Array[TripleTriadOpponentProfile] = []
	var clean_rank: int = maxi(1, player_rank)

	for profile in opponents:
		if profile == null:
			continue
		var availability: Dictionary = get_availability(
			profile.opponent_id,
			clean_rank,
			region_id,
			required_tag
		)
		if bool(availability.get("available", false)):
			result.append(profile)

	result.sort_custom(func(a, b):
		if a.duel_rank == b.duel_rank:
			return String(a.opponent_id) < String(b.opponent_id)
		return a.duel_rank < b.duel_rank
	)
	return result


func validate_registry(card_catalog: Resource = null) -> Dictionary:
	_cache.clear()
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var ids: Dictionary = {}

	for index in range(opponents.size()):
		var profile: TripleTriadOpponentProfile = opponents[index]
		if profile == null:
			errors.append("null opponent profile at registry index %d" % index)
			continue

		var opponent_key: String = String(profile.opponent_id).strip_edges()
		if opponent_key.is_empty():
			errors.append("empty opponent id at registry index %d" % index)
			continue
		if ids.has(opponent_key):
			errors.append("duplicate opponent id: %s" % opponent_key)
			continue
		ids[opponent_key] = true
		_cache[profile.opponent_id] = profile

		var audit: Dictionary = profile.validate_profile(card_catalog)
		for error in audit.get("errors", []):
			errors.append("%s: %s" % [opponent_key, str(error)])
		for warning in audit.get("warnings", []):
			warnings.append("%s: %s" % [opponent_key, str(warning)])

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"opponent_count": _cache.size(),
	}


func invalidate_cache() -> void:
	_cache.clear()


func _ensure_cache() -> void:
	if _cache.size() == opponents.size() and not opponents.is_empty():
		return
	_cache.clear()
	for profile in opponents:
		if profile == null:
			continue
		if String(profile.opponent_id).strip_edges().is_empty():
			continue
		if not _cache.has(profile.opponent_id):
			_cache[profile.opponent_id] = profile
