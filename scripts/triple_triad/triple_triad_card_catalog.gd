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
@export var stable_portrait_ids: PackedInt32Array = PackedInt32Array()
@export var legacy_portrait_ids: PackedInt32Array = PackedInt32Array()
@export_file("*.json") var card_stats_path: String = "res://data/triple_triad/card_stats.json"
@export var require_authored_portrait_stats: bool = true

# Optional shared content source. Triple Triad does not depend on fishing runtime
# services; it only reads portrait/name data from this catalog when present.
@export var supplemental_content_catalog: Resource
@export var include_fish_cards: bool = false

var _cache: Dictionary = {}
var _id_cache: Dictionary = {}
var _id_cache_complete: bool = false
var _card_stats_loaded: bool = false
var _card_stats_by_id: Dictionary = {}
var _card_stats_errors: PackedStringArray = PackedStringArray()

# Prototype ranks deliberately use the full 1-6 range. Fish remain supported by
# the backend, but are disabled in the current catalog while the card art is
# portrait-only.
const PROTOTYPE_MIN_RANK := 1
const PROTOTYPE_MAX_RANK := 6
const DEFAULT_FISH_LEVEL_SPAN := 3
const BUDGET_SEARCH_ATTEMPTS := 180


func reload_authored_stats() -> void:
	_card_stats_loaded = false
	_card_stats_by_id.clear()
	_card_stats_errors.clear()
	_cache.clear()
	_id_cache.clear()
	_id_cache_complete = false
	_ensure_card_stats_loaded()


func get_authored_stats(card_id: StringName) -> Dictionary:
	_ensure_card_stats_loaded()
	var key: String = String(card_id)
	if not _card_stats_by_id.has(key):
		return {}
	var entry: Dictionary = _card_stats_by_id[key]
	return entry.duplicate(true)


func _ensure_card_stats_loaded() -> void:
	if _card_stats_loaded:
		return
	_card_stats_loaded = true
	_card_stats_by_id.clear()
	_card_stats_errors.clear()

	if card_stats_path.strip_edges().is_empty():
		_card_stats_errors.append("card_stats_path is empty")
		return
	if not FileAccess.file_exists(card_stats_path):
		_card_stats_errors.append("card stats file is missing: %s" % card_stats_path)
		return

	var file := FileAccess.open(card_stats_path, FileAccess.READ)
	if file == null:
		_card_stats_errors.append("could not open card stats file: %s" % card_stats_path)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_card_stats_errors.append("card stats root must be a Dictionary")
		return
	var root: Dictionary = parsed
	var schema_version: int = int(root.get("schema_version", 0))
	if schema_version not in [1, 2, 3]:
		_card_stats_errors.append("unsupported card stats schema_version")
	var raw_cards = root.get("cards", [])
	if typeof(raw_cards) != TYPE_ARRAY:
		_card_stats_errors.append("card stats cards field must be an Array")
		return

	for raw_entry in raw_cards:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			_card_stats_errors.append("card stats contains a non-Dictionary entry")
			continue
		var entry: Dictionary = raw_entry
		var card_id: String = str(entry.get("card_id", "")).strip_edges()
		if card_id.is_empty():
			_card_stats_errors.append("card stats entry has an empty card_id")
			continue
		if _card_stats_by_id.has(card_id):
			_card_stats_errors.append("duplicate authored card_id: %s" % card_id)
			continue
		_card_stats_by_id[card_id] = entry.duplicate(true)


func _stable_portrait_id(index: int) -> int:
	if index >= 0 and index < stable_portrait_ids.size():
		return int(stable_portrait_ids[index])
	return index


