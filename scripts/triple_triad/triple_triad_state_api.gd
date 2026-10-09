extends RefCounted
class_name TripleTriadStateAPI

const API_SCHEMA_VERSION := 6

const DECKS_PATH := "user://triple_triad_decks.cfg"
const OPPONENT_COLLECTIONS_PATH := "user://triple_triad_opponents.cfg"
const DeckStore = preload("res://scripts/triple_triad/triple_triad_deck_store.gd")
const HAND_SIZE := 5

var _catalog: Resource = null
var _collection = null
var _progression = null
var _opponent_registry: Resource = null
var _encounter_records = null
var _acquisition_tracker = null
var _acquisition_service = null
var _acquisition_policy: Resource = null
var _world_acquisition_catalog = null
var _base_player_budget: int = 30

var _deck_config = null
var _deck_config_loaded: bool = false
var _opponent_config = null
var _opponent_config_loaded: bool = false

var _player_cache: Dictionary = {}
var _player_cache_valid: bool = false
var _collection_cache: Array = []
var _collection_cache_valid: bool = false
var _deck_cache: Array = []
var _deck_cache_valid: bool = false
var _opponent_cache: Dictionary = {}
var _all_opponents_cache: Array = []
var _all_opponents_cache_valid: bool = false


func initialize(
	catalog: Resource,
	collection,
	progression,
	opponent_registry: Resource,
	encounter_records,
	acquisition_tracker,
	acquisition_service,
	acquisition_policy: Resource,
	world_acquisition_catalog,
	base_player_budget: int = 30
) -> void:
	_catalog = catalog
	_collection = collection
	_progression = progression
	_opponent_registry = opponent_registry
	_encounter_records = encounter_records
	_acquisition_tracker = acquisition_tracker
	_acquisition_service = acquisition_service
	_acquisition_policy = acquisition_policy
	_world_acquisition_catalog = world_acquisition_catalog
	_base_player_budget = maxi(5, base_player_budget)
	invalidate("initialize")


func invalidate(_reason: String = "") -> void:
	_deck_config = null
	_deck_config_loaded = false
	_opponent_config = null
	_opponent_config_loaded = false
	_player_cache.clear()
	_player_cache_valid = false
	_collection_cache.clear()
	_collection_cache_valid = false
	_deck_cache.clear()
	_deck_cache_valid = false
	_opponent_cache.clear()
	_all_opponents_cache.clear()
	_all_opponents_cache_valid = false


func get_schema_version() -> int:
	return API_SCHEMA_VERSION


func get_player_snapshot() -> Dictionary:
	if not _player_cache_valid:
		_player_cache = _build_player_snapshot()
		_player_cache_valid = true
	return _player_cache.duplicate(true)


func get_acquisition_snapshot() -> Dictionary:
	return _acquisition_snapshot().duplicate(true)


func get_acquisition_sources_snapshot() -> Array:
	if (
		_world_acquisition_catalog == null
		or not _world_acquisition_catalog.has_method("get_all_source_snapshots")
	):
		return []
	return _world_acquisition_catalog.call("get_all_source_snapshots")


func get_card_acquisition_sources(card_id: StringName) -> Array:
	if (
		_world_acquisition_catalog == null
		or not _world_acquisition_catalog.has_method("get_sources_for_card")
	):
		return []
	return _world_acquisition_catalog.call("get_sources_for_card", card_id)


func get_available_opponents_snapshot() -> Array:
	var result: Array = []
	for snapshot in get_all_opponents_snapshot():
		if snapshot is Dictionary and bool(snapshot.get("available", false)):
			result.append(snapshot)
	return result


func get_collection_snapshot() -> Array:
	if not _collection_cache_valid:
		_collection_cache = _build_collection_snapshot()
		_collection_cache_valid = true
	return _collection_cache.duplicate(true)


func get_card_snapshot(card_id: StringName) -> Dictionary:
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		return {}
	var card = _catalog.call("get_card_by_id", card_id)
	if card == null:
		return {}
	return _card_snapshot(card, _quantity_for_card(card_id), _player_rank())


