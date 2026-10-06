extends RefCounted
class_name FishingSaveRecoveryInterruptionQA

## Save / recovery interruption QA v1.
##
## This suite never uses the player's real save paths.
##
## It simulates process restarts by:
## - writing state through one service instance
## - discarding that instance
## - creating a fresh instance against the same isolated QA path
##
## It also deliberately forces one persistence failure to prove that
## GameItemTransactionService restores the pre-transaction inventory state.

const MatchResolutionJournalScript = preload(
	"res://scripts/triple_triad/triple_triad_match_resolution_journal.gd"
)

const WorldRewardLedgerScript = preload(
	"res://scripts/triple_triad/triple_triad_world_reward_ledger.gd"
)

const PlayerInventoryScript = preload(
	"res://scripts/items/player_item_inventory.gd"
)

const InventoryFacadeScript = preload(
	"res://scripts/items/game_inventory_facade.gd"
)

const TransactionServiceScript = preload(
	"res://scripts/items/game_item_transaction_service.gd"
)

const FishingProgressScript = preload(
	"res://scripts/fishing_progress.gd"
)

const FishingInventoryScript = preload(
	"res://scripts/fishing_inventory.gd"
)

const CatchRepositoryScript = preload(
	"res://scripts/fishing_catch_repository.gd"
)

const CatchEvaluatorScript = preload(
	"res://scripts/fishing_catch_evaluator.gd"
)

const CardMakerServiceScript = preload(
	"res://scripts/economy/fishing_card_maker_service.gd"
)

const CardMakerCatalogResource = preload(
	"res://data/economy/card_maker/card_maker_catalog_v1.tres"
)

const FishingContentCatalogResource = preload(
	"res://data/bof4/catalogs/all_content.tres"
)

const ItemCatalogServiceScript = preload(
	"res://scripts/items/game_item_catalog_service.gd"
)

const EconomyConfigResource = preload(
	"res://data/economy/economy_foundation_v1.tres"
)

const QA_ROOT := "user://fishing_save_recovery_qa_v1"

const MATCH_RESOLUTION_PATH := (
	QA_ROOT
	+ "/triple_triad_match_resolution.cfg"
)

const WORLD_REWARD_PATH := (
	QA_ROOT
	+ "/triple_triad_world_reward.cfg"
)

const PLAYER_ITEM_PATH := (
	QA_ROOT
	+ "/player_items.json"
)

const SAVE_FAILURE_BLOCKER_PATH := (
	QA_ROOT
	+ "/save_failure_blocker"
)

const SAVE_FAILURE_PATH := (
	SAVE_FAILURE_BLOCKER_PATH
	+ "/inventory.json"
)

const CATCH_PROGRESS_PATH := (
	QA_ROOT
	+ "/catch_progress.json"
)

const CATCH_INVENTORY_PATH := (
	QA_ROOT
	+ "/catch_inventory.json"
)

const CATCH_PENDING_PATH := (
	QA_ROOT
	+ "/catch_pending.json"
)

const CATCH_PENDING_TEMP_PATH := (
	QA_ROOT
	+ "/catch_pending.tmp"
)

const CATCH_FAILURE_BLOCKER_PATH := (
	QA_ROOT
	+ "/catch_inventory_blocker"
)

const CATCH_FAILURE_SAVE_PATH := (
	CATCH_FAILURE_BLOCKER_PATH
	+ "/inventory.json"
)

const CARD_MAKER_INVENTORY_PATH := (
	QA_ROOT
	+ "/card_maker_inventory.json"
)

const CARD_MAKER_PENDING_PATH := (
	QA_ROOT
	+ "/card_maker_pending.json"
)

const CARD_MAKER_PENDING_TEMP_PATH := (
	QA_ROOT
	+ "/card_maker_pending.tmp"
)

class SignalProbe:
	extends RefCounted

	var transaction_completed_count: int = 0

	func on_transaction_completed(
		_result: Dictionary
	) -> void:
		transaction_completed_count += 1

class MockCardGame:
	extends Node

	var quantities: Dictionary = {}

	func set_quantity(
		card_id: StringName,
		quantity: int
	) -> void:
		quantities[String(card_id)] = maxi(
			0,
			quantity
		)

	func get_card_snapshot(
		card_id: StringName
	) -> Dictionary:
		return {
			"card_id": String(card_id),
			"display_name": "QA Card",
			"quantity": maxi(
				0,
				int(
					quantities.get(
						String(card_id),
						0
					)
				)
			),
		}

	func get_player_snapshot() -> Dictionary:
		return {
			"duel_rank": 10,
			"card_game_unlocked": true,
		}

