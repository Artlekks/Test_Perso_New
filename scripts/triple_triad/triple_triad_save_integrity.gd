extends RefCounted

const SAVE_SCHEMA_VERSION := 1
const MANIFEST_PATH := "user://triple_triad_save_manifest.cfg"

const PLAYER_COLLECTION_PATH := "user://triple_triad_collection.cfg"
const OPPONENTS_PATH := "user://triple_triad_opponents.cfg"
const DECKS_PATH := "user://triple_triad_decks.cfg"
const PROGRESSION_PATH := "user://triple_triad_progression.cfg"
const TRANSFER_JOURNAL_PATH := "user://triple_triad_transfer_journal.cfg"
const ACQUISITION_HISTORY_PATH := "user://triple_triad_acquisition_history.cfg"
const ACQUISITION_STATE_PATH := "user://triple_triad_acquisition_state.cfg"
const ENCOUNTER_RECORDS_PATH := "user://triple_triad_encounter_records.cfg"
const WORLD_REWARD_LEDGER_PATH := "user://triple_triad_world_delivery.cfg"
const COMPETITIONS_PATH := "user://triple_triad_competitions.cfg"
const COMPLETION_PATH := "user://triple_triad_completion.cfg"

const PROFILE_COUNT := 6
const HAND_SIZE := 5
const DECK_SAVE_VERSION := 1

var _last_report: Dictionary = {}


func preflight_restore_backups() -> Dictionary:
	var restored: Array[String] = []
	var failed: Array[String] = []

	for path in _protected_paths():
		var primary_exists: bool = FileAccess.file_exists(path)
		if primary_exists:
			var primary := ConfigFile.new()
			if primary.load(path) == OK:
				continue

		var backup_path: String = _backup_path(path)
		if not FileAccess.file_exists(backup_path):
			# Missing primary + missing backup is a normal first-run state. A corrupt
			# primary without a backup is the only unrecoverable preflight case.
			if primary_exists:
				failed.append(path)
			continue

		var backup := ConfigFile.new()
		if backup.load(backup_path) != OK:
			failed.append(path)
			continue

		var restore_error: Error = backup.save(path)
		if restore_error == OK:
			restored.append(path)
		else:
			failed.append(path)

	return {
		"restored": restored,
		"failed": failed,
		"valid": failed.is_empty(),
	}


func audit_and_checkpoint(
	catalog: Resource,
	player_collection,
	progression,
	base_player_budget: int,
	reason: String = "checkpoint",
	acquisition_policy: Resource = null
) -> Dictionary:
	var report := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"reason": reason,
		"valid": true,
		"repairs": 0,
		"warnings": [],
		"player_collection": {},
		"progression": {},
		"decks": {},
		"opponents": {},
		"backups_refreshed": false,
		"transfer_pending": _transfer_journal_pending(),
	}

	if catalog == null:
		report["valid"] = false
		report["warnings"].append("Card catalog unavailable during save audit.")
		_last_report = report
		return report

	if catalog.has_method("validate_catalog"):
		var catalog_audit: Dictionary = catalog.call("validate_catalog")
		if not bool(catalog_audit.get("valid", false)):
			report["valid"] = false
			report["warnings"].append(
				"Save audit aborted because the card catalog is invalid."
			)
			_last_report = report
			return report

	report["player_collection"] = _audit_player_collection(
		catalog,
		player_collection
	)
	report["progression"] = _audit_progression(progression)

	var active_budget: int = maxi(5, base_player_budget)
	if progression != null and progression.has_method("get_deck_budget"):
		active_budget = int(progression.call(
			"get_deck_budget",
			maxi(5, base_player_budget)
		))

	var active_player_rank: int = 1
	if progression != null and progression.has_method("get_rank_number"):
		active_player_rank = maxi(1, int(progression.call("get_rank_number")))

	report["decks"] = _audit_player_decks(
		catalog,
		player_collection,
		active_budget,
		active_player_rank,
		acquisition_policy
	)
	report["opponents"] = _audit_all_opponents(catalog)

	for key in ["player_collection", "progression", "decks", "opponents"]:
		var component: Dictionary = report[key]
		report["repairs"] += int(component.get("repairs", 0))
		if not bool(component.get("valid", true)):
			report["valid"] = false
		for warning in component.get("warnings", []):
			report["warnings"].append(str(warning))

	# Never overwrite healthy backups while a transfer journal is unresolved.
	# The journal is the source of truth until CardEconomy repairs both owners.
	if bool(report["valid"]) and not bool(report["transfer_pending"]):
		report["backups_refreshed"] = _refresh_backups()
		if not bool(report["backups_refreshed"]):
			report["valid"] = false
			report["warnings"].append("Could not refresh one or more save backups.")

	_write_manifest(report)
	_last_report = report
	return report