func get_deck_profiles() -> Array:
	if not _deck_cache_valid:
		_deck_cache = _build_deck_profiles()
		_deck_cache_valid = true
	return _deck_cache.duplicate(true)


func get_opponent_snapshot(opponent_id: StringName) -> Dictionary:
	var key: String = String(opponent_id)
	if key.is_empty():
		return {}
	if not _opponent_cache.has(key):
		var snapshot: Dictionary = _build_opponent_snapshot(opponent_id)
		if snapshot.is_empty():
			return {}
		_opponent_cache[key] = snapshot
	var cached: Dictionary = _opponent_cache[key]
	return cached.duplicate(true)


func get_all_opponents_snapshot() -> Array:
	if not _all_opponents_cache_valid:
		_all_opponents_cache.clear()
		if (
			_opponent_registry != null
			and _opponent_registry.has_method("get_all_opponents")
		):
			for profile in _opponent_registry.call("get_all_opponents"):
				if profile == null:
					continue
				var raw_id = profile.get("opponent_id")
				if raw_id == null:
					continue
				var snapshot: Dictionary = get_opponent_snapshot(
					StringName(str(raw_id))
				)
				if not snapshot.is_empty():
					_all_opponents_cache.append(snapshot)
		_all_opponents_cache_valid = true
	return _all_opponents_cache.duplicate(true)


func get_global_snapshot() -> Dictionary:
	return {
		"schema_version": API_SCHEMA_VERSION,
		"player": get_player_snapshot(),
		"collection": get_collection_snapshot(),
		"decks": get_deck_profiles(),
		"opponents": get_all_opponents_snapshot(),
		"acquisition": _acquisition_snapshot(),
		"acquisition_sources": get_acquisition_sources_snapshot(),
	}


func _acquisition_snapshot() -> Dictionary:
	if _acquisition_service == null or not _acquisition_service.has_method("get_snapshot"):
		return {
			"card_game_unlocked": false,
			"claimed_bundle_ids": PackedStringArray(),
			"available_bundle_ids": PackedStringArray(),
		}
	return _acquisition_service.call("get_snapshot")


func _availability_context() -> Dictionary:
	var beaten_ids := PackedStringArray()
	var total_wins: int = 0
	if _encounter_records != null:
		if _encounter_records.has_method("get_beaten_opponent_ids"):
			beaten_ids = _encounter_records.call("get_beaten_opponent_ids")
		if _encounter_records.has_method("get_total_player_wins"):
			total_wins = int(_encounter_records.call("get_total_player_wins"))
	return {
		"card_game_unlocked": bool(
			_acquisition_snapshot().get("card_game_unlocked", false)
		),
		"beaten_opponent_ids": beaten_ids,
		"total_player_wins": total_wins,
	}


func _build_player_snapshot() -> Dictionary:
	var progression_snapshot: Dictionary = {}
	if _progression != null and _progression.has_method("get_snapshot"):
		progression_snapshot = _progression.call(
			"get_snapshot",
			_base_player_budget
		)

	var deck_profiles: Array = get_deck_profiles()
	var active_profile: int = _active_profile_index()
	var active_deck: Dictionary = {}
	if active_profile >= 0 and active_profile < deck_profiles.size():
		active_deck = deck_profiles[active_profile]

	return {
		"duel_rank": int(progression_snapshot.get("rank", 1)),
		"duel_rank_id": str(progression_snapshot.get("rank_id", "rank_1")),
		"duel_rank_name": str(progression_snapshot.get("rank_name", "Rank 1")),
		"duel_points": int(progression_snapshot.get("points", 0)),
		"rank_progress": progression_snapshot.get("rank_progress", {}),
		"next_rank_threshold": int(
			progression_snapshot.get("next_rank_threshold", -1)
		),
		"deck_budget": int(
			progression_snapshot.get("deck_budget", _base_player_budget)
		),
		"matches": int(progression_snapshot.get("matches", 0)),
		"wins": int(progression_snapshot.get("wins", 0)),
		"losses": int(progression_snapshot.get("losses", 0)),
		"draws": int(progression_snapshot.get("draws", 0)),
		"owned_unique_cards": (
			int(_collection.call("unique_owned_count"))
			if _collection != null and _collection.has_method("unique_owned_count")
			else 0
		),
		"owned_total_cards": (
			int(_collection.call("total_owned_count"))
			if _collection != null and _collection.has_method("total_owned_count")
			else 0
		),
		"active_deck_profile": active_profile + 1,
		"active_deck": active_deck,
		"acquisition_event_count": (
			int(_acquisition_tracker.call("get_event_count"))
			if _acquisition_tracker != null
			and _acquisition_tracker.has_method("get_event_count")
			else 0
		),
		"card_game_unlocked": bool(
			_acquisition_snapshot().get("card_game_unlocked", false)
		),
		"claimed_acquisition_bundles": _acquisition_snapshot().get(
			"claimed_bundle_ids",
			PackedStringArray()
		),
	}


