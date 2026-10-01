extends RefCounted
class_name TripleTriadBalanceSimulator

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const NEUTRAL_RULES = preload("res://data/triple_triad/basic_rules.tres")

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2
const REPORT_PATH := "user://triple_triad_balance_report.json"
const BALANCE_VERSION := "6"


func run_registry_suite(
	card_catalog: Resource,
	opponent_registry: Resource,
	games_per_matchup: int = 40,
	seed: int = 1337,
	save_report: bool = true
) -> Dictionary:
	var errors: Array[String] = []
	if card_catalog == null:
		errors.append("Card catalog is missing.")
	if opponent_registry == null:
		errors.append("Opponent registry is missing.")
	if not errors.is_empty():
		return _failed_report(errors)

	var profiles: Array = opponent_registry.call("get_all_opponents")
	if profiles.size() < 2:
		errors.append("Balance simulation requires at least two opponents.")
		return _failed_report(errors)

	var authored_decks: Dictionary = {}
	var profile_summaries: Dictionary = {}
	for profile in profiles:
		if profile == null:
			continue
		var opponent_id: String = String(profile.get("opponent_id"))
		var deck: Array = _authored_deck(profile, card_catalog)
		if deck.size() != 5:
			errors.append("%s does not have a complete authored five-card deck." % opponent_id)
			continue
		var budget: int = _profile_budget(profile)
		var cost: int = _deck_cost(deck)
		if cost > budget:
			errors.append(
				"%s authored deck costs %d but budget is %d."
				% [opponent_id, cost, budget]
			)
			continue
		authored_decks[opponent_id] = deck
		profile_summaries[opponent_id] = _new_profile_metrics(profile, deck, budget)

	if not errors.is_empty():
		return _failed_report(errors)

	var clean_games: int = maxi(1, games_per_matchup)
	var matchup_reports: Array = []
	var card_metrics: Dictionary = {}
	var host_turn_metrics: Dictionary = {}
	var global_metrics: Dictionary = {
		"games": 0,
		"decisive_games": 0,
		"draws": 0,
		"starting_owner_wins": 0,
		"second_owner_wins": 0,
		"initiative_plus_one_first_wins": 0,
		"initiative_plus_one_second_wins": 0,
		"initiative_plus_one_draws": 0,
		"initiative_plus_two_first_wins": 0,
		"initiative_plus_two_second_wins": 0,
		"initiative_plus_two_draws": 0,
		"same_triggers": 0,
		"plus_triggers": 0,
		"influence_placements": 0,
		"influence_targets": 0,
		"captures": 0,
		"invalid_games": 0,
	}

	var matchup_index: int = 0
	# Ordered host/challenger matchups matter because the host supplies the region
	# and rules, just like challenging that NPC in the real game.
	for host_profile in profiles:
		if host_profile == null:
			continue
		var host_id: String = String(host_profile.get("opponent_id"))
		if not host_turn_metrics.has(host_id):
			host_turn_metrics[host_id] = _new_host_turn_metrics(host_profile)
		for challenger_profile in profiles:
			if challenger_profile == null:
				continue
			var challenger_id: String = String(challenger_profile.get("opponent_id"))
			if challenger_id == host_id:
				continue

			var matchup: Dictionary = _new_matchup_metrics(host_profile, challenger_profile)
			var host_deck: Array = authored_decks[host_id]
			var challenger_deck: Array = authored_decks[challenger_id]
			var rules: Resource = _profile_rules(host_profile)
			var region: Resource = host_profile.get("region_profile")

			for game_index in range(clean_games):
				var first_owner: int = OWNER_PLAYER
				if game_index % 2 == 1:
					first_owner = OWNER_OPPONENT
				var game_seed: int = seed + matchup_index * 100003 + game_index * 97
				var result: Dictionary = _simulate_game(
					challenger_deck,
					host_deck,
					challenger_profile.get("ai_profile"),
					host_profile.get("ai_profile"),
					rules,
					region,
					first_owner,
					game_seed
				)
				_accumulate_game(
					result,
					challenger_profile,
					host_profile,
					challenger_deck,
					host_deck,
					matchup,
					profile_summaries,
					card_metrics,
					global_metrics,
					host_turn_metrics
				)

			matchup_reports.append(_finalize_matchup(matchup))
			matchup_index += 1

	var simulation_errors: Array[String] = []
	if int(global_metrics["invalid_games"]) > 0:
		simulation_errors.append(
			"%d simulated games ended in an invalid state."
			% int(global_metrics["invalid_games"])
		)
	var finalized_profiles: Array = _finalize_profiles(profile_summaries)
	var authored_home_ladder_checks: Array = _build_ladder_checks(
		finalized_profiles,
		matchup_reports
	)
	var neutral_ladder_checks: Array = _build_neutral_ladder_checks(
		profiles,
		authored_decks,
		clean_games,
		seed
	)
	var report: Dictionary = {
		"valid": simulation_errors.is_empty(),
		"balance_version": BALANCE_VERSION,
		"errors": simulation_errors,
		"seed": seed,
		"games_per_matchup": clean_games,
		"neutral_games_per_direction": clean_games,
		"ordered_matchup_count": matchup_reports.size(),
		"global": _finalize_global(global_metrics),
		"turn_order_by_host": _finalize_host_turn_metrics(host_turn_metrics),
		"opponents": finalized_profiles,
		"ladder_method": "neutral_basic_rules_no_region",
		"ladder_checks": neutral_ladder_checks,
		"neutral_ladder_checks": neutral_ladder_checks,
		"authored_home_ladder_checks": authored_home_ladder_checks,
		"matchups": matchup_reports,
		"cards": _finalize_cards(card_metrics),
		"report_path": REPORT_PATH,
	}

	if save_report:
		_save_report(report)
	return report