func _apply_authored_stats(card) -> bool:
	_ensure_card_stats_loaded()
	var key: String = String(card.card_id)
	if not _card_stats_by_id.has(key):
		return false
	var entry: Dictionary = _card_stats_by_id[key]

	var authored_name: String = str(entry.get("display_name", card.display_name)).strip_edges()
	if not authored_name.is_empty():
		card.display_name = authored_name
	card.level = clampi(int(entry.get("level", card.level)), 1, 10)
	card.deck_cost = clampi(int(entry.get("points", card.deck_cost)), 1, 10)
	card.group_id = StringName(str(entry.get("group", "")).strip_edges())
	card.rarity_id = StringName(
		str(entry.get("rarity", "standard")).strip_edges()
	)
	if String(card.rarity_id).is_empty():
		card.rarity_id = &"standard"
	card.required_player_rank = clampi(
		int(entry.get("required_player_rank", 1)),
		1,
		10
	)

	var raw_acquisition_tags = entry.get("acquisition_tags", [])
	var parsed_acquisition_tags := PackedStringArray()
	if typeof(raw_acquisition_tags) == TYPE_ARRAY:
		for raw_tag in raw_acquisition_tags:
			var acquisition_tag: String = str(raw_tag).strip_edges()
			if not acquisition_tag.is_empty():
				parsed_acquisition_tags.append(acquisition_tag)
	card.acquisition_tags = parsed_acquisition_tags

	card.influence_mode = &"none"
	card.influence_strength = 0
	card.influence_offsets.clear()
	var raw_influence = entry.get("influence", {})
	if typeof(raw_influence) == TYPE_DICTIONARY:
		var influence: Dictionary = raw_influence
		var mode: String = str(influence.get("mode", "none")).strip_edges().to_lower()
		if mode == "pressure":
			card.influence_mode = &"pressure"
			card.influence_strength = clampi(int(influence.get("strength", 1)), 1, 2)
			var raw_offsets = influence.get("offsets", [])
			if typeof(raw_offsets) == TYPE_ARRAY:
				for raw_offset in raw_offsets:
					if typeof(raw_offset) != TYPE_ARRAY or raw_offset.size() != 2:
						continue
					var offset := Vector2i(int(raw_offset[0]), int(raw_offset[1]))
					if offset != Vector2i.ZERO and not card.influence_offsets.has(offset):
						card.influence_offsets.append(offset)

	var raw_tags = entry.get("tags", [])
	var parsed_tags := PackedStringArray()
	if typeof(raw_tags) == TYPE_ARRAY:
		for raw_tag in raw_tags:
			var tag: String = str(raw_tag).strip_edges()
			if not tag.is_empty():
				parsed_tags.append(tag)
	card.tags = parsed_tags

	var raw_ranks = entry.get("ranks", {})
	if typeof(raw_ranks) == TYPE_DICTIONARY:
		var ranks: Dictionary = raw_ranks
		card.top_rank = clampi(int(ranks.get("top", card.top_rank)), 1, 10)
		card.right_rank = clampi(int(ranks.get("right", card.right_rank)), 1, 10)
		card.bottom_rank = clampi(int(ranks.get("bottom", card.bottom_rank)), 1, 10)
		card.left_rank = clampi(int(ranks.get("left", card.left_rank)), 1, 10)
	return true


func _validate_authored_entry(card_id: String, entry: Dictionary, errors: PackedStringArray) -> void:
	var level: int = int(entry.get("level", 0))
	var points: int = int(entry.get("points", 0))
	var required_player_rank: int = int(entry.get("required_player_rank", 1))
	var rarity: String = str(entry.get("rarity", "standard")).strip_edges()
	if level < 1 or level > 10:
		errors.append("%s has invalid level %d" % [card_id, level])
	if points < 1 or points > 10:
		errors.append("%s has invalid points %d" % [card_id, points])
	if required_player_rank < 1 or required_player_rank > 10:
		errors.append(
			"%s has invalid required_player_rank %d"
			% [card_id, required_player_rank]
		)
	if rarity.is_empty():
		errors.append("%s has an empty rarity" % card_id)
	var raw_influence = entry.get("influence", {})
	if typeof(raw_influence) == TYPE_DICTIONARY and not raw_influence.is_empty():
		var influence: Dictionary = raw_influence
		var influence_mode: String = str(influence.get("mode", "none")).strip_edges().to_lower()
		if influence_mode not in ["none", "pressure"]:
			errors.append("%s has unsupported influence mode %s" % [card_id, influence_mode])
		if influence_mode == "pressure":
			var strength: int = int(influence.get("strength", 0))
			if strength < 1 or strength > 2:
				errors.append("%s has invalid influence strength %d" % [card_id, strength])
			var offsets = influence.get("offsets", [])
			if typeof(offsets) != TYPE_ARRAY or offsets.is_empty():
				errors.append("%s pressure influence has no offsets" % card_id)
			else:
				var seen_offsets: Dictionary = {}
				for raw_offset in offsets:
					if typeof(raw_offset) != TYPE_ARRAY or raw_offset.size() != 2:
						errors.append("%s has malformed influence offset" % card_id)
						continue
					var x: int = int(raw_offset[0])
					var y: int = int(raw_offset[1])
					if x == 0 and y == 0:
						errors.append("%s influence cannot target its own cell" % card_id)
					if absi(x) > 2 or absi(y) > 2:
						errors.append("%s influence offset is outside prototype bounds" % card_id)
					var key: String = "%d,%d" % [x, y]
					if seen_offsets.has(key):
						errors.append("%s has duplicate influence offset %s" % [card_id, key])
					seen_offsets[key] = true
	var raw_ranks = entry.get("ranks", {})
	if typeof(raw_ranks) != TYPE_DICTIONARY:
		errors.append("%s is missing ranks" % card_id)
		return
	var ranks: Dictionary = raw_ranks
	for side_name in ["top", "right", "bottom", "left"]:
		var value: int = int(ranks.get(side_name, 0))
		if value < 1 or value > 10:
			errors.append("%s has invalid %s rank %d" % [card_id, side_name, value])