func _build_collection_snapshot() -> Array:
	var result: Array = []
	if _catalog == null or not _catalog.has_method("get_total_source_count"):
		return result

	var player_rank: int = _player_rank()
	for source_index in range(int(_catalog.call("get_total_source_count"))):
		var card = _catalog.call("get_card", source_index)
		if card == null:
			continue
		var quantity: int = _quantity_for_card(StringName(card.card_id))
		if quantity > 0:
			result.append(_card_snapshot(card, quantity, player_rank))
	return result


func _build_deck_profiles() -> Array:
	var result: Array = []
	var config: ConfigFile = _get_deck_config()
	var player_rank: int = _player_rank()
	var budget: int = _player_budget()
	var active_profile: int = _active_profile_index()

	for profile_index in range(DeckStore.profile_count(config)):
		var card_ids := PackedStringArray()
		var id_key: String = "deck_ids_%d" % (profile_index + 1)
		var raw_ids = config.get_value("decks", id_key, PackedStringArray())
		if raw_ids is PackedStringArray or raw_ids is Array:
			for raw_id in raw_ids:
				card_ids.append(str(raw_id))

		var cards: Array = []
		var reasons := PackedStringArray()
		var seen: Dictionary = {}
		var cost: int = 0

		for raw_id in card_ids:
			var card_id := StringName(str(raw_id))
			if seen.has(card_id):
				reasons.append("Duplicate card: %s" % String(card_id))
				continue
			seen[card_id] = true

			var card = null
			if _catalog != null and _catalog.has_method("get_card_by_id"):
				card = _catalog.call("get_card_by_id", card_id)
			if card == null:
				reasons.append("Missing card: %s" % String(card_id))
				continue

			var quantity: int = _quantity_for_card(card_id)
			if quantity <= 0:
				reasons.append("Card no longer owned: %s" % String(card_id))
			if not _can_use_card(card, player_rank):
				reasons.append("Card locked by Duel Rank: %s" % String(card_id))

			cost += int(card.deck_cost)
			cards.append(_card_snapshot(card, quantity, player_rank))

		if card_ids.size() != HAND_SIZE:
			reasons.append("Deck must contain exactly %d cards." % HAND_SIZE)
		if cost > budget:
			reasons.append("Deck cost %d exceeds budget %d." % [cost, budget])

		result.append({
			"profile_index": profile_index,
			"profile_number": profile_index + 1,
			"active": profile_index == active_profile,
			"card_ids": card_ids,
			"cards": cards,
			"card_count": card_ids.size(),
			"cost": cost,
			"budget": budget,
			"valid": reasons.is_empty(),
			"invalid_reasons": reasons,
		})
	return result


