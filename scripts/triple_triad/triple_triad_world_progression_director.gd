extends RefCounted
class_name TripleTriadWorldProgressionDirector


func build_snapshot(
	player_snapshot: Dictionary,
	onboarding_snapshot: Dictionary,
	competitive_snapshot: Dictionary,
	completion_snapshot: Dictionary,
	available_opponent_ids
) -> Dictionary:
	var player_rank: int = maxi(1, int(player_snapshot.get("duel_rank", 1)))
	var unlocked: bool = bool(onboarding_snapshot.get("card_game_unlocked", false))
	var collection_complete: bool = bool(completion_snapshot.get("collection_complete", false))
	var campaign_complete: bool = bool(completion_snapshot.get("campaign_complete", false))
	var full_complete: bool = bool(
		completion_snapshot.get("full_card_game_completion", false)
	)

	var available_ids := PackedStringArray()
	if available_opponent_ids is PackedStringArray or available_opponent_ids is Array:
		for raw_id in available_opponent_ids:
			available_ids.append(str(raw_id))

	var active: Dictionary = {}
	var raw_active = competitive_snapshot.get("active", {})
	if raw_active is Dictionary:
		active = (raw_active as Dictionary).duplicate(true)

	var circuits: Array = []
	for raw_circuit in competitive_snapshot.get("circuits", []):
		if raw_circuit is Dictionary:
			circuits.append((raw_circuit as Dictionary).duplicate(true))

	var competitions: Array = []
	for raw_competition in competitive_snapshot.get("competitions", []):
		if raw_competition is Dictionary:
			competitions.append((raw_competition as Dictionary).duplicate(true))

	var incomplete_circuits: Array = []
	var circuit_targets := PackedStringArray()
	for circuit in circuits:
		if bool(circuit.get("complete", false)):
			continue
		incomplete_circuits.append(circuit.duplicate(true))
		for raw_id in circuit.get("remaining_opponent_ids", []):
			var opponent_id: String = str(raw_id)
			if not opponent_id.is_empty() and not circuit_targets.has(opponent_id):
				circuit_targets.append(opponent_id)

	var regional: Dictionary = _competition_by_id(
		competitions,
		"regional_championship"
	)
	var masters: Dictionary = _competition_by_id(
		competitions,
		"masters_cup"
	)

	var phase: StringName = &"regional_circuits"
	var objective_code: StringName = &"clear_regional_circuits"
	var next_competition_id: StringName = &""
	var next_opponent_ids := PackedStringArray()
	var headline: String = "Challenge regional card players."
	var detail: String = ""

	if not unlocked:
		phase = &"discover_cards"
		objective_code = &"find_starter_case"
		headline = "Find your first cards."
		detail = "Recover the Saltworn Card Case through fishing."
	elif full_complete:
		phase = &"full_complete"
		objective_code = &"card_game_complete"
		headline = "Card game complete."
		detail = "Card Master earned and all 179 cards collected."
	elif bool(active.get("active", false)):
		phase = &"active_competition"
		objective_code = &"continue_competition"
		next_competition_id = StringName(str(active.get("competition_id", "")))
		var active_opponent: String = str(active.get("next_opponent_id", ""))
		if not active_opponent.is_empty():
			next_opponent_ids.append(active_opponent)
		headline = "Continue the active tournament."
		detail = str(active.get("display_name", ""))
	elif campaign_complete and not collection_complete:
		phase = &"collection_cleanup"
		objective_code = &"complete_collection"
		headline = "Complete the card collection."
		detail = "%d cards remain." % int(completion_snapshot.get("missing_unique", 0))
	elif not incomplete_circuits.is_empty():
		phase = &"regional_circuits"
		objective_code = &"clear_regional_circuits"
		next_opponent_ids = circuit_targets
		headline = "Clear the regional circuits."
		detail = "%d circuits remain." % incomplete_circuits.size()
	elif int(regional.get("clears", 0)) <= 0:
		next_competition_id = &"regional_championship"
		if bool(regional.get("available", false)):
			phase = &"regional_championship"
			objective_code = &"enter_regional_championship"
			headline = "Enter the Regional Card Championship."
			detail = "The three regional circuits are complete."
		else:
			phase = &"regional_qualification"
			objective_code = &"raise_duel_rank"
			headline = "Qualify for the Regional Championship."
			detail = str(regional.get("reason", "Raise your Duel Rank."))
	elif int(masters.get("clears", 0)) <= 0:
		next_competition_id = &"masters_cup"
		if bool(masters.get("available", false)):
			phase = &"masters_cup"
			objective_code = &"enter_masters_cup"
			headline = "Enter the Masters' Cup."
			detail = "Win the endgame championship to become Card Master."
		else:
			phase = &"masters_qualification"
			objective_code = &"qualify_for_masters"
			headline = "Qualify for the Masters' Cup."
			detail = str(masters.get("reason", "Raise your Duel Rank."))
	elif not collection_complete:
		phase = &"collection_cleanup"
		objective_code = &"complete_collection"
		headline = "Complete the card collection."
		detail = "%d cards remain." % int(completion_snapshot.get("missing_unique", 0))
	else:
		phase = &"campaign_complete"
		objective_code = &"campaign_complete"
		headline = "Card Master."
		detail = "The competitive campaign is complete."

	return {
		"phase": String(phase),
		"objective_code": String(objective_code),
		"headline": headline,
		"detail": detail,
		"duel_rank": player_rank,
		"card_game_unlocked": unlocked,
		"campaign_complete": campaign_complete,
		"collection_complete": collection_complete,
		"full_card_game_completion": full_complete,
		"collection_owned_unique": int(completion_snapshot.get("owned_unique", 0)),
		"collection_total_unique": int(
			completion_snapshot.get("catalog_total_unique", 0)
		),
		"collection_missing_unique": int(completion_snapshot.get("missing_unique", 0)),
		"available_opponent_ids": available_ids,
		"next_opponent_ids": next_opponent_ids,
		"next_competition_id": String(next_competition_id),
		"active_competition": active,
		"incomplete_circuits": incomplete_circuits,
		"available_collection_sources": _available_source_suggestions(
			completion_snapshot.get("source_progress", [])
		),
	}


func _competition_by_id(competitions: Array, competition_id: String) -> Dictionary:
	for competition in competitions:
		if str(competition.get("competition_id", "")) == competition_id:
			return competition.duplicate(true)
	return {}


func _available_source_suggestions(raw_sources) -> Array:
	var result: Array = []
	if not (raw_sources is Array):
		return result
	for raw_source in raw_sources:
		if not (raw_source is Dictionary):
			continue
		var source: Dictionary = raw_source
		if bool(source.get("complete", false)):
			continue
		if not bool(source.get("rank_available", false)):
			continue
		result.append({
			"source_type": str(source.get("source_type", "")),
			"source_id": str(source.get("source_id", "")),
			"display_name": str(source.get("display_name", "")),
			"missing_count": int(source.get("missing_count", 0)),
		})

	result.sort_custom(func(a, b):
		var missing_a: int = int(a.get("missing_count", 0))
		var missing_b: int = int(b.get("missing_count", 0))
		if missing_a == missing_b:
			return str(a.get("display_name", "")) < str(
				b.get("display_name", "")
			)
		return missing_a < missing_b
	)
	if result.size() > 5:
		result.resize(5)
	return result
