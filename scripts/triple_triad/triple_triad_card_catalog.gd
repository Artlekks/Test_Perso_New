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

# Optional shared content source. Triple Triad does not depend on fishing runtime
# services; it only reads portrait/name data from this catalog when present.
@export var supplemental_content_catalog: Resource
@export var include_fish_cards: bool = false

var _cache: Dictionary = {}

# Prototype ranks deliberately use the full 1-6 range. Fish use the same range
# for now; source_kind lets us give them a separate balance curve later without
# changing the card game engine.
const PROTOTYPE_MIN_RANK := 1
const PROTOTYPE_MAX_RANK := 6
const DEFAULT_FISH_LEVEL_SPAN := 3


func get_card(index: int):
	if index < 0 or index >= get_total_source_count():
		return null
	if _cache.has(index):
		return _cache[index]
	var card = _build_card(index)
	_cache[index] = card
	return card


func get_total_source_count() -> int:
	return card_count + _get_fish_entries().size()


func get_cards_for_level_range(min_level: int, max_level: int) -> Array:
	var result: Array = []
	var low: int = clampi(min_level, 1, 10)
	var high: int = clampi(max_level, low, 10)
	for source_index in range(get_total_source_count()):
		if source_index < card_count and disabled_indices.has(source_index):
			continue
		var card = get_card(source_index)
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

	var valid_count: int = 0
	var fish_count: int = 0
	for source_index in range(get_total_source_count()):
		if source_index < card_count and disabled_indices.has(source_index):
			continue
		var card = get_card(source_index)
		if card == null or not card.is_valid_definition():
			errors.append("invalid card %d" % source_index)
			continue
		valid_count += 1
		if card.source_kind == &"fish":
			fish_count += 1

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"card_count": valid_count,
		"fish_card_count": fish_count,
	}


func _build_card(index: int):
	if index < card_count:
		return _build_portrait_card(index)
	return _build_fish_card(index - card_count)


func _build_portrait_card(index: int):
	var card = CardDefinitionScript.new()
	card.card_id = StringName("mugshot_%03d" % index)
	card.display_name = "Portrait %03d" % (index + 1)
	card.source_index = index
	card.source_kind = &"portrait"
	card.level = 1 + (index % 10)
	var ranks: Array[int] = _generate_ranks(index, card.level)
	_assign_ranks(card, ranks)
	card.portrait = _build_portrait_texture(index)
	return card


func _build_fish_card(fish_index: int):
	var fish_entries: Array = _get_fish_entries()
	if fish_index < 0 or fish_index >= fish_entries.size():
		return null
	var fish = fish_entries[fish_index]
	if fish == null:
		return null

	var fish_name: String = str(fish.get("fish_name")).strip_edges()
	var species_id: String = ""
	if fish.has_method("get_stable_species_id"):
		species_id = str(fish.call("get_stable_species_id")).strip_edges().to_lower()
	if species_id.is_empty():
		species_id = fish_name.to_snake_case()

	var card = CardDefinitionScript.new()
	card.card_id = StringName("fish_%s" % species_id)
	card.display_name = fish_name if not fish_name.is_empty() else "Fish %02d" % (fish_index + 1)
	card.source_index = fish_index
	card.source_kind = &"fish"
	card.level = 1 + (fish_index % DEFAULT_FISH_LEVEL_SPAN)
	var ranks: Array[int] = _generate_ranks(card_count + fish_index + 4096, card.level)
	_assign_ranks(card, ranks)
	var fish_portrait = fish.get("portrait")
	if fish_portrait is Texture2D:
		card.portrait = fish_portrait
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


func _get_fish_entries() -> Array:
	if not include_fish_cards or supplemental_content_catalog == null:
		return []
	var raw_fish = supplemental_content_catalog.get("fish")
	if raw_fish is Array:
		return raw_fish
	return []


func _assign_ranks(card, ranks: Array[int]) -> void:
	card.top_rank = ranks[0]
	card.right_rank = ranks[1]
	card.bottom_rank = ranks[2]
	card.left_rank = ranks[3]


func _generate_ranks(index: int, level: int) -> Array[int]:
	var state: int = _next_state((index + 1) * 7919 + level * 104729)
	var ranks: Array[int] = []
	for _side_index in range(4):
		state = _next_state(state)
		ranks.append(PROTOTYPE_MIN_RANK + posmod(state, PROTOTYPE_MAX_RANK - PROTOTYPE_MIN_RANK + 1))
	return ranks


func _next_state(value: int) -> int:
	return int((value * 1103515245 + 12345) & 0x7fffffff)