func _simulate_game(
	player_deck: Array,
	opponent_deck: Array,
	player_ai_profile: Resource,
	opponent_ai_profile: Resource,
	rules: Resource,
	region: Resource,
	first_owner: int,
	seed: int
) -> Dictionary:
	var match_state = MatchScript.new()
	match_state.reset_match(
		player_deck.duplicate(),
		opponent_deck.duplicate(),
		first_owner,
		rules,
		region
	)
	var ai = AIScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var events: Array = []
	var safety: int = 0
	var valid: bool = true

	while not match_state.game_over and safety < 12:
		safety += 1
		var owner: int = match_state.current_owner
		var ai_profile: Resource = player_ai_profile
		if owner == OWNER_OPPONENT:
			ai_profile = opponent_ai_profile
		var move: Dictionary = ai.choose_move(match_state, owner, rng, ai_profile)
		if not bool(move.get("valid", false)):
			valid = false
			break

		var hand: Array = match_state.get_hand(owner)
		var hand_index: int = int(move.get("hand_index", -1))
		if hand_index < 0 or hand_index >= hand.size():
			valid = false
			break
		var card = hand[hand_index]
		if bool(move.get("rotate", false)):
			match_state.rotate_hand_card(owner, hand_index)

		var result: Dictionary = match_state.place_card(
			owner,
			hand_index,
			int(move.get("cell_index", -1))
		)
		if not bool(result.get("success", false)):
			valid = false
			break

		var captured_cells: Array = result.get("captured", [])
		var influence_cells: Array = result.get("influence_cells", [])
		events.append({
			"card_id": String(card.card_id),
			"owner": owner,
			"captures": captured_cells.size(),
			"same": bool(result.get("same_triggered", false)),
			"plus": bool(result.get("plus_triggered", false)),
			"influence_targets": influence_cells.size(),
		})

	if not match_state.game_over:
		valid = false
	if not match_state.validate_state():
		valid = false

	return {
		"valid": valid,
		"winner": match_state.get_winner(),
		"score": match_state.get_score(),
		"starting_owner": first_owner,
		"events": events,
	}


