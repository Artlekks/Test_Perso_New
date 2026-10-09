extends RefCounted

## Canonical saved-profile format/policy. UI decks and match hands are drafts/copies.
const Storage = preload("res://scripts/triple_triad/triple_triad_config_store.gd")
const SAVE_PATH := "user://triple_triad_decks.cfg"
const SAVE_VERSION := 2
const MIN_PROFILES := 5
const MAX_PROFILES := 50

static func load_config(config: ConfigFile) -> Error:
	var error: Error = Storage.load_recover(config, SAVE_PATH)
	if error == OK and int(config.get_value("meta", "version", 0)) > SAVE_VERSION:
		return ERR_INVALID_DATA
	if error == OK:
		for key in ["profile_count", "last_profile"]:
			if config.has_section_key("meta", key) and not config.get_value("meta", key) is int:
				return ERR_INVALID_DATA
	return error

static func profile_count(config: ConfigFile) -> int:
	var highest := MIN_PROFILES
	if config.has_section("decks"):
		for raw_key in config.get_section_keys("decks"):
			var key: String = str(raw_key)
			var number := key.trim_prefix("deck_ids_") if key.begins_with("deck_ids_") else key.trim_prefix("deck_")
			if number.is_valid_int():
				highest = maxi(highest, number.to_int())
	return clampi(maxi(highest, int(config.get_value("meta", "profile_count", MIN_PROFILES))), MIN_PROFILES, MAX_PROFILES)

static func active_profile(config: ConfigFile) -> int:
	return clampi(int(config.get_value("meta", "last_profile", 0)), 0, profile_count(config) - 1)

static func save_config(config: ConfigFile) -> Error:
	# Never overwrite an unreadable/newer save from a UI-local empty draft.
	var previous := ConfigFile.new()
	var error: Error = load_config(previous)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		return error
	for key in ["profile_count", "last_profile"]:
		if config.has_section_key("meta", key) and not config.get_value("meta", key) is int:
			return ERR_INVALID_DATA
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "profile_count", profile_count(config))
	config.set_value("meta", "last_profile", active_profile(config))
	return Storage.commit(config, SAVE_PATH)


static func audit_profiles(
	catalog: Resource,
	player_collection,
	budget_limit: int,
	player_rank: int,
	acquisition_policy: Resource = null
) -> Dictionary:
	var report := {
		"valid": true,
		"repairs": 0,
		"warnings": [],
		"profiles_checked": 0,
		"budget": maxi(5, budget_limit),
	}

	var config := ConfigFile.new()
	var load_error: Error = load_config(config)
	if load_error != OK:
		# No deck file yet is a normal fresh-save state.
		if load_error == ERR_FILE_NOT_FOUND:
			return report
		report["valid"] = false
		report["warnings"].append("Deck profile save cannot be loaded.")
		return report

	var changed: bool = false
	for profile_index in range(profile_count(config)):
		var id_key: String = "deck_ids_%d" % (profile_index + 1)
		var legacy_key: String = "deck_%d" % (profile_index + 1)
		var source_ids: Array = []
		var had_profile: bool = false

		if config.has_section_key("decks", id_key):
			had_profile = true
			var raw_ids = config.get_value("decks", id_key, PackedStringArray())
			if raw_ids is PackedStringArray or raw_ids is Array:
				for raw_id in raw_ids:
					source_ids.append(StringName(str(raw_id)))
		elif config.has_section_key("decks", legacy_key):
			had_profile = true
			var raw_indices = config.get_value(
				"decks",
				legacy_key,
				PackedInt32Array()
			)
			if raw_indices is PackedInt32Array or raw_indices is Array:
				for raw_index in raw_indices:
					var legacy_card = null
					if catalog.has_method("get_card_by_legacy_source_index"):
						legacy_card = catalog.call(
							"get_card_by_legacy_source_index",
							int(raw_index)
						)
					elif catalog.has_method("get_card"):
						legacy_card = catalog.call("get_card", int(raw_index))
					if legacy_card != null:
						source_ids.append(StringName(legacy_card.card_id))

		if not had_profile:
			continue

		report["profiles_checked"] += 1
		var clean_ids: Array = []
		var seen: Dictionary = {}
		var running_cost: int = 0

		for raw_id in source_ids:
			var card_id := StringName(raw_id)
			if seen.has(card_id):
				report["repairs"] += 1
				continue

			var card = null
			if catalog.has_method("get_card_by_id"):
				card = catalog.call("get_card_by_id", card_id)
			if card == null:
				report["repairs"] += 1
				continue

			if not _player_owns_id(player_collection, card_id):
				report["repairs"] += 1
				continue

			if not _card_usable_at_rank(card, player_rank, acquisition_policy):
				report["repairs"] += 1
				continue

			if clean_ids.size() >= 5:
				report["repairs"] += 1
				continue

			var card_cost: int = maxi(0, int(card.deck_cost))
			if running_cost + card_cost > maxi(5, budget_limit):
				report["repairs"] += 1
				continue

			clean_ids.append(card_id)
			seen[card_id] = true
			running_cost += card_cost

		var clean_packed := PackedStringArray()
		for card_id in clean_ids:
			clean_packed.append(String(card_id))

		var current_packed := PackedStringArray()
		if config.has_section_key("decks", id_key):
			var current = config.get_value("decks", id_key, PackedStringArray())
			if current is PackedStringArray or current is Array:
				for raw_id in current:
					current_packed.append(str(raw_id))

		if current_packed != clean_packed or not config.has_section_key("decks", id_key) or not config.get_value("decks", id_key) is PackedStringArray:
			config.set_value("decks", id_key, clean_packed)
			changed = true

	if not config.has_section("meta"):
		changed = true

	var last_profile: int = clampi(
		int(config.get_value("meta", "last_profile", 0)),
		0,
		profile_count(config) - 1
	)
	if int(config.get_value("meta", "last_profile", 0)) != last_profile:
		report["repairs"] += 1
		changed = true
	config.set_value("meta", "last_profile", last_profile)
	config.set_value("meta", "version", SAVE_VERSION)
	config.set_value("meta", "integrity_version", 2)

	if changed:
		var save_error: Error = save_config(config)
		if save_error != OK:
			report["valid"] = false
			report["warnings"].append("Deck profile repairs could not be saved.")

	return report


static func _player_owns_id(player_collection, card_id: StringName) -> bool:
	if player_collection == null:
		return false
	if player_collection.has_method("get_quantity_by_id"):
		return int(player_collection.call(
			"get_quantity_by_id",
			card_id
		)) > 0
	return false


static func _card_usable_at_rank(
	card,
	player_rank: int,
	acquisition_policy: Resource
) -> bool:
	if card == null:
		return false
	if (
		acquisition_policy != null
		and acquisition_policy.has_method("can_use_card")
	):
		return bool(acquisition_policy.call(
			"can_use_card",
			card,
			player_rank
		))
	if card.has_method("is_usable_at_player_rank"):
		return bool(card.call("is_usable_at_player_rank", player_rank))
	return true