static func run(
	session: Node
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
		"valid": false,
	}

	_cleanup_test_files()

	var root_ready: bool = (
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(QA_ROOT)
		) == OK
	)

	if not root_ready:
		_record(
			report,
			"QA recovery sandbox can be created",
			false,
			"Could not create the isolated QA save directory."
		)

		report["valid"] = false
		return report

	_test_match_resolution_restart(report)
	_test_world_reward_restart(report)
	_test_player_inventory_restart(
		report,
		session
	)
	_test_transaction_save_failure(
		report,
		session
	)

	_test_catch_repository_recovery(
		report
	)

	_test_card_maker_recovery(
		report
	)

	_cleanup_test_files()

	var cleanup_ok: bool = (
		not FileAccess.file_exists(
			MATCH_RESOLUTION_PATH
		)
		and not FileAccess.file_exists(
			WORLD_REWARD_PATH
		)
		and not FileAccess.file_exists(
			PLAYER_ITEM_PATH
		)
		and not FileAccess.file_exists(
			SAVE_FAILURE_BLOCKER_PATH
		)
	)

	_record(
		report,
		"Recovery QA removes all temporary save files",
		cleanup_ok,
		"The interruption suite must leave no persistent QA state behind."
	)

	report["valid"] = (
		int(report["passed_count"])
		== int(report["test_count"])
	)

	return report


static func _test_match_resolution_restart(
	report: Dictionary
) -> void:
	var journal = (
		MatchResolutionJournalScript.new()
	)

	journal.initialize(
		MATCH_RESOLUTION_PATH
	)

	var begin_ok: bool = journal.begin_resolution({
		"opponent_id": "qa_opponent",
		"winner": 1,
		"result_reason": "qa_win",
		"surrendered": false,
		"player_card_ids": PackedStringArray([
			"p1",
			"p2",
			"p3",
			"p4",
			"p5",
		]),
		"opponent_card_ids": PackedStringArray([
			"o1",
			"o2",
			"o3",
			"o4",
			"o5",
		]),
		"eligible_reward_ids": PackedStringArray([
			"o1",
			"o2",
		]),
		"competition_change": {
			"points": 3,
		},
	})

	_record(
		report,
		"Resolution journal durably begins a pending match",
		begin_ok
		and journal.has_pending(),
		"A legal unresolved card match must be durable before reward transfer starts."
	)

	journal = null

	var restarted = (
		MatchResolutionJournalScript.new()
	)

	restarted.initialize(
		MATCH_RESOLUTION_PATH
	)

	var restart_snapshot: Dictionary = (
		restarted.get_snapshot()
	)

	_record(
		report,
		"Pending match survives simulated process restart",
		bool(
			restart_snapshot.get(
				"pending",
				false
			)
		)
		and str(
			restart_snapshot.get(
				"opponent_id",
				""
			)
		) == "qa_opponent"
		and int(
			restart_snapshot.get(
				"winner",
				0
			)
		) == 1
		and (
			restart_snapshot.get(
				"player_card_ids",
				PackedStringArray()
			)
			as PackedStringArray
		).size() == 5,
		"An interruption after result creation must not lose the unresolved match."
	)

	var selection_ok: bool = (
		restarted.record_selection(
			&"o2",
			{
				"from_owner": "opponent",
				"to_owner": "player",
				"quantity": 1,
			}
		)
	)

	restarted = null

	var after_selection = (
		MatchResolutionJournalScript.new()
	)

	after_selection.initialize(
		MATCH_RESOLUTION_PATH
	)

	var selected_snapshot: Dictionary = (
		after_selection.get_snapshot()
	)

	_record(
		report,
		"Selected card transfer survives simulated restart",
		selection_ok
		and str(
			selected_snapshot.get(
				"selected_card_id",
				""
			)
		) == "o2"
		and not bool(
			selected_snapshot.get(
				"transfer_committed",
				true
			)
		),
		"A crash after reward selection must preserve which transfer was being attempted."
	)

	var transfer_marked: bool = (
		after_selection.mark_transfer_committed()
	)

	after_selection = null

	var after_transfer = (
		MatchResolutionJournalScript.new()
	)

	after_transfer.initialize(
		MATCH_RESOLUTION_PATH
	)

	var transfer_snapshot: Dictionary = (
		after_transfer.get_snapshot()
	)

	var metadata_marked: bool = (
		after_transfer.mark_metadata_committed()
	)

	after_transfer = null

	var after_metadata = (
		MatchResolutionJournalScript.new()
	)

	after_metadata.initialize(
		MATCH_RESOLUTION_PATH
	)

	var metadata_snapshot: Dictionary = (
		after_metadata.get_snapshot()
	)

	_record(
		report,
		"Partial match-resolution commit stages survive restart",
		transfer_marked
		and metadata_marked
		and bool(
			transfer_snapshot.get(
				"transfer_committed",
				false
			)
		)
		and not bool(
			transfer_snapshot.get(
				"metadata_committed",
				true
			)
		)
		and bool(
			metadata_snapshot.get(
				"transfer_committed",
				false
			)
		)
		and bool(
			metadata_snapshot.get(
				"metadata_committed",
				false
			)
		),
		"Recovery must know exactly which durable resolution stages completed before interruption."
	)

	var clear_ok: bool = (
		after_metadata.clear()
	)

	after_metadata = null

	var after_clear = (
		MatchResolutionJournalScript.new()
	)

	after_clear.initialize(
		MATCH_RESOLUTION_PATH
	)

	_record(
		report,
		"Completed resolution remains cleared after restart",
		clear_ok
		and not after_clear.has_pending()
		and after_clear.get_snapshot().is_empty(),
		"Once resolution is finalized, a later boot must not replay the old card transfer."
	)