func _accumulate_game(
	result: Dictionary,
	player_profile: Resource,
	opponent_profile: Resource,
	player_deck: Array,
	opponent_deck: Array,
	matchup: Dictionary,
	profile_metrics: Dictionary,
	card_metrics: Dictionary,
	global_metrics: Dictionary,
	host_turn_metrics: Dictionary
) -> void:
	global_metrics["games"] = int(global_metrics["games"]) + 1
	matchup["games"] = int(matchup["games"]) + 1
	if not bool(result.get("valid", false)):
		global_metrics["invalid_games"] = int(global_metrics["invalid_games"]) + 1
		matchup["invalid_games"] = int(matchup["invalid_games"]) + 1
		return

	var player_id: String = String(player_profile.get("opponent_id"))
	var opponent_id: String = String(opponent_profile.get("opponent_id"))
	var winner: int = int(result.get("winner", OWNER_NONE))
	var score: Dictionary = result.get("score", {})
	var player_score: int = int(score.get("player", 0))
	var opponent_score: int = int(score.get("opponent", 0))

	_accumulate_initiative_candidate(
		global_metrics,
		int(result.get("starting_owner", OWNER_NONE)),
		player_score,
		opponent_score,
		1,
		"initiative_plus_one"
	)
	_accumulate_initiative_candidate(
		global_metrics,
		int(result.get("starting_owner", OWNER_NONE)),
		player_score,
		opponent_score,
		2,
		"initiative_plus_two"
	)

	_accumulate_profile_game(
		profile_metrics[player_id],
		winner,
		OWNER_PLAYER,
		player_score,
		opponent_score
	)
	_accumulate_profile_game(
		profile_metrics[opponent_id],
		winner,
		OWNER_OPPONENT,
		opponent_score,
		player_score
	)

	if winner == OWNER_PLAYER:
		matchup["challenger_wins"] = int(matchup["challenger_wins"]) + 1
	elif winner == OWNER_OPPONENT:
		matchup["host_wins"] = int(matchup["host_wins"]) + 1
	else:
		matchup["draws"] = int(matchup["draws"]) + 1

	var starting_owner: int = int(result.get("starting_owner", OWNER_NONE))
	if winner == OWNER_NONE:
		global_metrics["draws"] = int(global_metrics["draws"]) + 1
	else:
		global_metrics["decisive_games"] = int(global_metrics["decisive_games"]) + 1
		if winner == starting_owner:
			global_metrics["starting_owner_wins"] = int(global_metrics["starting_owner_wins"]) + 1
		else:
			global_metrics["second_owner_wins"] = int(global_metrics["second_owner_wins"]) + 1

	_accumulate_turn_order(matchup, result, false)
	if host_turn_metrics.has(opponent_id):
		var host_metric: Dictionary = host_turn_metrics[opponent_id]
		_accumulate_turn_order(host_metric, result, true)
		_accumulate_initiative_candidate(
			host_metric,
			starting_owner,
			player_score,
			opponent_score,
			1,
			"initiative_plus_one"
		)
		host_turn_metrics[opponent_id] = host_metric

	var player_won: bool = winner == OWNER_PLAYER
	var opponent_won: bool = winner == OWNER_OPPONENT
	_register_deck_cards(card_metrics, player_deck, player_id, player_won, winner == OWNER_NONE)
	_register_deck_cards(card_metrics, opponent_deck, opponent_id, opponent_won, winner == OWNER_NONE)

	for raw_event in result.get("events", []):
		var event: Dictionary = raw_event
		var owner: int = int(event.get("owner", OWNER_NONE))
		var profile_id: String = player_id
		if owner == OWNER_OPPONENT:
			profile_id = opponent_id
		var card_id: String = str(event.get("card_id", ""))
		var metric: Dictionary = _ensure_card_metric(card_metrics, card_id)
		metric["placements"] = int(metric["placements"]) + 1
		metric["captures"] = int(metric["captures"]) + int(event.get("captures", 0))
		if bool(event.get("same", false)):
			metric["same_triggers"] = int(metric["same_triggers"]) + 1
			global_metrics["same_triggers"] = int(global_metrics["same_triggers"]) + 1
		if bool(event.get("plus", false)):
			metric["plus_triggers"] = int(metric["plus_triggers"]) + 1
			global_metrics["plus_triggers"] = int(global_metrics["plus_triggers"]) + 1
		var target_count: int = int(event.get("influence_targets", 0))
		if target_count > 0:
			metric["influence_placements"] = int(metric["influence_placements"]) + 1
			metric["influence_targets"] = int(metric["influence_targets"]) + target_count
			global_metrics["influence_placements"] = int(global_metrics["influence_placements"]) + 1
			global_metrics["influence_targets"] = int(global_metrics["influence_targets"]) + target_count
		global_metrics["captures"] = int(global_metrics["captures"]) + int(event.get("captures", 0))
		metric["last_profile_id"] = profile_id
		card_metrics[card_id] = metric


func _accumulate_initiative_candidate(
	metric: Dictionary,
	starting_owner: int,
	player_score: int,
	opponent_score: int,
	bonus: int,
	prefix: String
) -> void:
	var adjusted_player: int = player_score
	var adjusted_opponent: int = opponent_score
	if starting_owner == OWNER_PLAYER:
		adjusted_player += bonus
	elif starting_owner == OWNER_OPPONENT:
		adjusted_opponent += bonus
	else:
		return

	if adjusted_player == adjusted_opponent:
		metric["%s_draws" % prefix] = int(metric.get("%s_draws" % prefix, 0)) + 1
		return
	var adjusted_winner: int = (
		OWNER_PLAYER
		if adjusted_player > adjusted_opponent
		else OWNER_OPPONENT
	)
	var suffix: String = "first_wins" if adjusted_winner == starting_owner else "second_wins"
	var key: String = "%s_%s" % [prefix, suffix]
	metric[key] = int(metric.get(key, 0)) + 1


