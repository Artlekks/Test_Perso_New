extends Resource

@export var card_id: StringName = &""
@export var display_name: String = "Card"
@export_range(1, 10, 1) var level: int = 1
@export_range(1, 10, 1) var deck_cost: int = 1
@export_range(1, 10, 1) var top_rank: int = 1
@export_range(1, 10, 1) var right_rank: int = 1
@export_range(1, 10, 1) var bottom_rank: int = 1
@export_range(1, 10, 1) var left_rank: int = 1
@export var portrait: Texture2D
@export var source_index: int = -1
@export var source_kind: StringName = &"portrait"
@export var group_id: StringName = &""
@export var tags: PackedStringArray = PackedStringArray()
@export var rarity_id: StringName = &"standard"
@export_range(1, 10, 1) var required_player_rank: int = 1
@export var acquisition_tags: PackedStringArray = PackedStringArray()


func strength_points() -> int:
	# Deck points are currently the authoritative strength/economy value.
	# Keeping this method on the definition means UI/AI code does not need to know
	# where that value came from.
	return deck_cost


func is_usable_at_player_rank(player_rank: int) -> bool:
	return maxi(1, player_rank) >= required_player_rank


func has_acquisition_tag(tag: StringName) -> bool:
	var wanted: String = String(tag).strip_edges().to_lower()
	if wanted.is_empty():
		return false
	for raw_tag in acquisition_tags:
		if str(raw_tag).strip_edges().to_lower() == wanted:
			return true
	return false


func rank_for_side(side: int) -> int:
	match side:
		0:
			return top_rank
		1:
			return right_rank
		2:
			return bottom_rank
		3:
			return left_rank
		_:
			return 0


func rank_for_side_rotated(side: int, quarter_turns_clockwise: int) -> int:
	# Rotating the card clockwise moves its original top value to the right,
	# so the value currently facing a side comes from side - rotation.
	var source_side: int = posmod(side - posmod(quarter_turns_clockwise, 4), 4)
	return rank_for_side(source_side)


func rank_total() -> int:
	return top_rank + right_rank + bottom_rank + left_rank


func is_valid_definition() -> bool:
	return (
		not String(card_id).is_empty()
		and not String(source_kind).is_empty()
		and level >= 1
		and level <= 10
		and deck_cost >= 1
		and deck_cost <= 10
		and top_rank >= 1
		and top_rank <= 10
		and right_rank >= 1
		and right_rank <= 10
		and bottom_rank >= 1
		and bottom_rank <= 10
		and left_rank >= 1
		and left_rank <= 10
		and required_player_rank >= 1
		and required_player_rank <= 10
		and not String(rarity_id).strip_edges().is_empty()
		and portrait != null
	)
