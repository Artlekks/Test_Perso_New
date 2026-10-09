extends RefCounted
class_name FishingTortureQA

## Adversarial integration QA v1.
##
## This suite is deliberately save-safe:
## - live FishingSessionServices is read only
## - transaction tests use isolated in-memory inventories
## - dialogue tests use an isolated DialogueService
## - request-objective tests use mock inventories
## - cast-input tests use the deterministic input gate directly
##
## No player save, card collection, fish inventory, request reward,
## progression state, or authored content is mutated.

const CastInputGateScript = preload(
	"res://scripts/fishing_cast_input_gate.gd"
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

const PreparedBaitServiceScript = preload(
	"res://scripts/economy/fishing_prepared_bait_service.gd"
)

const DialogueServiceScript = preload(
	"res://scripts/dialogue/dialogue_service.gd"
)

const MaterialObjectiveScript = preload(
	"res://scripts/quests/material_count_request_objective.gd"
)

const ItemCatalogServiceScript = preload(
	"res://scripts/items/game_item_catalog_service.gd"
)

const EconomyConfigResource = preload(
	"res://data/economy/economy_foundation_v1.tres"
)

const STRESS_ITERATIONS: int = 64
const DIALOGUE_ITERATIONS: int = 40


class SignalProbe:
	extends RefCounted

	var transaction_count: int = 0
	var dialogue_started_count: int = 0
	var dialogue_finished_count: int = 0
	var objective_progress_count: int = 0
	var prepared_bait_consumed_count: int = 0

	func on_transaction_completed(
		_result: Dictionary
	) -> void:
		transaction_count += 1

	func on_dialogue_started(
		_snapshot: Dictionary
	) -> void:
		dialogue_started_count += 1

	func on_dialogue_finished(
		_dialogue_id: StringName,
		_reason: StringName
	) -> void:
		dialogue_finished_count += 1

	func on_objective_progress(
		_current: int,
		_required: int,
		_complete: bool
	) -> void:
		objective_progress_count += 1

	func on_prepared_bait_consumed(
		_result: Dictionary
	) -> void:
		prepared_bait_consumed_count += 1


class MockMaterialInventory:
	extends Node

	signal material_changed(
		material_id: StringName,
		count: int
	)

	signal changed(snapshot: Dictionary)

	var counts: Dictionary = {}

	func get_count(
		material_id: StringName
	) -> int:
		return maxi(
			0,
			int(counts.get(String(material_id), 0))
		)

	func set_count(
		material_id: StringName,
		count: int
	) -> void:
		var clean_count: int = maxi(0, count)
		var key: String = String(material_id)

		if clean_count <= 0:
			counts.erase(key)
		else:
			counts[key] = clean_count

		material_changed.emit(
			material_id,
			clean_count
		)

		changed.emit({
			"counts": counts.duplicate(true),
		})


static func run(
	session: Node
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
		"valid": false,
		"stress_iterations": STRESS_ITERATIONS,
	}

	var live_items = null
	var live_item_snapshot: Dictionary = {}

	var live_dialogue = null
	var live_dialogue_active_before: bool = false

	if session != null:
		live_items = session.get(
			"player_item_inventory"
		)

		if (
			live_items != null
			and live_items.has_method("get_snapshot")
		):
			live_item_snapshot = (
				live_items.call("get_snapshot")
				as Dictionary
			).duplicate(true)

		live_dialogue = session.get(
			"dialogue_service"
		)

		if (
			live_dialogue != null
			and live_dialogue.has_method("is_active")
		):
			live_dialogue_active_before = bool(
				live_dialogue.call("is_active")
			)

	_test_live_baseline(report, session)
	_test_unconfigured_fail_closed(report)
	_test_cast_input_abuse(report)
	_test_dialogue_reentrancy(report)
	_test_transaction_abuse(report, session)
	_test_prepared_bait_abuse(report, session)
	_test_objective_signal_abuse(report)

	var live_items_unchanged: bool = false

	if (
		live_items != null
		and live_items.has_method("get_snapshot")
	):
		var after_snapshot = live_items.call(
			"get_snapshot"
		)

		live_items_unchanged = (
			after_snapshot is Dictionary
			and after_snapshot == live_item_snapshot
		)

	_record(
		report,
		"Torture QA leaves live player-item inventory unchanged",
		live_items_unchanged,
		"The adversarial suite must never mutate the real player-item inventory."
	)

	var live_dialogue_unchanged: bool = false

	if (
		live_dialogue != null
		and live_dialogue.has_method("is_active")
	):
		live_dialogue_unchanged = (
			bool(live_dialogue.call("is_active"))
			== live_dialogue_active_before
		)

	_record(
		report,
		"Torture QA leaves live dialogue state unchanged",
		live_dialogue_unchanged,
		"Isolated dialogue stress must not open, close, or replace the live conversation."
	)

	report["valid"] = (
		int(report["passed_count"])
		== int(report["test_count"])
	)

	return report


static func _test_live_baseline(
	report: Dictionary,
	session: Node
) -> void:
	_record(
		report,
		"Live session exists before torture testing",
		session != null,
		"Torture QA requires the composed FishingSessionServices host."
	)

	if session == null:
		_record(
			report,
			"Live session is ready before torture testing",
			false,
			"FishingSessionServices is unavailable."
		)

		_record(
			report,
			"Existing stability gate is green before torture testing",
			false,
			"FishingSessionServices is unavailable."
		)

		return

	_record(
		report,
		"Live session is ready before torture testing",
		session.has_method("is_ready")
		and bool(session.call("is_ready")),
		"Torture QA must run only after normal service composition has completed."
	)

	_record(
		report,
		"Existing stability gate is green before torture testing",
		_report_passed(
			FishingSessionQA.reports(session).get(
				"system_stability_qa_report"
			)
		),
		"Adversarial tests should run on top of the already-green integration baseline."
	)


static func _test_unconfigured_fail_closed(
	report: Dictionary
) -> void:
	var transaction = (
		TransactionServiceScript.new()
	)

	var evaluation: Dictionary = (
		transaction.evaluate_player_costs({
			"qa_missing_item": 1,
		})
	)

	_record(
		report,
		"Unconfigured item transaction evaluation fails closed",
		not bool(
			evaluation.get("can_afford", true)
		)
		and str(
			evaluation.get("reason", "")
		) == "item_backend_unavailable",
		"Missing item dependencies must return a controlled failure instead of dereferencing null services."
	)

	var grant_result: Dictionary = (
		transaction.grant_player_items(
			{
				"qa_missing_item": 1,
			},
			false,
			&"torture_unconfigured"
		)
	)

	_record(
		report,
		"Unconfigured item grant fails closed",
		not bool(
			grant_result.get("success", true)
		)
		and str(
			grant_result.get("reason", "")
		) == "item_backend_unavailable",
		"Reward mutation must not proceed before the item backend is configured."
	)

	var prepared = (
		PreparedBaitServiceScript.new()
	)

	var prepared_result: Dictionary = (
		prepared.try_begin_cast(false)
	)

	_record(
		report,
		"Unconfigured prepared bait fails closed",
		not bool(
			prepared_result.get("used", true)
		)
		and str(
			prepared_result.get("reason", "")
		) == "prepared_bait_backend_unavailable",
		"A missing prepared-bait backend must degrade to an ordinary cast rather than crash."
	)

	var dialogue = DialogueServiceScript.new()

	var advance_result: Dictionary = (
		dialogue.advance()
	)

	_record(
		report,
		"Inactive dialogue advance fails closed",
		not bool(
			advance_result.get("success", true)
		)
		and str(
			advance_result.get("reason", "")
		) == "no_active_dialogue",
		"Advancing without an active conversation must remain a harmless rejected action."
	)

	transaction.free()
	prepared.free()
	dialogue.free()


static func _test_cast_input_abuse(
	report: Dictionary
) -> void:
	var gate = CastInputGateScript.new()

	gate.reset(false)

	var first_press = gate.press(
		CastInputGateScript.Stage.AIM
	)

	_record(
		report,
		"First physical cast confirm is consumed once",
		first_press
		== CastInputGateScript.PressResult.CONSUMED,
		"A fresh K press should advance exactly one legal cast stage."
	)

	var held_spam_safe: bool = true

	for _index in range(STRESS_ITERATIONS):
		if (
			gate.press(
				CastInputGateScript.Stage.AIM
			)
			!= CastInputGateScript.PressResult.IGNORED
		):
			held_spam_safe = false
			break

	_record(
		report,
		"Held K spam cannot consume additional cast stages",
		held_spam_safe,
		"Repeated presses without a release must never advance casting again."
	)

	var echo_spam_safe: bool = true

	for _index in range(STRESS_ITERATIONS):
		if (
			gate.press(
				CastInputGateScript.Stage.AIM,
				true
			)
			!= CastInputGateScript.PressResult.IGNORED
		):
			echo_spam_safe = false
			break

	_record(
		report,
		"Keyboard echo spam is ignored",
		echo_spam_safe,
		"OS key-repeat events must never behave like new physical cast confirms."
	)

	gate.release(
		CastInputGateScript.Stage.AIM
	)

	var prep_press = gate.press(
		CastInputGateScript.Stage.PREP_THROW
	)

	var prep_spam_safe: bool = (
		prep_press
		== CastInputGateScript.PressResult.BUFFERED
	)

	for _index in range(STRESS_ITERATIONS):
		if (
			gate.press(
				CastInputGateScript.Stage.PREP_THROW
			)
			!= CastInputGateScript.PressResult.IGNORED
		):
			prep_spam_safe = false
			break

	_record(
		report,
		"Prep Throw accepts only one buffered confirm",
		prep_spam_safe,
		"A fast second physical K may buffer once, but repeated held input must not stack buffers."
	)

	gate.release(
		CastInputGateScript.Stage.PREP_THROW
	)

	var first_buffer: bool = (
		gate.take_prep_buffer()
	)

	var second_buffer: bool = (
		gate.take_prep_buffer()
	)

	var buffer_snapshot: Dictionary = (
		gate.get_debug_snapshot()
	)

	_record(
		report,
		"Buffered cast confirm is consumed exactly once",
		first_buffer
		and not second_buffer
		and bool(
			buffer_snapshot.get(
				"ready_for_press",
				false
			)
		),
		"Prep Throw buffering must not duplicate a future cast transition."
	)

	var curve_press = gate.press(
		CastInputGateScript.Stage.CURVE
	)

	var curve_spam_safe: bool = (
		curve_press
		== CastInputGateScript.PressResult.CONSUMED
	)

	for _index in range(STRESS_ITERATIONS):
		if (
			gate.press(
				CastInputGateScript.Stage.CURVE
			)
			!= CastInputGateScript.PressResult.IGNORED
		):
			curve_spam_safe = false
			break

	_record(
		report,
		"Curve confirmation cannot double-consume",
		curve_spam_safe,
		"One physical confirmation must remain one transition even under repeated input."
	)


static func _test_dialogue_reentrancy(
	report: Dictionary
) -> void:
	var service = DialogueServiceScript.new()
	var probe := SignalProbe.new()

	service.dialogue_started.connect(
		Callable(
			probe,
			"on_dialogue_started"
		)
	)

	service.dialogue_finished.connect(
		Callable(
			probe,
			"on_dialogue_finished"
		)
	)

	var normal_flow_ok: bool = true
	var busy_guard_ok: bool = true

	for index in range(
		DIALOGUE_ITERATIONS
	):
		var dialogue_id := StringName(
			"torture_dialogue_%d" % index
		)

		var started: Dictionary = (
			service.start_inline_dialogue(
				dialogue_id,
				[
					"TORTURE LINE",
				],
				true
			)
		)

		if not bool(
			started.get("success", false)
		):
			normal_flow_ok = false
			break

		var overlapping: Dictionary = (
			service.start_inline_dialogue(
				&"torture_overlap",
				[
					"OVERLAP",
				],
				true
			)
		)

		if (
			bool(
				overlapping.get(
					"success",
					true
				)
			)
			or str(
				overlapping.get(
					"reason",
					""
				)
			) != "dialogue_busy"
		):
			busy_guard_ok = false

		var finished: Dictionary = (
			service.advance()
		)

		if (
			not bool(
				finished.get(
					"success",
					false
				)
			)
			or not bool(
				finished.get(
					"finished",
					false
				)
			)
			or service.is_active()
		):
			normal_flow_ok = false
			break

	_record(
		report,
		"Repeated dialogue open-finish cycles remain deterministic",
		normal_flow_ok,
		"Repeated conversation lifecycle transitions must always return to an inactive state."
	)

	_record(
		report,
		"Overlapping dialogue starts are rejected",
		busy_guard_ok,
		"A second interaction may not replace or stack on top of the active conversation."
	)

	_record(
		report,
		"Dialogue lifecycle signals do not multiply",
		probe.dialogue_started_count
		== DIALOGUE_ITERATIONS
		and probe.dialogue_finished_count
		== DIALOGUE_ITERATIONS,
		"Repeated dialogue use must emit exactly one start and one finish signal per conversation."
	)

	var protected_start: Dictionary = (
		service.start_inline_dialogue(
			&"torture_uncancellable",
			[
				"CANNOT CANCEL",
			],
			false
		)
	)

	var protected_cancel: Dictionary = (
		service.cancel(&"torture_cancel")
	)

	_record(
		report,
		"Cancel cannot steal ownership from protected dialogue",
		bool(
			protected_start.get(
				"success",
				false
			)
		)
		and not bool(
			protected_cancel.get(
				"success",
				true
			)
		)
		and str(
			protected_cancel.get(
				"reason",
				""
			)
		) == "cancel_disabled"
		and service.is_active(),
		"A disabled cancel path must leave the current conversation intact."
	)

	var forced: Dictionary = (
		service.force_close(
			&"torture_cleanup"
		)
	)

	_record(
		report,
		"Forced dialogue cleanup restores a balanced lifecycle",
		bool(
			forced.get("success", false)
		)
		and not service.is_active()
		and probe.dialogue_started_count
		== DIALOGUE_ITERATIONS + 1
		and probe.dialogue_finished_count
		== DIALOGUE_ITERATIONS + 1,
		"Emergency dialogue cleanup must finish exactly once and return ownership cleanly."
	)

	service.free()


static func _test_transaction_abuse(
	report: Dictionary,
	session: Node
) -> void:
	var setup: Dictionary = (
		_make_item_setup(session)
	)

	if setup.is_empty():
		_record_unavailable_group(
			report,
			"Item transaction torture",
			6,
			"Could not create isolated item backend."
		)
		return

	var catalog = setup.get(
		"catalog",
		null
	)

	var items = setup.get(
		"items",
		null
	)

	var transaction = setup.get(
		"transaction",
		null
	)

	var item_id: StringName = setup.get(
		"item_id",
		&""
	)

	var item_available: bool = (
		catalog != null
		and items != null
		and transaction != null
		and item_id != &""
		and catalog.get_definition(
			item_id
		) != null
	)

	_record(
		report,
		"Isolated transaction torture resolves a real player item",
		item_available,
		"Prepared bait should resolve through the canonical item catalog for transaction stress."
	)

	if not item_available:
		_record_unavailable_group(
			report,
			"Item transaction continuation",
			5,
			"Prepared-bait item definition was unavailable."
		)
		_free_item_setup(setup)
		return

	var probe := SignalProbe.new()

	transaction.transaction_completed.connect(
		Callable(
			probe,
			"on_transaction_completed"
		)
	)

	items.grant(
		item_id,
		1,
		false
	)

	var first: Dictionary = (
		transaction.consume_player_items(
			{
				String(item_id): 1,
			},
			false,
			&"torture_first_consume"
		)
	)

	var duplicate: Dictionary = (
		transaction.consume_player_items(
			{
				String(item_id): 1,
			},
			false,
			&"torture_duplicate_consume"
		)
	)

	_record(
		report,
		"Duplicate consume cannot spend the same item twice",
		bool(first.get("success", false))
		and not bool(
			duplicate.get("can_afford", true)
		)
		and str(
			duplicate.get("reason", "")
		) == "missing_items"
		and items.get_count(item_id) == 0,
		"A second transaction against an exhausted quantity must fail without producing negative inventory."
	)

	_record(
		report,
		"Failed duplicate consume emits no completion transaction",
		probe.transaction_count == 1,
		"Only successful mutations may publish transaction_completed."
	)

	var stress_ok: bool = true

	for _index in range(STRESS_ITERATIONS):
		var grant_result: Dictionary = (
			transaction.grant_player_items(
				{
					String(item_id): 1,
				},
				false,
				&"torture_refill"
			)
		)

		var consume_result: Dictionary = (
			transaction.consume_player_items(
				{
					String(item_id): 1,
				},
				false,
				&"torture_consume"
			)
		)

		if (
			not bool(
				grant_result.get(
					"success",
					false
				)
			)
			or not bool(
				consume_result.get(
					"success",
					false
				)
			)
			or items.get_count(item_id) != 0
		):
			stress_ok = false
			break

	_record(
		report,
		"Repeated grant-consume transactions produce no quantity drift",
		stress_ok
		and items.get_count(item_id) == 0,
		"Repeated atomic transactions must always return the isolated inventory to the expected count."
	)

	var expected_completed: int = (
		1
		+ STRESS_ITERATIONS * 2
	)

	_record(
		report,
		"Repeated transactions emit exactly one completion each",
		stress_ok
		and probe.transaction_count
		== expected_completed,
		"Transaction listeners must not multiply during repeated use."
	)

	var signals_before_invalid: int = (
		probe.transaction_count
	)

	var invalid_result: Dictionary = (
		transaction.grant_player_items(
			{
				"qa_item_that_does_not_exist": 1,
			},
			false,
			&"torture_unknown_reward"
		)
	)

	_record(
		report,
		"Unknown item reward is rejected without mutation",
		not bool(
			invalid_result.get(
				"success",
				true
			)
		)
		and str(
			invalid_result.get(
				"reason",
				""
			)
		) == "unknown_item"
		and items.get_count(item_id) == 0
		and probe.transaction_count
		== signals_before_invalid,
		"Invalid content IDs must fail before inventory mutation or transaction publication."
	)

	_free_item_setup(setup)


static func _test_prepared_bait_abuse(
	report: Dictionary,
	session: Node
) -> void:
	var setup: Dictionary = (
		_make_item_setup(session)
	)

	if setup.is_empty():
		_record_unavailable_group(
			report,
			"Prepared bait torture",
			5,
			"Could not create isolated prepared-bait backend."
		)
		return

	var catalog = setup.get(
		"catalog",
		null
	)

	var items = setup.get(
		"items",
		null
	)

	var prepared = setup.get(
		"prepared",
		null
	)

	var item_id: StringName = setup.get(
		"item_id",
		&""
	)

	var setup_valid: bool = (
		catalog != null
		and items != null
		and prepared != null
		and item_id != &""
		and catalog.get_definition(
			item_id
		) != null
	)

	_record(
		report,
		"Isolated prepared-bait torture backend is valid",
		setup_valid,
		"Prepared-bait stress requires the canonical prepared-bait item definition."
	)

	if not setup_valid:
		_record_unavailable_group(
			report,
			"Prepared bait continuation",
			4,
			"Prepared-bait item definition was unavailable."
		)
		_free_item_setup(setup)
		return

	var probe := SignalProbe.new()

	prepared.prepared_bait_consumed.connect(
		Callable(
			probe,
			"on_prepared_bait_consumed"
		)
	)

	items.grant(
		item_id,
		2,
		false
	)

	var first: Dictionary = (
		prepared.try_begin_cast(false)
	)

	_record(
		report,
		"Prepared bait consumes exactly one portion at cast start",
		bool(first.get("used", false))
		and prepared.is_cast_baited()
		and items.get_count(item_id) == 1,
		"A committed baited cast must consume exactly one prepared-bait portion."
	)

	prepared.clear_cast(
		&"torture_first_clear"
	)

	prepared.clear_cast(
		&"torture_duplicate_clear"
	)

	_record(
		report,
		"Repeated cast cleanup cannot consume extra bait",
		not prepared.is_cast_baited()
		and items.get_count(item_id) == 1,
		"Cleanup must remain idempotent after the first cast state clear."
	)

	var second: Dictionary = (
		prepared.try_begin_cast(false)
	)

	prepared.clear_cast(
		&"torture_second_clear"
	)

	var third: Dictionary = (
		prepared.try_begin_cast(false)
	)

	_record(
		report,
		"Prepared bait exhausts cleanly without negative inventory",
		bool(second.get("used", false))
		and not bool(
			third.get("used", true)
		)
		and str(
			third.get("reason", "")
		) == "no_prepared_bait"
		and items.get_count(item_id) == 0,
		"Once the final portion is consumed, later casts must proceed unbaited rather than consume below zero."
	)

	_record(
		report,
		"Prepared-bait consume signal fires exactly once per used portion",
		probe.prepared_bait_consumed_count == 2
		and items.get_count(item_id) == 0
		and not prepared.is_cast_baited(),
		"Prepared-bait listeners must not duplicate consumption events across cast cleanup cycles."
	)

	_free_item_setup(setup)


static func _test_objective_signal_abuse(
	report: Dictionary
) -> void:
	var objective = (
		MaterialObjectiveScript.new()
	)

	objective.material_id = &"sea_glass"
	objective.required_count = 3

	var inventory_a := (
		MockMaterialInventory.new()
	)

	var inventory_b := (
		MockMaterialInventory.new()
	)

	var probe := SignalProbe.new()

	objective.progress_changed.connect(
		Callable(
			probe,
			"on_objective_progress"
		)
	)

	objective.configure(inventory_a)

	_record(
		report,
		"Objective first bind publishes one initial snapshot",
		probe.objective_progress_count == 1,
		"Binding one objective source should publish one initial progress state."
	)

	for _index in range(STRESS_ITERATIONS):
		objective.configure(inventory_a)

	_record(
		report,
		"Repeated objective configure does not multiply listeners",
		probe.objective_progress_count == 1,
		"Reconfiguring the same dependency repeatedly must not create duplicate signal subscriptions."
	)

	inventory_a.set_count(
		&"sea_glass",
		1
	)

	_record(
		report,
		"Dual inventory signals collapse to one objective transition",
		probe.objective_progress_count == 2
		and objective.get_current_count() == 1,
		"material_changed and changed may both fire, but unchanged objective progress must not be emitted twice."
	)

	objective.configure(inventory_b)

	var count_after_rebind: int = (
		probe.objective_progress_count
	)

	inventory_a.set_count(
		&"sea_glass",
		2
	)

	var old_source_ignored: bool = (
		probe.objective_progress_count
		== count_after_rebind
	)

	inventory_b.set_count(
		&"sea_glass",
		3
	)

	_record(
		report,
		"Objective rebind disconnects the old dependency",
		old_source_ignored
		and probe.objective_progress_count
		== count_after_rebind + 1
		and objective.is_complete()
		and str(
			objective.get_progress_snapshot().get(
				"progress_text",
				""
			)
		) == "3/3",
		"After rebinding, stale inventory signals must no longer mutate or republish objective progress."
	)

	objective.configure(null)

	var count_after_detach: int = (
		probe.objective_progress_count
	)

	inventory_b.set_count(
		&"sea_glass",
		4
	)

	_record(
		report,
		"Objective survives late dependency removal",
		objective.get_current_count() == 0
		and not objective.is_complete()
		and probe.objective_progress_count
		== count_after_detach,
		"A missing or removed inventory dependency must read as neutral and remain disconnected from the former source."
	)

	objective.free()
	inventory_a.free()
	inventory_b.free()


static func _make_item_setup(
	session: Node
) -> Dictionary:
	if session == null:
		return {}

	var catalog = session.get(
		"item_catalog"
	)

	if catalog == null:
		return {}

	var items = (
		PlayerInventoryScript.new()
	)

	var facade = (
		InventoryFacadeScript.new()
	)

	facade.configure(
		catalog,
		items,
		null
	)

	var transaction = (
		TransactionServiceScript.new()
	)

	transaction.configure(
		catalog,
		items,
		facade,
		null
	)

	var prepared = (
		PreparedBaitServiceScript.new()
	)

	prepared.configure(
		EconomyConfigResource,
		catalog,
		items,
		transaction
	)

	var item_id: StringName = (
		catalog.make_item_id(
			ItemCatalogServiceScript.STORAGE_PLAYER,
			EconomyConfigResource.prepared_bait_item_domain_id
		)
	)

	return {
		"catalog": catalog,
		"items": items,
		"facade": facade,
		"transaction": transaction,
		"prepared": prepared,
		"item_id": item_id,
	}


static func _free_item_setup(
	setup: Dictionary
) -> void:
	for key in [
		"prepared",
		"transaction",
		"facade",
		"items",
	]:
		var instance = setup.get(
			key,
			null
		)

		if is_instance_valid(instance):
			instance.free()


static func _report_passed(
	value
) -> bool:
	if not (value is Dictionary):
		return false

	var report: Dictionary = value
	var test_count: int = int(
		report.get("test_count", 0)
	)

	var raw_failures = report.get(
		"failures",
		PackedStringArray()
	)

	var failure_count: int = 1

	if (
		raw_failures is PackedStringArray
		or raw_failures is Array
	):
		failure_count = raw_failures.size()

	return (
		test_count > 0
		and int(
			report.get(
				"passed_count",
				-1
			)
		) == test_count
		and failure_count == 0
	)


static func _record_unavailable_group(
	report: Dictionary,
	prefix: String,
	count: int,
	detail: String
) -> void:
	for index in range(count):
		_record(
			report,
			"%s %d" % [
				prefix,
				index + 1,
			],
			false,
			detail
		)


static func _record(
	report: Dictionary,
	label: String,
	passed: bool,
	failure_detail: String
) -> void:
	report["test_count"] = (
		int(report.get("test_count", 0))
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
		"%s - %s" % [
			label,
			failure_detail,
		]
	)

	report["failures"] = failures