func _accumulate_profile_game(
	metric: Dictionary,
	winner: int,
	owner: int,
	score_for: int,
	score_against: int
) -> void:
	metric["games"] = int(metric["games"]) + 1
	metric["score_for"] = int(metric["score_for"]) + score_for
	metric["score_against"] = int(metric["score_against"]) + score_against
	if winner == owner:
		metric["wins"] = int(metric["wins"]) + 1
	elif winner == OWNER_NONE:
		metric["draws"] = int(metric["draws"]) + 1
	else:
		metric["losses"] = int(metric["losses"]) + 1


func _register_deck_cards(
	card_metrics: Dictionary,
	deck: Array,
	profile_id: String,
	won: bool,
	drew: bool
) -> void:
	for card in deck:
		if card == null:
			continue
		var card_id: String = String(card.card_id)
		var metric: Dictionary = _ensure_card_metric(card_metrics, card_id)
		metric["deck_games"] = int(metric["deck_games"]) + 1
		if won:
			metric["deck_wins"] = int(metric["deck_wins"]) + 1
		elif drew:
			metric["deck_draws"] = int(metric["deck_draws"]) + 1
		else:
			metric["deck_losses"] = int(metric["deck_losses"]) + 1
		var profiles: Array = metric["profiles"]
		if not profiles.has(profile_id):
			profiles.append(profile_id)
		metric["profiles"] = profiles
		metric["display_name"] = str(card.display_name)
		metric["deck_cost"] = int(card.deck_cost)
		metric["rank_total"] = int(card.rank_total())
		metric["rarity"] = String(card.rarity_id)
		card_metrics[card_id] = metric


func _ensure_card_metric(card_metrics: Dictionary, card_id: String) -> Dictionary:
	if card_metrics.has(card_id):
		return card_metrics[card_id]
	var metric: Dictionary = {
		"card_id": card_id,
		"display_name": card_id,
		"rarity": "",
		"deck_cost": 0,
		"rank_total": 0,
		"profiles": [],
		"deck_games": 0,
		"deck_wins": 0,
		"deck_losses": 0,
		"deck_draws": 0,
		"placements": 0,
		"captures": 0,
		"same_triggers": 0,
		"plus_triggers": 0,
		"influence_placements": 0,
		"influence_targets": 0,
		"last_profile_id": "",
	}
	card_metrics[card_id] = metric
	return metric


func _new_profile_metrics(profile: Resource, deck: Array, budget: int) -> Dictionary:
	var rank_total: int = 0
	var influence_cards: int = 0
	for card in deck:
		if card == null:
			continue
		rank_total += int(card.rank_total())
		if card.has_method("has_influence") and bool(card.call("has_influence")):
			influence_cards += 1
	return {
		"opponent_id": String(profile.get("opponent_id")),
		"display_name": str(profile.get("display_name")),
		"archetype_id": String(profile.get("archetype_id")),
		"duel_rank": int(profile.get("duel_rank")),
		"required_player_rank": int(profile.get("required_player_rank")),
		"deck_budget": budget,
		"deck_cost": _deck_cost(deck),
		"deck_rank_total": rank_total,
		"influence_cards": influence_cards,
		"games": 0,
		"wins": 0,
		"losses": 0,
		"draws": 0,
		"score_for": 0,
		"score_against": 0,
	}


func _new_matchup_metrics(host_profile: Resource, challenger_profile: Resource) -> Dictionary:
	return {
		"host_id": String(host_profile.get("opponent_id")),
		"host_name": str(host_profile.get("display_name")),
		"challenger_id": String(challenger_profile.get("opponent_id")),
		"challenger_name": str(challenger_profile.get("display_name")),
		"games": 0,
		"host_wins": 0,
		"challenger_wins": 0,
		"draws": 0,
		"invalid_games": 0,
		"first_player_wins": 0,
		"second_player_wins": 0,
		"challenger_started_games": 0,
		"host_started_games": 0,
		"challenger_wins_when_starting": 0,
		"challenger_wins_when_second": 0,
		"host_wins_when_starting": 0,
		"host_wins_when_second": 0,
	}


func _new_host_turn_metrics(host_profile: Resource) -> Dictionary:
	var rules: Resource = _profile_rules(host_profile)
	var region: Resource = host_profile.get("region_profile")
	return {
		"host_id": String(host_profile.get("opponent_id")),
		"host_name": str(host_profile.get("display_name")),
		"duel_rank": int(host_profile.get("duel_rank")),
		"rules": _resource_key(rules),
		"region": _resource_key(region),
		"games": 0,
		"draws": 0,
		"first_player_wins": 0,
		"second_player_wins": 0,
		"challenger_started_games": 0,
		"host_started_games": 0,
		"challenger_wins_when_starting": 0,
		"challenger_wins_when_second": 0,
		"host_wins_when_starting": 0,
		"host_wins_when_second": 0,
	}


