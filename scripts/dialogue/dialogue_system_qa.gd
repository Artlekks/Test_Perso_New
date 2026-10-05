extends RefCounted
class_name DialogueSystemQA

const DialogueServiceScript = preload("res://scripts/dialogue/dialogue_service.gd")
const PORTRAIT: Texture2D = preload("res://data/dialogue/portraits/master_gyosil.tres")
const COMPLETE_DIALOGUE_ID: StringName = &"master_gyosil_complete"


static func run(catalog: DialogueCatalog) -> Dictionary:
	var report := {
		"test_count": 0,
		"passed_count": 0,
		"failures": PackedStringArray(),
	}

	_record(report, "catalog exists", catalog != null, "Dialogue catalog must be available at session startup.")
	var audit: Dictionary = {}
	if catalog != null:
		audit = catalog.audit()
	_record(
		report,
		"catalog audit is clean",
		catalog != null and audit.get("errors", PackedStringArray()).is_empty(),
		"Authored dialogue ids/lines must be valid and unique."
	)
	_record(
		report,
		"Gyosil completion dialogue exists",
		catalog != null and catalog.has_dialogue(COMPLETE_DIALOGUE_ID),
		"The first live authored dialogue endpoint must remain in the catalog."
	)
	var definition: DialogueDefinition = null
	if catalog != null:
		definition = catalog.get_dialogue(COMPLETE_DIALOGUE_ID)
	_record(
		report,
		"Gyosil completion has two authored lines",
		definition != null and definition.lines.size() == 2,
		"The live catalog path must exercise multi-line advancement."
	)
	_record(
		report,
		"Gyosil authored dialogue has a portrait",
		definition != null and not definition.lines.is_empty() and definition.lines[0].portrait != null,
		"Authored dialogue must support portrait presentation without NPC-specific UI code."
	)

	var service = DialogueServiceScript.new()
	service.configure(catalog)
	_record(report, "service configures", service.is_configured(), "DialogueService must accept the shared catalog.")

	var missing: Dictionary = service.start_dialogue(&"missing_dialogue")
	_record(
		report,
		"missing authored id is rejected",
		not bool(missing.get("success", true)) and str(missing.get("reason", "")) == "dialogue_not_found",
		"Unknown ids must fail without creating active state."
	)

	var started: Dictionary = service.start_dialogue(COMPLETE_DIALOGUE_ID)
	_record(report, "authored dialogue starts", bool(started.get("success", false)), "Catalog dialogue should start normally.")
	var first := service.get_snapshot()
	_record(report, "authored dialogue is active", bool(first.get("active", false)), "Starting dialogue must create active state.")
	_record(report, "authored id is retained", first.get("dialogue_id", &"") == COMPLETE_DIALOGUE_ID, "Snapshot must expose stable dialogue id.")
	_record(report, "first speaker is Gyosil", str(first.get("speaker_name", "")) == "Master Gyosil", "View-facing speaker metadata must survive catalog conversion.")
	_record(report, "authored portrait survives runtime conversion", first.get("portrait", null) is Texture2D, "Portrait data must survive Resource -> runtime -> snapshot conversion.")
	_record(report, "first line is not terminal", not bool(first.get("is_last_line", true)), "The two-line authored sample must advance before closing.")

	var busy := service.start_dialogue(COMPLETE_DIALOGUE_ID)
	_record(
		report,
		"active dialogue rejects replacement",
		not bool(busy.get("success", true)) and str(busy.get("reason", "")) == "dialogue_busy",
		"An NPC must not overwrite an active conversation."
	)

	var advanced: Dictionary = service.advance()
	var second := service.get_snapshot()
	_record(report, "advance reaches second line", bool(advanced.get("success", false)) and int(second.get("line_index", -1)) == 1, "K/confirm must advance exactly one line.")
	_record(report, "second line is terminal", bool(second.get("is_last_line", false)), "View needs a stable K:Close state on the final line.")
	_record(report, "portrait persists across authored lines", second.get("portrait", null) is Texture2D, "Portrait must not disappear while advancing the same speaker's conversation.")

	var completed: Dictionary = service.advance()
	_record(report, "final advance completes", bool(completed.get("success", false)) and bool(completed.get("finished", false)), "Advancing the final line must finish the conversation.")
	_record(report, "service clears after completion", not service.is_active(), "Completed dialogue must release active state.")

	var empty_inline: Dictionary = service.start_inline_dialogue(&"inline_empty", [])
	_record(
		report,
		"empty inline dialogue is rejected",
		not bool(empty_inline.get("success", true)) and str(empty_inline.get("reason", "")) == "dialogue_has_no_lines",
		"Dynamic NPC messages may not open an empty box."
	)

	var inline_lines: Array = [{
		"speaker_id": &"qa_speaker",
		"speaker_name": "QA Speaker",
		"portrait": PORTRAIT,
		"text": "Progress {current} / {target}",
	}]
	var inline_started: Dictionary = service.start_inline_dialogue(
		&"qa_inline",
		inline_lines,
		true,
		{"current": 12, "target": 20},
		{"source": "dialogue_qa"}
	)
	_record(report, "inline dialogue starts", bool(inline_started.get("success", false)), "Dynamic reward/progress speech must use the same runtime.")
	var inline_snapshot := service.get_snapshot()
	_record(report, "inline context tokens resolve", str(inline_snapshot.get("text", "")) == "Progress 12 / 20", "Runtime context replacement must be deterministic.")
	var inline_metadata: Dictionary = inline_snapshot.get("metadata", {})
	_record(report, "inline metadata is retained", str(inline_metadata.get("source", "")) == "dialogue_qa", "Dialogue metadata must survive in snapshots for future hooks.")
	_record(report, "inline portrait is retained", inline_snapshot.get("portrait", null) == PORTRAIT, "Dynamic NPC speech must support the same portrait path as authored dialogue.")
	var cancelled: Dictionary = service.cancel()
	_record(report, "cancellable dialogue closes", bool(cancelled.get("success", false)) and not service.is_active(), "I/back must be able to release cancellable dialogue.")

	var fallback_started: Dictionary = service.start_inline_dialogue(
		&"qa_metadata_portrait",
		[{"speaker_name": "QA", "text": "Metadata portrait fallback."}],
		true,
		{},
		{"portrait": PORTRAIT}
	)
	_record(report, "metadata portrait dialogue starts", bool(fallback_started.get("success", false)), "Portrait fallback metadata must not block dialogue startup.")
	var fallback_snapshot := service.get_snapshot()
	_record(report, "metadata portrait fallback resolves", fallback_snapshot.get("portrait", null) == PORTRAIT, "Authored/runtime callers can provide one portrait for a whole conversation.")
	service.force_close(&"qa_portrait_cleanup")

	var bad_portrait: Dictionary = service.start_inline_dialogue(
		&"qa_bad_portrait",
		[{"text": "Bad portrait", "portrait": "not_a_texture"}]
	)
	_record(report, "invalid inline portrait is rejected", not bool(bad_portrait.get("success", true)), "Dialogue runtime must reject malformed portrait payloads instead of leaking them into the view.")

	var locked_started: Dictionary = service.start_inline_dialogue(
		&"qa_locked",
		["This line cannot be cancelled."],
		false
	)
	_record(report, "non-cancellable dialogue starts", bool(locked_started.get("success", false)), "Runtime must support future mandatory story lines.")
	var locked_cancel: Dictionary = service.cancel()
	_record(report, "cancel lock is respected", not bool(locked_cancel.get("success", true)) and service.is_active(), "Cancel-disabled dialogue must remain active.")
	var forced: Dictionary = service.force_close(&"qa_cleanup")
	_record(report, "force close always cleans up", bool(forced.get("success", false)) and not service.is_active(), "Scene/system cleanup needs an unconditional escape hatch.")

	service.free()
	return report


static func _record(report: Dictionary, label: String, passed: bool, failure: String) -> void:
	report["test_count"] = int(report.get("test_count", 0)) + 1
	if passed:
		report["passed_count"] = int(report.get("passed_count", 0)) + 1
		return
	var failures: PackedStringArray = report.get("failures", PackedStringArray())
	failures.append("%s — %s" % [label, failure])
	report["failures"] = failures
