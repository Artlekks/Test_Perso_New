extends Node
class_name FishingCardMakerService
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")
const SaveStorage = preload("res://scripts/fishing_save_storage.gd")

signal card_made(result: Dictionary)
signal pending_recovery_completed(result: Dictionary)

const PENDING_PATH := "user://fishing_card_maker_pending.json"
const PENDING_TEMP_PATH := "user://fishing_card_maker_pending.tmp"
const JOURNAL_VERSION := 1
const SOURCE_TYPE := &"card_maker"

var recipe_catalog: FishingCardMakerCatalog = null
var fishing_inventory: FishingInventory = null
var content_catalog: FishingContentCatalog = null
var _cached_game: Node = null

var _pending_path: String = PENDING_PATH
var _pending_temp_path: String = PENDING_TEMP_PATH

var _transaction_counter: int = 0

func configure_pending_journal_paths(
	pending_path: String,
	pending_temp_path: String
) -> void:
	if (
		recipe_catalog != null
		or fishing_inventory != null
		or content_catalog != null
	):
		return

	var clean_pending: String = pending_path.strip_edges()
	var clean_temp: String = pending_temp_path.strip_edges()

	_pending_path = (
		clean_pending
		if not clean_pending.is_empty()
		else PENDING_PATH
	)

	_pending_temp_path = (
		clean_temp
		if not clean_temp.is_empty()
		else PENDING_TEMP_PATH
	)


func get_pending_journal_paths() -> Dictionary:
	return {
		"pending_path": _pending_path,
		"pending_temp_path": _pending_temp_path,
	}

func configure(
	new_recipe_catalog: FishingCardMakerCatalog,
	new_fishing_inventory: FishingInventory,
	new_content_catalog: FishingContentCatalog
) -> void:
	recipe_catalog = new_recipe_catalog
	fishing_inventory = new_fishing_inventory
	content_catalog = new_content_catalog
	if fishing_inventory != null:
		SaveStorage.register_card_maker_journal(_pending_path, _pending_temp_path,
			fishing_inventory.get_save_path())


func bind_triple_triad_game(game: Node) -> void:
	if is_instance_valid(game):
		_cached_game = game
	else:
		_cached_game = null


func get_all_recipe_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if recipe_catalog == null:
		return result
	for recipe in recipe_catalog.get_all_recipes():
		result.append(evaluate_recipe(recipe.recipe_id))
	return result


func evaluate_recipe(recipe_id: StringName) -> Dictionary:
	if recipe_catalog == null or fishing_inventory == null:
		return _failure(recipe_id, "card_maker_unavailable")
	var recipe: FishingCardMakerRecipe = recipe_catalog.get_recipe(recipe_id)
	if recipe == null or not recipe.enabled:
		return _failure(recipe_id, "unknown_recipe")

	var game: Node = _find_game()
	if game == null:
		return _failure(recipe_id, "triple_triad_game_unavailable")
	if not game.has_method("get_card_snapshot") or not game.has_method("get_player_snapshot"):
		return _failure(recipe_id, "triple_triad_card_api_unavailable")

	var card_snapshot: Dictionary = game.call("get_card_snapshot", recipe.card_id)
	if card_snapshot.is_empty():
		return _failure(recipe_id, "unknown_card")
	var player_snapshot: Dictionary = game.call("get_player_snapshot")
	var duel_rank: int = maxi(1, int(player_snapshot.get("duel_rank", 1)))
	var card_quantity: int = maxi(0, int(card_snapshot.get("quantity", 0)))
	var fish_owned: int = fishing_inventory.get_fish_count(String(recipe.fish_species_id))
	var zenny_owned: int = fishing_inventory.get_zenny()

	var quote: Dictionary = build_quote_from_state(
		recipe,
		fish_owned,
		zenny_owned,
		card_quantity,
		duel_rank
	)
	quote["card_display_name"] = str(card_snapshot.get("display_name", String(recipe.card_id)))
	quote["fish_display_name"] = _fish_display_name(recipe.fish_species_id)
	if not bool(player_snapshot.get("card_game_unlocked", false)):
		quote["can_make"] = false
		quote["reason"] = "card_game_locked"
	return quote