func _accumulate_turn_order(
	metric: Dictionary,
	result: Dictionary,
	count_totals: bool
) -> void:
	if not bool(result.get("valid", false)):
		return
	var starting_owner: int = int(result.get("starting_owner", OWNER_NONE))
	var winner: int = int(result.get("winner", OWNER_NONE))
	if count_totals:
		metric["games"] = int(metric.get("games", 0)) + 1
	if starting_owner == OWNER_PLAYER:
		metric["challenger_started_games"] = int(metric.get("challenger_started_games", 0)) + 1
	else:
		metric["host_started_games"] = int(metric.get("host_started_games", 0)) + 1

	if winner == OWNER_NONE:
		if count_totals:
			metric["draws"] = int(metric.get("draws", 0)) + 1
		return
	if winner == starting_owner:
		metric["first_player_wins"] = int(metric.get("first_player_wins", 0)) + 1
	else:
		metric["second_player_wins"] = int(metric.get("second_player_wins", 0)) + 1

	if winner == OWNER_PLAYER:
		if starting_owner == OWNER_PLAYER:
			metric["challenger_wins_when_starting"] = int(metric.get("challenger_wins_when_starting", 0)) + 1
		else:
			metric["challenger_wins_when_second"] = int(metric.get("challenger_wins_when_second", 0)) + 1
	elif winner == OWNER_OPPONENT:
		if starting_owner == OWNER_OPPONENT:
			metric["host_wins_when_starting"] = int(metric.get("host_wins_when_starting", 0)) + 1
		else:
			metric["host_wins_when_second"] = int(metric.get("host_wins_when_second", 0)) + 1


func _finalize_host_turn_metrics(metrics: Dictionary) -> Array:
	var result: Array = []
	for raw_id in metrics.keys():
		var metric: Dictionary = metrics[raw_id]
		var games: int = maxi(1, int(metric.get("games", 0)))
		var decisive: int = maxi(1, games - int(metric.get("draws", 0)))
		var challenger_starts: int = maxi(1, int(metric.get("challenger_started_games", 0)))
		var host_starts: int = maxi(1, int(metric.get("host_started_games", 0)))
		var finalized: Dictionary = metric.duplicate(true)
		finalized["draw_rate"] = float(metric.get("draws", 0)) / float(games)
		finalized["first_player_win_rate_decisive"] = float(metric.get("first_player_wins", 0)) / float(decisive)
		finalized["second_player_win_rate_decisive"] = float(metric.get("second_player_wins", 0)) / float(decisive)
		finalized["challenger_win_rate_when_starting"] = float(metric.get("challenger_wins_when_starting", 0)) / float(challenger_starts)
		finalized["challenger_win_rate_when_second"] = float(metric.get("challenger_wins_when_second", 0)) / float(host_starts)
		finalized["host_win_rate_when_starting"] = float(metric.get("host_wins_when_starting", 0)) / float(host_starts)
		finalized["host_win_rate_when_second"] = float(metric.get("host_wins_when_second", 0)) / float(challenger_starts)
		finalized["initiative_candidate_plus_one"] = _finalize_initiative_candidate(
			metric,
			"initiative_plus_one",
			games
		)
		result.append(finalized)
	result.sort_custom(func(a, b):
		return int(a.get("duel_rank", 0)) < int(b.get("duel_rank", 0))
	)
	return result


