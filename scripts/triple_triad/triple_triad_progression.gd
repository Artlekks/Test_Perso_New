extends RefCounted

signal changed(snapshot: Dictionary)
signal rank_changed(previous_rank: int, new_rank: int, crossed_ranks: Array)

const DefaultProgressionCatalog: TripleTriadProgressionCatalog = preload(
	"res://data/triple_triad/progression/all_progression.tres"
)

const SAVE_PATH := "user://triple_triad_progression.cfg"
const SAVE_VERSION := 2
const DEFAULT_WIN_REWARD := 3

var progression_catalog: TripleTriadProgressionCatalog = DefaultProgressionCatalog

var _points: int = 0
var _matches: int = 0
var _wins: int = 0
var _losses: int = 0
var _draws: int = 0


func initialize() -> void:
	if (
		progression_catalog == null
		or not progression_catalog.is_valid_catalog()
	):
		push_error("TripleTriadProgression: invalid progression catalog.")
		return

	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		_save()
		return

	# Version 1 already stored the same counters. Version 2 moves rank
	# thresholds/budget bonuses out of code and into an authored resource, so
	# the save migrates without resetting the player's progress.
	var version: int = int(config.get_value("progression", "version", 0))
	if version <= 0:
		_save()
		return

	_points = progression_catalog.clamp_points(
		int(config.get_value("progression", "points", 0))
	)
	_matches = maxi(0, int(config.get_value("progression", "matches", 0)))
	_wins = maxi(0, int(config.get_value("progression", "wins", 0)))
	_losses = maxi(0, int(config.get_value("progression", "losses", 0)))
	_draws = maxi(0, int(config.get_value("progression", "draws", 0)))
	_repair_counters()
	_save()


func configure_progression_catalog(
	new_catalog: TripleTriadProgressionCatalog
) -> bool:
	if new_catalog == null or not new_catalog.is_valid_catalog():
		return false

	var previous_rank: int = get_rank_number()
	progression_catalog = new_catalog
	_points = progression_catalog.clamp_points(_points)
	var new_rank: int = get_rank_number()
	_save()
	changed.emit(get_snapshot())
	if new_rank != previous_rank:
		rank_changed.emit(previous_rank, new_rank, [])
	return true


func record_result(
	winner: int,
	player_owner: int,
	opponent_profile: Resource = null,
	progression_reward_override: int = -1
) -> Dictionary:
	var before_points: int = _points
	var before_rank: int = get_rank_number()
	var earned: int = 0

	_matches += 1
	if winner == player_owner:
		_wins += 1
		if progression_reward_override >= 0:
			earned = progression_reward_override
		else:
			earned = _win_reward(opponent_profile)
	elif winner == 0:
		_draws += 1
	else:
		_losses += 1

	_points = progression_catalog.clamp_points(_points + earned)
	var crossed_ranks: Array[Dictionary] = progression_catalog.get_crossed_ranks(
		before_points,
		_points
	)
	var after_rank: int = get_rank_number()

	_save()
	var snapshot: Dictionary = get_snapshot()
	changed.emit(snapshot)
	if after_rank != before_rank:
		rank_changed.emit(before_rank, after_rank, crossed_ranks)

	return {
		"points_before": before_points,
		"points_after": _points,
		"points_earned": earned,
		"rank_before": before_rank,
		"rank_after": after_rank,
		"rank_name": get_rank_name(),
		"rank_up": after_rank > before_rank,
		"crossed_ranks": crossed_ranks,
		"rank_progress": get_rank_progress(),
		"deck_budget": get_deck_budget(),
		"matches": _matches,
		"wins": _wins,
		"losses": _losses,
		"draws": _draws,
	}


func get_points() -> int:
	return _points


func get_rank_index() -> int:
	return progression_catalog.get_rank_index(_points)


func get_rank_number() -> int:
	return get_rank_index() + 1


func get_rank_name() -> String:
	return progression_catalog.get_rank_name(_points)


func get_rank_id() -> StringName:
	return progression_catalog.get_rank_id(_points)


func get_rank_count() -> int:
	return progression_catalog.get_rank_count()


func get_deck_budget(base_budget: int = 30) -> int:
	return progression_catalog.get_deck_budget(base_budget, _points)


func get_next_rank_threshold() -> int:
	return progression_catalog.get_next_rank_threshold(_points)


func get_rank_progress() -> Dictionary:
	return progression_catalog.get_rank_progress(_points)


func get_snapshot(base_budget: int = 30) -> Dictionary:
	return {
		"points": _points,
		"rank": get_rank_number(),
		"rank_id": str(get_rank_id()),
		"rank_name": get_rank_name(),
		"rank_count": get_rank_count(),
		"deck_budget": get_deck_budget(base_budget),
		"next_rank_threshold": get_next_rank_threshold(),
		"rank_progress": get_rank_progress(),
		"matches": _matches,
		"wins": _wins,
		"losses": _losses,
		"draws": _draws,
	}


func save_state() -> Error:
	return _save()


func audit_state() -> Dictionary:
	var repairs: int = 0
	var warnings: Array[String] = []

	var clean_points: int = progression_catalog.clamp_points(_points)
	if clean_points != _points:
		_points = clean_points
		repairs += 1

	var clean_wins: int = maxi(0, _wins)
	var clean_losses: int = maxi(0, _losses)
	var clean_draws: int = maxi(0, _draws)
	var clean_matches: int = maxi(
		0,
		maxi(_matches, clean_wins + clean_losses + clean_draws)
	)

	if clean_wins != _wins:
		_wins = clean_wins
		repairs += 1
	if clean_losses != _losses:
		_losses = clean_losses
		repairs += 1
	if clean_draws != _draws:
		_draws = clean_draws
		repairs += 1
	if clean_matches != _matches:
		_matches = clean_matches
		repairs += 1

	var save_error: Error = _save()
	var valid: bool = save_error == OK
	if not valid:
		warnings.append("Progression repair could not be saved.")

	return {
		"valid": valid,
		"repairs": repairs,
		"warnings": warnings,
		"snapshot": get_snapshot(),
	}


func _win_reward(opponent_profile: Resource) -> int:
	if opponent_profile != null:
		var value = opponent_profile.get("progression_points_on_win")
		if value != null:
			return maxi(0, int(value))
	return DEFAULT_WIN_REWARD


func _repair_counters() -> void:
	var resolved: int = _wins + _losses + _draws
	if _matches < resolved:
		_matches = resolved


func _save() -> Error:
	var config := ConfigFile.new()
	config.set_value("progression", "version", SAVE_VERSION)
	config.set_value("progression", "points", _points)
	config.set_value("progression", "matches", _matches)
	config.set_value("progression", "wins", _wins)
	config.set_value("progression", "losses", _losses)
	config.set_value("progression", "draws", _draws)

	var save_error: Error = config.save(SAVE_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadProgression: could not save progression (%s)."
			% error_string(save_error)
		)
	return save_error
