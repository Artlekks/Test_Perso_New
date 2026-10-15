extends RefCounted

static var _cross_store_registrations: Array[Dictionary] = []
static var _active_cross_store_journal: String = ""
static var _active_cross_store_id: String = ""
static var _card_maker_registrations: Array[Dictionary] = []
static var _active_card_maker_journal: String = ""

static func register_cross_store_journal(journal_path: String, item_path: String,
		fish_path: String, keys: Dictionary, extra_path: String = "") -> void:
	for entry in _cross_store_registrations:
		if entry.journal == journal_path:
			entry.item = item_path
			entry.fish = fish_path
			entry.keys = keys
			if not extra_path.is_empty():
				entry.extra = extra_path
			return
	_cross_store_registrations.append({"journal": journal_path, "item": item_path,
		"fish": fish_path, "extra": extra_path, "keys": keys})

static func has_pending_for_store(path: String) -> bool:
	for entry in _cross_store_registrations:
		if path == entry.item or path == entry.fish or path == entry.get("extra", ""):
			if read(entry.journal, 1, entry.keys).status != "new":
				return true
	return false

static func begin_cross_store_write(journal_path: String, transaction_id: String) -> void:
	_active_cross_store_journal = journal_path
	_active_cross_store_id = transaction_id

static func end_cross_store_write() -> void:
	_active_cross_store_journal = ""
	_active_cross_store_id = ""

static func register_card_maker_journal(journal_path: String, temp_path: String, fish_path: String) -> void:
	for entry in _card_maker_registrations:
		if entry.journal == journal_path:
			entry.temp = temp_path
			entry.fish = fish_path
			return
	_card_maker_registrations.append({"journal": journal_path, "temp": temp_path, "fish": fish_path})

static func has_pending_card_maker_for_store(path: String) -> bool:
	for entry in _card_maker_registrations:
		if entry.fish == path and (_card_maker_journal_occupied(entry.journal) or _card_maker_journal_occupied(entry.temp)):
			return true
	return false

static func _card_maker_journal_occupied(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))

static func begin_card_maker_write(journal_path: String) -> void:
	_active_card_maker_journal = journal_path

static func end_card_maker_write() -> void:
	_active_card_maker_journal = ""

static func _cross_store_write_allowed(path: String) -> bool:
	for entry in _cross_store_registrations:
		if path != entry.item and path != entry.fish and path != entry.get("extra", ""):
			continue
		var pending := read(entry.journal, 1, entry.keys)
		if pending.status == "new":
			continue
		if pending.status != "valid" or _active_cross_store_journal != entry.journal or _active_cross_store_id != str(pending.data.get("transaction_id", "")):
			return false
	for entry in _card_maker_registrations:
		if entry.fish == path and (_card_maker_journal_occupied(entry.journal) or _card_maker_journal_occupied(entry.temp)) and _active_card_maker_journal != entry.journal:
			return false
	return true

const CURRENT_SPECIMEN_KEYS = ["specimen_id", "species_id", "fish_name", "size", "points", "is_king", "spot_id", "spot_name", "lure_id", "lure_name", "catch_transaction_id", "legacy"]
const CURRENT_RECORD_KEYS = ["fish_name", "caught_count", "record_miss_streak", "best_size", "best_size_points", "best_size_score_tier", "best_size_spot_id", "best_size_spot_name", "best_size_lure_id", "best_size_lure_name", "best_points", "best_points_size", "best_points_score_tier", "best_points_spot_id", "best_points_spot_name", "best_points_lure_id", "best_points_lure_name", "last_catch_size", "last_catch_points", "last_catch_is_king", "last_catch_size_band", "last_catch_score_tier", "last_catch_size_ratio_to_king", "last_catch_spot_id", "last_catch_spot_name", "last_catch_lure_id", "last_catch_lure_name", "king_caught", "king_count", "known_spots", "successful_lures"]

## Single-file JSON durability for the fishing stores. A valid primary wins;
## otherwise recovery tries backup, then a complete staged file. Unsupported
## primary versions always block loading to avoid downgrading future saves.

