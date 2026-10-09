extends RefCounted
## Optional observer seam. No QA scripts, recorder or debug scene is loaded
## unless the development composition explicitly installs an implementation.
var _observer = null
var _configuration: Array = []
var _ledger = null

func disable_development() -> void:
	if _observer != null: _observer.dispose()
	_observer = null

func initialize(host: Node, catalog, opponents, version: String, callbacks: Dictionary) -> void:
	_configuration = [host, catalog, opponents, version, callbacks]

func enable_development() -> void:
	if _observer != null: return
	_observer = load("res://scripts/triple_triad/triple_triad_developer_tools_controller.gd").new()
	_observer.callv("initialize", _configuration)
	_observer.bind_runtime(_ledger)

func bind_runtime(ledger) -> void:
	_ledger = ledger
	if _observer != null: _observer.bind_runtime(ledger)

func record_session_start(recovery: Dictionary) -> void:
	if _observer != null: _observer.record_session_start(recovery)

func append_playtest_event(event_type: StringName, payload: Dictionary = {}) -> void:
	if _observer != null: _observer.append_playtest_event(event_type, payload)

func is_campaign_qa_menu_open() -> bool:
	return _observer != null and _observer.is_campaign_qa_menu_open()

func toggle_campaign_qa_menu() -> void:
	if _observer != null: _observer.toggle_campaign_qa_menu()

func handle_campaign_qa_input(event: InputEvent) -> bool:
	return _observer != null and _observer.handle_campaign_qa_input(event)

func run_backend_qa() -> Dictionary:
	# An explicit QA command opts in; production never executes this method.
	enable_development()
	return _observer.run_backend_qa()

func run_balance_simulation(games: int, seed_value: int) -> Dictionary:
	enable_development()
	return _observer.run_balance_simulation(games, seed_value)
