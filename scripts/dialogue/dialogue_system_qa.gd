extends RefCounted
class_name DialogueSystemQA

const DialogueServiceScript = preload("res://scripts/dialogue/dialogue_service.gd")
const DialogueChoiceDefinitionScript = preload("res://scripts/dialogue/dialogue_choice_definition.gd")
const DialogueLineDefinitionScript = preload("res://scripts/dialogue/dialogue_line_definition.gd")
const DialogueNPCBridgeScript = preload("res://scripts/dialogue/dialogue_npc_bridge.gd")
const NPCDialogueRouterScript = preload("res://scripts/dialogue/npc_dialogue_router.gd")
const MasterDialogueProfilesScript = preload(
	"res://scripts/mastery/fishing_master_dialogue_profiles.gd"
)
const BeachMerchantNPCScript = preload("res://scripts/beach_merchant_npc.gd")
const BeachMerchantScene = preload("res://actors/BeachMerchantNPC.tscn")
const FishingEconomyMenuScene = preload("res://actors/FishingEconomyMenu.tscn")
const FishingCardMakerNPCScript = preload("res://scripts/economy/fishing_card_maker_npc.gd")
const FishingCardMakerScene = preload("res://actors/FishingCardMakerNPC.tscn")
const BeachCrafterNPCScript = preload("res://scripts/beach_crafter_npc.gd")
const BeachCrafterScene = preload("res://actors/BeachCrafterNPC.tscn")
const BeachCrafterRequestSourceScript = preload("res://scripts/quests/beach_crafter_request_source.gd")
const MaterialCountRequestObjectiveScript = preload("res://scripts/quests/material_count_request_objective.gd")
const WorldRequestProgressStoreScript = preload("res://scripts/quests/world_request_progress_store.gd")
const PORTRAIT: Texture2D = preload("res://data/dialogue/portraits/master_gyosil.tres")
const COMPLETE_DIALOGUE_ID: StringName = &"master_gyosil_complete"
const WorldRequestStateScript = preload("res://scripts/quests/world_request_state.gd")
const HarborRequestBoardScript = preload(
	"res://scripts/triple_triad/triple_triad_harbor_request_board.gd"
)
const HarborRequestBoardScene = preload("res://actors/HarborRequestBoard.tscn")
const WorldRequestMarkerScript = preload("res://scripts/quests/world_request_marker.gd")
const WorldObjectiveTrackerScript = preload("res://scripts/quests/world_objective_tracker.gd")
const WorldObjectiveTrackerScene = preload("res://actors/WorldObjectiveTracker.tscn")
const WorldRequestJournalScript = preload("res://scripts/quests/world_request_journal.gd")
const WorldRequestJournalScene = preload("res://actors/WorldRequestJournal.tscn")


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

	var bridge_lines_started := bridge.start_lines(
		&"qa_bridge_lines",
		&"qa_explanation",
		[
			{"speaker_name": "QA NPC", "text": "First explanation line."},
			{"speaker_name": "QA NPC", "text": "Second explanation line."},
		],
		true,
		{"source": "qa_multiline_bridge"}
	)
	_record(
		report,
		"NPC bridge starts reusable multi-line dialogue",
		bridge_lines_started
		and service.is_active()
		and bridge.has_pending_interaction(),
		"NPC explanations should use the same bridge instead of reaching into DialogueService directly."
	)
	service.advance()
	var bridge_lines_second := service.get_snapshot()
	_record(
		report,
		"NPC bridge multi-line dialogue advances normally",
		service.is_active()
		and int(bridge_lines_second.get("line_index", -1)) == 1
		and str(bridge_lines_second.get("text", "")) == "Second explanation line.",
		"Multi-line help must preserve normal K-to-advance behavior."
	)
	service.advance()
	_record(
		report,
		"NPC bridge multi-line completion releases pending state",
		not service.is_active() and not bridge.has_pending_interaction(),
		"Finishing an explanation must release pause/input ownership before an NPC reopens its choices."
	)


	# Card Maker + Crafter now use the same single-key service-choice pattern.
	var card_maker_scene_node = FishingCardMakerScene.instantiate()
	_record(
		report,
		"card maker world prompt is unified under K talk",
		card_maker_scene_node != null
		and str(card_maker_scene_node.get("interaction_prompt")) == "K : Talk",
		"The Card Maker should enter conversation first instead of advertising a direct menu action."
	)
	if card_maker_scene_node != null:
		card_maker_scene_node.free()

	var card_maker_choices: Array = FishingCardMakerNPCScript.build_service_choices(true)
	_record(
		report,
		"card maker choices are make about leave",
		card_maker_choices.size() == 3
		and card_maker_choices[0].get("choice_id", &"") == &"make_card"
		and card_maker_choices[1].get("choice_id", &"") == &"about"
		and card_maker_choices[2].get("choice_id", &"") == &"leave",
		"The Card Maker must expose stable service ids without moving card-making rules into dialogue."
	)
	var unavailable_card_maker_choices: Array = FishingCardMakerNPCScript.build_service_choices(false)
	_record(
		report,
		"card maker disables only unavailable workshop action",
		not bool(unavailable_card_maker_choices[0].get("enabled", true))
		and bool(unavailable_card_maker_choices[1].get("enabled", false))
		and bool(unavailable_card_maker_choices[2].get("enabled", false)),
		"Help and Leave must remain usable even if the card-making service is temporarily unavailable."
	)

	var crafter_scene_node = BeachCrafterScene.instantiate()
	_record(
		report,
		"crafter world prompt is unified under K talk",
		crafter_scene_node != null
		and str(crafter_scene_node.get("interaction_prompt")) == "K : Talk",
		"The Crafter should use conversation as the single player-facing interaction entry point."
	)
	if crafter_scene_node != null:
		crafter_scene_node.free()

	var crafter_choices: Array = BeachCrafterNPCScript.build_service_choices(true, false, false)
	_record(
		report,
		"crafter base choices are craft about leave",
		crafter_choices.size() == 3
		and crafter_choices[0].get("choice_id", &"") == &"craft"
		and crafter_choices[1].get("choice_id", &"") == &"about"
		and crafter_choices[2].get("choice_id", &"") == &"leave",
		"The normal beach crafter should route crafting and explanation through stable choices."
	)
	var crafter_has_cards_choice := false
	for raw_choice in crafter_choices:
		if raw_choice is Dictionary and raw_choice.get("choice_id", &"") == &"cards":
			crafter_has_cards_choice = true
			break
	_record(
		report,
		"crafter does not invent a card role",
		not crafter_has_cards_choice,
		"An NPC should only expose Play Cards when it is genuinely configured as an opponent."
	)
	var mixed_crafter_choices: Array = BeachCrafterNPCScript.build_service_choices(true, true, false)
	var mixed_crafter_cards: Dictionary = {}
	for raw_choice in mixed_crafter_choices:
		if raw_choice is Dictionary and raw_choice.get("choice_id", &"") == &"cards":
			mixed_crafter_cards = raw_choice
			break
	_record(
		report,
		"crafter choice model supports optional card role",
		not mixed_crafter_cards.is_empty()
		and not bool(mixed_crafter_cards.get("enabled", true)),
		"A future mixed-role crafter can route Cards through dialogue without restoring a separate C hotkey."
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

	# State-aware master presentation. The profile layer owns only dialogue
	# flavor/state labels; mastery scripts still own every lesson rule.
	var master_profile_ids: Array[StringName] = [
		&"master_still_water",
		&"master_current_reader",
		&"master_depth_reader",
		&"master_structure_hunter",
		&"master_line_fighter",
		&"master_deepwater_veteran",
		&"master_surface_angler",
		&"master_landing_guide",
		&"master_weather_watcher",
		&"master_tide_reader",
		&"master_sign_reader",
		&"master_nature_guide",
		&"master_drift_angler",
	]
	_record(
		report,
		"all current lesson masters have dialogue profiles",
		MasterDialogueProfilesScript.get_profile_count() == master_profile_ids.size(),
		"The shared state-aware dialogue table must cover every current lesson master exactly once."
	)
	for teacher_id in master_profile_ids:
		var complete_profile := (
			MasterDialogueProfilesScript.has_profile(teacher_id)
			and not MasterDialogueProfilesScript.get_state_line(teacher_id, &"intro").is_empty()
			and not MasterDialogueProfilesScript.get_state_line(teacher_id, &"active").is_empty()
			and not MasterDialogueProfilesScript.get_state_line(teacher_id, &"learned").is_empty()
			and not MasterDialogueProfilesScript.get_state_line(teacher_id, &"revisit").is_empty()
		)
		_record(
			report,
			"master profile covers %s" % str(teacher_id),
			complete_profile,
			"Every current master needs intro, active, learned and revisit presentation states."
		)

	_record(
		report,
		"master dialogue classifies untouched lesson as intro",
		MasterDialogueProfilesScript.classify_state(false, 0, false) == &"intro",
		"A lesson that has not started must present its introduction state."
	)
	_record(
		report,
		"master dialogue classifies running lesson as active",
		MasterDialogueProfilesScript.classify_state(false, 1, false) == &"active",
		"Any non-INACTIVE lesson phase must present active coaching when the player talks to the master."
	)
	_record(
		report,
		"master dialogue exposes one-time learned acknowledgement",
		MasterDialogueProfilesScript.classify_state(true, 3, true) == &"learned",
		"A technique learned in the current runtime should get one acknowledgement before ordinary revisits."
	)
	_record(
		report,
		"master dialogue classifies saved known technique as revisit",
		MasterDialogueProfilesScript.classify_state(true, 0, false) == &"revisit",
		"Techniques restored from save must not replay a fresh-learning acknowledgement."
	)

	var master_intro_lines: Array = MasterDialogueProfilesScript.build_runtime_lines(
		&"master_current_reader",
		&"intro",
		"Current Reader: Cast, then let the lure drift.",
		null
	)
	_record(
		report,
		"master state dialogue preserves original instruction first",
		master_intro_lines.size() == 2
		and str(master_intro_lines[0].get("text", "")) == "Cast, then let the lure drift.",
		"Cancelling a richer conversation must never hide the instruction the old one-line interaction showed."
	)
	_record(
		report,
		"master state dialogue appends relationship flavor",
		master_intro_lines.size() == 2
		and not str(master_intro_lines[1].get("text", "")).is_empty(),
		"State-aware master conversations should add personality without replacing gameplay instructions."
	)
	_record(
		report,
		"master state dialogue strips speaker prefix",
		master_intro_lines.size() == 2
		and str(master_intro_lines[0].get("speaker_name", "")) == "Current Reader",
		"The portrait/name field should own the speaker identity instead of duplicating it in body text."
	)

	var unavailable_master_lines: Array = MasterDialogueProfilesScript.build_runtime_lines(
		&"master_current_reader",
		&"unavailable",
		"Current Reader: The lesson needs live water.",
		null
	)
	_record(
		report,
		"unavailable master dialogue stays concise",
		unavailable_master_lines.size() == 1,
		"Runtime/service failures should not be padded with normal lesson-state flavor."
	)
	_record(
		report,
		"master profile preserves authored display names",
		MasterDialogueProfilesScript.get_speaker_name(&"master_deepwater_veteran") == "Deep-Water Veteran",
		"Profile display names must preserve intentional punctuation instead of relying only on id humanization."
	)


	# First real progression-driven dialogue flow: the existing Harbor Request
	# Board keeps objective/reward ownership outside dialogue and adds only a
	# durable acceptance state plus presentation routing.
	_record(
		report,
		"world request state keeps locked requests locked",
		WorldRequestStateScript.resolve(false, false, false, false, false)
		== WorldRequestStateScript.State.LOCKED,
		"A request may not become available before its owning progression gate unlocks."
	)
	_record(
		report,
		"world request state exposes available before acceptance",
		WorldRequestStateScript.resolve(true, false, false, false, false)
		== WorldRequestStateScript.State.AVAILABLE,
		"Unlocked but unaccepted requests need a stable AVAILABLE presentation state."
	)
	_record(
		report,
		"world request state exposes accepted while objective is open",
		WorldRequestStateScript.resolve(true, true, false, false, false)
		== WorldRequestStateScript.State.ACCEPTED,
		"Acceptance must not pretend that the underlying gameplay objective is complete."
	)
	_record(
		report,
		"world request state exposes ready after objective completion",
		WorldRequestStateScript.resolve(true, true, true, false, false)
		== WorldRequestStateScript.State.READY_TO_TURN_IN,
		"The request dialogue layer must distinguish objective completion from reward delivery."
	)
	_record(
		report,
		"world request state exposes completed after reward claim",
		WorldRequestStateScript.resolve(true, true, true, true, false)
		== WorldRequestStateScript.State.COMPLETED,
		"A claimed reward is the durable terminal request state."
	)
	_record(
		report,
		"claimed request wins over source completion",
		WorldRequestStateScript.resolve(true, true, true, true, true)
		== WorldRequestStateScript.State.COMPLETED,
		"A player's completed request history must remain true even if the entire source later becomes complete."
	)

	var request_scene_node = HarborRequestBoardScene.instantiate()
	_record(
		report,
		"harbor request board has shared dialogue bridge",
		request_scene_node != null
		and request_scene_node.get_node_or_null("DialogueBridge") != null,
		"The existing world request must use the reusable dialogue layer instead of a bespoke request UI."
	)
	_record(
		report,
		"harbor request keeps stable reward event id",
		request_scene_node != null
		and str(request_scene_node.get("request_id")) == "beach_demo_harbor_errand_01"
		and str(request_scene_node.get_node("QuestRewardAdapter").get("quest_event_id"))
		== "beach_demo_harbor_errand_01",
		"Dialogue integration must not fork the one-shot reward identity used by the crash-safe ledger."
	)
	if request_scene_node != null:
		request_scene_node.free()

	var request_available_choices: Array = HarborRequestBoardScript.build_available_choices()
	_record(
		report,
		"available request choices expose acceptance and journal",
		request_available_choices.size() == 3
		and request_available_choices[0].get("choice_id", &"") == &"accept"
		and request_available_choices[1].get("choice_id", &"") == &"journal"
		and request_available_choices[2].get("choice_id", &"") == &"later",
		"AVAILABLE requests should allow explicit acceptance while keeping the shared request log reachable."
	)
	var request_accepted_choices: Array = HarborRequestBoardScript.build_accepted_choices()
	_record(
		report,
		"accepted request choices expose review and journal",
		request_accepted_choices.size() == 3
		and request_accepted_choices[0].get("choice_id", &"") == &"review"
		and request_accepted_choices[1].get("choice_id", &"") == &"journal"
		and request_accepted_choices[2].get("choice_id", &"") == &"leave",
		"ACCEPTED requests need both local objective review and access to the shared read-only request log."
	)
	var request_ready_choices: Array = HarborRequestBoardScript.build_ready_choices()
	_record(
		report,
		"ready request choices expose turn in and journal",
		request_ready_choices.size() == 3
		and request_ready_choices[0].get("choice_id", &"") == &"turn_in"
		and request_ready_choices[1].get("choice_id", &"") == &"journal"
		and request_ready_choices[2].get("choice_id", &"") == &"not_yet",
		"READY requests must keep explicit turn-in while the request log remains inspectable."
	)

	# Request presentation: world markers and a lightweight exploration tracker
	# consume already-resolved request state without becoming quest owners.
	var available_marker: Dictionary = WorldRequestMarkerScript.presentation_for_state(&"available")
	_record(
		report,
		"available request uses exclamation marker",
		bool(available_marker.get("visible", false))
		and str(available_marker.get("marker", "")) == "!",
		"Unaccepted visible requests need a clear world-space discovery marker."
	)
	var accepted_marker: Dictionary = WorldRequestMarkerScript.presentation_for_state(&"accepted")
	_record(
		report,
		"accepted request keeps a quieter active marker",
		bool(accepted_marker.get("visible", false))
		and str(accepted_marker.get("marker", "")) == "*",
		"Active requests should remain identifiable without looking identical to new requests."
	)
	var ready_marker: Dictionary = WorldRequestMarkerScript.presentation_for_state(&"ready_to_turn_in")
	_record(
		report,
		"ready request uses question marker",
		bool(ready_marker.get("visible", false))
		and str(ready_marker.get("marker", "")) == "?",
		"Turn-in-ready requests need a distinct return-to-source marker."
	)
	_record(
		report,
		"terminal request states hide world marker",
		not bool(WorldRequestMarkerScript.presentation_for_state(&"completed").get("visible", true))
		and not bool(WorldRequestMarkerScript.presentation_for_state(&"locked").get("visible", true)),
		"Completed or unavailable requests must stop advertising themselves in the world."
	)

	_record(
		report,
		"objective tracker tracks accepted requests",
		WorldObjectiveTrackerScript.should_track_state(&"accepted")
		and WorldObjectiveTrackerScript.status_text(&"accepted") == "ACTIVE",
		"An accepted request should produce a persistent exploration objective."
	)
	_record(
		report,
		"objective tracker tracks ready requests",
		WorldObjectiveTrackerScript.should_track_state(&"ready_to_turn_in")
		and WorldObjectiveTrackerScript.status_text(&"ready_to_turn_in") == "READY",
		"A completed objective must remain visible until its explicit turn-in."
	)
	_record(
		report,
		"objective tracker ignores available and completed requests",
		not WorldObjectiveTrackerScript.should_track_state(&"available")
		and not WorldObjectiveTrackerScript.should_track_state(&"completed"),
		"The tracker should show current obligations, not every discoverable or historical request."
	)
	_record(
		report,
		"ready objective outranks ordinary active objective",
		WorldObjectiveTrackerScript.priority_for_state(&"ready_to_turn_in")
		> WorldObjectiveTrackerScript.priority_for_state(&"accepted"),
		"When several requests exist later, a turn-in-ready request should be surfaced first."
	)

	var tracker_candidates := {
		"alpha": {
			"request_id": &"alpha",
			"title": "Alpha",
			"objective": "Keep working.",
			"state_id": &"accepted",
		},
		"beta": {
			"request_id": &"beta",
			"title": "Beta",
			"objective": "Return now.",
			"state_id": &"ready_to_turn_in",
		},
	}
	var primary_request: Dictionary = WorldObjectiveTrackerScript.select_primary(tracker_candidates)
	_record(
		report,
		"objective tracker deterministically selects ready request",
		str(primary_request.get("request_id", "")) == "beta",
		"The reusable tracker must have deterministic primary-objective selection before multiple requests are added."
	)

	var marker_board = HarborRequestBoardScene.instantiate()
	_record(
		report,
		"harbor request board includes reusable request marker",
		marker_board != null and marker_board.get_node_or_null("RequestMarker") != null,
		"The first request slice must prove world-marker integration through the reusable marker scene."
	)
	if marker_board != null:
		marker_board.free()

	var tracker_scene_node = WorldObjectiveTrackerScene.instantiate()
	_record(
		report,
		"objective tracker scene exposes reusable request API",
		tracker_scene_node != null
		and tracker_scene_node.has_method("register_request")
		and tracker_scene_node.has_method("remove_request")
		and tracker_scene_node.has_method("get_primary_snapshot"),
		"Future request sources must be able to share one tracker instead of authoring bespoke HUDs."
	)
	if tracker_scene_node != null:
		tracker_scene_node.free()

	# Request Journal v1: historical/read-only presentation reuses the same
	# request snapshots without becoming another progression owner.
	_record(
		report,
		"request journal keeps accepted ready and completed states",
		WorldObjectiveTrackerScript.should_keep_journal_state(&"accepted")
		and WorldObjectiveTrackerScript.should_keep_journal_state(&"ready_to_turn_in")
		and WorldObjectiveTrackerScript.should_keep_journal_state(&"completed"),
		"The journal must preserve active, return-ready, and completed request history."
	)
	_record(
		report,
		"request journal ignores available and locked states",
		not WorldObjectiveTrackerScript.should_keep_journal_state(&"available")
		and not WorldObjectiveTrackerScript.should_keep_journal_state(&"locked"),
		"The journal is a log of accepted requests, not a discovery list of every possible request."
	)
	_record(
		report,
		"completed requests stay out of active tracker",
		not WorldObjectiveTrackerScript.should_track_state(&"completed")
		and WorldObjectiveTrackerScript.status_text(&"completed") == "COMPLETE",
		"Completion history may remain journal-visible without reappearing as an active HUD objective."
	)

	var journal_candidates := {
		"done": {
			"request_id": &"done",
			"title": "Done Request",
			"objective": "Completed.",
			"state_id": &"completed",
		},
		"active": {
			"request_id": &"active",
			"title": "Active Request",
			"objective": "Keep working.",
			"state_id": &"accepted",
		},
		"ready": {
			"request_id": &"ready",
			"title": "Ready Request",
			"objective": "Return now.",
			"state_id": &"ready_to_turn_in",
		},
	}
	var journal_sorted: Array = WorldObjectiveTrackerScript.sort_journal_snapshots(journal_candidates)
	_record(
		report,
		"request journal ordering prioritizes ready then active then complete",
		journal_sorted.size() == 3
		and str(journal_sorted[0].get("request_id", "")) == "ready"
		and str(journal_sorted[1].get("request_id", "")) == "active"
		and str(journal_sorted[2].get("request_id", "")) == "done",
		"When several requests exist, the journal should surface actionable entries before history."
	)
	_record(
		report,
		"journal view normalizes supported request states",
		WorldRequestJournalScript.normalize_snapshots(journal_sorted).size() == 3,
		"The presentation view must consume resolved snapshots without inventing request state."
	)
	_record(
		report,
		"journal view exposes stable status labels",
		WorldRequestJournalScript.state_label(&"accepted") == "ACTIVE"
		and WorldRequestJournalScript.state_label(&"ready_to_turn_in") == "READY"
		and WorldRequestJournalScript.state_label(&"completed") == "COMPLETE",
		"Request status language must remain consistent between the compact tracker and full journal."
	)
	var completed_choices: Array = HarborRequestBoardScript.build_completed_choices()
	_record(
		report,
		"completed request remains journal-accessible",
		completed_choices.size() == 2
		and completed_choices[0].get("choice_id", &"") == &"journal"
		and completed_choices[1].get("choice_id", &"") == &"leave",
		"Turning in a request must not remove the player's ability to review that completed history."
	)
	var journal_scene_node = WorldRequestJournalScene.instantiate()
	_record(
		report,
		"request journal scene exposes read-only open close API",
		journal_scene_node != null
		and journal_scene_node.has_method("open_with_requests")
		and journal_scene_node.has_method("close_journal")
		and journal_scene_node.has_method("is_open"),
		"Request sources need one reusable journal view instead of bespoke quest-log panels."
	)
	if journal_scene_node != null:
		journal_scene_node.free()
	var journal_tracker_node = WorldObjectiveTrackerScene.instantiate()
	_record(
		report,
		"objective tracker exposes journal snapshot and open APIs",
		journal_tracker_node != null
		and journal_tracker_node.has_method("get_journal_snapshots")
		and journal_tracker_node.has_method("open_journal")
		and journal_tracker_node.has_method("has_journal_entries"),
		"The active objective tracker must double as a read model for the journal without owning quest state."
	)
	if journal_tracker_node != null:
		journal_tracker_node.free()


	# Second Request Source v1: prove the request stack against a non-duel
	# objective owned by the gathering inventory and surfaced through the Crafter.
	var material_two: Dictionary = MaterialCountRequestObjectiveScript.progress_snapshot_for_count(2, 3)
	_record(
		report,
		"material request progress stays incomplete below target",
		int(material_two.get("current", -1)) == 2
		and int(material_two.get("required", -1)) == 3
		and not bool(material_two.get("complete", true))
		and str(material_two.get("progress_text", "")) == "2/3",
		"Inventory-backed requests need deterministic progress before completion."
	)
	var material_three: Dictionary = MaterialCountRequestObjectiveScript.progress_snapshot_for_count(3, 3)
	_record(
		report,
		"material request completes exactly at target",
		bool(material_three.get("complete", false))
		and int(material_three.get("remaining", -1)) == 0
		and str(material_three.get("progress_text", "")) == "3/3",
		"Gathering objectives must become turn-in-ready as soon as the required count is owned."
	)
	_record(
		report,
		"material request progress clamps negative counts",
		int(MaterialCountRequestObjectiveScript.progress_snapshot_for_count(-5, 3).get("current", -1)) == 0,
		"Malformed/legacy inventory counts must never create negative objective progress."
	)
	_record(
		report,
		"generic request acceptance key is stable",
		WorldRequestProgressStoreScript.acceptance_key(&"beach_demo_crafter_sea_glass_01")
		== "world_request/accepted/beach_demo_crafter_sea_glass_01",
		"Future request sources need deterministic acceptance persistence without inventing new save files."
	)
	_record(
		report,
		"crafter request main labels reflect request state",
		BeachCrafterRequestSourceScript.main_choice_text_for_state(&"available") == "Sea Glass Survey"
		and BeachCrafterRequestSourceScript.main_choice_text_for_state(&"accepted") == "Review Sea Glass Survey"
		and BeachCrafterRequestSourceScript.main_choice_text_for_state(&"ready_to_turn_in") == "Turn In Sea Glass Survey"
		and BeachCrafterRequestSourceScript.main_choice_text_for_state(&"completed") == "Sea Glass Survey Complete",
		"The same NPC service menu must remain truthful as the request advances."
	)
	_record(
		report,
		"locked crafter request stays out of service choices",
		BeachCrafterRequestSourceScript.main_choice_text_for_state(&"locked").is_empty(),
		"A reward-backed request must not advertise itself before its unlock condition is valid."
	)
	var crafter_available_choices: Array = BeachCrafterRequestSourceScript.build_available_choices()
	_record(
		report,
		"crafter available request choices accept or defer",
		crafter_available_choices.size() == 2
		and crafter_available_choices[0].get("choice_id", &"") == &"accept"
		and crafter_available_choices[1].get("choice_id", &"") == &"later",
		"The second request source must use the same explicit acceptance pattern as the Harbor Board."
	)
	var crafter_active_choices: Array = BeachCrafterRequestSourceScript.build_accepted_choices()
	_record(
		report,
		"crafter active request choices review or back",
		crafter_active_choices.size() == 2
		and crafter_active_choices[0].get("choice_id", &"") == &"review"
		and crafter_active_choices[1].get("choice_id", &"") == &"back",
		"Active material requests need a reusable progress-review path."
	)
	var crafter_ready_choices: Array = BeachCrafterRequestSourceScript.build_ready_choices()
	_record(
		report,
		"crafter ready request choices claim or defer",
		crafter_ready_choices.size() == 2
		and crafter_ready_choices[0].get("choice_id", &"") == &"turn_in"
		and crafter_ready_choices[1].get("choice_id", &"") == &"not_yet",
		"Turn-in remains explicit even when the objective is already satisfied."
	)
	var crafter_request_scene = BeachCrafterScene.instantiate()
	_record(
		report,
		"beach crafter scene contains modular request source",
		crafter_request_scene != null and crafter_request_scene.get_node_or_null("RequestSource") != null,
		"The second request must be composed as a reusable child instead of bloating the core crafter controller."
	)
	_record(
		report,
		"beach crafter scene contains request marker",
		crafter_request_scene != null and crafter_request_scene.get_node_or_null("RequestMarker") != null,
		"Every live request source should feed the shared world-marker presentation."
	)
	var crafter_reward_adapter: Node = null
	var crafter_material_objective: Node = null
	if crafter_request_scene != null:
		crafter_reward_adapter = crafter_request_scene.get_node_or_null("RequestSource/QuestRewardAdapter")
		crafter_material_objective = crafter_request_scene.get_node_or_null("RequestSource/MaterialObjective")
	_record(
		report,
		"crafter survey uses canonical Town Requests card source",
		crafter_reward_adapter != null
		and StringName(str(crafter_reward_adapter.get("source_id"))) == &"town_requests",
		"A gathering request should extend the authored card-acquisition map instead of inventing a new reward source."
	)
	_record(
		report,
		"crafter survey has unique one-shot reward event",
		crafter_reward_adapter != null
		and StringName(str(crafter_reward_adapter.get("quest_event_id"))) == &"beach_demo_crafter_sea_glass_01",
		"The second request reward needs independent durable claim identity."
	)
	_record(
		report,
		"crafter survey objective is three Sea Glass",
		crafter_material_objective != null
		and StringName(str(crafter_material_objective.get("material_id"))) == &"sea_glass"
		and int(crafter_material_objective.get("required_count")) == 3,
		"The scalability proof must use a real beach-gathering domain id rather than a synthetic QA item."
	)
	var multi_source_candidates := {
		"beach_demo_harbor_errand_01": {
			"request_id": &"beach_demo_harbor_errand_01",
			"title": "Harbor Request",
			"objective": "Defeat Beach Trader.",
			"state_id": &"accepted",
		},
		"beach_demo_crafter_sea_glass_01": {
			"request_id": &"beach_demo_crafter_sea_glass_01",
			"title": "Sea Glass Survey",
			"objective": "Return to the Crafter.",
			"state_id": &"ready_to_turn_in",
		},
	}
	var multi_primary: Dictionary = WorldObjectiveTrackerScript.select_primary(multi_source_candidates)
	_record(
		report,
		"tracker prioritizes ready request across different objective backends",
		str(multi_primary.get("request_id", "")) == "beach_demo_crafter_sea_glass_01",
		"Ready-to-turn-in priority must work across duel and gathering request sources, not only within one system."
	)
	if crafter_request_scene != null:
		crafter_request_scene.free()

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