func _build_neutral_ladder_checks(
	profiles: Array,
	authored_decks: Dictionary,
	games_per_direction: int,
	seed: int
) -> Array:
	var sorted_profiles: Array = profiles.duplicate()
	sorted_profiles.sort_custom(func(a, b):
		return int(a.get("duel_rank")) < int(b.get("duel_rank"))
	)

	var result: Array = []
	var clean_games: int = maxi(1, games_per_direction)
	for index in range(1, sorted_profiles.size()):
		var lower_profile: Resource = sorted_profiles[index - 1]
		var higher_profile: Resource = sorted_profiles[index]
		if lower_profile == null or higher_profile == null:
			continue

		var lower_id: String = String(lower_profile.get("opponent_id"))
		var higher_id: String = String(higher_profile.get("opponent_id"))
		if not authored_decks.has(lower_id) or not authored_decks.has(higher_id):
			continue

		var higher_wins: int = 0
		var lower_wins: int = 0
		var draws: int = 0
		var invalid_games: int = 0
		var first_player_wins: int = 0
		var second_player_wins: int = 0
		var higher_starts: int = 0
		var higher_second: int = 0
		var higher_wins_when_starting: int = 0
		var higher_wins_when_second: int = 0

		# Run both ownership orientations so this benchmark measures deck/AI
		# strength rather than PLAYER/OPPONENT role assumptions. Every game uses
		# Basic rules and no region modifiers.
		for direction in range(2):
			var player_profile: Resource = higher_profile if direction == 0 else lower_profile
			var opponent_profile: Resource = lower_profile if direction == 0 else higher_profile
			var player_id: String = String(player_profile.get("opponent_id"))
			var opponent_id: String = String(opponent_profile.get("opponent_id"))
			var player_deck: Array = authored_decks[player_id]
			var opponent_deck: Array = authored_decks[opponent_id]

			for game_index in range(clean_games):
				var first_owner: int = OWNER_PLAYER
				if game_index % 2 == 1:
					first_owner = OWNER_OPPONENT
				var benchmark_seed: int = (
					seed
					+ index * 1000003
					+ direction * 50021
					+ game_index * 131
				)
				var game: Dictionary = _simulate_game(
					player_deck,
					opponent_deck,
					player_profile.get("ai_profile"),
					opponent_profile.get("ai_profile"),
					NEUTRAL_RULES,
					null,
					first_owner,
					benchmark_seed
				)
				if not bool(game.get("valid", false)):
					invalid_games += 1
					continue

				var higher_owner: int = OWNER_OPPONENT
				if player_id == higher_id:
					higher_owner = OWNER_PLAYER
				if first_owner == higher_owner:
					higher_starts += 1
				else:
					higher_second += 1

				var winner: int = int(game.get("winner", OWNER_NONE))
				if winner == OWNER_NONE:
					draws += 1
					continue

				if winner == first_owner:
					first_player_wins += 1
				else:
					second_player_wins += 1

				if winner == higher_owner:
					higher_wins += 1
					if first_owner == higher_owner:
						higher_wins_when_starting += 1
					else:
						higher_wins_when_second += 1
				else:
					lower_wins += 1

		var valid_games: int = clean_games * 2 - invalid_games
		var decisive: int = maxi(1, higher_wins + lower_wins)
		var higher_rate: float = float(higher_wins) / float(decisive)
		var status: String = "on_target"
		if higher_rate < 0.55:
			status = "too_weak"
		elif higher_rate > 0.75:
			status = "too_dominant"

		result.append({
			"lower_id": lower_id,
			"lower_name": str(lower_profile.get("display_name")),
			"higher_id": higher_id,
			"higher_name": str(higher_profile.get("display_name")),
			"method": "basic_rules_no_region",
			"games": valid_games,
			"invalid_games": invalid_games,
			"draws": draws,
			"draw_rate": float(draws) / float(maxi(1, valid_games)),
			"higher_wins": higher_wins,
			"lower_wins": lower_wins,
			"higher_decisive_win_rate": higher_rate,
			"higher_win_rate_when_starting": (
				float(higher_wins_when_starting) / float(maxi(1, higher_starts))
			),
			"higher_win_rate_when_second": (
				float(higher_wins_when_second) / float(maxi(1, higher_second))
			),
			"first_player_win_rate_decisive": (
				float(first_player_wins) / float(decisive)
			),
			"second_player_win_rate_decisive": (
				float(second_player_wins) / float(decisive)
			),
			"target_min": 0.55,
			"target_max": 0.75,
			"status": status,
		})
	return result