func build_quote_from_state(
	recipe: FishingCardMakerRecipe,
	fish_owned: int,
	zenny_owned: int,
	card_quantity: int,
	duel_rank: int
) -> Dictionary:
	if recipe == null:
		return _failure(&"", "unknown_recipe")
	var is_duplicate_print: bool = card_quantity > 0
	var fish_required: int = (
		maxi(0, recipe.duplicate_fish_count)
		if is_duplicate_print
		else maxi(0, recipe.first_time_fish_count)
	)
	var zenny_required: int = (
		maxi(0, recipe.duplicate_zenny)
		if is_duplicate_print
		else maxi(0, recipe.first_time_zenny)
	)
	var result := {
		"success": false,
		"can_make": false,
		"reason": "",
		"recipe_id": String(recipe.recipe_id),
		"display_name": recipe.display_name,
		"description": recipe.description,
		"fish_species_id": String(recipe.fish_species_id),
		"card_id": String(recipe.card_id),
		"is_duplicate_print": is_duplicate_print,
		"card_quantity_before": maxi(0, card_quantity),
		"fish_required": fish_required,
		"zenny_required": zenny_required,
		"fish_owned": maxi(0, fish_owned),
		"zenny_owned": maxi(0, zenny_owned),
		"minimum_duel_rank": maxi(1, recipe.minimum_duel_rank),
		"duel_rank": maxi(1, duel_rank),
	}
	if not recipe.enabled:
		result["reason"] = "recipe_disabled"
		return result
	if maxi(1, duel_rank) < maxi(1, recipe.minimum_duel_rank):
		result["reason"] = "duel_rank_too_low"
		return result
	if maxi(0, fish_owned) < fish_required:
		result["reason"] = "not_enough_fish"
		return result
	if maxi(0, zenny_owned) < zenny_required:
		result["reason"] = "not_enough_zenny"
		return result
	result["can_make"] = true
	result["reason"] = "ok"
	return result