func _build_opponent_snapshot(opponent_id: StringName) -> Dictionary:
	if (
		_opponent_registry == null
		or not _opponent_registry.has_method("get_opponent")
	):
		return {}

	var profile = _opponent_registry.call("get_opponent", opponent_id)
	if profile == null:
		return {}

	var availability: Dictionary = {
		"available": bool(profile.get("enabled_by_default")),
		"reason": "",
		"required_player_rank": maxi(1, int(profile.get("required_player_rank"))),
	}
	if _opponent_registry.has_method("get_availability"):
		availability = _opponent_registry.call(
			"get_availability",
			opponent_id,
			_player_rank(),
			&"",
			&"",
			_availability_context()
		)

	var record: Dictionary = (
		_encounter_records.call("get_snapshot", opponent_id)
		if _encounter_records != null
		and _encounter_records.has_method("get_snapshot")
		else {}
	)
	var persistent_collection: Dictionary = _opponent_collection_snapshot(
		opponent_id,
		profile
	)
	var stolen_cards: Array = []
	var stolen_quantities: Dictionary = record.get("stolen_quantities", {})
	for raw_card_id in stolen_quantities.keys():
		var snapshot: Dictionary = _snapshot_for_external_card(
			StringName(str(raw_card_id)),
			int(stolen_quantities[raw_card_id])
		)
		if not snapshot.is_empty():
			stolen_cards.append(snapshot)

	return {
		"opponent_id": String(opponent_id),
		"display_name": str(profile.get("display_name")),
		"duel_rank": int(profile.get("duel_rank")),
		"required_player_rank": int(availability.get("required_player_rank", 1)),
		"enabled": bool(profile.get("enabled_by_default")),
		"available": bool(availability.get("available", false)),
		"lock_reason": str(availability.get("reason", "")),
		"encounter_tags": profile.get("encounter_tags"),
		"region_id": (
			String(profile.call("get_region_id"))
			if profile.has_method("get_region_id")
			else ""
		),
		"deck_budget_override": int(profile.get("deck_budget_override")),
		"progression_points_on_win": int(profile.get("progression_points_on_win")),
		"first_win_progression_only": bool(profile.get("first_win_progression_only")),
		"rematch_progression_points_on_win": int(profile.get("rematch_progression_points_on_win")),
		"progression_spine": bool(profile.get("progression_spine")),
		"unlock_after_opponent_ids": profile.get("unlock_after_opponent_ids"),
		"required_total_player_wins": int(profile.get("required_total_player_wins")),
		"archetype_id": String(profile.get("archetype_id")),
		"strategy_summary": str(profile.get("strategy_summary")),
		"content_revision": int(profile.get("content_revision")),
		"native_card_ids": profile.get("native_card_ids"),
		"preferred_deck_ids": profile.get("preferred_deck_ids"),
		"reward_card_ids": profile.get("reward_card_ids"),
		"record": record,
		"beaten_before": bool(record.get("beaten_before", false)),
		"current_owned_cards": persistent_collection.get("cards", []),
		"collection_initialized": bool(
			persistent_collection.get("initialized", false)
		),
		"current_deck_ids": persistent_collection.get(
			"deck_ids",
			PackedStringArray()
		),
		"priority_card_ids": persistent_collection.get(
			"priority_ids",
			PackedStringArray()
		),
		"stolen_from_player": stolen_cards,
		"stolen_total": int(record.get("stolen_total", 0)),
	}


func _card_snapshot(card, quantity: int, player_rank: int) -> Dictionary:
	var card_id := StringName(card.card_id)
	var history: Dictionary = {}
	if (
		_acquisition_tracker != null
		and _acquisition_tracker.has_method("get_card_history")
	):
		history = _acquisition_tracker.call("get_card_history", card_id)

	return {
		"card_id": String(card_id),
		"display_name": str(card.display_name),
		"flavor_text": str(card.get("flavor_text")),
		"portrait": card.portrait,
		"quantity": maxi(0, quantity),
		"owned": quantity > 0,
		"level": int(card.level),
		"points": int(card.deck_cost),
		"top": int(card.top_rank),
		"right": int(card.right_rank),
		"bottom": int(card.bottom_rank),
		"left": int(card.left_rank),
		"rank_total": int(card.rank_total()),
		"rarity": String(card.rarity_id),
		"required_player_rank": int(card.required_player_rank),
		"usable_at_current_rank": _can_use_card(card, player_rank),
		"group_id": String(card.group_id),
		"tags": card.tags,
		"acquisition_tags": card.acquisition_tags,
		"acquisition_sources": get_card_acquisition_sources(card_id),
		"influence": (
			card.get_influence_snapshot()
			if card.has_method("get_influence_snapshot")
			else {"mode": "none", "strength": 0, "offsets": []}
		),
		"history": history,
	}