static func read(path: String, maximum_version: int, required_keys: Dictionary) -> Dictionary:
	var primary := _inspect(path, maximum_version, required_keys)
	if primary.status == "valid" or primary.status == "unsupported":
		return primary
	var backup := _inspect(path + ".bak", maximum_version, required_keys)
	if backup.status == "valid":
		backup["source"] = "backup"
		return backup
	if backup.status == "unsupported":
		return backup
	var staged := _inspect(path + ".tmp", maximum_version, required_keys)
	if staged.status == "valid":
		staged["source"] = "temporary"
		return staged
	if staged.status == "unsupported":
		return staged
	var alternate := _inspect(path + ".tmp.next", maximum_version, required_keys)
	if alternate.status == "valid":
		alternate["source"] = "temporary_next"
		return alternate
	if alternate.status == "unsupported":
		return alternate
	if primary.status == "missing" and backup.status == "missing" and staged.status == "missing" and alternate.status == "missing":
		return {"status": "new", "data": {}}
	return {"status": "blocked", "data": {}, "primary": primary.status,
		"backup": backup.status, "temporary": staged.status,
		"temporary_next": alternate.status}


static func write(path: String, payload: Dictionary, maximum_version: int, required_keys: Dictionary) -> bool:
	if not _cross_store_write_allowed(path):
		return false
	var current := read(path, maximum_version, required_keys)
	if current.status == "blocked" or current.status == "unsupported":
		push_warning("FishingSaveStorage: refusing to replace unreadable or unsupported save: " + path)
		return false
	# Never open the selected recovery copy with WRITE. Two bounded slots let
	# repeated interrupted saves keep alternating without losing that copy.
	var temporary := path + (".tmp.next" if current.get("source", "") == "temporary" else ".tmp")
	var old_temp := _inspect(temporary, maximum_version, required_keys)
	if old_temp.status != "missing" and old_temp.status != "valid":
		if not _preserve(temporary):
			return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	_qa_pause(path, "temporary_open")
	var serialized := JSON.stringify(payload, "\t")
	file.store_string(serialized)
	var write_error := file.get_error()
	if write_error == OK:
		file.flush()
		write_error = file.get_error()
	file.close()
	if write_error != OK:
		return false
	var staged := _inspect(temporary, maximum_version, required_keys)
	if staged.status != "valid" or FileAccess.get_file_as_string(temporary) != serialized:
		return false
	_qa_pause(path, "before_promotion")
	var primary := _inspect(path, maximum_version, required_keys)
	var backup_path := path + ".bak"
	var absolute := ProjectSettings.globalize_path(path)
	var staged_absolute := ProjectSettings.globalize_path(temporary)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	if primary.status == "valid":
		# The primary is the verified surviving copy before rotating the backup.
		if FileAccess.file_exists(backup_path):
			var old_backup := _inspect(backup_path, maximum_version, required_keys)
			if old_backup.status != "valid":
				if not _preserve(backup_path):
					return false
			elif DirAccess.remove_absolute(backup_absolute) != OK:
				return false
		if DirAccess.rename_absolute(absolute, backup_absolute) != OK:
			return false
	elif primary.status != "missing":
		if not _preserve(path):
			return false
	if _qa_failure(path, "promotion_failure"):
		return false
	if DirAccess.rename_absolute(staged_absolute, absolute) != OK:
		# A successful rotation leaves the valid backup in place for recovery.
		return false
	var promoted := _inspect(path, maximum_version, required_keys)
	return promoted.status == "valid" and FileAccess.get_file_as_string(path) == serialized


static func _inspect(path: String, maximum_version: int, required_keys: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing", "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": "inaccessible", "data": {}}
	var raw := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"status": "inaccessible", "data": {}}
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return {"status": "invalid", "data": {}}
	var data: Dictionary = parsed
	var version: Variant = data.get("version", null)
	if version == null and bool(required_keys.get("allow_versionless", false)):
		version = 0
	elif typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return {"status": "invalid", "data": {}}
	if float(version) != floorf(float(version)) or int(version) < 0 or (int(version) == 0 and not bool(required_keys.get("allow_versionless", false))):
		return {"status": "invalid", "data": {}}
	if int(version) > maximum_version:
		return {"status": "unsupported", "data": {}}
	for threshold in required_keys.keys():
		if typeof(threshold) != TYPE_INT:
			continue
		var required_version := int(threshold)
		if (required_version < 0 and int(version) != -required_version) or (required_version > 0 and int(version) < required_version):
			continue
		for key in required_keys[threshold]:
			if not data.has(key) or not _valid_field(key, data[key]):
				return {"status": "invalid", "data": {}}
	if not _valid_nested(data, int(version), str(required_keys.get("store", ""))):
		return {"status": "invalid", "data": {}}
	return {"status": "valid", "data": data, "source": "primary"}