static func _test_world_reward_restart(
	report: Dictionary
) -> void:
	var ledger = (
		WorldRewardLedgerScript.new()
	)

	ledger.initialize(
		WORLD_REWARD_PATH
	)

	var begin_ok: bool = (
		ledger.begin_delivery(
			&"qa_reward_event",
			&"quest_reward",
			&"qa_request",
			&"qa_card",
			&"save_recovery_qa",
			0
		)
	)

	_record(
		report,
		"World reward ledger durably begins delivery",
		begin_ok
		and not ledger.get_pending_delivery(
			&"qa_reward_event"
		).is_empty(),
		"A one-shot reward needs a durable pending record before external card delivery."
	)

	ledger = null

	var restarted = (
		WorldRewardLedgerScript.new()
	)

	restarted.initialize(
		WORLD_REWARD_PATH
	)

	var pending: Dictionary = (
		restarted.get_pending_delivery(
			&"qa_reward_event"
		)
	)

	_record(
		report,
		"Pending world reward survives simulated restart",
		not pending.is_empty()
		and str(
			pending.get(
				"card_id",
				""
			)
		) == "qa_card"
		and not restarted.has_claimed(
			&"qa_reward_event"
		),
		"An interrupted reward must remain recoverable rather than disappear or become prematurely claimed."
	)

	var duplicate_same: bool = (
		restarted.begin_delivery(
			&"qa_reward_event",
			&"quest_reward",
			&"qa_request",
			&"qa_card",
			&"save_recovery_qa",
			0
		)
	)

	var conflicting_duplicate: bool = (
		restarted.begin_delivery(
			&"qa_reward_event",
			&"quest_reward",
			&"qa_request",
			&"different_card",
			&"save_recovery_qa",
			0
		)
	)

	_record(
		report,
		"Pending world reward is idempotent but rejects conflicting replay",
		duplicate_same
		and not conflicting_duplicate
		and restarted.get_pending_deliveries().size()
		== 1,
		"Retrying the same delivery must be safe, while the same event id may not silently change reward payload."
	)

	var complete_ok: bool = (
		restarted.complete_delivery(
			&"qa_reward_event"
		)
	)

	restarted = null

	var after_completion = (
		WorldRewardLedgerScript.new()
	)

	after_completion.initialize(
		WORLD_REWARD_PATH
	)

	_record(
		report,
		"Completed world reward claim survives restart",
		complete_ok
		and after_completion.has_claimed(
			&"qa_reward_event"
		)
		and after_completion.get_pending_delivery(
			&"qa_reward_event"
		).is_empty(),
		"Once external reward delivery succeeds, the one-shot claim must remain durable."
	)

	var replay_blocked: bool = not (
		after_completion.begin_delivery(
			&"qa_reward_event",
			&"quest_reward",
			&"qa_request",
			&"qa_card",
			&"save_recovery_qa",
			1
		)
	)

	_record(
		report,
		"Claimed world reward cannot be replayed",
		replay_blocked
		and after_completion.has_claimed(
			&"qa_reward_event"
		),
		"A restart or repeated interaction must never duplicate a completed one-shot reward."
	)

	var counter_value: int = (
		after_completion.increment_counter(
			&"qa_counter"
		)
	)

	after_completion = null

	var counter_restart = (
		WorldRewardLedgerScript.new()
	)

	counter_restart.initialize(
		WORLD_REWARD_PATH
	)

	_record(
		report,
		"World reward counters survive restart",
		counter_value == 1
		and counter_restart.get_counter(
			&"qa_counter"
		) == 1,
		"Durable progression counters may not drift or reset merely because the application restarted."
	)