func get_last_report() -> Dictionary:
	return _last_report.duplicate(true)


func _audit_player_collection(catalog: Resource, player_collection) -> Dictionary:
	var report := {
		"valid": true,
		"repairs": 0,
		"warnings": [],
		"unique_cards": 0,
		"total_cards": 0,
	}

	if player_collection == null:
		report["valid"] = false
		report["warnings"].append("Player collection backend unavailable.")
		return report

	# The collection backend already sanitizes IDs against the current catalog.
	# Re-save its in-memory authoritative state, then verify the file it produced.
	if player_collection.has_method("save_state"):
		var save_error: Error = player_collection.call("save_state")
		if save_error != OK:
			report["valid"] = false
			report["warnings"].append("Player collection could not be saved.")
			return report

	if player_collection.has_method("unique_owned_count"):
		report["unique_cards"] = int(player_collection.call("unique_owned_count"))
	if player_collection.has_method("total_owned_count"):
		report["total_cards"] = int(player_collection.call("total_owned_count"))

	var config := ConfigFile.new()
	if config.load(PLAYER_COLLECTION_PATH) != OK:
		report["valid"] = false
		report["warnings"].append("Player collection save cannot be reloaded.")
		return report

	if not config.has_section("cards"):
		return report

	var changed: bool = false
	for raw_key in config.get_section_keys("cards"):
		var card_id := StringName(str(raw_key))
		var quantity: int = int(config.get_value("cards", raw_key, 0))
		var card = null
		if catalog.has_method("get_card_by_id"):
			card = catalog.call("get_card_by_id", card_id)
		if card == null or quantity <= 0:
			config.erase_section_key("cards", str(raw_key))
			report["repairs"] += 1
			changed = true

	if changed:
		var save_error: Error = config.save(PLAYER_COLLECTION_PATH)
		if save_error != OK:
			report["valid"] = false
			report["warnings"].append("Player collection repairs could not be saved.")

	return report


func _audit_progression(progression) -> Dictionary:
	var report := {
		"valid": true,
		"repairs": 0,
		"warnings": [],
		"snapshot": {},
	}

	if progression == null:
		report["valid"] = false
		report["warnings"].append("Triple Triad progression backend unavailable.")
		return report

	if progression.has_method("audit_state"):
		var audit: Dictionary = progression.call("audit_state")
		report["snapshot"] = audit.get("snapshot", {})
		report["repairs"] = int(audit.get("repairs", 0))
		report["valid"] = bool(audit.get("valid", true))
		for warning in audit.get("warnings", []):
			report["warnings"].append(str(warning))
	elif progression.has_method("get_snapshot"):
		report["snapshot"] = progression.call("get_snapshot")

	if progression.has_method("save_state"):
		var save_error: Error = progression.call("save_state")
		if save_error != OK:
			report["valid"] = false
			report["warnings"].append("Triple Triad progression could not be saved.")

	return report