static func _valid_field(key: String, value: Variant) -> bool:
	if key in ["fish_counts", "fish_specimens", "lure_counts", "rod_counts",
		"species_records", "claimed_reward_keys", "counts", "metadata",
		"player_before", "player_after", "wallet_before", "wallet_after"]:
		return value is Dictionary
	if key in ["transaction_id", "item_id", "item_save_path", "wallet_save_path"]:
		return value is String
	if key == "recent_catch_transaction_ids":
		return value is Array
	if key == "records":
		return value is Array
	if key == "progress_migrated":
		return value is bool
	if key == "version":
		return true
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) == floorf(float(value))


static func _valid_nested(data: Dictionary, version: int, store: String) -> bool:
	match store:
		"inventory":
			for key in ["fish_counts", "lure_counts", "rod_counts"]:
				if data.has(key) and not _valid_count_map(data[key]):
					return false
			if version >= 2 and not _valid_specimens(data.get("fish_specimens", {}), version >= 6):
				return false
		"progress":
			if not _valid_records(data.get("species_records", {}), version >= 7):
				return false
			if version >= 7:
				for transaction_id in data.get("recent_catch_transaction_ids", []):
					if not transaction_id is String or transaction_id.strip_edges().is_empty():
						return false
		"rewards":
			if version >= 2:
				for claimed in data.get("claimed_reward_keys", {}).values():
					if not claimed is bool:
						return false
		"player_items":
			if data.has("counts") and not _valid_count_map(data["counts"]):
				return false
			if data.has("metadata") and not data["metadata"] is Dictionary:
				return false
		"sale_journal":
			return _valid_sale_intent(data)
		"cross_store_journal":
			if data.get("kind", "sale") == "beach_craft":
				return _valid_beach_craft_intent(data)
			if data.get("kind", "sale") == "mixed_exchange":
				return _valid_mixed_intent(data)
			if data.get("kind", "sale") == "sale":
				return _valid_sale_intent(data)
			return false
		"beach_crafted_lures":
			return valid_beach_crafted_records(data, version)
	return true


static func valid_beach_crafted_records(data: Dictionary, version: int) -> bool:
	if version != 1 or not data.get("records") is Array:
		return false
	if not _integer_number(data.get("next_instance_number", null)) or int(data.next_instance_number) < 1:
		return false
	var seen_ids := {}
	for entry in data.records:
		if not entry is Dictionary:
			return false
		var record: Dictionary = entry
		for key in ["lure_id", "recipe_id", "body_id", "core_id"]:
			if not record.get(key) is String or str(record[key]).strip_edges().is_empty():
				return false
		if seen_ids.has(record.lure_id):
			return false
		seen_ids[record.lure_id] = true
		for key in ["accent_id", "display_name_override", "qa_feel_role"]:
			if record.has(key) and not record[key] is String:
				return false
		for key in ["instance_number", "buoyancy", "handling", "attraction", "created_unix"]:
			if record.has(key) and not _integer_number(record[key]):
				return false
		if record.has("instance_number") and int(record.instance_number) < 1:
			return false
	return true


