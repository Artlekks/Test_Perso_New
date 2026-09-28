extends Resource

@export var card_id: StringName = &""
@export var display_name: String = "Card"
@export_range(1, 10, 1) var level: int = 1
@export_range(1, 10, 1) var top_rank: int = 1
@export_range(1, 10, 1) var right_rank: int = 1
@export_range(1, 10, 1) var bottom_rank: int = 1
@export_range(1, 10, 1) var left_rank: int = 1
@export var portrait: Texture2D
@export var source_index: int = -1
@export var source_kind: StringName = &"portrait"


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


func rank_total() -> int:
	return top_rank + right_rank + bottom_rank + left_rank


func is_valid_definition() -> bool:
	return (
		not String(card_id).is_empty()
		and not String(source_kind).is_empty()
		and level >= 1
		and level <= 10
		and top_rank >= 1
		and top_rank <= 10
		and right_rank >= 1
		and right_rank <= 10
		and bottom_rank >= 1
		and bottom_rank <= 10
		and left_rank >= 1
		and left_rank <= 10
		and portrait != null
	)
