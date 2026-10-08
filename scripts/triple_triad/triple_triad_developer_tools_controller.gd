extends RefCounted
class_name TripleTriadDeveloperToolsController
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

const BalanceSimulatorScript = preload("res://scripts/triple_triad/triple_triad_balance_simulator.gd")
const CampaignQAHarnessScript = preload("res://scripts/triple_triad/triple_triad_campaign_qa_harness.gd")
const CampaignQAMenuScene = preload("res://actors/TripleTriadCampaignQAMenu.tscn")
const PlaytestRecorderScript = preload("res://scripts/triple_triad/triple_triad_playtest_recorder.gd")
const REPORT_PATH := "user://triple_triad_qa_report.json"

var _host: Node = null
var _card_catalog = null
var _opponent_registry = null
var _backend_version: String = ""
var _callbacks: Dictionary = {}
var _world_reward_ledger = null
var _campaign_qa_harness = CampaignQAHarnessScript.new()
var _campaign_qa_menu: CanvasLayer = null
var _playtest_recorder = PlaytestRecorderScript.new()


func initialize(
	host: Node,
	card_catalog,
	opponent_registry,
	backend_version: String,
	callbacks: Dictionary
) -> void:
	_host = host
	_card_catalog = card_catalog
	_opponent_registry = opponent_registry
	_backend_version = backend_version
	_callbacks = callbacks.duplicate()
	_build_campaign_qa_menu()


func bind_runtime(world_reward_ledger) -> void:
	_world_reward_ledger = world_reward_ledger


func toggle_campaign_qa_menu() -> void:
	if _campaign_qa_menu == null:
		return
	if bool(_campaign_qa_menu.call("is_open")):
		_campaign_qa_menu.call("close_menu")
	else:
		_campaign_qa_menu.call("open_menu", get_campaign_qa_snapshot())



func is_campaign_qa_menu_open() -> bool:
	return (
		_campaign_qa_menu != null
		and bool(_campaign_qa_menu.call("is_open"))
	)


func handle_campaign_qa_input(event: InputEvent) -> bool:
	if _campaign_qa_menu == null or not is_campaign_qa_menu_open():
		return false
	var close_requested: bool = bool(
		_campaign_qa_menu.call("handle_input", event)
	)
	if close_requested:
		_campaign_qa_menu.call("close_menu")
	return true

func get_campaign_qa_snapshot() -> Dictionary:
	var backend_ready: bool = bool(_call_callback(&"is_backend_ready", [], false))
	return {
		"player": _call_callback(&"get_player_snapshot", [], {}) if backend_ready else {},
		"acquisition": _call_callback(&"get_acquisition_snapshot", [], {}) if backend_ready else {},
		"completion": _call_callback(&"get_collection_completion_snapshot", [], {}) if backend_ready else {},
		"recovery": _call_callback(&"get_runtime_recovery_snapshot", [], {}),
		"qa_snapshot": _campaign_qa_harness.get_qa_snapshot_info(),
		"playtest_log": _playtest_recorder.get_info(),
	}


func append_playtest_event(
	event_type: StringName,
	payload: Dictionary = {}
) -> void:
	if not OS.is_debug_build():
		return
	_playtest_recorder.append(event_type, payload)


func record_session_start(recovery: Dictionary) -> void:
	if not OS.is_debug_build():
		return
	_playtest_recorder.append(
		&"session_start",
		{
			"backend_version": _backend_version,
			"recovery": recovery.duplicate(true),
		}
	)


func run_backend_qa() -> Dictionary:
	var qa_script = load("res://scripts/triple_triad/triple_triad_backend_qa.gd")
	if qa_script == null:
		var missing_report := {
			"passed": false,
			"test_count": 0,
			"passed_count": 0,
			"failed_count": 1,
			"failures": ["QA harness missing"],
		}
		push_error("TripleTriad developer tools: backend QA harness could not be loaded.")
		return missing_report

	var qa_runner = qa_script.new()
	var report: Dictionary = qa_runner.run_all()
	if bool(report.get("passed", false)):
		print(
			"TripleTriad QA: %d/%d backend tests passed."
			% [
				int(report.get("passed_count", 0)),
				int(report.get("test_count", 0)),
			]
		)
	else:
		push_error(
			"TripleTriad QA: %d/%d tests failed: %s"
			% [
				int(report.get("failed_count", 0)),
				int(report.get("test_count", 0)),
				str(report.get("failures", [])),
			]
		)
		for raw_result in report.get("results", []):
			var qa_result: Dictionary = raw_result
			if not bool(qa_result.get("passed", false)):
				push_error(
					"  QA FAIL — %s: %s"
					% [
						str(qa_result.get("name", "unknown")),
						str(qa_result.get("error", "")),
					]
				)
	return report