static func _valid_beach_craft_intent(data: Dictionary) -> bool:
	for key in ["transaction_id", "item_save_path", "wallet_save_path", "record_save_path", "lure_id"]:
		if not data.get(key) is String or str(data[key]).strip_edges().is_empty():
			return false
	for key in ["item_save_path", "wallet_save_path", "record_save_path"]:
		if not str(data[key]).begins_with("user://"):
			return false
	if not data.get("material_costs") is Dictionary or not _valid_count_map(data.material_costs) or data.material_costs.is_empty():
		return false
	for amount in data.material_costs.values():
		if int(amount) <= 0:
			return false
	for key in ["player_before", "player_after", "wallet_before", "wallet_after", "record_before", "record_after", "crafted_record"]:
		if not data.get(key) is Dictionary:
			return false
	var before: Dictionary = data.player_before
	var after: Dictionary = data.player_after
	if not _valid_count_map(before.get("counts", null)) or not _valid_count_map(after.get("counts", null)):
		return false
	var expected := before.duplicate(true)
	var counts: Dictionary = expected.counts
	for raw_id in data.material_costs:
		var item_id := str(raw_id)
		var remaining := int(counts.get(item_id, 0)) - int(data.material_costs[raw_id])
		if remaining < 0:
			return false
		if remaining == 0:
			counts.erase(item_id)
		else:
			counts[item_id] = remaining
	expected.erase("dirty")
	after = after.duplicate(true)
	after.erase("dirty")
	if _normalized_json(expected) != _normalized_json(after):
		return false
	var fish_before: Dictionary = data.wallet_before
	var fish_after: Dictionary = data.wallet_after
	if not _valid_count_map(fish_before.get("lure_counts", null)) or not _valid_count_map(fish_after.get("lure_counts", null)):
		return false
	var expected_fish := fish_before.duplicate(true)
	var lures: Dictionary = expected_fish.lure_counts
	var lure_id := str(data.lure_id)
	if int(lures.get(lure_id, 0)) != 0:
		return false
	lures[lure_id] = int(lures.get(lure_id, 0)) + 1
	expected_fish.erase("dirty")
	fish_after = fish_after.duplicate(true)
	fish_after.erase("dirty")
	if _normalized_json(expected_fish) != _normalized_json(fish_after):
		return false
	var record_before: Dictionary = data.record_before
	var record_after: Dictionary = data.record_after
	var crafted: Dictionary = data.crafted_record
	if str(crafted.get("lure_id", "")) != lure_id or not record_before.get("records") is Array or not record_after.get("records") is Array:
		return false
	for existing in record_before.records:
		if not existing is Dictionary or str(existing.get("lure_id", "")) == lure_id:
			return false
	if not _integer_number(record_before.get("next_instance_number", null)) or not _integer_number(record_after.get("next_instance_number", null)):
		return false
	var expected_record := record_before.duplicate(true)
	expected_record.records.append(crafted)
	expected_record.next_instance_number = int(record_before.next_instance_number) + 1
	return _normalized_json(expected_record) == _normalized_json(record_after)


static func _valid_sale_intent(data: Dictionary) -> bool:
	for key in ["amount", "unit_value_zenny", "total_value_zenny"]:
		if not data.has(key) or not _integer_number(data[key]):
			return false
	for key in ["transaction_id", "item_id", "item_save_path", "wallet_save_path"]:
		if not data.get(key) is String or str(data[key]).strip_edges().is_empty():
			return false
	if not str(data["item_save_path"]).begins_with("user://") or not str(data["wallet_save_path"]).begins_with("user://"):
		return false
	var amount := int(data["amount"])
	var unit_value := int(data["unit_value_zenny"])
	var total := int(data["total_value_zenny"])
	if amount <= 0 or unit_value <= 0 or total <= 0 or total != amount * unit_value:
		return false
	var player_before: Dictionary = data["player_before"]
	var player_after: Dictionary = data["player_after"]
	var wallet_before: Dictionary = data["wallet_before"]
	var wallet_after: Dictionary = data["wallet_after"]
	if not player_before.get("counts", null) is Dictionary or not player_after.get("counts", null) is Dictionary:
		return false
	if not wallet_before.has("zenny_balance") or not wallet_after.has("zenny_balance"):
		return false
	if not _integer_number(wallet_before["zenny_balance"]) or not _integer_number(wallet_after["zenny_balance"]):
		return false
	var item_id := str(data["item_id"])
	var before_counts: Dictionary = player_before["counts"]
	var after_counts: Dictionary = player_after["counts"]
	if not _valid_count_map(before_counts) or not _valid_count_map(after_counts):
		return false
	if int(before_counts.get(item_id, 0)) < amount or int(after_counts.get(item_id, 0)) != int(before_counts.get(item_id, 0)) - amount:
		return false
	if int(wallet_after["zenny_balance"]) != int(wallet_before["zenny_balance"]) + total:
		return false
	var expected_player := player_before.duplicate(true)
	var expected_counts: Dictionary = before_counts.duplicate(true)
	var remaining := int(before_counts.get(item_id, 0)) - amount
	if remaining == 0:
		expected_counts.erase(item_id)
	else:
		expected_counts[item_id] = remaining
	expected_player["counts"] = expected_counts
	var expected_wallet := wallet_before.duplicate(true)
	expected_wallet["zenny_balance"] = int(wallet_before["zenny_balance"]) + total
	if _normalized_json(expected_player) != _normalized_json(player_after) or _normalized_json(expected_wallet) != _normalized_json(wallet_after):
		return false
	return true