func make_card(
	recipe_id: StringName,
	source_context: StringName = &"card_maker"
) -> Dictionary:
	if fishing_inventory != null and SaveStorage.has_pending_for_store(fishing_inventory.get_save_path()):
		return _failure(recipe_id, "pending_cross_store_transaction")
	if _catch_journal_pending():
		return _failure(recipe_id, "pending_catch_transaction")
	var recovery: Dictionary = recover_pending_transaction()
	if bool(recovery.get("blocked", false)):
		return {
			"success": false,
			"reason": "pending_recovery_blocked",
			"recovery": recovery,
		}
	if str(recovery.get("reason", "")) != "nothing_pending":
		return {"success": false, "reason": "pending_transaction_recovered",
			"recovery": recovery}

	var quote: Dictionary = evaluate_recipe(recipe_id)
	if not bool(quote.get("can_make", false)):
		return quote
	var game: Node = _find_game()
	if game == null or not game.has_method("claim_world_source_card"):
		quote["reason"] = "triple_triad_acquisition_api_unavailable"
		return quote

	if not fishing_inventory.commit_changes():
		quote["reason"] = "fishing_inventory_save_failed"
		return quote
	var inventory_snapshot: Dictionary = fishing_inventory.create_transaction_snapshot()
	if _snapshot_phase(_disk_inventory_snapshot(), inventory_snapshot, inventory_snapshot) != "after":
		quote["reason"] = "fishing_inventory_changed"
		return quote
	var planned_after := _planned_inventory_after(inventory_snapshot,
		str(quote.get("fish_species_id", "")), int(quote.get("fish_required", 0)),
		int(quote.get("zenny_required", 0)))
	if planned_after.is_empty():
		quote["reason"] = "inventory_plan_failed"
		return quote
	var transaction_id: String = _create_transaction_id()
	var pending: Dictionary = {
		"version": JOURNAL_VERSION,
		"transaction_id": transaction_id,
		"recipe_id": str(quote.get("recipe_id", "")),
		"card_id": str(quote.get("card_id", "")),
		"card_quantity_before": int(quote.get("card_quantity_before", 0)),
		"inventory_snapshot": inventory_snapshot,
		"inventory_after": planned_after,
	}
	if not _write_pending(pending):
		quote["reason"] = "pending_journal_write_failed"
		return quote
	_qa_pause("after_intent")

	fishing_inventory.begin_notification_batch()
	var fish_required: int = int(quote.get("fish_required", 0))
	if fish_required > 0:
		var fish_result: Dictionary = fishing_inventory.consume_fish_costs(
			PackedStringArray([str(quote.get("fish_species_id", ""))]),
			PackedInt32Array([fish_required]),
			false
		)
		if not bool(fish_result.get("success", false)):
			_restore_inventory_snapshot(inventory_snapshot, false)
			fishing_inventory.cancel_notification_batch()
			_clear_pending()
			quote["reason"] = "fish_inventory_changed"
			return quote
		quote["consumed_specimens"] = fish_result.get("consumed_specimens", {})

	var zenny_required: int = int(quote.get("zenny_required", 0))
	if zenny_required > 0 and not fishing_inventory.spend_zenny(zenny_required, false):
		_restore_inventory_snapshot(inventory_snapshot, false)
		fishing_inventory.cancel_notification_batch()
		_clear_pending()
		quote["reason"] = "wallet_changed"
		return quote

	if _snapshot_phase(fishing_inventory.create_transaction_snapshot(), inventory_snapshot, planned_after) != "after":
		_restore_inventory_snapshot(inventory_snapshot, false)
		fishing_inventory.cancel_notification_batch()
		quote["reason"] = "inventory_plan_changed"
		return quote
	SaveStorage.begin_card_maker_write(_pending_path)
	var inventory_saved := fishing_inventory.commit_changes()
	SaveStorage.end_card_maker_write()
	if not inventory_saved:
		_restore_inventory_snapshot(inventory_snapshot, false)
		fishing_inventory.cancel_notification_batch()
		quote["reason"] = "fishing_inventory_save_failed"
		return quote
	_qa_pause("after_inventory_commit")
	if _snapshot_phase(_disk_inventory_snapshot(), inventory_snapshot, planned_after) != "after":
		fishing_inventory.cancel_notification_batch()
		quote["reason"] = "fishing_inventory_commit_unverified"
		return quote

	var acquisition: Dictionary = game.call(
		"claim_world_source_card",
		SOURCE_TYPE,
		recipe_id,
		StringName(str(quote.get("card_id", ""))),
		source_context
	)
	if not bool(acquisition.get("success", false)):
		var rollback_saved: bool = _restore_inventory_snapshot(inventory_snapshot, true)
		fishing_inventory.cancel_notification_batch()
		if rollback_saved:
			_clear_pending()
		quote["reason"] = "card_grant_failed"
		quote["acquisition"] = acquisition.duplicate(true)
		quote["rollback_saved"] = rollback_saved
		return quote

	fishing_inventory.commit_notification_batch()
	_qa_pause("before_cleanup")
	var cleaned := _clear_pending()
	quote["success"] = true
	quote["can_make"] = true
	quote["reason"] = "completed"
	quote["transaction_id"] = transaction_id
	quote["journal_cleanup_pending"] = not cleaned
	quote["card_quantity_after"] = int(acquisition.get("quantity_after", int(quote.get("card_quantity_before", 0)) + 1))
	quote["zenny_after"] = fishing_inventory.get_zenny()
	quote["fish_owned_after"] = fishing_inventory.get_fish_count(str(quote.get("fish_species_id", "")))
	quote["acquisition"] = acquisition.duplicate(true)
	card_made.emit(quote.duplicate(true))
	return quote