static func _test_player_inventory_restart(
	report: Dictionary,
	session: Node
) -> void:
	var catalog = _item_catalog(
		session
	)

	var item_id: StringName = (
		_prepared_bait_item_id(
			catalog
		)
	)

	if (
		catalog == null
		or item_id == &""
		or catalog.get_definition(
			item_id
		) == null
	):
		_record(
			report,
			"Player-item persisted grant survives restart",
			false,
			"Canonical prepared-bait item could not be resolved."
		)

		_record(
			report,
			"Player-item persisted removal survives restart",
			false,
			"Canonical prepared-bait item could not be resolved."
		)

		return

	var inventory = (
		PlayerInventoryScript.new()
	)

	inventory.configure(
		PLAYER_ITEM_PATH
	)

	inventory.initialize()

	inventory.grant(
		item_id,
		3,
		true
	)

	inventory = null

	var restarted = (
		PlayerInventoryScript.new()
	)

	restarted.configure(
		PLAYER_ITEM_PATH
	)

	restarted.initialize()

	_record(
		report,
		"Player-item persisted grant survives restart",
		restarted.get_count(
			item_id
		) == 3,
		"A successfully saved item grant must be visible to a fresh inventory instance."
	)

	var remove_ok: bool = (
		restarted.remove(
			item_id,
			2,
			true
		)
	)

	restarted = null

	var after_remove = (
		PlayerInventoryScript.new()
	)

	after_remove.configure(
		PLAYER_ITEM_PATH
	)

	after_remove.initialize()

	_record(
		report,
		"Player-item persisted removal survives restart",
		remove_ok
		and after_remove.get_count(
			item_id
		) == 1,
		"A successfully saved debit must remain durable without over-consuming the stack."
	)

	after_remove.free()


static func _test_transaction_save_failure(
	report: Dictionary,
	session: Node
) -> void:
	var catalog = _item_catalog(
		session
	)

	var item_id: StringName = (
		_prepared_bait_item_id(
			catalog
		)
	)

	if (
		catalog == null
		or item_id == &""
		or catalog.get_definition(
			item_id
		) == null
	):
		_record(
			report,
			"Failed persistent transaction restores inventory",
			false,
			"Canonical prepared-bait item could not be resolved."
		)

		_record(
			report,
			"Failed persistent transaction emits no completion event",
			false,
			"Canonical prepared-bait item could not be resolved."
		)

		return

	_remove_path(
		SAVE_FAILURE_BLOCKER_PATH
	)

	var blocker := FileAccess.open(
		SAVE_FAILURE_BLOCKER_PATH,
		FileAccess.WRITE
	)

	if blocker == null:
		_record(
			report,
			"Failed persistent transaction restores inventory",
			false,
			"Could not create the deliberate save-path blocker."
		)

		_record(
			report,
			"Failed persistent transaction emits no completion event",
			false,
			"Could not create the deliberate save-path blocker."
		)

		return

	blocker.store_string(
		"THIS FILE DELIBERATELY BLOCKS A CHILD SAVE PATH"
	)

	blocker.close()

	var inventory = (
		PlayerInventoryScript.new()
	)

	inventory.configure(
		SAVE_FAILURE_PATH
	)

	inventory.grant(
		item_id,
		1,
		false
	)

	var facade = (
		InventoryFacadeScript.new()
	)

	facade.configure(
		catalog,
		inventory,
		null
	)

	var transaction = (
		TransactionServiceScript.new()
	)

	transaction.configure(
		catalog,
		inventory,
		facade,
		null
	)

	var probe := SignalProbe.new()

	transaction.transaction_completed.connect(
		Callable(
			probe,
			"on_transaction_completed"
		)
	)

	var result: Dictionary = (
		transaction.consume_player_items(
			{
				String(item_id): 1,
			},
			true,
			&"qa_forced_save_failure"
		)
	)

	_record(
		report,
		"Failed persistent transaction restores inventory",
		not bool(
			result.get(
				"success",
				true
			)
		)
		and str(
			result.get(
				"reason",
				""
			)
		) == "save_failed"
		and inventory.get_count(
			item_id
		) == 1
		and not inventory.is_notification_batch_active(),
		"A disk failure after debit must restore the pre-transaction quantity and close the notification batch."
	)

	_record(
		report,
		"Failed persistent transaction emits no completion event",
		probe.transaction_completed_count == 0,
		"A transaction that rolled back because persistence failed must never be advertised as completed."
	)

	transaction.free()
	facade.free()
	inventory.free()

	_remove_path(
		SAVE_FAILURE_BLOCKER_PATH
	)