func get_card(index: int):
	if index < 0 or index >= get_total_source_count():
		return null
	if _cache.has(index):
		var cached = _cache[index]
		_register_card_id(cached)
		return cached
	var card = _build_card(index)
	_cache[index] = card
	_register_card_id(card)
	return card


func get_card_by_id(card_id: StringName):
	var wanted: String = String(card_id)
	if wanted.is_empty():
		return null
	if _id_cache.has(wanted):
		return _id_cache[wanted]
	_ensure_id_cache()
	return _id_cache.get(wanted, null)


func _register_card_id(card) -> void:
	if card == null:
		return
	var key: String = String(card.card_id)
	if not key.is_empty():
		_id_cache[key] = card


func _ensure_id_cache() -> void:
	if _id_cache_complete:
		return
	for source_index in range(get_total_source_count()):
		get_card(source_index)
	_id_cache_complete = true


func get_card_by_legacy_source_index(legacy_index: int):
	if legacy_index < 0:
		return null
	if legacy_index < legacy_portrait_ids.size():
		var stable_id: int = int(legacy_portrait_ids[legacy_index])
		return get_card_by_id(StringName("mugshot_%03d" % stable_id))
	# Pre-compaction saves used the original source index directly.
	return get_card_by_id(StringName("mugshot_%03d" % legacy_index))


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


func get_cards_for_player_rank(player_rank: int) -> Array:
	var result: Array = []
	var clean_rank: int = maxi(1, player_rank)
	for source_index in range(get_total_source_count()):
		if source_index < card_count and disabled_indices.has(source_index):
			continue
		var card = get_card(source_index)
		if card == null:
			continue
		if card.has_method("is_usable_at_player_rank"):
			if not bool(card.call("is_usable_at_player_rank", clean_rank)):
				continue
		result.append(card)
	return result


func get_cards_with_acquisition_tag(
	tag: StringName,
	player_rank: int = 10
) -> Array:
	var result: Array = []
	var clean_rank: int = maxi(1, player_rank)
	for card in get_cards_for_player_rank(clean_rank):
		if card != null and card.has_method("has_acquisition_tag"):
			if bool(card.call("has_acquisition_tag", tag)):
				result.append(card)
	return result


func build_random_hand(rng: RandomNumberGenerator, min_level: int = 1, max_level: int = 3, hand_size: int = 5) -> Array:
	var pool: Array = get_cards_for_level_range(min_level, max_level)
	return _draw_unique_cards(rng, pool, hand_size)


func build_budgeted_hand(
	rng: RandomNumberGenerator,
	min_level: int = 1,
	max_level: int = 3,
	hand_size: int = 5,
	deck_budget: int = 30
) -> Array:
	var pool: Array = get_cards_for_level_range(min_level, max_level)
	if pool.size() < hand_size:
		return []
	if pool.size() == hand_size:
		return pool.duplicate() if get_hand_cost(pool) <= deck_budget else []

	var best_hand: Array = []
	var best_cost: int = -1
	for _attempt in range(BUDGET_SEARCH_ATTEMPTS):
		var candidate: Array = _draw_unique_cards(rng, pool, hand_size)
		if candidate.size() != hand_size:
			continue
		var candidate_cost: int = get_hand_cost(candidate)
		if candidate_cost <= deck_budget:
			# Prefer a hand that actually uses the available budget instead of always
			# settling for the first cheap combination we happen to roll.
			if candidate_cost > best_cost:
				best_hand = candidate
				best_cost = candidate_cost
			if candidate_cost == deck_budget:
				return candidate

	if not best_hand.is_empty():
		return best_hand

	# A very restrictive future region should still produce a legal five-card
	# hand when possible: fall back to the cheapest available cards.
	var cheapest: Array = pool.duplicate()
	cheapest.sort_custom(func(a, b):
		if int(a.deck_cost) == int(b.deck_cost):
			return int(a.rank_total()) < int(b.rank_total())
		return int(a.deck_cost) < int(b.deck_cost)
	)
	var fallback: Array = []
	for index in range(mini(hand_size, cheapest.size())):
		fallback.append(cheapest[index])
	if fallback.size() != hand_size or get_hand_cost(fallback) > deck_budget:
		return []
	return fallback