func recover_pending_transaction() -> Dictionary:
	if has_pending_transaction() and fishing_inventory != null and SaveStorage.has_pending_for_store(fishing_inventory.get_save_path()):
		return {"recovered": false, "reason": "pending_cross_store_transaction", "blocked": true}
	if has_pending_transaction() and _catch_journal_pending():
		return {"recovered": false, "reason": "pending_catch_transaction", "blocked": true}
	var state := _read_pending()
	if state.status == "new":
		return {"recovered": false, "reason": "nothing_pending", "blocked": false}
	if state.status != "valid":
		return {"recovered": false, "reason": str(state.status) + "_pending_journal", "blocked": true}
	if fishing_inventory == null:
		return {"recovered": false, "reason": "inventory_unavailable", "blocked": true}
	var game: Node = _find_game()
	if game == null or not game.has_method("get_card_snapshot"):
		return {"recovered": false, "reason": "triple_triad_not_ready", "blocked": true}
	var pending: Dictionary = state.data
	var card_id := StringName(str(pending.get("card_id", "")))
	var before_quantity: int = int(pending.card_quantity_before)
	var card_snapshot: Dictionary = game.call("get_card_snapshot", card_id)
	if not _nonnegative_integer(card_snapshot.get("quantity", null)):
		return {"recovered": false, "reason": "card_state_unavailable", "blocked": true}
	var current_quantity: int = int(card_snapshot.quantity)
	var result := {
		"recovered": false,
		"blocked": true,
		"transaction_id": str(pending.get("transaction_id", "")),
		"card_id": String(card_id),
		"card_quantity_before": before_quantity,
		"card_quantity_now": current_quantity,
	}
	var before: Dictionary = pending.inventory_snapshot
	var recipe: FishingCardMakerRecipe = recipe_catalog.get_recipe(StringName(str(pending.recipe_id))) if recipe_catalog != null else null
	if recipe == null or String(recipe.card_id) != str(pending.card_id):
		result.reason = "pending_recipe_unavailable"
		return result
	var fish_cost := recipe.duplicate_fish_count if before_quantity > 0 else recipe.first_time_fish_count
	var zenny_cost := recipe.duplicate_zenny if before_quantity > 0 else recipe.first_time_zenny
	var expected_after := _planned_inventory_after(before, String(recipe.fish_species_id), fish_cost, zenny_cost)
	var after: Dictionary = pending.get("inventory_after", expected_after)
	if _snapshot_phase(after, expected_after, expected_after) != "after":
		result.reason = "invalid_pending_transition"
		return result
	if after.is_empty():
		result.reason = "pending_inventory_plan_unavailable"
		return result
	var phase := _snapshot_phase(_disk_inventory_snapshot(), before, after)
	if current_quantity == before_quantity + 1 and phase == "after":
		result.reason = "commit_already_completed"
	elif current_quantity == before_quantity and phase == "before":
		result.reason = "rolled_back_unfinished_transaction"
	elif current_quantity == before_quantity and phase == "after":
		var rollback_saved := _restore_inventory_snapshot(before, true)
		result.rollback_saved = rollback_saved
		if not rollback_saved or _snapshot_phase(_disk_inventory_snapshot(), before, after) != "before":
			result.reason = "rollback_save_failed"
			return result
		result.reason = "rolled_back_unfinished_transaction"
	else:
		result.reason = "ambiguous_pending_state"
		return result
	if not _clear_pending():
		result.reason = "pending_journal_clear_failed"
		return result
	result.recovered = true
	result.blocked = false
	pending_recovery_completed.emit(result.duplicate(true))
	return result


func has_pending_transaction() -> bool:
	return _journal_occupied(_pending_path) or _journal_occupied(_pending_temp_path)


func _find_game() -> Node:
	if is_instance_valid(_cached_game):
		return _cached_game

	# FishingSessionServices is intentionally initialized before its deferred
	# attachment to the SceneTree. During that short bootstrap window this
	# service is a valid Node, but calling get_tree() would make Godot emit
	# "Parameter data.tree is null". Treat that state as temporarily
	# unavailable and let the next runtime query resolve the game normally.
	if not is_inside_tree():
		return null

	var tree: SceneTree = get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return null
	_cached_game = GameplaySceneRoot.resolve(tree).find_child("TripleTriadGame", true, false)
	return _cached_game