func run_balance_simulation(
	games_per_matchup: int = 40,
	simulation_seed: int = 1337
) -> Dictionary:
	if _card_catalog == null or _opponent_registry == null:
		return {
			"valid": false,
			"errors": ["Card catalog or opponent registry is unavailable."],
		}
	var simulator = BalanceSimulatorScript.new()
	var report: Dictionary = simulator.run_registry_suite(
		_card_catalog,
		_opponent_registry,
		maxi(1, games_per_matchup),
		simulation_seed,
		true
	)
	if bool(report.get("valid", false)):
		var global: Dictionary = report.get("global", {})
		print(
			"TripleTriad Balance: %d games, first-player %.1f%% / second-player %.1f%% of decisive games, draw %.1f%%. Report: %s"
			% [
				int(global.get("games", 0)),
				float(global.get("first_player_win_rate", 0.0)) * 100.0,
				float(global.get("second_player_win_rate", 0.0)) * 100.0,
				float(global.get("draw_rate", 0.0)) * 100.0,
				str(report.get("report_path", "")),
			]
		)
		for raw_check in report.get("ladder_checks", []):
			var check: Dictionary = raw_check
			print(
				"  Ladder %s -> %s: %.1f%% decisive wins (%s)"
				% [
					str(check.get("lower_name", "?")),
					str(check.get("higher_name", "?")),
					float(check.get("higher_decisive_win_rate", 0.0)) * 100.0,
					str(check.get("status", "")),
				]
			)
	else:
		push_error(
			"TripleTriad Balance simulation failed: %s"
			% str(report.get("errors", []))
		)
	return report


