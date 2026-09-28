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

# Prototype rank range. We keep the card level field for future collection/progression,
# but the current playable slice deliberately uses the full 1-6 range uniformly.
const PROTOTYPE_MIN_RANK := 1
const PROTOTYPE_MAX_RANK := 6



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
	var state: int = _next_state((index + 1) * 7919 + level * 104729)
	var ranks: Array[int] = []
	for _side_index in range(4):
		state = _next_state(state)
		ranks.append(PROTOTYPE_MIN_RANK + posmod(state, PROTOTYPE_MAX_RANK - PROTOTYPE_MIN_RANK + 1))
	return ranks


func _next_state(value: int) -> int:
	return int((value * 1103515245 + 12345) & 0x7fffffff)