static func _valid_mixed_intent(data: Dictionary) -> bool:
	for key in ["transaction_id", "item_save_path", "wallet_save_path"]:
		if not data.get(key) is String or str(data[key]).strip_edges().is_empty():
			return false
	if not str(data["item_save_path"]).begins_with("user://") or not str(data["wallet_save_path"]).begins_with("user://"):
		return false
	for key in ["fish_costs", "player_costs", "player_rewards", "consumed_fish"]:
		if not data.get(key) is Dictionary:
			return false
	for key in ["fish_costs", "player_costs", "player_rewards"]:
		if not _valid_count_map(data[key]):
			return false
		for raw_id in data[key]:
			if str(raw_id).strip_edges().is_empty() or int(data[key][raw_id]) <= 0:
				return false
	var player_before: Dictionary = data.get("player_before", {})
	var player_after: Dictionary = data.get("player_after", {})
	var fish_before: Dictionary = data.get("wallet_before", {})
	var fish_after: Dictionary = data.get("wallet_after", {})
	if not player_before.get("counts") is Dictionary or not player_before.get("metadata") is Dictionary or not player_after.get("counts") is Dictionary or not player_after.get("metadata") is Dictionary:
		return false
	if not _valid_count_map(player_before.counts) or not _valid_count_map(player_after.counts):
		return false
	for count in player_before.counts.values():
		if int(count) < 0:
			return false
	for count in player_after.counts.values():
		if int(count) < 0:
			return false
	if not fish_before.get("fish_specimens") is Dictionary or not fish_after.get("fish_specimens") is Dictionary:
		return false
	if not _valid_specimens(fish_before.fish_specimens, true) or not _valid_specimens(fish_after.fish_specimens, true):
		return false
	var expected_player: Dictionary = player_before.duplicate(true)
	var counts: Dictionary = expected_player.counts
	for raw_key in data.player_costs:
		var key := str(raw_key)
		var remaining := int(counts.get(key, 0)) - int(data.player_costs[raw_key])
		if remaining < 0:
			return false
		if remaining == 0:
			counts.erase(key)
		else:
			counts[key] = remaining
	for raw_key in data.player_rewards:
		var key := str(raw_key)
		counts[key] = int(counts.get(key, 0)) + int(data.player_rewards[raw_key])
	var expected_fish: Dictionary = fish_before.duplicate(true)
	var specimens: Dictionary = expected_fish.fish_specimens
	var consumed: Dictionary = data.consumed_fish
	if consumed.size() != data.fish_costs.size():
		return false
	for raw_key in data.fish_costs:
		var key := str(raw_key)
		if not consumed.get(key) is Array or not specimens.get(key) is Array:
			return false
		var removed: Array = consumed[key]
		if removed.size() != int(data.fish_costs[raw_key]):
			return false
		var remaining: Array = specimens[key].duplicate(true)
		for entry in removed:
			if not entry is Dictionary:
				return false
			var match_index := -1
			for index in range(remaining.size()):
				if _normalized_json(remaining[index]) == _normalized_json(entry):
					match_index = index
					break
			if match_index < 0:
				return false
			remaining.remove_at(match_index)
		if remaining.is_empty():
			specimens.erase(key)
		else:
			specimens[key] = remaining
	expected_player.erase("dirty")
	player_after = player_after.duplicate(true)
	player_after.erase("dirty")
	expected_fish.erase("dirty")
	fish_after = fish_after.duplicate(true)
	fish_after.erase("dirty")
	return _normalized_json(expected_player) == _normalized_json(player_after) and _normalized_json(expected_fish) == _normalized_json(fish_after)


static func _normalized_json(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))