static func _test_catch_repository_recovery(
	report: Dictionary
) -> void:
	_remove_path(
		CATCH_PROGRESS_PATH
	)

	_remove_path(
		CATCH_INVENTORY_PATH
	)

	_remove_path(
		CATCH_PENDING_PATH
	)

	_remove_path(
		CATCH_PENDING_TEMP_PATH
	)

	_remove_path(
		CATCH_FAILURE_BLOCKER_PATH
	)

	var blocker := FileAccess.open(
		CATCH_FAILURE_BLOCKER_PATH,
		FileAccess.WRITE
	)

	if blocker == null:
		_record(
			report,
			"Interrupted catch leaves a durable recovery journal",
			false,
			"Could not create the deliberate catch-inventory save blocker."
		)

		_record(
			report,
			"Catch recovery repairs the missing durable side exactly once",
			false,
			"Catch interruption fixture could not be created."
		)

		_record(
			report,
			"Repeated catch recovery cannot duplicate the catch",
			false,
			"Catch interruption fixture could not be created."
		)

		return

	blocker.store_string(
		"THIS FILE DELIBERATELY BLOCKS THE CATCH INVENTORY SAVE"
	)

	blocker.close()

	var fish = _get_qa_fish()

	if fish == null:
		_record(
			report,
			"Interrupted catch leaves a durable recovery journal",
			false,
			"No authored fish was available for catch recovery QA."
		)

		_record(
			report,
			"Catch recovery repairs the missing durable side exactly once",
			false,
			"No authored fish was available for catch recovery QA."
		)

		_record(
			report,
			"Repeated catch recovery cannot duplicate the catch",
			false,
			"No authored fish was available for catch recovery QA."
		)

		_remove_path(
			CATCH_FAILURE_BLOCKER_PATH
		)

		return

	var progress = (
		FishingProgressScript.new()
	)

	progress.configure_save_path(
		CATCH_PROGRESS_PATH
	)

	progress.initialize()

	var inventory = (
		FishingInventoryScript.new()
	)

	inventory.configure_save_path(
		CATCH_FAILURE_SAVE_PATH
	)

	var repository = (
		CatchRepositoryScript.new()
	)

	repository.configure_pending_journal_paths(
		CATCH_PENDING_PATH,
		CATCH_PENDING_TEMP_PATH
	)

	repository.configure(
		progress,
		inventory
	)

	var snapshot: Dictionary = (
		CatchEvaluatorScript.create_snapshot_from_values(
			fish,
			maxf(
				float(fish.average_size),
				1.0
			),
			{
				"spot_id": "qa_recovery_spot",
				"spot_name": "QA Recovery Spot",
				"lure_id": "qa_lure",
				"lure_name": "QA Lure",
			}
		)
	)

	snapshot["transaction_id"] = (
		"qa-catch-interruption-001"
	)

	var transaction_id: String = str(
		snapshot.get(
			"transaction_id",
			""
		)
	)

	var species_id: String = str(
		snapshot.get(
			"species_id",
			""
		)
	)

	var result: Dictionary = (
		repository.commit_snapshot(
			snapshot
		)
	)

	var interruption_created: bool = (
		bool(
			result.get(
				"committed",
				false
			)
		)
		and not bool(
			result.get(
				"durable",
				true
			)
		)
		and bool(
			result.get(
				"pending_recovery",
				false
			)
		)
		and repository.has_pending_transaction()
		and progress.has_catch_transaction(
			transaction_id
		)
	)

	_record(
		report,
		"Interrupted catch leaves a durable recovery journal",
		interruption_created,
		"When progress saves but physical inventory cannot, the catch journal must remain pending for recovery."
	)

	repository.free()
	progress.free()
	inventory.free()

	_remove_path(
		CATCH_FAILURE_BLOCKER_PATH
	)

	var restarted_progress = (
		FishingProgressScript.new()
	)

	restarted_progress.configure_save_path(
		CATCH_PROGRESS_PATH
	)

	restarted_progress.initialize()

	var restarted_inventory = (
		FishingInventoryScript.new()
	)

	restarted_inventory.configure_save_path(
		CATCH_INVENTORY_PATH
	)

	restarted_inventory.initialize()

	var restarted_repository = (
		CatchRepositoryScript.new()
	)

	restarted_repository.configure_pending_journal_paths(
		CATCH_PENDING_PATH,
		CATCH_PENDING_TEMP_PATH
	)

	restarted_repository.configure(
		restarted_progress,
		restarted_inventory
	)

	var recovered_exactly_once: bool = (
		not restarted_repository.has_pending_transaction()
		and restarted_progress.has_catch_transaction(
			transaction_id
		)
		and restarted_inventory.has_catch_transaction(
			transaction_id
		)
		and restarted_progress.get_total_catches()
		== 1
		and restarted_inventory.get_fish_count(
			species_id
		) == 1
	)

	_record(
		report,
		"Catch recovery repairs the missing durable side exactly once",
		recovered_exactly_once,
		"After restart, recovery must fill only the missing inventory side and preserve the already-saved progress side."
	)

	var catches_before_repeat: int = (
		restarted_progress.get_total_catches()
	)

	var fish_before_repeat: int = (
		restarted_inventory.get_fish_count(
			species_id
		)
	)

	var repeat_recovery: Dictionary = (
		restarted_repository.recover_pending_transaction()
	)

	_record(
		report,
		"Repeated catch recovery cannot duplicate the catch",
		str(
			repeat_recovery.get(
				"reason",
				""
			)
		) == "nothing_pending"
		and restarted_progress.get_total_catches()
		== catches_before_repeat
		and restarted_inventory.get_fish_count(
			species_id
		) == fish_before_repeat,
		"Once the journal is resolved, another recovery attempt must be a no-op."
	)

	restarted_repository.free()
	restarted_progress.free()
	restarted_inventory.free()

