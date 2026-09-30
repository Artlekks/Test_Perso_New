extends Resource
class_name TripleTriadProgressionCatalog

@export_category("Global")
@export_range(1, 999999, 1)
var max_duel_points: int = 9999

@export_category("Ranks")
## Keep authored in ascending min_points order.
@export var ranks: Array[TripleTriadRankDefinition] = []


func is_valid_catalog() -> bool:
	if max_duel_points <= 0 or ranks.is_empty():
		return false

	var previous_min: int = -1
	var previous_budget_bonus: int = -1
	var seen_ids: Dictionary = {}
	var seen_names: Dictionary = {}

	for index in range(ranks.size()):
		var rank: TripleTriadRankDefinition = ranks[index]
		if rank == null or not rank.is_valid_definition():
			return false

		if index == 0 and rank.min_points != 0:
			return false
		if index > 0 and rank.min_points <= previous_min:
			return false
		if rank.min_points > max_duel_points:
			return false

		# Rank progression must never lower the deck budget.
		if rank.deck_budget_bonus < previous_budget_bonus:
			return false

		var id_key: String = str(rank.rank_id).strip_edges().to_lower()
		var name_key: String = rank.display_name.strip_edges().to_lower()
		if seen_ids.has(id_key) or seen_names.has(name_key):
			return false
		seen_ids[id_key] = true
		seen_names[name_key] = true

		previous_min = rank.min_points
		previous_budget_bonus = rank.deck_budget_bonus

	return true


func clamp_points(points: int) -> int:
	return clampi(points, 0, maxi(max_duel_points, 1))


func get_rank_count() -> int:
	return ranks.size()


func get_rank_index(points: int) -> int:
	if ranks.is_empty():
		return 0

	var value: int = clamp_points(points)
	var index: int = 0
	for candidate_index in range(ranks.size()):
		var rank: TripleTriadRankDefinition = ranks[candidate_index]
		if rank == null:
			continue
		if value < rank.min_points:
			break
		index = candidate_index
	return index


func get_rank(points: int) -> TripleTriadRankDefinition:
	if ranks.is_empty():
		return null
	return ranks[clampi(get_rank_index(points), 0, ranks.size() - 1)]


func get_rank_name(points: int) -> String:
	var rank: TripleTriadRankDefinition = get_rank(points)
	return "" if rank == null else rank.display_name


func get_rank_id(points: int) -> StringName:
	var rank: TripleTriadRankDefinition = get_rank(points)
	return &"" if rank == null else rank.rank_id


func get_deck_budget(base_budget: int, points: int) -> int:
	var rank: TripleTriadRankDefinition = get_rank(points)
	var bonus: int = 0 if rank == null else maxi(rank.deck_budget_bonus, 0)
	return maxi(5, base_budget + bonus)


func get_next_rank_threshold(points: int) -> int:
	if ranks.is_empty():
		return maxi(max_duel_points, 1)

	var current_index: int = get_rank_index(points)
	if current_index >= ranks.size() - 1:
		return -1

	var next_rank: TripleTriadRankDefinition = ranks[current_index + 1]
	return -1 if next_rank == null else next_rank.min_points


func get_rank_progress(points: int) -> Dictionary:
	if ranks.is_empty():
		return {
			"index": 0,
			"id": "",
			"name": "",
			"points": 0,
			"current_min": 0,
			"next_threshold": -1,
			"is_max_rank": true,
			"points_into_rank": 0,
			"rank_span_points": 1,
			"points_to_next": 0,
			"progress_ratio": 0.0,
			"deck_budget_bonus": 0,
			"max_duel_points": maxi(max_duel_points, 1),
		}

	var value: int = clamp_points(points)
	var index: int = get_rank_index(value)
	var current_rank: TripleTriadRankDefinition = ranks[index]
	var is_max_rank: bool = index >= ranks.size() - 1
	var next_threshold: int = get_next_rank_threshold(value)
	var span_end: int = max_duel_points if is_max_rank else next_threshold
	var span_size: int = maxi(span_end - current_rank.min_points, 1)
	var points_into_rank: int = clampi(
		value - current_rank.min_points,
		0,
		span_size
	)

	return {
		"index": index,
		"id": str(current_rank.rank_id),
		"name": current_rank.display_name,
		"points": value,
		"current_min": current_rank.min_points,
		"next_threshold": next_threshold,
		"is_max_rank": is_max_rank,
		"points_into_rank": points_into_rank,
		"rank_span_points": span_size,
		"points_to_next": (
			maxi(span_end - value, 0)
			if not is_max_rank
			else 0
		),
		"progress_ratio": clampf(
			float(points_into_rank) / float(span_size),
			0.0,
			1.0
		),
		"deck_budget_bonus": current_rank.deck_budget_bonus,
		"max_duel_points": max_duel_points,
	}


func get_crossed_ranks(from_points: int, to_points: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if ranks.is_empty():
		return result

	var from_value: int = clamp_points(from_points)
	var to_value: int = clamp_points(to_points)
	if to_value <= from_value:
		return result

	var from_index: int = get_rank_index(from_value)
	var to_index: int = get_rank_index(to_value)
	if to_index <= from_index:
		return result

	for index in range(from_index + 1, to_index + 1):
		var rank: TripleTriadRankDefinition = ranks[index]
		if rank == null:
			continue
		result.append({
			"index": index,
			"id": str(rank.rank_id),
			"name": rank.display_name,
			"threshold": rank.min_points,
			"deck_budget_bonus": rank.deck_budget_bonus,
		})

	return result
