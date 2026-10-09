extends RefCounted

const Storage = preload("res://scripts/triple_triad/triple_triad_config_store.gd")

const JOURNAL_PATH := "user://triple_triad_transfer_journal.cfg"
const JOURNAL_VERSION := 1
const OpponentCollectionScript = preload("res://scripts/triple_triad/triple_triad_opponent_collection.gd")


func has_pending_transfer() -> bool:
	var config := ConfigFile.new()
	if config.load(JOURNAL_PATH) != OK or not config.has_section("transaction"):
		return false
	var card_id: String = str(config.get_value("transaction", "card_id", "")).strip_edges()
	var opponent_id: String = str(config.get_value("transaction", "opponent_id", "")).strip_edges()
	return not card_id.is_empty() and not opponent_id.is_empty()


func recover_pending(catalog: Resource, player_collection) -> bool:
	var config := ConfigFile.new()
	if config.load(JOURNAL_PATH) != OK or not config.has_section("transaction"):
		return true
	if player_collection.has_method("can_commit_state") and player_collection.can_commit_state() != OK:
		return false

	var card_id := StringName(str(config.get_value("transaction", "card_id", "")))
	var opponent_id := StringName(str(config.get_value("transaction", "opponent_id", "")))
	if String(card_id).is_empty() or String(opponent_id).is_empty():
		_clear_journal()
		return true

	var card = null
	if catalog != null and catalog.has_method("get_card_by_id"):
		card = catalog.call("get_card_by_id", card_id)
	if card == null:
		push_warning("TripleTriadCardEconomy: dropping journal for missing card %s." % String(card_id))
		_clear_journal()
		return false

	# Opponent state is guaranteed to have been initialized/saved before a match
	# can reach the reward transfer. Loading by id is therefore sufficient here.
	var opponent_collection = OpponentCollectionScript.new()
	opponent_collection.initialize(catalog, opponent_id, 1, 10, 50, null)
	var desired_player: int = maxi(0, int(config.get_value("transaction", "player_quantity", 0)))
	var desired_opponent: int = maxi(0, int(config.get_value("transaction", "opponent_quantity", 0)))
	var promote_for_rematch: bool = bool(config.get_value("transaction", "promote_for_rematch", false))

	player_collection.set_quantity_by_id(card_id, desired_player, false)
	opponent_collection.set_quantity_by_id(card_id, desired_opponent, false)
	if promote_for_rematch and desired_opponent > 0:
		opponent_collection.promote_card(card_id, false)

	var player_error: Error = player_collection.save_state()
	var opponent_error: Error = opponent_collection.save_state()
	if player_error != OK or opponent_error != OK:
		push_warning("TripleTriadCardEconomy: pending transfer recovery could not be fully saved.")
		return false
	return _clear_journal()


func reconcile_quantities(
	catalog: Resource,
	card_id: StringName,
	opponent_id: StringName,
	desired_player: int,
	desired_opponent: int,
	player_collection,
	promote_for_rematch: bool
) -> bool:
	if (
		catalog == null
		or String(card_id).is_empty()
		or String(opponent_id).is_empty()
		or player_collection == null
	):
		return false
	if has_pending_transfer():
		return false
	if player_collection.has_method("can_commit_state") and player_collection.can_commit_state() != OK:
		return false
	if (
		not catalog.has_method("get_card_by_id")
		or catalog.call("get_card_by_id", card_id) == null
	):
		return false

	var opponent_collection = OpponentCollectionScript.new()
	opponent_collection.initialize(
		catalog,
		opponent_id,
		1,
		10,
		50,
		null
	)

	if not _write_journal(
		card_id,
		opponent_id,
		maxi(0, desired_player),
		maxi(0, desired_opponent),
		promote_for_rematch
	):
		return false

	player_collection.set_quantity_by_id(
		card_id,
		maxi(0, desired_player),
		false
	)
	opponent_collection.set_quantity_by_id(
		card_id,
		maxi(0, desired_opponent),
		false
	)
	if promote_for_rematch and desired_opponent > 0:
		opponent_collection.promote_card(card_id, false)

	var player_error: Error = player_collection.save_state()
	var opponent_error: Error = opponent_collection.save_state()
	if player_error != OK or opponent_error != OK:
		return false
	return _clear_journal()