static func _test_card_maker_recovery(
	report: Dictionary
) -> void:
	var recipe = _get_qa_card_maker_recipe()

	if recipe == null:
		for label in [
			"Interrupted Card Maker transaction is durably staged",
			"Card Maker restart rolls back unfinished transaction",
			"Repeated Card Maker recovery cannot refund twice",
			"Completed Card Maker transaction is not incorrectly refunded",
		]:
			_record(
				report,
				label,
				false,
				"No suitable authored first-print Card Maker recipe was available."
			)

		return

	var fish_required: int = maxi(
		1,
		int(
			recipe.first_time_fish_count
		)
	)

	var zenny_required: int = maxi(
		0,
		int(
			recipe.first_time_zenny
		)
	)

	var baseline_fish: int = (
		fish_required + 1
	)

	var baseline_zenny: int = (
		zenny_required + 200
	)

	_cleanup_card_maker_recovery_files()

	var inventory = (
		_create_card_maker_inventory(
			CARD_MAKER_INVENTORY_PATH,
			recipe,
			baseline_fish,
			baseline_zenny
		)
	)

	if inventory == null:
		for label in [
			"Interrupted Card Maker transaction is durably staged",
			"Card Maker restart rolls back unfinished transaction",
			"Repeated Card Maker recovery cannot refund twice",
			"Completed Card Maker transaction is not incorrectly refunded",
		]:
			_record(
				report,
				label,
				false,
				"Could not create the isolated Card Maker inventory."
			)

		return

	var before_snapshot: Dictionary = (
		inventory.create_transaction_snapshot()
	)

	var fish_consumed: Dictionary = (
		inventory.consume_fish_costs(
			PackedStringArray([
				String(
					recipe.fish_species_id
				),
			]),
			PackedInt32Array([
				fish_required,
			]),
			false
		)
	)

	var zenny_spent: bool = (
		inventory.spend_zenny(
			zenny_required,
			false
		)
	)

	var spent_saved: bool = (
		bool(
			fish_consumed.get(
				"success",
				false
			)
		)
		and zenny_spent
		and inventory.commit_changes()
	)

	var game := MockCardGame.new()

	game.set_quantity(
		recipe.card_id,
		0
	)

	var service = (
		CardMakerServiceScript.new()
	)

	service.configure_pending_journal_paths(
		CARD_MAKER_PENDING_PATH,
		CARD_MAKER_PENDING_TEMP_PATH
	)

	service.configure(
		CardMakerCatalogResource,
		inventory,
		FishingContentCatalogResource
	)

	service.bind_triple_triad_game(
		game
	)

	var pending_payload := {
		"version": 1,
		"transaction_id": "qa-card-maker-interruption-001",
		"recipe_id": String(
			recipe.recipe_id
		),
		"card_id": String(
			recipe.card_id
		),
		"card_quantity_before": 0,
		"inventory_snapshot": (
			before_snapshot.duplicate(true)
		),
	}

	var pending_written: bool = bool(
		service.call(
			"_write_pending",
			pending_payload
		)
	)

	_record(
		report,
		"Interrupted Card Maker transaction is durably staged",
		spent_saved
		and pending_written
		and service.has_pending_transaction()
		and inventory.get_fish_count(
			String(
				recipe.fish_species_id
			)
		) == baseline_fish - fish_required
		and inventory.get_zenny()
		== baseline_zenny - zenny_required,
		"An interruption after paying Card Maker costs must preserve both the spent inventory and the pre-transaction rollback snapshot."
	)

	service.free()
	inventory.free()

	var restarted_inventory = (
		FishingInventoryScript.new()
	)

	restarted_inventory.configure_save_path(
		CARD_MAKER_INVENTORY_PATH
	)

	restarted_inventory.initialize()

	var restarted_service = (
		CardMakerServiceScript.new()
	)

	restarted_service.configure_pending_journal_paths(
		CARD_MAKER_PENDING_PATH,
		CARD_MAKER_PENDING_TEMP_PATH
	)

	restarted_service.configure(
		CardMakerCatalogResource,
		restarted_inventory,
		FishingContentCatalogResource
	)

	restarted_service.bind_triple_triad_game(
		game
	)

	var rollback_result: Dictionary = (
		restarted_service.recover_pending_transaction()
	)

	_record(
		report,
		"Card Maker restart rolls back unfinished transaction",
		bool(
			rollback_result.get(
				"recovered",
				false
			)
		)
		and str(
			rollback_result.get(
				"reason",
				""
			)
		) == "rolled_back_unfinished_transaction"
		and not restarted_service.has_pending_transaction()
		and restarted_inventory.get_fish_count(
			String(
				recipe.fish_species_id
			)
		) == baseline_fish
		and restarted_inventory.get_zenny()
		== baseline_zenny,
		"If the card quantity never increased, startup recovery must restore the exact pre-payment fishing inventory."
	)

	var repeat_fish: int = (
		restarted_inventory.get_fish_count(
			String(
				recipe.fish_species_id
			)
		)
	)

	var repeat_zenny: int = (
		restarted_inventory.get_zenny()
	)

	var second_recovery: Dictionary = (
		restarted_service.recover_pending_transaction()
	)

	_record(
		report,
		"Repeated Card Maker recovery cannot refund twice",
		str(
			second_recovery.get(
				"reason",
				""
			)
		) == "nothing_pending"
		and restarted_inventory.get_fish_count(
			String(
				recipe.fish_species_id
			)
		) == repeat_fish
		and restarted_inventory.get_zenny()
		== repeat_zenny,
		"Once rollback completes, the same interrupted transaction must never refund costs again."
	)

	restarted_service.free()
	restarted_inventory.free()

	_cleanup_card_maker_recovery_files()

	var committed_inventory = (
		_create_card_maker_inventory(
			CARD_MAKER_INVENTORY_PATH,
			recipe,
			baseline_fish,
			baseline_zenny
		)
	)

	if committed_inventory == null:
		_record(
			report,
			"Completed Card Maker transaction is not incorrectly refunded",
			false,
			"Could not create the committed-transaction fixture."
		)

		game.free()
		return

	var committed_before: Dictionary = (
		committed_inventory.create_transaction_snapshot()
	)

	var committed_fish_result: Dictionary = (
		committed_inventory.consume_fish_costs(
			PackedStringArray([
				String(
					recipe.fish_species_id
				),
			]),
			PackedInt32Array([
				fish_required,
			]),
			false
		)
	)

	var committed_zenny_spent: bool = (
		committed_inventory.spend_zenny(
			zenny_required,
			false
		)
	)

	var committed_spent_saved: bool = (
		bool(
			committed_fish_result.get(
				"success",
				false
			)
		)
		and committed_zenny_spent
		and committed_inventory.commit_changes()
	)

	var committed_service = (
		CardMakerServiceScript.new()
	)

	committed_service.configure_pending_journal_paths(
		CARD_MAKER_PENDING_PATH,
		CARD_MAKER_PENDING_TEMP_PATH
	)

	committed_service.configure(
		CardMakerCatalogResource,
		committed_inventory,
		FishingContentCatalogResource
	)

	committed_service.bind_triple_triad_game(
		game
	)

	var committed_pending := {
		"version": 1,
		"transaction_id": "qa-card-maker-interruption-002",
		"recipe_id": String(
			recipe.recipe_id
		),
		"card_id": String(
			recipe.card_id
		),
		"card_quantity_before": 0,
		"inventory_snapshot": (
			committed_before.duplicate(true)
		),
	}

	var committed_pending_written: bool = bool(
		committed_service.call(
			"_write_pending",
			committed_pending
		)
	)

	committed_service.free()
	committed_inventory.free()

	game.set_quantity(
		recipe.card_id,
		1
	)

	var completed_inventory = (
		FishingInventoryScript.new()
	)

	completed_inventory.configure_save_path(
		CARD_MAKER_INVENTORY_PATH
	)

	completed_inventory.initialize()

	var completed_service = (
		CardMakerServiceScript.new()
	)

	completed_service.configure_pending_journal_paths(
		CARD_MAKER_PENDING_PATH,
		CARD_MAKER_PENDING_TEMP_PATH
	)

	completed_service.configure(
		CardMakerCatalogResource,
		completed_inventory,
		FishingContentCatalogResource
	)

	completed_service.bind_triple_triad_game(
		game
	)

	var completed_recovery: Dictionary = (
		completed_service.recover_pending_transaction()
	)

	_record(
		report,
		"Completed Card Maker transaction is not incorrectly refunded",
		committed_spent_saved
		and committed_pending_written
		and bool(
			completed_recovery.get(
				"recovered",
				false
			)
		)
		and str(
			completed_recovery.get(
				"reason",
				""
			)
		) == "commit_already_completed"
		and not completed_service.has_pending_transaction()
		and completed_inventory.get_fish_count(
			String(
				recipe.fish_species_id
			)
		) == baseline_fish - fish_required
		and completed_inventory.get_zenny()
		== baseline_zenny - zenny_required,
		"If the card already exists after restart, recovery must finalize the journal without refunding costs."
	)

	completed_service.free()
	completed_inventory.free()
	game.free()

	_cleanup_card_maker_recovery_files()
	
