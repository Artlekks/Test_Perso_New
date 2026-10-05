extends RefCounted
class_name DialogueSystemQA

const DialogueServiceScript = preload("res://scripts/dialogue/dialogue_service.gd")
const DialogueChoiceDefinitionScript = preload("res://scripts/dialogue/dialogue_choice_definition.gd")
const DialogueLineDefinitionScript = preload("res://scripts/dialogue/dialogue_line_definition.gd")
const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const NPCDialogueRouterScript = preload("res://scripts/dialogue/npc_dialogue_router.gd")
const BeachMerchantNPCScript = preload("res://scripts/beach_merchant_npc.gd")
const BeachMerchantScene = preload("res://actors/BeachMerchantNPC.tscn")
const FishingEconomyMenuScene = preload("res://actors/FishingEconomyMenu.tscn")
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

	var prefixed: Dictionary = NPCDialogueRouterScript.split_speaker_prefix(
		"Current Reader: Let the water move it.",
		"Fishing Master"
	)
	_record(
		report,
		"NPC speech prefix becomes speaker name",
		str(prefixed.get("speaker_name", "")) == "Current Reader",
		"Master-authored 'Name: line' text should populate the dialogue speaker field."
	)
	_record(
		report,
		"NPC speech prefix is removed from body",
		str(prefixed.get("text", "")) == "Let the water move it.",
		"Dialogue body should not repeat the speaker name."
	)
	var fallback_speech: Dictionary = NPCDialogueRouterScript.split_speaker_prefix(
		"Technique learned — Read the Current.",
		"Current Reader"
	)
	_record(
		report,
		"NPC speech without prefix keeps fallback speaker",
		str(fallback_speech.get("speaker_name", "")) == "Current Reader",
		"Technique/system-style master lines need a stable speaker when no prefix is authored."
	)
	_record(
		report,
		"master id humanizes for dialogue",
		NPCDialogueRouterScript.humanize_id(
			&"master_deepwater_veteran",
			"master_",
			"Fishing Master"
		) == "Deepwater Veteran",
		"Master ids must produce readable fallback names without per-master UI code."
	)
	_record(
		report,
		"missing sprite portrait is safe",
		NPCDialogueRouterScript.portrait_from_sprite(null) == null,
		"NPCs without portrait art must still be able to speak."
	)

	var bridge = DialogueNPCBridgeScript.new()
	bridge.configure_service(service)
	var routed_started: bool = NPCDialogueRouterScript.start_spoken_line(
		bridge,
		&"qa_npc_routed",
		&"qa_action",
		&"qa_master",
		"QA Master",
		"QA Master: Routed through the shared dialogue box.",
		null,
		true,
		{"source": "qa"}
	)
	_record(
		report,
		"shared NPC router starts dialogue",
		routed_started and service.is_active(),
		"Direct NPC speech should enter the same DialogueService used by Gyosil and menu NPCs."
	)
	var routed_snapshot := service.get_snapshot()
	_record(
		report,
		"shared NPC router preserves speaker and body",
		str(routed_snapshot.get("speaker_name", "")) == "QA Master"
		and str(routed_snapshot.get("text", "")) == "Routed through the shared dialogue box.",
		"The router must present clean speaker metadata instead of a top-HUD notification."
	)
	service.advance()
	_record(
		report,
		"routed NPC dialogue releases cleanly",
		not service.is_active(),
		"One-line NPC conversations must close normally and release the pause/input layer."
	)
	# Choice foundation: presentation/result routing only. Existing NPC behavior
	# remains unchanged until a caller explicitly opts into a choice prompt.
	var choice_definition = DialogueChoiceDefinitionScript.new()
	choice_definition.choice_id = &"trade"
	choice_definition.text = "Trade"
	_record(
		report,
		"choice resource validates stable id and text",
		choice_definition.get_validation_errors().is_empty(),
		"Authored choices need a stable result id and visible label."
	)

	var choice_line = DialogueLineDefinitionScript.new()
	choice_line.text = "What do you need?"
	choice_line.choices.append(choice_definition)
	var runtime_choice_line: Dictionary = choice_line.to_runtime_line()
	var authored_runtime_choices: Array = runtime_choice_line.get("choices", [])
	_record(
		report,
		"authored line exports runtime choices",
		authored_runtime_choices.size() == 1
		and str(authored_runtime_choices[0].get("choice_id", "")) == "trade",
		"Resource-authored choices must survive conversion without gameplay coupling."
	)

	var choice_started: Dictionary = service.start_inline_dialogue(
		&"qa_choices",
		[{
			"speaker_name": "Merchant",
			"text": "What do you need?",
			"choices": [
				{
					"choice_id": &"locked",
					"text": "Locked option",
					"enabled": false,
				},
				{
					"choice_id": &"trade",
					"text": "Trade {currency}",
					"metadata": {"menu": "economy"},
				},
				{
					"choice_id": &"cards",
					"text": "Play Cards",
				},
			],
		}],
		true,
		{"currency": "z"}
	)
	_record(
		report,
		"inline choice prompt starts",
		bool(choice_started.get("success", false)),
		"Dynamic NPC choice prompts must use the same DialogueService."
	)
	var choice_snapshot := service.get_snapshot()
	var choice_options: Array = choice_snapshot.get("choices", [])
	_record(
		report,
		"choice snapshot exposes all options",
		bool(choice_snapshot.get("has_choices", false)) and choice_options.size() == 3,
		"DialogueView needs all available choices in the active snapshot."
	)
	_record(
		report,
		"first selection skips disabled choice",
		int(choice_snapshot.get("selected_choice_index", -1)) == 1,
		"Choice navigation must never land on a disabled entry."
	)
	_record(
		report,
		"choice labels resolve context tokens",
		str(choice_options[1].get("text", "")) == "Trade z",
		"Choice labels should support the same deterministic context tokens as dialogue text."
	)
	var blocked_advance := service.advance()
	_record(
		report,
		"choice line cannot be bypassed by advance",
		not bool(blocked_advance.get("success", true))
		and str(blocked_advance.get("reason", "")) == "choice_required"
		and service.is_active(),
		"K/confirm must select a choice rather than silently advancing past it."
	)
	var moved_choice := service.move_choice(1)
	var moved_snapshot := service.get_snapshot()
	_record(
		report,
		"choice navigation moves to next enabled option",
		bool(moved_choice.get("success", false))
		and int(moved_snapshot.get("selected_choice_index", -1)) == 2,
		"W/S choice navigation must move only among enabled options."
	)
	service.move_choice(1)
	var wrapped_snapshot := service.get_snapshot()
	_record(
		report,
		"choice navigation wraps safely",
		int(wrapped_snapshot.get("selected_choice_index", -1)) == 1,
		"Choice navigation should wrap without indexing outside the list."
	)
	var selected_choice := service.select_choice()
	_record(
		report,
		"select choice returns stable id",
		bool(selected_choice.get("success", false))
		and selected_choice.get("choice_id", &"") == &"trade",
		"Gameplay callers need the stable choice id rather than presentation text."
	)
	var selected_metadata: Dictionary = selected_choice.get("choice_metadata", {})
	_record(
		report,
		"choice metadata survives selection",
		str(selected_metadata.get("menu", "")) == "economy",
		"Optional choice metadata must survive without being interpreted by dialogue."
	)
	_record(
		report,
		"choice selection closes dialogue",
		not service.is_active(),
		"A selected terminal choice must release dialogue/pause ownership cleanly."
	)

	var duplicate_choices := service.start_inline_dialogue(
		&"qa_duplicate_choices",
		[{
			"text": "Duplicate test",
			"choices": [
				{"choice_id": &"same", "text": "One"},
				{"choice_id": &"same", "text": "Two"},
			],
		}]
	)
	_record(
		report,
		"duplicate inline choice ids are rejected",
		not bool(duplicate_choices.get("success", true))
		and str(duplicate_choices.get("reason", "")) == "invalid_inline_line",
		"One choice prompt may not expose ambiguous duplicate result ids."
	)
	var empty_choice_id := service.start_inline_dialogue(
		&"qa_empty_choice_id",
		[{
			"text": "Bad choice",
			"choices": [{"choice_id": &"", "text": "No id"}],
		}]
	)
	_record(
		report,
		"empty inline choice id is rejected",
		not bool(empty_choice_id.get("success", true)),
		"Every selectable option must have a stable non-empty id."
	)
	var disabled_started := service.start_inline_dialogue(
		&"qa_all_disabled",
		[{
			"text": "Nothing available.",
			"choices": [
				{"choice_id": &"a", "text": "A", "enabled": false},
				{"choice_id": &"b", "text": "B", "enabled": false},
			],
		}]
	)
	_record(
		report,
		"all-disabled choice prompt can still render",
		bool(disabled_started.get("success", false))
		and int(service.get_snapshot().get("selected_choice_index", 0)) == -1,
		"A conversation may explain unavailable options without forcing a selection."
	)
	var disabled_select := service.select_choice()
	_record(
		report,
		"all-disabled choice prompt cannot select",
		not bool(disabled_select.get("success", true))
		and str(disabled_select.get("reason", "")) == "no_enabled_choices",
		"Disabled choices must never dispatch an action id."
	)
	service.force_close(&"qa_disabled_cleanup")

	var bridge_choice_started := bridge.start_choice_prompt(
		&"qa_bridge_choices",
		&"qa_menu_action",
		&"qa_merchant",
		"QA Merchant",
		"Choose an action.",
		[
			{"choice_id": &"trade", "text": "Trade"},
			{"choice_id": &"leave", "text": "Leave"},
		],
		null,
		true,
		{"source": "qa_choice_bridge"}
	)
	_record(
		report,
		"NPC bridge starts reusable choice prompt",
		bridge_choice_started
		and service.is_active()
		and bridge.has_pending_interaction(),
		"NPCs should be able to request choices without learning DialogueView internals."
	)
	service.move_choice(1)
	var bridge_choice_result := service.select_choice()
	_record(
		report,
		"NPC bridge clears pending choice after selection",
		bool(bridge_choice_result.get("success", false))
		and bridge_choice_result.get("choice_id", &"") == &"leave"
		and not bridge.has_pending_interaction(),
		"Choice completion must not leave an NPC bridge stuck waiting forever."
	)


	# First live choice integration: the beach merchant now uses one K dialogue
	# interaction and routes stable choice ids back to its existing economy owner.
	var merchant_scene_node = BeachMerchantScene.instantiate()
	_record(
		report,
		"merchant world prompt is unified under K talk",
		merchant_scene_node != null
		and str(merchant_scene_node.get("interaction_prompt")) == "K : Talk",
		"A choice-driven NPC should advertise one conversation key rather than separate service hotkeys."
	)
	if merchant_scene_node != null:
		merchant_scene_node.free()

	var merchant_choices: Array = BeachMerchantNPCScript.build_service_choices(
		true,
		true,
		false,
		false
	)
	_record(
		report,
		"merchant base choices are buy sell leave",
		merchant_choices.size() == 3
		and merchant_choices[0].get("choice_id", &"") == &"buy"
		and merchant_choices[1].get("choice_id", &"") == &"sell"
		and merchant_choices[2].get("choice_id", &"") == &"leave",
		"The live merchant must route economy actions through stable choice ids."
	)
	var merchant_has_cards_choice := false
	for raw_choice in merchant_choices:
		if raw_choice is Dictionary and raw_choice.get("choice_id", &"") == &"cards":
			merchant_has_cards_choice = true
			break
	_record(
		report,
		"merchant does not invent a card role",
		not merchant_has_cards_choice,
		"The current beach merchant is not the beach_trader card opponent and should not expose a fake Cards action."
	)

	var mixed_role_choices: Array = BeachMerchantNPCScript.build_service_choices(
		true,
		true,
		true,
		false
	)
	var cards_choice: Dictionary = {}
	for raw_choice in mixed_role_choices:
		if raw_choice is Dictionary and raw_choice.get("choice_id", &"") == &"cards":
			cards_choice = raw_choice
			break
	_record(
		report,
		"merchant choice model supports optional card role",
		not cards_choice.is_empty() and not bool(cards_choice.get("enabled", true)),
		"A future mixed-role merchant may advertise Cards without moving card availability logic into dialogue."
	)

	var economy_menu_node = FishingEconomyMenuScene.instantiate()
	_record(
		report,
		"economy menu exposes direct buy and sell entry points",
		economy_menu_node != null
		and economy_menu_node.has_method("open_buy_menu")
		and economy_menu_node.has_method("open_sell_menu"),
		"Merchant choices need public mode entry points instead of mutating the economy menu's private state."
	)
	if economy_menu_node != null:
		economy_menu_node.free()

	bridge.free()

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