func _fish_display_name(species_id: StringName) -> String:
	if content_catalog != null and content_catalog.has_method("get_fish_by_id"):
		var fish = content_catalog.call("get_fish_by_id", species_id)
		if fish != null:
			return str(fish.get("fish_name"))
	return String(species_id)


func _failure(recipe_id: StringName, reason: String) -> Dictionary:
	return {
		"success": false,
		"can_make": false,
		"reason": reason,
		"recipe_id": String(recipe_id),
	}


func _create_transaction_id() -> String:
	_transaction_counter += 1
	return "card-maker-%d-%d-%d" % [
		int(Time.get_unix_time_from_system()),
		Time.get_ticks_usec(),
		_transaction_counter,
	]


func _restore_inventory_snapshot(snapshot: Dictionary, persist: bool) -> bool:
	fishing_inventory.restore_transaction_snapshot(snapshot)
	if not persist:
		return true
	# restore_transaction_snapshot intentionally preserves the old dirty flag;
	# save_to_disk() is required here because the modified state may already
	# have been committed before a card-side failure.
	SaveStorage.begin_card_maker_write(_pending_path)
	var saved := fishing_inventory.save_to_disk()
	SaveStorage.end_card_maker_write()
	return saved


func _write_pending(payload: Dictionary) -> bool:
	if not _valid_pending_payload(payload) or _pending_state().status != "new":
		return false
	var serialized := JSON.stringify(payload, "\t")
	var file := FileAccess.open(_pending_temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(serialized)
	var write_error := file.get_error()
	if write_error == OK:
		file.flush()
		write_error = file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(_pending_temp_path) != serialized:
		return false
	var staged := _pending_state()
	if staged.status != "valid" or staged.source != "temporary":
		return false
	_qa_pause("before_promotion")
	if _qa_failure("fail_promotion") or _journal_occupied(_pending_path):
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(_pending_temp_path),
			ProjectSettings.globalize_path(_pending_path)) != OK:
		return false
	var promoted := _pending_state()
	return promoted.status == "valid" and promoted.source == "primary" and FileAccess.get_file_as_string(_pending_path) == serialized

func _read_pending() -> Dictionary:
	return _pending_state()


func _pending_state() -> Dictionary:
	var primary := _inspect_pending_file(_pending_path)
	var temporary := _inspect_pending_file(_pending_temp_path)
	for entry in [primary, temporary]:
		if entry.status != "missing" and entry.status != "valid":
			return {"status": entry.status, "data": {}}
	if primary.status == "valid" and temporary.status == "valid":
		if JSON.stringify(primary.data) != JSON.stringify(temporary.data):
			return {"status": "ambiguous", "data": {}}
		return {"status": "valid", "source": "primary", "data": primary.data}
	if primary.status == "valid":
		return {"status": "valid", "source": "primary", "data": primary.data}
	if temporary.status == "valid":
		return {"status": "valid", "source": "temporary", "data": temporary.data}
	return {"status": "new", "data": {}}


func _inspect_pending_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "inaccessible" if _journal_occupied(path) else "missing", "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": "inaccessible", "data": {}}
	var raw := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"status": "inaccessible", "data": {}}
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary:
		return {"status": "invalid", "data": {}}
	var payload: Dictionary = parser.data
	if not _nonnegative_integer(payload.get("version", null)):
		return {"status": "invalid", "data": {}}
	if int(payload.version) > JOURNAL_VERSION:
		return {"status": "unsupported", "data": {}}
	if not _valid_pending_payload(payload):
		return {"status": "invalid", "data": {}}
	return {"status": "valid", "data": payload}