func capture_diagnostic_report() -> Dictionary:
	var tree: SceneTree = _host.get_tree() if is_instance_valid(_host) else null
	var scene_path: String = ""
	var tree_paused: bool = false
	if tree != null:
		tree_paused = tree.paused
		if GameplaySceneRoot.resolve(tree) != null:
			scene_path = str(GameplaySceneRoot.resolve(tree).scene_file_path)
	var backend_ready: bool = bool(_call_callback(&"is_backend_ready", [], false))
	var global_snapshot: Dictionary = {}
	if backend_ready:
		global_snapshot = _call_callback(&"get_global_triple_triad_snapshot", [], {})
	var report := {
		"generated_time": Time.get_datetime_string_from_system(),
		"generated_unix": int(Time.get_unix_time_from_system()),
		"backend_version": _backend_version,
		"engine": Engine.get_version_info(),
		"scene": scene_path,
		"tree_paused": tree_paused,
		"backend_health": _call_callback(&"get_backend_health", [], {}),
		"global": global_snapshot,
		"recovery": _call_callback(&"get_runtime_recovery_snapshot", [], {}),
		"pending_gameplay_events": _call_callback(&"get_pending_gameplay_events", [], []),
		"campaign_qa": get_campaign_qa_snapshot(),
		"qa_snapshot": _campaign_qa_harness.get_qa_snapshot_info(),
		"playtest_log": _playtest_recorder.get_info(),
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return {
			"success": false,
			"reason": "report_open_failed",
		}
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_playtest_recorder.append(
		&"diagnostic_report_captured",
		{"path": REPORT_PATH}
	)
	return {
		"success": true,
		"path": REPORT_PATH,
	}


func _build_campaign_qa_menu() -> void:
	if not OS.is_debug_build() or _campaign_qa_menu != null or not is_instance_valid(_host):
		return
	_campaign_qa_menu = CampaignQAMenuScene.instantiate() as CanvasLayer
	_host.add_child(_campaign_qa_menu)
	if _campaign_qa_menu.has_method("configure"):
		_campaign_qa_menu.call("configure", _campaign_qa_harness)
	_campaign_qa_menu.connect(
		"scenario_requested",
		Callable(self, "_on_campaign_qa_scenario_requested")
	)
	_campaign_qa_menu.connect(
		"action_requested",
		Callable(self, "_on_campaign_qa_action_requested")
	)


func _on_campaign_qa_scenario_requested(scenario_id: StringName) -> void:
	if not OS.is_debug_build():
		return
	var scenario_result: Dictionary = _campaign_qa_harness.apply_scenario(
		scenario_id,
		_card_catalog
	)
	if not bool(scenario_result.get("success", false)):
		_set_status(
			"FAILED: %s" % str(scenario_result.get("reason", "unknown"))
		)
		return
	_playtest_recorder.append(&"qa_scenario_applied", scenario_result)
	_reload_scene()


func _on_campaign_qa_action_requested(action_id: StringName) -> void:
	if not OS.is_debug_build():
		return
	match action_id:
		&"arm_next_coast_salvage":
			var backend_ready: bool = bool(_call_callback(&"is_backend_ready", [], false))
			if not backend_ready or _world_reward_ledger == null:
				_set_status("Backend unavailable.")
				return
			if not bool(_call_callback(&"is_card_game_unlocked", [], false)):
				_set_status(
					"Card game is locked. Use Fresh / Undiscovered and catch the starter case first."
				)
				return
			var counter_id := StringName("fishing_salvage:coast_shallows")
			_world_reward_ledger.call("reset_counter", counter_id)
			for _index in range(3):
				_world_reward_ledger.call("increment_counter", counter_id)
			_set_status(
				"Armed: next eligible Ocean 2 catch grants Coast Shallows salvage."
			)
		&"resume_active_tournament":
			if bool(_call_callback(&"open_active_competition_match", [], false)):
				if _campaign_qa_menu != null:
					_campaign_qa_menu.call("close_menu")
			else:
				_set_status("No resumable tournament round is active.")
		&"save_qa_snapshot":
			var save_result: Dictionary = _campaign_qa_harness.save_qa_snapshot()
			if bool(save_result.get("success", false)):
				_set_status(
					"QA Snapshot A saved (%d files)."
					% int(save_result.get("file_count", 0))
				)
			else:
				_set_status("QA Snapshot save FAILED.")
		&"restore_qa_snapshot":
			var restore_result: Dictionary = _campaign_qa_harness.restore_qa_snapshot()
			if bool(restore_result.get("success", false)):
				_playtest_recorder.append(&"qa_snapshot_restored", restore_result)
				_reload_scene()
			else:
				_set_status(
					"Restore FAILED: %s"
					% str(restore_result.get("reason", "unknown"))
				)
		&"delete_qa_snapshot":
			var delete_result: Dictionary = _campaign_qa_harness.delete_qa_snapshot()
			if bool(delete_result.get("success", false)):
				_set_status("QA Snapshot A deleted.")
			else:
				_set_status("QA Snapshot delete FAILED.")
		&"reset_decks":
			var reset_result: Dictionary = _campaign_qa_harness.reset_decks_only()
			if bool(reset_result.get("success", false)):
				_reload_scene()
			else:
				_set_status("Could not reset decks.")
		&"reconcile":
			var recovery: Dictionary = _call_callback(
				&"reconcile_runtime_state",
				[],
				{}
			)
			if bool(recovery.get("valid", true)):
				_set_status("Reconcile: clean")
			else:
				_set_status("Reconcile: attention required")
		&"capture_qa_report":
			var report_result: Dictionary = capture_diagnostic_report()
			if bool(report_result.get("success", false)):
				_set_status("Diagnostic report captured.")
			else:
				_set_status("Diagnostic report FAILED.")
		&"clear_playtest_log":
			if _playtest_recorder.clear():
				_set_status("Playtest log cleared.")
			else:
				_set_status("Could not clear playtest log.")
		&"run_backend_qa":
			var qa_report: Dictionary = run_backend_qa()
			_set_status(
				"Backend QA: %d / %d passed"
				% [
					int(qa_report.get("passed_count", 0)),
					int(qa_report.get("test_count", 0)),
				]
			)


func _set_status(text: String) -> void:
	if _campaign_qa_menu != null:
		_campaign_qa_menu.call("set_status", text)


func _reload_scene() -> void:
	if not is_instance_valid(_host):
		return
	var tree: SceneTree = _host.get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.reload_current_scene()


func _call_callback(
	key: StringName,
	args: Array = [],
	fallback = null
):
	var callback = _callbacks.get(key)
	if callback is Callable and callback.is_valid():
		return callback.callv(args)
	return fallback