func transfer_player_to_opponent(card, player_collection, opponent_collection) -> bool:
	if has_pending_transfer():
		push_warning("TripleTriadCardEconomy: refusing a second transfer while recovery is pending.")
		return false
	if card == null or player_collection == null or opponent_collection == null:
		return false
	var card_id := StringName(card.card_id)
	var player_before: int = player_collection.get_quantity_by_id(card_id)
	if player_before <= 0:
		return false
	var opponent_before: int = opponent_collection.get_quantity_by_id(card_id)
	return _commit_transfer(
		card_id,
		player_before - 1,
		opponent_before + 1,
		player_collection,
		opponent_collection,
		true
	)


func transfer_opponent_to_player(card, player_collection, opponent_collection) -> bool:
	if has_pending_transfer():
		push_warning("TripleTriadCardEconomy: refusing a second transfer while recovery is pending.")
		return false
	if card == null or player_collection == null or opponent_collection == null:
		return false
	var card_id := StringName(card.card_id)
	var opponent_before: int = opponent_collection.get_quantity_by_id(card_id)
	if opponent_before <= 0:
		return false
	var player_before: int = player_collection.get_quantity_by_id(card_id)
	return _commit_transfer(
		card_id,
		player_before + 1,
		opponent_before - 1,
		player_collection,
		opponent_collection,
		false
	)


func _commit_transfer(
	card_id: StringName,
	desired_player: int,
	desired_opponent: int,
	player_collection,
	opponent_collection,
	promote_for_rematch: bool
) -> bool:
	if player_collection.has_method("can_commit_state") and player_collection.can_commit_state() != OK:
		return false
	var opponent_id: StringName = opponent_collection.get_opponent_id()
	if not _write_journal(card_id, opponent_id, desired_player, desired_opponent, promote_for_rematch):
		return false

	player_collection.set_quantity_by_id(card_id, desired_player, false)
	opponent_collection.set_quantity_by_id(card_id, desired_opponent, false)
	if promote_for_rematch and desired_opponent > 0:
		opponent_collection.promote_card(card_id, false)

	var player_error: Error = player_collection.save_state()
	var opponent_error: Error = opponent_collection.save_state()
	if player_error != OK or opponent_error != OK:
		# Keep the journal. recover_pending() will force both sides to the exact
		# intended quantities on the next session, so cards cannot duplicate/vanish.
		return false
	if not _clear_journal():
		# Ownership is already in the intended state. Keeping the journal makes the
		# recovery idempotent on next boot and prevents another transfer this session.
		return false
	return true


func _write_journal(
	card_id: StringName,
	opponent_id: StringName,
	player_quantity: int,
	opponent_quantity: int,
	promote_for_rematch: bool
) -> bool:
	var config := ConfigFile.new()
	config.set_value("transaction", "version", JOURNAL_VERSION)
	config.set_value("transaction", "card_id", String(card_id))
	config.set_value("transaction", "opponent_id", String(opponent_id))
	config.set_value("transaction", "player_quantity", maxi(0, player_quantity))
	config.set_value("transaction", "opponent_quantity", maxi(0, opponent_quantity))
	config.set_value("transaction", "promote_for_rematch", promote_for_rematch)
	var save_error: Error = Storage.commit(config, JOURNAL_PATH)
	if save_error != OK:
		push_warning("TripleTriadCardEconomy: could not write transfer journal (%s)." % error_string(save_error))
		return false
	return true


func _clear_journal() -> bool:
	var config := ConfigFile.new()
	# Saving an empty ConfigFile is portable and keeps recovery logic simple.
	var save_error: Error = Storage.commit(config, JOURNAL_PATH)
	if save_error != OK:
		push_warning("TripleTriadCardEconomy: could not clear transfer journal (%s)." % error_string(save_error))
		return false
	return true
