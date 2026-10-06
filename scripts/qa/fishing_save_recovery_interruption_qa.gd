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


class SignalProbe:
	extends RefCounted

	var transaction_completed_count: int = 0

	func on_transaction_completed(
		_result: Dictionary
	) -> void:
		transaction_completed_count += 1


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
