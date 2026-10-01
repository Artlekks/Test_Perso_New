extends Node
class_name FishingDebugController

## Development/QA ownership boundary.
##
## The gameplay Fishing controller only asks whether debug owns input and
## whether a debug-forced catch should be persisted. All debug menu/settings
## lifecycle stays here.

const FishingDebugSettingsScript = preload(
	"res://scripts/fishing_debug_settings.gd"
)
const FishingRegressionHarnessScript = preload(
	"res://scripts/fishing_regression_harness.gd"
)
const FishingDebugMenuScene = preload(
	"res://actors/FishingDebugMenu.tscn"
)

var settings = null
var regression_harness: FishingRegressionHarness = null
var debug_menu: Node = null

var _game_mode: Node = null
var _encounter: Node = null
var _aim: Node = null
var _loadout: FishingLoadout = null
var _progress: FishingProgress = null
var _journal: FishingJournalService = null
var _unlock_state: FishingUnlockState = null
var _reward_service: FishingRewardService = null
var _session_modifier_service = null
var _open: bool = false


func configure(
	game_mode: Node,
	encounter: Node,
	aim: Node,
	loadout: FishingLoadout,
	progress: FishingProgress,
	journal: FishingJournalService = null,
	unlock_state: FishingUnlockState = null,
	reward_service: FishingRewardService = null,
	session_modifier_service = null
) -> void:
	_game_mode = game_mode
	_encounter = encounter
	_aim = aim
	_loadout = loadout
	_progress = progress
	_journal = journal
	_unlock_state = unlock_state
	_reward_service = reward_service
	_session_modifier_service = session_modifier_service

	settings = FishingDebugSettingsScript.new()
	if settings.has_method("configure_progress"):
		settings.configure_progress(_progress)
	regression_harness = FishingRegressionHarnessScript.new()

	if _encounter != null and _encounter.has_method("set_debug_settings"):
		_encounter.set_debug_settings(settings)

	debug_menu = FishingDebugMenuScene.instantiate()
	add_child(debug_menu)
	debug_menu.configure(
		_loadout,
		settings,
		_progress,
		_encounter,
		regression_harness
	)
	debug_menu.connect(
		"spot_requested",
		Callable(self, "_on_spot_requested")
	)
	debug_menu.connect(
		"debug_environment_changed",
		Callable(self, "sync_environment")
	)
	debug_menu.connect(
		"reset_fishing_progress_requested",
		Callable(self, "_on_reset_fishing_progress_requested")
	)

	set_fish_zone(_get_active_zone())
	sync_environment()


func is_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	if not event.pressed or event.echo:
		return false
	# Shift+F10 is reserved for the Triple Triad Campaign QA harness. Normal F10
	# remains the fishing QA menu.
	if event.shift_pressed:
		return false

	return (
		event.keycode == KEY_F10
		or event.physical_keycode == KEY_F10
	)


func is_open() -> bool:
	return _open


func toggle(can_open: bool) -> void:
	if _open:
		close(true)
	elif can_open:
		open()


func route_open_input(event: InputEvent) -> bool:
	if not _open or debug_menu == null:
		return false

	var close_requested: bool = bool(
		debug_menu.handle_input(event)
	)
	if close_requested:
		close(true)

	return true


func open() -> bool:
	if debug_menu == null:
		return false

	set_fish_zone(_get_active_zone())

	if not debug_menu.open_menu():
		return false

	_open = true
	if _aim != null and _aim.has_method("stop"):
		_aim.stop()
	return true


func close(resume_aim: bool) -> void:
	if debug_menu != null:
		debug_menu.close_menu()

	var was_open := _open
	_open = false

	if (
		was_open
		and resume_aim
		and _aim != null
		and _aim.has_method("resume")
	):
		_aim.resume()


func set_fish_zone(zone: Node) -> void:
	if debug_menu != null:
		debug_menu.set_fish_zone(zone)


func sync_environment() -> void:
	var zone = _get_active_zone()
	if zone == null:
		return

	if _encounter != null and _encounter.has_method("set_fish_population"):
		_encounter.set_fish_population(
			zone.get_fish_population()
		)

	if settings == null:
		return

	if zone.has_method("set_debug_shadow_overrides"):
		zone.set_debug_shadow_overrides(
			settings.get_shadow_fish_override(),
			settings.get_shadow_count_override()
		)
		return

	# Compatibility path for older FishZone scenes.
	if zone.has_method("set_debug_shadow_fish"):
		zone.set_debug_shadow_fish(
			settings.get_shadow_fish_override()
		)
	if zone.has_method("set_debug_shadow_count"):
		zone.set_debug_shadow_count(
			settings.get_shadow_count_override()
		)


func run_regression_suite() -> Dictionary:
	if regression_harness == null:
		return {}

	return regression_harness.run_all()


func should_record_catch() -> bool:
	if settings == null:
		return true

	# Persistence is gated only by QA controls that can alter the actual catch
	# outcome. Presentation-only shadow overrides are deliberately excluded so
	# profiles such as SHADOWS / FIVE cannot silently disable progression.
	var outcome_override_active: bool = bool(
		settings.is_catch_outcome_override_active()
	)
	var allow_debug_record: bool = bool(
		settings.should_record_debug_catches()
	)

	return not outcome_override_active or allow_debug_record


func _on_reset_fishing_progress_requested() -> void:
	# One authoritative QA reset path. The journal owns progress + physical fish
	# inventory, while unlock/reward services own their own persistence. This
	# produces the same baseline as a new fishing player without touching camera,
	# environment, or unrelated game systems.
	if is_instance_valid(_journal):
		_journal.reset_all_fishing_data(true, true)
	elif is_instance_valid(_progress):
		_progress.reset_all_progress(true)

	if is_instance_valid(_unlock_state):
		_unlock_state.reset_unlocks(true)

	if is_instance_valid(_reward_service):
		_reward_service.reset_rewards(true)

	if (
		_session_modifier_service != null
		and _session_modifier_service.has_method("clear_all")
	):
		_session_modifier_service.clear_all()

	if _loadout != null and _loadout.has_method("repair_selection"):
		_loadout.repair_selection(true)

	print("Fishing QA reset complete: Beginner / 0 fishing points / no records / no session buffs.")


func _on_spot_requested(spot: FishingSpotData) -> void:
	var zone = _get_active_zone()
	if zone == null or spot == null:
		return

	if zone.has_method("set_fishing_spot"):
		zone.set_fishing_spot(spot)
	else:
		zone.set("fishing_spot", spot)

	if _encounter != null and _encounter.has_method("set_fish_population"):
		_encounter.set_fish_population(
			zone.get_fish_population()
		)


func _get_active_zone() -> Node:
	if _game_mode == null:
		return null
	return _game_mode.active_fish_zone
