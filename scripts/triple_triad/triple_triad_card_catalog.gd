extends Resource

const CardDefinitionScript = preload("res://scripts/triple_triad/triple_triad_card_definition.gd")

@export var portrait_atlas: Texture2D
@export_range(1, 64, 1) var columns: int = 16
@export_range(1, 64, 1) var rows: int = 16
@export_range(1, 256, 1) var cell_stride_x: int = 44
@export_range(1, 256, 1) var cell_stride_y: int = 52
@export_range(1, 256, 1) var portrait_width: int = 40
@export_range(1, 256, 1) var portrait_height: int = 48
@export var origin: Vector2i = Vector2i(4, 4)
@export_range(1, 4096, 1) var card_count: int = 256
@export var disabled_indices: PackedInt32Array = PackedInt32Array()

var _cache: Dictionary = {}

# FFVIII-inspired card-level envelopes. The portrait art is BOF4, but the rank
# totals/maxima follow the original Triple Triad level bands for prototype balance.
const LEVEL_BANDS := {
	1: {"min_total": 10, "max_total": 13, "max_side": 6},
	2: {"min_total": 12, "max_total": 15, "max_side": 7},
	3: {"min_total": 16, "max_total": 18, "max_side": 7},
	4: {"min_total": 17, "max_total": 20, "max_side": 7},
	5: {"min_total": 20, "max_total": 22, "max_side": 7},
	6: {"min_total": 20, "max_total": 23, "max_side": 8},
	7: {"min_total": 23, "max_total": 26, "max_side": 8},
	8: {"min_total": 23, "max_total": 26, "max_side": 9},
	9: {"min_total": 24, "max_total": 27, "max_side": 10},
	10: {"min_total": 26, "max_total": 29, "max_side": 10},
}


func get_card(index: int):
	if index < 0 or index >= card_count:
		return null
	if _cache.has(index):
		return _cache[index]
	var card = _build_card(index)
	_cache[index] = card
	return card


func get_cards_for_level_range(min_level: int, max_level: int) -> Array:
	var result: Array = []
	var low: int = clampi(min_level, 1, 10)
	var high: int = clampi(max_level, low, 10)
	for card_index in range(card_count):
		if disabled_indices.has(card_index):
			continue
		var card = get_card(card_index)
		if card == null:
			continue
		if card.level >= low and card.level <= high:
			result.append(card)
	return result


func build_random_hand(rng: RandomNumberGenerator, min_level: int = 1, max_level: int = 3, hand_size: int = 5) -> Array:
	var pool: Array = get_cards_for_level_range(min_level, max_level)
	var result: Array = []
	if pool.is_empty():
		return result
	var available: Array = pool.duplicate()
	var desired_count: int = mini(hand_size, available.size())
	for _draw_index in range(desired_count):
		var pick_index: int = rng.randi_range(0, available.size() - 1)
		result.append(available[pick_index])
		available.remove_at(pick_index)
	return result


func validate_catalog() -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	if portrait_atlas == null:
		errors.append("portrait atlas is missing")
	if card_count <= 0 or card_count > columns * rows:
		errors.append("card_count exceeds configured atlas grid")
	for card_index in range(card_count):
		if disabled_indices.has(card_index):
			continue
		var card = get_card(card_index)
		if card == null or not card.is_valid_definition():
			errors.append("invalid card %d" % card_index)
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"card_count": card_count - disabled_indices.size(),
	}


func _build_card(index: int):
	var card = CardDefinitionScript.new()
	card.card_id = StringName("mugshot_%03d" % index)
	card.display_name = "Portrait %03d" % (index + 1)
	card.source_index = index
	card.level = 1 + (index % 10)
	var ranks: Array[int] = _generate_ranks(index, card.level)
	card.top_rank = ranks[0]
	card.right_rank = ranks[1]
	card.bottom_rank = ranks[2]
	card.left_rank = ranks[3]
	card.portrait = _build_portrait_texture(index)
	return card


func _build_portrait_texture(index: int) -> Texture2D:
	var column: int = index % columns
	var row: int = floori(float(index) / float(columns))
	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = portrait_atlas
	atlas_texture.region = Rect2(
		origin.x + column * cell_stride_x,
		origin.y + row * cell_stride_y,
		portrait_width,
		portrait_height
	)
	return atlas_texture


func _generate_ranks(index: int, level: int) -> Array[int]:
	var band: Dictionary = LEVEL_BANDS[level]
	var min_total: int = int(band["min_total"])
	var max_total: int = int(band["max_total"])
	var max_side: int = int(band["max_side"])
	var state: int = _next_state((index + 1) * 7919 + level * 104729)
	var target_total: int = min_total + posmod(state, max_total - min_total + 1)
	var ranks: Array[int] = [1, 1, 1, 1]
	var remaining: int = target_total - 4
	var safety: int = 0
	while remaining > 0 and safety < 256:
		state = _next_state(state)
		var side_index: int = posmod(state, 4)
		if ranks[side_index] < max_side:
			ranks[side_index] += 1
			remaining -= 1
		safety += 1
	return ranks


func _next_state(value: int) -> int:
	return int((value * 1103515245 + 12345) & 0x7fffffff)