func get_hand_cost(cards: Array) -> int:
	var total: int = 0
	for card in cards:
		if card != null:
			total += int(card.deck_cost)
	return total


func is_hand_within_budget(cards: Array, deck_budget: int, required_size: int = 5) -> bool:
	return cards.size() == required_size and get_hand_cost(cards) <= deck_budget


func validate_catalog() -> Dictionary:
	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()
	_ensure_card_stats_loaded()
	for stats_error in _card_stats_errors:
		errors.append(str(stats_error))
	if portrait_atlas == null:
		errors.append("portrait atlas is missing")
	if card_count <= 0 or card_count > columns * rows:
		errors.append("card_count exceeds configured atlas grid")
	if not stable_portrait_ids.is_empty() and stable_portrait_ids.size() != card_count:
		errors.append("stable portrait id count does not match card_count")

	var expected_portrait_ids: Dictionary = {}
	for portrait_index in range(card_count):
		var expected_id: String = "mugshot_%03d" % _stable_portrait_id(portrait_index)
		expected_portrait_ids[expected_id] = true
		if require_authored_portrait_stats and not _card_stats_by_id.has(expected_id):
			errors.append("missing authored stats for %s" % expected_id)
	for raw_id in _card_stats_by_id.keys():
		var authored_id: String = str(raw_id)
		var authored_entry: Dictionary = _card_stats_by_id[authored_id]
		_validate_authored_entry(authored_id, authored_entry, errors)
		if authored_id.begins_with("mugshot_") and not expected_portrait_ids.has(authored_id):
			warnings.append("authored stats references inactive portrait %s" % authored_id)

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
		"warnings": warnings,
		"authored_stats_count": _card_stats_by_id.size(),
		"card_count": valid_count,
		"fish_card_count": fish_count,
	}


func _build_card(index: int):
	if index < card_count:
		return _build_portrait_card(index)
	return _build_fish_card(index - card_count)


func _build_portrait_card(index: int):
	var stable_id: int = _stable_portrait_id(index)

	var card = CardDefinitionScript.new()
	card.card_id = StringName("mugshot_%03d" % stable_id)
	card.display_name = "Portrait %03d" % (stable_id + 1)
	card.source_index = index
	card.source_kind = &"portrait"
	card.level = 1 + (stable_id % 10)
	var ranks: Array[int] = _generate_ranks(stable_id, card.level)
	_assign_ranks(card, ranks)
	card.deck_cost = _cost_from_ranks(card.rank_total())
	_apply_authored_stats(card)
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
	card.deck_cost = _cost_from_ranks(card.rank_total())
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


func _cost_from_ranks(rank_total: int) -> int:
	# Prototype cost is intentionally strength-based, not rarity-based. Real card
	# definitions can override this later. Current generated cards span roughly
	# 2-9 points, leaving room for hand-authored 10-point legendary cards.
	var normalized: float = remap(float(rank_total), 4.0, 24.0, 1.0, 10.0)
	return clampi(roundi(normalized), 1, 10)


func _draw_unique_cards(rng: RandomNumberGenerator, pool: Array, hand_size: int) -> Array:
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


func _generate_ranks(index: int, level: int) -> Array[int]:
	var state: int = _next_state((index + 1) * 7919 + level * 104729)
	var ranks: Array[int] = []
	for _side_index in range(4):
		state = _next_state(state)
		ranks.append(PROTOTYPE_MIN_RANK + posmod(state, PROTOTYPE_MAX_RANK - PROTOTYPE_MIN_RANK + 1))
	return ranks


func _next_state(value: int) -> int:
	return int((value * 1103515245 + 12345) & 0x7fffffff)