func _audit_player_decks(
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
	var load_error: Error = config.load(DECKS_PATH)
	if load_error != OK:
		# No deck file yet is a normal fresh-save state.
		if load_error == ERR_FILE_NOT_FOUND:
			return report
		report["valid"] = false
		report["warnings"].append("Deck profile save cannot be loaded.")
		return report

	var changed: bool = false
	for profile_index in range(PROFILE_COUNT):
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

			if clean_ids.size() >= HAND_SIZE:
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

		if current_packed != clean_packed:
			config.set_value("decks", id_key, clean_packed)
			changed = true

	if not config.has_section("meta"):
		changed = true

	var last_profile: int = clampi(
		int(config.get_value("meta", "last_profile", 0)),
		0,
		PROFILE_COUNT - 1
	)
	if int(config.get_value("meta", "last_profile", 0)) != last_profile:
		report["repairs"] += 1
		changed = true
	config.set_value("meta", "last_profile", last_profile)
	config.set_value("meta", "version", DECK_SAVE_VERSION)
	config.set_value("meta", "integrity_version", SAVE_SCHEMA_VERSION)

	if changed:
		var save_error: Error = config.save(DECKS_PATH)
		if save_error != OK:
			report["valid"] = false
			report["warnings"].append("Deck profile repairs could not be saved.")

	return report


func _audit_all_opponents(catalog: Resource) -> Dictionary:
	var report := {
		"valid": true,
		"repairs": 0,
		"warnings": [],
		"opponents_checked": 0,
	}

	var config := ConfigFile.new()
	var load_error: Error = config.load(OPPONENTS_PATH)
	if load_error != OK:
		if load_error == ERR_FILE_NOT_FOUND:
			return report
		report["valid"] = false
		report["warnings"].append("Opponent collection save cannot be loaded.")
		return report

	var changed: bool = false
	for raw_section in config.get_sections():
		var meta_section: String = str(raw_section)
		if not meta_section.begins_with("opponent_"):
			continue
		if not meta_section.ends_with("_meta"):
			continue

		report["opponents_checked"] += 1
		var prefix: String = meta_section.substr(
			0,
			meta_section.length() - "_meta".length()
		)
		var cards_section: String = "%s_cards" % prefix
		var owned: Dictionary = {}

		if config.has_section(cards_section):
			for raw_key in config.get_section_keys(cards_section):
				var card_id := StringName(str(raw_key))
				var quantity: int = int(
					config.get_value(cards_section, raw_key, 0)
				)
				var card = null
				if catalog.has_method("get_card_by_id"):
					card = catalog.call("get_card_by_id", card_id)

				if card == null or quantity <= 0:
					config.erase_section_key(cards_section, str(raw_key))
					report["repairs"] += 1
					changed = true
					continue
				owned[card_id] = quantity

		var clean_deck: PackedStringArray = _clean_opponent_id_list(
			config.get_value(
				meta_section,
				"deck_ids",
				PackedStringArray()
			),
			owned,
			catalog,
			HAND_SIZE
		)
		var old_deck: PackedStringArray = _as_packed_string_array(
			config.get_value(
				meta_section,
				"deck_ids",
				PackedStringArray()
			)
		)
		if old_deck != clean_deck:
			report["repairs"] += 1
			config.set_value(meta_section, "deck_ids", clean_deck)
			changed = true

		var clean_priority: PackedStringArray = _clean_opponent_id_list(
			config.get_value(
				meta_section,
				"priority_ids",
				PackedStringArray()
			),
			owned,
			catalog,
			-1
		)
		var old_priority: PackedStringArray = _as_packed_string_array(
			config.get_value(
				meta_section,
				"priority_ids",
				PackedStringArray()
			)
		)
		if old_priority != clean_priority:
			report["repairs"] += 1
			config.set_value(meta_section, "priority_ids", clean_priority)
			changed = true

		config.set_value(
			meta_section,
			"integrity_version",
			SAVE_SCHEMA_VERSION
		)

	if changed:
		var save_error: Error = config.save(OPPONENTS_PATH)
		if save_error != OK:
			report["valid"] = false
			report["warnings"].append("Opponent save repairs could not be saved.")

	return report


func _clean_opponent_id_list(
	raw_values,
	owned: Dictionary,
	catalog: Resource,
	max_count: int
) -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}

	if not (raw_values is PackedStringArray or raw_values is Array):
		return result

	for raw_id in raw_values:
		var card_id := StringName(str(raw_id))
		if seen.has(card_id):
			continue
		if not owned.has(card_id):
			continue

		var card = null
		if catalog.has_method("get_card_by_id"):
			card = catalog.call("get_card_by_id", card_id)
		if card == null:
			continue

		result.append(String(card_id))
		seen[card_id] = true
		if max_count > 0 and result.size() >= max_count:
			break

	return result