static func _valid_count_map(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for count in value.values():
		if not _integer_number(count):
			return false
	return true


static func _valid_specimens(value: Variant, current: bool) -> bool:
	if not value is Dictionary:
		return false
	for species_key in value.keys():
		if str(species_key).strip_edges().is_empty():
			return false
		var entries: Variant = value[species_key]
		if not entries is Array:
			return false
		for entry in entries:
			if not entry is Dictionary:
				return false
			if current:
				for key in CURRENT_SPECIMEN_KEYS:
					if not entry.has(key):
						return false
				if str(entry["species_id"]).strip_edges().is_empty():
					return false
			for key in entry.keys():
				var item: Variant = entry[key]
				if key in ["specimen_id", "points"] and not _integer_number(item):
					return false
				if key == "size" and not _number(item):
					return false
				if key in ["is_king", "legacy"] and not item is bool:
					return false
				if key in ["species_id", "fish_name", "spot_id", "spot_name", "lure_id", "lure_name", "catch_transaction_id"] and not item is String:
					return false
	return true


static func _valid_records(value: Variant, current: bool) -> bool:
	if not value is Dictionary:
		return false
	for record in value.values():
		if not record is Dictionary:
			return false
		if current:
			for key in CURRENT_RECORD_KEYS:
				if not record.has(key):
					return false
		for key in record.keys():
			var item: Variant = record[key]
			if key in ["caught_count", "record_miss_streak", "best_size_points", "best_size_score_tier", "best_points", "best_points_score_tier", "last_catch_points", "last_catch_score_tier", "king_count"] and not _integer_number(item):
				return false
			if key in ["best_size", "best_points_size", "last_catch_size", "last_catch_size_ratio_to_king"] and not _number(item):
				return false
			if key in ["last_catch_is_king", "king_caught"] and not item is bool:
				return false
			if key in ["fish_name", "best_size_spot_id", "best_size_spot_name", "best_size_lure_id", "best_size_lure_name", "best_points_spot_id", "best_points_spot_name", "best_points_lure_id", "best_points_lure_name", "last_catch_size_band", "last_catch_spot_id", "last_catch_spot_name", "last_catch_lure_id", "last_catch_lure_name"] and not item is String:
				return false
		for field in ["known_spots", "successful_lures"]:
			if record.has(field) and not _valid_discovery_entries(record[field], "spot_id" if field == "known_spots" else "lure_id", "spot_name" if field == "known_spots" else "lure_name"):
				return false
	return true


static func _valid_discovery_entries(value: Variant, id_key: String, name_key: String) -> bool:
	if not value is Array:
		return false
	for entry in value:
		if not entry is Dictionary:
			return false
		if not entry.has(id_key) or not entry[id_key] is String or str(entry[id_key]).strip_edges().is_empty():
			return false
		if entry.has(name_key) and not entry[name_key] is String:
			return false
	return true


static func _number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _integer_number(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _preserve(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	for index in range(1, 10000):
		var target := absolute + ".invalid.%04d" % index
		if not FileAccess.file_exists(target) and not DirAccess.dir_exists_absolute(target):
			return DirAccess.rename_absolute(absolute, target) == OK
	return false


static func erase_known_valid(path: String, maximum_version: int, required_keys: Dictionary) -> bool:
	# Explicit reset must clear sidecars too, or an old backup can resurrect.
	for candidate in [path, path + ".bak", path + ".tmp", path + ".tmp.next"]:
		var state := _inspect(candidate, maximum_version, required_keys)
		if state.status != "missing" and state.status != "valid":
			return false
	for candidate in [path + ".tmp.next", path + ".tmp", path + ".bak", path]:
		if FileAccess.file_exists(candidate):
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate)) != OK:
				return false
	return true


static func _qa_enabled(path: String, stage: String) -> bool:
	return (not OS.get_environment("FISHING_QA_RUN_ID").is_empty()
		and (path.begins_with("user://durability_focus/")
			or path.begins_with("user://sale_fault_qa/")
			or path.begins_with("user://mixed_exchange_qa/"))
		and OS.get_environment("FISHING_QA_FAULT_STAGE") == stage)


static func _qa_pause(path: String, stage: String) -> void:
	if not _qa_enabled(path, stage):
		return
	var marker_path := "user://mixed_exchange_qa/fault.marker" if path.begins_with("user://mixed_exchange_qa/") else ("user://sale_fault_qa/fault.marker" if path.begins_with("user://sale_fault_qa/") else "user://durability_focus/fault.marker")
	var marker := FileAccess.open(marker_path, FileAccess.WRITE)
	if marker != null:
		marker.store_string(stage)
		marker.close()
	OS.delay_msec(15000)


static func _qa_failure(path: String, stage: String) -> bool:
	return _qa_enabled(path, stage)