static func _get_qa_fish():
	for fish in FishingContentCatalogResource.fish:
		if fish == null:
			continue

		if String(
			fish.get_stable_species_id()
		).strip_edges().is_empty():
			continue

		return fish

	return null


static func _get_qa_card_maker_recipe():
	for recipe in CardMakerCatalogResource.get_all_recipes():
		if recipe == null:
			continue

		if not recipe.enabled:
			continue

		if int(
			recipe.first_time_fish_count
		) <= 0:
			continue

		if String(
			recipe.card_id
		).strip_edges().is_empty():
			continue

		return recipe

	return null


static func _create_card_maker_inventory(
	save_path: String,
	recipe,
	fish_count: int,
	zenny: int
):
	var inventory = (
		FishingInventoryScript.new()
	)

	inventory.configure_save_path(
		save_path
	)

	inventory.initialize()

	for _index in range(
		maxi(
			0,
			fish_count
		)
	):
		var specimen = (
			inventory.add_fish_specimen(
				String(
					recipe.fish_species_id
				),
				"QA Card Maker Fish",
				10.0,
				1,
				false,
				false,
				false,
				{},
				"",
				false
			)
		)

		if specimen == null:
			inventory.free()
			return null

	inventory.set_zenny(
		maxi(
			0,
			zenny
		),
		false
	)

	if not inventory.commit_changes():
		inventory.free()
		return null

	return inventory