func _card_usable_at_rank(
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


func _player_owns_id(player_collection, card_id: StringName) -> bool:
	if player_collection == null:
		return false
	if player_collection.has_method("get_quantity_by_id"):
		return int(player_collection.call(
			"get_quantity_by_id",
			card_id
		)) > 0
	return false


func _as_packed_string_array(raw_values) -> PackedStringArray:
	var result := PackedStringArray()
	if raw_values is PackedStringArray or raw_values is Array:
		for raw_value in raw_values:
			result.append(str(raw_value))
	return result


func _transfer_journal_pending() -> bool:
	var config := ConfigFile.new()
	if config.load(TRANSFER_JOURNAL_PATH) != OK:
		return false
	if not config.has_section("transaction"):
		return false

	var card_id: String = str(
		config.get_value("transaction", "card_id", "")
	).strip_edges()
	var opponent_id: String = str(
		config.get_value("transaction", "opponent_id", "")
	).strip_edges()
	return not card_id.is_empty() and not opponent_id.is_empty()


func _refresh_backups() -> bool:
	var success: bool = true
	for path in _protected_paths():
		if not FileAccess.file_exists(path):
			continue

		var config := ConfigFile.new()
		if config.load(path) != OK:
			success = false
			continue

		if config.save(_backup_path(path)) != OK:
			success = false
	return success


func _protected_paths() -> Array[String]:
	return [
		PLAYER_COLLECTION_PATH,
		OPPONENTS_PATH,
		DECKS_PATH,
		PROGRESSION_PATH,
		ACQUISITION_HISTORY_PATH,
		ACQUISITION_STATE_PATH,
		ENCOUNTER_RECORDS_PATH,
		WORLD_REWARD_LEDGER_PATH,
		COMPETITIONS_PATH,
		COMPLETION_PATH,
	]


func _backup_path(path: String) -> String:
	return "%s.bak" % path


func _write_manifest(report: Dictionary) -> void:
	var config := ConfigFile.new()
	config.load(MANIFEST_PATH)

	var checkpoint_count: int = maxi(
		0,
		int(config.get_value("meta", "checkpoint_count", 0))
	) + 1

	config.set_value("meta", "schema_version", SAVE_SCHEMA_VERSION)
	config.set_value("meta", "checkpoint_count", checkpoint_count)
	config.set_value(
		"meta",
		"last_checkpoint_unix",
		int(Time.get_unix_time_from_system())
	)
	config.set_value("meta", "last_reason", str(report.get("reason", "")))
	config.set_value("health", "valid", bool(report.get("valid", false)))
	config.set_value("health", "repairs", int(report.get("repairs", 0)))
	config.set_value(
		"health",
		"transfer_pending",
		bool(report.get("transfer_pending", false))
	)
	config.set_value(
		"health",
		"backups_refreshed",
		bool(report.get("backups_refreshed", false))
	)
	config.set_value(
		"health",
		"warnings",
		PackedStringArray(report.get("warnings", []))
	)

	var save_error: Error = config.save(MANIFEST_PATH)
	if save_error != OK:
		push_warning(
			"TripleTriadSaveIntegrity: manifest save failed (%s)."
			% error_string(save_error)
		)