func _build_ladder_checks(profiles: Array, matchups: Array) -> Array:
	var result: Array = []
	if profiles.size() < 2:
		return result
	for index in range(1, profiles.size()):
		var lower: Dictionary = profiles[index - 1]
		var higher: Dictionary = profiles[index]
		var lower_id: String = str(lower.get("opponent_id", ""))
		var higher_id: String = str(higher.get("opponent_id", ""))
		var higher_wins: int = 0
		var lower_wins: int = 0
		var draws: int = 0
		var games: int = 0
		for raw_matchup in matchups:
			var matchup: Dictionary = raw_matchup
			var host_id: String = str(matchup.get("host_id", ""))
			var challenger_id: String = str(matchup.get("challenger_id", ""))
			if host_id == lower_id and challenger_id == higher_id:
				higher_wins += int(matchup.get("challenger_wins", 0))
				lower_wins += int(matchup.get("host_wins", 0))
				draws += int(matchup.get("draws", 0))
				games += int(matchup.get("games", 0)) - int(matchup.get("invalid_games", 0))
			elif host_id == higher_id and challenger_id == lower_id:
				higher_wins += int(matchup.get("host_wins", 0))
				lower_wins += int(matchup.get("challenger_wins", 0))
				draws += int(matchup.get("draws", 0))
				games += int(matchup.get("games", 0)) - int(matchup.get("invalid_games", 0))
		var decisive: int = maxi(1, higher_wins + lower_wins)
		var decisive_win_rate: float = float(higher_wins) / float(decisive)
		var status: String = "on_target"
		if decisive_win_rate < 0.55:
			status = "too_weak"
		elif decisive_win_rate > 0.75:
			status = "too_dominant"
		result.append({
			"lower_id": lower_id,
			"lower_name": str(lower.get("display_name", lower_id)),
			"higher_id": higher_id,
			"higher_name": str(higher.get("display_name", higher_id)),
			"games": games,
			"draws": draws,
			"higher_wins": higher_wins,
			"lower_wins": lower_wins,
			"higher_decisive_win_rate": decisive_win_rate,
			"target_min": 0.55,
			"target_max": 0.75,
			"status": status,
		})
	return result


func _resource_key(resource: Resource) -> String:
	if resource == null:
		return ""
	if not resource.resource_path.is_empty():
		return resource.resource_path.get_file().get_basename()
	return str(resource)


func _finalize_matchup(metric: Dictionary) -> Dictionary:
	var games: int = maxi(1, int(metric.get("games", 0)) - int(metric.get("invalid_games", 0)))
	var decisive: int = maxi(1, games - int(metric.get("draws", 0)))
	var challenger_starts: int = maxi(1, int(metric.get("challenger_started_games", 0)))
	var host_starts: int = maxi(1, int(metric.get("host_started_games", 0)))
	var result: Dictionary = metric.duplicate(true)
	result["host_win_rate"] = float(metric.get("host_wins", 0)) / float(games)
	result["challenger_win_rate"] = float(metric.get("challenger_wins", 0)) / float(games)
	result["draw_rate"] = float(metric.get("draws", 0)) / float(games)
	result["first_player_win_rate_decisive"] = float(metric.get("first_player_wins", 0)) / float(decisive)
	result["second_player_win_rate_decisive"] = float(metric.get("second_player_wins", 0)) / float(decisive)
	result["challenger_win_rate_when_starting"] = float(metric.get("challenger_wins_when_starting", 0)) / float(challenger_starts)
	result["challenger_win_rate_when_second"] = float(metric.get("challenger_wins_when_second", 0)) / float(host_starts)
	result["host_win_rate_when_starting"] = float(metric.get("host_wins_when_starting", 0)) / float(host_starts)
	result["host_win_rate_when_second"] = float(metric.get("host_wins_when_second", 0)) / float(challenger_starts)
	return result


func _finalize_global(metric: Dictionary) -> Dictionary:
	var valid_games: int = maxi(
		1,
		int(metric.get("games", 0)) - int(metric.get("invalid_games", 0))
	)
	var decisive: int = maxi(1, int(metric.get("decisive_games", 0)))
	var result: Dictionary = metric.duplicate(true)
	result["valid_games"] = int(metric.get("games", 0)) - int(metric.get("invalid_games", 0))
	result["first_player_win_rate"] = float(metric.get("starting_owner_wins", 0)) / float(decisive)
	result["second_player_win_rate"] = float(metric.get("second_owner_wins", 0)) / float(decisive)
	result["turn_order_bias"] = absf(float(result["first_player_win_rate"]) - 0.5)
	result["draw_rate"] = float(metric.get("draws", 0)) / float(valid_games)
	result["captures_per_game"] = float(metric.get("captures", 0)) / float(valid_games)
	result["same_triggers_per_game"] = float(metric.get("same_triggers", 0)) / float(valid_games)
	result["plus_triggers_per_game"] = float(metric.get("plus_triggers", 0)) / float(valid_games)
	result["influence_placements_per_game"] = float(metric.get("influence_placements", 0)) / float(valid_games)
	result["influence_targets_per_game"] = float(metric.get("influence_targets", 0)) / float(valid_games)
	result["initiative_candidates"] = {
		"first_player_score_bonus_1": _finalize_initiative_candidate(
			metric,
			"initiative_plus_one",
			valid_games
		),
		"first_player_score_bonus_2": _finalize_initiative_candidate(
			metric,
			"initiative_plus_two",
			valid_games
		),
	}
	return result