static func _cleanup_card_maker_recovery_files() -> void:
	for path in [
		CARD_MAKER_INVENTORY_PATH,
		CARD_MAKER_PENDING_PATH,
		CARD_MAKER_PENDING_TEMP_PATH,
	]:
		_remove_path(
			path
		)
		
static func _item_catalog(
	session: Node
):
	if session == null:
		return null

	return session.get(
		"item_catalog"
	)


static func _prepared_bait_item_id(
	catalog
) -> StringName:
	if catalog == null:
		return &""

	return catalog.make_item_id(
		ItemCatalogServiceScript.STORAGE_PLAYER,
		EconomyConfigResource.prepared_bait_item_domain_id
	)


static func _cleanup_test_files() -> void:
	for path in [
		MATCH_RESOLUTION_PATH,
		WORLD_REWARD_PATH,
		PLAYER_ITEM_PATH,
		SAVE_FAILURE_PATH,
		SAVE_FAILURE_BLOCKER_PATH,
		CATCH_PROGRESS_PATH,
		CATCH_INVENTORY_PATH,
		CATCH_PENDING_PATH,
		CATCH_PENDING_TEMP_PATH,
		CATCH_FAILURE_SAVE_PATH,
		CATCH_FAILURE_BLOCKER_PATH,
		CARD_MAKER_INVENTORY_PATH,
		CARD_MAKER_PENDING_PATH,
		CARD_MAKER_PENDING_TEMP_PATH,
	]:
		_remove_path(path)

	var absolute_root: String = (
		ProjectSettings.globalize_path(
			QA_ROOT
		)
	)

	if DirAccess.dir_exists_absolute(
		absolute_root
	):
		DirAccess.remove_absolute(
			absolute_root
		)


static func _remove_path(
	path: String
) -> void:
	if not FileAccess.file_exists(path):
		return

	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(
			path
		)
	)


static func _record(
	report: Dictionary,
	label: String,
	passed: bool,
	failure_detail: String
) -> void:
	report["test_count"] = (
		int(
			report.get(
				"test_count",
				0
			)
		)
		+ 1
	)

	if passed:
		report["passed_count"] = (
			int(
				report.get(
					"passed_count",
					0
				)
			)
			+ 1
		)
		return

	var failures: PackedStringArray = (
		report.get(
			"failures",
			PackedStringArray()
		)
	)

	failures.append(
		"%s - %s"
		% [
			label,
			failure_detail,
		]
	)

	report["failures"] = failures
