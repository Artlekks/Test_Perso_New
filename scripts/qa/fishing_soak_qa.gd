extends RefCounted
class_name FishingSoakQA

## Long-run adversarial regression soak.
##
## Reuses the already-green Torture QA and Save/Recovery QA instead of
## maintaining parallel fake implementations.
##
## The nested suites own their isolated test state/save paths.
## The live session is observed before/after to prove that soak execution
## never leaks mutations into normal gameplay state.

const TortureQAScript = preload(
	"res://scripts/qa/fishing_torture_qa.gd"
)

const SaveRecoveryQAScript = preload(
	"res://scripts/qa/fishing_save_recovery_interruption_qa.gd"
)

const TORTURE_CYCLES: int = 25
const RECOVERY_CYCLES: int = 10

## Warmup loads resources and scripts before the object-count baseline.
## A small amount of engine-side caching is acceptable; unbounded growth is not.
const MAX_OBJECT_GROWTH: int = 96


static func run(
	session: Node
) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
		"valid": false,
		"torture_cycles": TORTURE_CYCLES,
		"recovery_cycles": RECOVERY_CYCLES,
		"nested_test_count": 0,
		"nested_passed_count": 0,
		"object_count_before": 0,
		"object_count_after": 0,
		"object_growth": 0,
	}

	if session == null:
		_record(
			report,
			"Soak session exists",
			false,
			"FishingSessionServices was unavailable."
		)

		report["valid"] = false
		return report

	var live_items = session.get(
		"player_item_inventory"
	)

	var live_items_available: bool = (
		live_items != null
		and live_items.has_method(
			"get_snapshot"
		)
	)

	var live_items_before: Dictionary = {}

	if live_items_available:
		var raw_items_before = live_items.call(
			"get_snapshot"
		)

		if raw_items_before is Dictionary:
			live_items_before = (
				raw_items_before as Dictionary
			).duplicate(true)

	var live_dialogue = session.get(
		"dialogue_service"
	)

	var live_dialogue_available: bool = (
		live_dialogue != null
		and live_dialogue.has_method(
			"is_active"
		)
	)

	var live_dialogue_before: bool = false

	if live_dialogue_available:
		live_dialogue_before = bool(
			live_dialogue.call(
				"is_active"
			)
		)

	# ------------------------------------------------------------------
	# Warmup
	# ------------------------------------------------------------------

	var warmup_torture: Dictionary = (
		TortureQAScript.run(
			session
		)
	)

	_record(
		report,
		"Torture QA warmup is green",
		_is_green(
			warmup_torture
		),
		"Soak testing must begin from a green adversarial baseline."
	)

	var warmup_recovery: Dictionary = (
		SaveRecoveryQAScript.run(
			session
		)
	)

	_record(
		report,
		"Save/Recovery QA warmup is green",
		_is_green(
			warmup_recovery
		),
		"Soak testing must begin from a green recovery baseline."
	)

	warmup_torture.clear()
	warmup_recovery.clear()

	var objects_before: int = int(
		Performance.get_monitor(
			Performance.OBJECT_COUNT
		)
	)

	report["object_count_before"] = objects_before

	# ------------------------------------------------------------------
	# Torture soak
	# ------------------------------------------------------------------

	var torture_cycles_green: bool = true

	for cycle_index in range(
		TORTURE_CYCLES
	):
		var cycle_report: Dictionary = (
			TortureQAScript.run(
				session
			)
		)

		report["nested_test_count"] = (
			int(
				report.get(
					"nested_test_count",
					0
				)
			)
			+ int(
				cycle_report.get(
					"test_count",
					0
				)
			)
		)

		report["nested_passed_count"] = (
			int(
				report.get(
					"nested_passed_count",
					0
				)
			)
			+ int(
				cycle_report.get(
					"passed_count",
					0
				)
			)
		)

		if not _is_green(
			cycle_report
		):
			torture_cycles_green = false

			_append_nested_failure(
				report,
				"Torture cycle %d"
				% [
					cycle_index + 1,
				],
				cycle_report
			)

		cycle_report.clear()

	_record(
		report,
		"All repeated Torture QA cycles remain green",
		torture_cycles_green,
		"Repeated adversarial execution exposed state, signal, input, or transaction drift."
	)

	# ------------------------------------------------------------------
	# Save/recovery soak
	# ------------------------------------------------------------------

	var recovery_cycles_green: bool = true

	for cycle_index in range(
		RECOVERY_CYCLES
	):
		var cycle_report: Dictionary = (
			SaveRecoveryQAScript.run(
				session
			)
		)

		report["nested_test_count"] = (
			int(
				report.get(
					"nested_test_count",
					0
				)
			)
			+ int(
				cycle_report.get(
					"test_count",
					0
				)
			)
		)

		report["nested_passed_count"] = (
			int(
				report.get(
					"nested_passed_count",
					0
				)
			)
			+ int(
				cycle_report.get(
					"passed_count",
					0
				)
			)
		)

		if not _is_green(
			cycle_report
		):
			recovery_cycles_green = false

			_append_nested_failure(
				report,
				"Recovery cycle %d"
				% [
					cycle_index + 1,
				],
				cycle_report
			)

		cycle_report.clear()

	_record(
		report,
		"All repeated Save/Recovery cycles remain green",
		recovery_cycles_green,
		"Repeated interruption/restart simulation exposed persistence drift."
	)

	# ------------------------------------------------------------------
	# Aggregate invariants
	# ------------------------------------------------------------------

	var nested_test_count: int = int(
		report.get(
			"nested_test_count",
			0
		)
	)

	var nested_passed_count: int = int(
		report.get(
			"nested_passed_count",
			0
		)
	)

	_record(
		report,
		"Every nested soak assertion passed",
		nested_test_count > 0
		and nested_passed_count
		== nested_test_count,
		"At least one nested adversarial assertion failed during long-run execution."
	)

	var live_items_after: Dictionary = {}

	if live_items_available:
		var raw_items_after = live_items.call(
			"get_snapshot"
		)

		if raw_items_after is Dictionary:
			live_items_after = (
				raw_items_after as Dictionary
			).duplicate(true)

	_record(
		report,
		"Soak leaves live player-item inventory unchanged",
		live_items_available
		and live_items_after
		== live_items_before,
		"Isolated soak work must never leak mutations into the live player-item inventory."
	)

	var live_dialogue_after: bool = false

	if live_dialogue_available:
		live_dialogue_after = bool(
			live_dialogue.call(
				"is_active"
			)
		)

	_record(
		report,
		"Soak leaves live dialogue ownership unchanged",
		live_dialogue_available
		and live_dialogue_after
		== live_dialogue_before,
		"Repeated isolated dialogue tests must not capture or release the live dialogue owner."
	)

	var objects_after: int = int(
		Performance.get_monitor(
			Performance.OBJECT_COUNT
		)
	)

	var object_growth: int = (
		objects_after
		- objects_before
	)

	report["object_count_after"] = objects_after
	report["object_growth"] = object_growth

	_record(
		report,
		"Soak object growth remains bounded",
		object_growth
		<= MAX_OBJECT_GROWTH,
		"Object count grew by %d after warmup; expected no runaway node/resource accumulation."
		% object_growth
	)

	report["coverage"] = {
		"dialogue_lifecycles": (
			TORTURE_CYCLES * 40
		),
		"transaction_stress_cycles": (
			TORTURE_CYCLES * 64
		),
		"objective_reconfigure_cycles": (
			TORTURE_CYCLES * 64
		),
		"cast_abuse_cycles_per_path": (
			TORTURE_CYCLES * 64
		),
		"recovery_suite_cycles": (
			RECOVERY_CYCLES
		),
	}

	report["valid"] = (
		int(
			report.get(
				"passed_count",
				0
			)
		)
		== int(
			report.get(
				"test_count",
				0
			)
		)
	)

	return report


static func _is_green(
	report: Dictionary
) -> bool:
	if report.is_empty():
		return false

	var total: int = int(
		report.get(
			"test_count",
			0
		)
	)

	var passed: int = int(
		report.get(
			"passed_count",
			-1
		)
	)

	var failures = report.get(
		"failures",
		PackedStringArray()
	)

	var failure_count: int = 1

	if (
		failures is PackedStringArray
		or failures is Array
	):
		failure_count = failures.size()

	return (
		total > 0
		and passed == total
		and failure_count == 0
	)


static func _append_nested_failure(
	report: Dictionary,
	prefix: String,
	nested_report: Dictionary
) -> void:
	var failures: PackedStringArray = (
		report.get(
			"failures",
			PackedStringArray()
		)
	)

	var nested_failures = (
		nested_report.get(
			"failures",
			PackedStringArray()
		)
	)

	if (
		nested_failures is PackedStringArray
		or nested_failures is Array
	):
		for failure in nested_failures:
			failures.append(
				"%s: %s"
				% [
					prefix,
					str(failure),
				]
			)

	report["failures"] = failures


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