func _snapshot_for_external_card(
	card_id: StringName,
	quantity: int
) -> Dictionary:
	if _catalog == null or not _catalog.has_method("get_card_by_id"):
		return {}
	var card = _catalog.call("get_card_by_id", card_id)
	if card == null:
		return {}
	return _card_snapshot(card, quantity, _player_rank())


func _opponent_collection_snapshot(
	opponent_id: StringName,
	profile: Resource
) -> Dictionary:
	var config: ConfigFile = _get_opponent_config()
	var meta_section: String = "opponent_%s_meta" % String(opponent_id)
	var cards_section: String = "opponent_%s_cards" % String(opponent_id)
	var initialized: bool = config.has_section(meta_section)

	var cards: Array = []
	if initialized and config.has_section(cards_section):
		for raw_key in config.get_section_keys(cards_section):
			var quantity: int = maxi(
				0,
				int(config.get_value(cards_section, raw_key, 0))
			)
			if quantity <= 0:
				continue
			var snapshot: Dictionary = _snapshot_for_external_card(
				StringName(str(raw_key)),
				quantity
			)
			if not snapshot.is_empty():
				cards.append(snapshot)
	elif profile != null:
		var native_ids = profile.get("native_card_ids")
		if native_ids is PackedStringArray or native_ids is Array:
			for raw_id in native_ids:
				var snapshot: Dictionary = _snapshot_for_external_card(
					StringName(str(raw_id)),
					1
				)
				if not snapshot.is_empty():
					cards.append(snapshot)

	var deck_ids := PackedStringArray()
	var priority_ids := PackedStringArray()
	if initialized:
		var raw_deck = config.get_value(
			meta_section,
			"deck_ids",
			PackedStringArray()
		)
		if raw_deck is PackedStringArray or raw_deck is Array:
			for raw_id in raw_deck:
				deck_ids.append(str(raw_id))

		var raw_priority = config.get_value(
			meta_section,
			"priority_ids",
			PackedStringArray()
		)
		if raw_priority is PackedStringArray or raw_priority is Array:
			for raw_id in raw_priority:
				priority_ids.append(str(raw_id))

	return {
		"initialized": initialized,
		"cards": cards,
		"deck_ids": deck_ids,
		"priority_ids": priority_ids,
	}


func _get_deck_config() -> ConfigFile:
	if not _deck_config_loaded:
		_deck_config = ConfigFile.new()
		if DeckStore.load_config(_deck_config) != OK:
			_deck_config.clear()
		_deck_config_loaded = true
	return _deck_config


func _get_opponent_config() -> ConfigFile:
	if not _opponent_config_loaded:
		_opponent_config = ConfigFile.new()
		_opponent_config.load(OPPONENT_COLLECTIONS_PATH)
		_opponent_config_loaded = true
	return _opponent_config


func _active_profile_index() -> int:
	var config: ConfigFile = _get_deck_config()
	return DeckStore.active_profile(config)


func _player_rank() -> int:
	if _progression != null and _progression.has_method("get_rank_number"):
		return maxi(1, int(_progression.call("get_rank_number")))
	return 1


func _player_budget() -> int:
	if _progression != null and _progression.has_method("get_deck_budget"):
		return maxi(
			5,
			int(_progression.call("get_deck_budget", _base_player_budget))
		)
	return _base_player_budget


func _quantity_for_card(card_id: StringName) -> int:
	if (
		_collection != null
		and _collection.has_method("get_quantity_by_id")
	):
		return maxi(
			0,
			int(_collection.call("get_quantity_by_id", card_id))
		)
	return 0


func _can_use_card(card, player_rank: int) -> bool:
	if card == null:
		return false
	if (
		_acquisition_policy != null
		and _acquisition_policy.has_method("can_use_card")
	):
		return bool(_acquisition_policy.call(
			"can_use_card",
			card,
			player_rank
		))
	if card.has_method("is_usable_at_player_rank"):
		return bool(card.call("is_usable_at_player_rank", player_rank))
	return true
