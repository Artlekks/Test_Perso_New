extends Node
class_name FishingCardMakerService

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
	var recovery: Dictionary = recover_pending_transaction()
	if bool(recovery.get("blocked", false)):
		return {
			"success": false,
			"reason": "pending_recovery_blocked",
			"recovery": recovery,
		}

	var quote: Dictionary = evaluate_recipe(recipe_id)
	if not bool(quote.get("can_make", false)):
		return quote
	var game: Node = _find_game()
	if game == null or not game.has_method("claim_world_source_card"):
		quote["reason"] = "triple_triad_acquisition_api_unavailable"
		return quote

	var inventory_snapshot: Dictionary = fishing_inventory.create_transaction_snapshot()
	var transaction_id: String = _create_transaction_id()
	var pending: Dictionary = {
		"version": JOURNAL_VERSION,
		"transaction_id": transaction_id,
		"recipe_id": str(quote.get("recipe_id", "")),
		"card_id": str(quote.get("card_id", "")),
		"card_quantity_before": int(quote.get("card_quantity_before", 0)),
		"inventory_snapshot": inventory_snapshot,
	}
	if not _write_pending(pending):
		quote["reason"] = "pending_journal_write_failed"
		return quote

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

	if not fishing_inventory.commit_changes():
		_restore_inventory_snapshot(inventory_snapshot, false)
		fishing_inventory.cancel_notification_batch()
		_clear_pending()
		quote["reason"] = "fishing_inventory_save_failed"
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
	_clear_pending()
	quote["success"] = true
	quote["can_make"] = true
	quote["reason"] = "completed"
	quote["transaction_id"] = transaction_id
	quote["card_quantity_after"] = int(acquisition.get("quantity_after", int(quote.get("card_quantity_before", 0)) + 1))
	quote["zenny_after"] = fishing_inventory.get_zenny()
	quote["fish_owned_after"] = fishing_inventory.get_fish_count(str(quote.get("fish_species_id", "")))
	quote["acquisition"] = acquisition.duplicate(true)
	card_made.emit(quote.duplicate(true))
	return quote


func recover_pending_transaction() -> Dictionary:
	var pending: Dictionary = _read_pending()
	if pending.is_empty():
		return {"recovered": false, "reason": "nothing_pending", "blocked": false}
	if fishing_inventory == null:
		return {"recovered": false, "reason": "inventory_unavailable", "blocked": true}
	var game: Node = _find_game()
	if game == null or not game.has_method("get_card_snapshot"):
		return {"recovered": false, "reason": "triple_triad_not_ready", "blocked": true}

	var card_id := StringName(str(pending.get("card_id", "")))
	var before_quantity: int = maxi(0, int(pending.get("card_quantity_before", 0)))
	var card_snapshot: Dictionary = game.call("get_card_snapshot", card_id)
	var current_quantity: int = maxi(0, int(card_snapshot.get("quantity", 0)))
	var result := {
		"recovered": true,
		"blocked": false,
		"transaction_id": str(pending.get("transaction_id", "")),
		"card_id": String(card_id),
		"card_quantity_before": before_quantity,
		"card_quantity_now": current_quantity,
	}
	if current_quantity > before_quantity:
		result["reason"] = "commit_already_completed"
		_clear_pending()
		pending_recovery_completed.emit(result.duplicate(true))
		return result

	var raw_snapshot = pending.get("inventory_snapshot", {})
	if not (raw_snapshot is Dictionary):
		result["recovered"] = false
		result["blocked"] = true
		result["reason"] = "invalid_pending_snapshot"
		return result
	var rollback_saved: bool = _restore_inventory_snapshot(raw_snapshot, true)
	result["rollback_saved"] = rollback_saved
	result["reason"] = "rolled_back_unfinished_transaction" if rollback_saved else "rollback_save_failed"
	result["recovered"] = rollback_saved
	result["blocked"] = not rollback_saved
	if rollback_saved:
		_clear_pending()
		pending_recovery_completed.emit(result.duplicate(true))
	return result


func has_pending_transaction() -> bool:
	return FileAccess.file_exists(
		_pending_path
	)


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
	if tree == null or tree.current_scene == null:
		return null
	_cached_game = tree.current_scene.find_child("TripleTriadGame", true, false)
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
	return fishing_inventory.save_to_disk()


func _write_pending(
	payload: Dictionary
) -> bool:
	var file := FileAccess.open(
		_pending_temp_path,
		FileAccess.WRITE
	)

	if file == null:
		return false

	file.store_string(
		JSON.stringify(
			payload,
			"\t"
		)
	)

	file.close()

	var temp_absolute: String = (
		ProjectSettings.globalize_path(
			_pending_temp_path
		)
	)

	var final_absolute: String = (
		ProjectSettings.globalize_path(
			_pending_path
		)
	)

	if FileAccess.file_exists(
		_pending_path
	):
		DirAccess.remove_absolute(
			final_absolute
		)

	return (
		DirAccess.rename_absolute(
			temp_absolute,
			final_absolute
		)
		== OK
	)

func _read_pending() -> Dictionary:
	if not FileAccess.file_exists(
		_pending_path
	):
		return {}

	var file := FileAccess.open(
		_pending_path,
		FileAccess.READ
	)

	if file == null:
		return {}

	var parsed = JSON.parse_string(
		file.get_as_text()
	)

	file.close()

	if not (parsed is Dictionary):
		return {}

	var payload: Dictionary = parsed

	if int(
		payload.get(
			"version",
			0
		)
	) != JOURNAL_VERSION:
		return {}

	return payload

func _clear_pending() -> void:
	for path in [
		_pending_path,
		_pending_temp_path,
	]:
		if not FileAccess.file_exists(
			path
		):
			continue

		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(
				path
			)
		)