func _valid_pending_payload(payload: Dictionary) -> bool:
	if not _nonnegative_integer(payload.get("version", null)) or int(payload.version) != JOURNAL_VERSION:
		return false
	for key in ["transaction_id", "recipe_id", "card_id"]:
		if not payload.get(key) is String or str(payload[key]).strip_edges().is_empty():
			return false
	if not _nonnegative_integer(payload.get("card_quantity_before", null)):
		return false
	if not _valid_inventory_snapshot(payload.get("inventory_snapshot", null)):
		return false
	if payload.has("inventory_after") and not _valid_inventory_snapshot(payload.inventory_after):
		return false
	return true


func _valid_inventory_snapshot(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	if not SaveStorage._valid_specimens(value.get("fish_specimens", null), true):
		return false
	for key in ["lure_counts", "rod_counts"]:
		if not SaveStorage._valid_count_map(value.get(key, null)):
			return false
		for count in value[key].values():
			if int(count) < 0:
				return false
	for key in ["zenny_balance", "next_specimen_id", "manillo_point_units",
			"manillo_stamps", "manillo_stamp_cards"]:
		if not _nonnegative_integer(value.get(key, null)):
			return false
	if int(value.next_specimen_id) < 1 or not value.get("dirty") is bool:
		return false
	return true


func _nonnegative_integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) == floorf(float(value)) and int(value) >= 0


func _planned_inventory_after(before: Dictionary, species_id: String, fish_cost: int, zenny_cost: int) -> Dictionary:
	if species_id.is_empty() or fish_cost < 0 or zenny_cost < 0:
		return {}
	var scratch := FishingInventory.new()
	scratch.restore_transaction_snapshot(before)
	var consumed := scratch.consume_fish_costs(PackedStringArray([species_id]), PackedInt32Array([fish_cost]), false)
	var paid := scratch.spend_zenny(zenny_cost, false)
	var result := scratch.create_transaction_snapshot() if bool(consumed.get("success", false)) and paid else {}
	scratch.free()
	return result


func _disk_inventory_snapshot() -> Dictionary:
	if fishing_inventory == null:
		return {}
	var path := fishing_inventory.get_save_path()
	if SaveStorage.read(path, FishingInventory.SAVE_VERSION, FishingInventory.SAVE_KEYS).status != "valid":
		return {}
	var disk_inventory := FishingInventory.new()
	disk_inventory.configure_save_path(path)
	var loaded := disk_inventory.load_from_disk()
	var snapshot := disk_inventory.create_transaction_snapshot() if loaded else {}
	disk_inventory.free()
	return snapshot


func _snapshot_phase(actual: Dictionary, before: Dictionary, after: Dictionary) -> String:
	if actual.is_empty():
		return "unknown"
	var candidate := actual.duplicate(true)
	var old := before.duplicate(true)
	var planned := after.duplicate(true)
	for entry in [candidate, old, planned]:
		entry.erase("dirty")
	if SaveStorage._normalized_json(candidate) == SaveStorage._normalized_json(planned):
		return "after"
	if SaveStorage._normalized_json(candidate) == SaveStorage._normalized_json(old):
		return "before"
	return "unknown"


func _clear_pending() -> bool:
	if _qa_failure("fail_cleanup"):
		return false
	for path in [_pending_temp_path, _pending_path]:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			return false
	return not has_pending_transaction()


func _journal_occupied(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _catch_journal_pending() -> bool:
	return FileAccess.file_exists("user://fishing_catch_pending.json") or FileAccess.file_exists("user://fishing_catch_pending.tmp")


func _qa_failure(stage: String) -> bool:
	return not OS.get_environment("FISHING_QA_RUN_ID").is_empty() and OS.get_environment("FISHING_QA_CARD_FAULT") == stage


func _qa_pause(stage: String) -> void:
	if not OS.get_environment("FISHING_QA_RUN_ID").is_empty() and OS.get_environment("FISHING_QA_CARD_PAUSE") == stage:
		var marker := FileAccess.open("user://card_maker_fault.marker", FileAccess.WRITE)
		if marker != null:
			marker.store_string(stage)
			marker.close()
		OS.delay_msec(15000)