func _finalize_initiative_candidate(
	metric: Dictionary,
	prefix: String,
	valid_games: int
) -> Dictionary:
	var first_wins: int = int(metric.get("%s_first_wins" % prefix, 0))
	var second_wins: int = int(metric.get("%s_second_wins" % prefix, 0))
	var draws: int = int(metric.get("%s_draws" % prefix, 0))
	var decisive: int = maxi(1, first_wins + second_wins)
	return {
		"first_player_wins": first_wins,
		"second_player_wins": second_wins,
		"draws": draws,
		"first_player_win_rate_decisive": float(first_wins) / float(decisive),
		"second_player_win_rate_decisive": float(second_wins) / float(decisive),
		"draw_rate": float(draws) / float(maxi(1, valid_games)),
	}


func _finalize_profiles(metrics: Dictionary) -> Array:
	var result: Array = []
	for raw_id in metrics.keys():
		var metric: Dictionary = metrics[raw_id]
		var games: int = maxi(1, int(metric.get("games", 0)))
		var finalized: Dictionary = metric.duplicate(true)
		finalized["win_rate"] = float(metric.get("wins", 0)) / float(games)
		finalized["draw_rate"] = float(metric.get("draws", 0)) / float(games)
		finalized["average_score"] = float(metric.get("score_for", 0)) / float(games)
		finalized["average_score_against"] = float(metric.get("score_against", 0)) / float(games)
		var deck_cost: int = maxi(1, int(metric.get("deck_cost", 0)))
		finalized["rank_total_per_cost"] = float(metric.get("deck_rank_total", 0)) / float(deck_cost)
		result.append(finalized)
	result.sort_custom(func(a, b):
		return int(a.get("duel_rank", 0)) < int(b.get("duel_rank", 0))
	)
	return result


func _finalize_cards(metrics: Dictionary) -> Array:
	var result: Array = []
	for raw_id in metrics.keys():
		var metric: Dictionary = metrics[raw_id]
		var finalized: Dictionary = metric.duplicate(true)
		var deck_games: int = maxi(1, int(metric.get("deck_games", 0)))
		var placements: int = maxi(1, int(metric.get("placements", 0)))
		finalized["win_rate_in_deck"] = float(metric.get("deck_wins", 0)) / float(deck_games)
		finalized["play_rate"] = float(metric.get("placements", 0)) / float(deck_games)
		finalized["captures_per_placement"] = float(metric.get("captures", 0)) / float(placements)
		finalized["influence_targets_per_placement"] = float(metric.get("influence_targets", 0)) / float(placements)
		result.append(finalized)
	result.sort_custom(func(a, b):
		if int(a.get("deck_games", 0)) == int(b.get("deck_games", 0)):
			return str(a.get("card_id", "")) < str(b.get("card_id", ""))
		return int(a.get("deck_games", 0)) > int(b.get("deck_games", 0))
	)
	return result


func _authored_deck(profile: Resource, card_catalog: Resource) -> Array:
	var result: Array = []
	if profile == null or card_catalog == null:
		return result
	var raw_ids = profile.get("preferred_deck_ids")
	if not (raw_ids is PackedStringArray or raw_ids is Array):
		return result
	for raw_id in raw_ids:
		var card = card_catalog.call("get_card_by_id", StringName(str(raw_id)))
		if card != null:
			result.append(card)
	return result


func _profile_budget(profile: Resource) -> int:
	if profile == null:
		return 30
	var override_value = profile.get("deck_budget_override")
	if override_value != null and int(override_value) > 0:
		return maxi(5, int(override_value))
	var region: Resource = profile.get("region_profile")
	if region != null:
		var region_budget = region.get("deck_budget")
		if region_budget != null:
			return maxi(5, int(region_budget))
	return 30


func _profile_rules(profile: Resource) -> Resource:
	if profile == null:
		return null
	var override_rules: Resource = profile.get("rule_set_override")
	if override_rules != null:
		return override_rules
	var region: Resource = profile.get("region_profile")
	if region != null:
		var region_rules: Resource = region.get("rule_set")
		if region_rules != null:
			return region_rules
	return null


func _deck_cost(deck: Array) -> int:
	var total: int = 0
	for card in deck:
		if card != null:
			total += int(card.deck_cost)
	return total


func _save_report(report: Dictionary) -> void:
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("TripleTriadBalanceSimulator: could not write %s." % REPORT_PATH)
		return
	file.store_string(JSON.stringify(report, "\t"))


func _failed_report(errors: Array[String]) -> Dictionary:
	return {
		"valid": false,
		"errors": errors,
		"global": {},
		"turn_order_by_host": [],
		"opponents": [],
		"ladder_checks": [],
		"matchups": [],
		"cards": [],
		"report_path": REPORT_PATH,
	}
