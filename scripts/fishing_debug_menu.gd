extends CanvasLayer

signal spot_requested(spot: FishingSpotData)
signal debug_environment_changed
signal reset_fishing_progress_requested

const CONTENT_CATALOG: FishingContentCatalog = preload(
	"res://data/bof4/catalogs/all_content.tres"
)

const CatchScoring = preload(
	"res://scripts/fishing_catch_scoring.gd"
)
const DebugSettingsScript = preload(
	"res://scripts/fishing_debug_settings.gd"
)
const EconomyProgressionSimulatorScript = preload(
	"res://scripts/progression/economy_progression_simulator.gd"
)

const TECHNIQUE_CATALOG: FishingTechniqueCatalog = preload(
	"res://data/bof4/techniques/all_techniques.tres"
)

const QA_PROFILE_DIRECTORY := "res://data/debug/qa_profiles"
const MAX_DEBUG_SHADOW_COUNT := 12
const ResponsiveWindow = preload("res://scripts/mobile/mobile_playtest_window.gd")


enum Row {
	PROFILE,
	SPOT,
	FISH,
	SPECIMEN,
	SHADOWS,
	KING,
	LURE,
	ROD,
	TECH,
	SAVE_DEBUG,
	TELEMETRY,
}

const ROW_COUNT := 11

@onready var root: Control = $Root
@onready var profile_label: Label = $Root/Panel/ProfileLabel
@onready var spot_label: Label = $Root/Panel/SpotLabel
@onready var fish_label: Label = $Root/Panel/FishLabel
@onready var specimen_label: Label = $Root/Panel/SpecimenLabel
@onready var shadow_count_label: Label = $Root/Panel/ShadowCountLabel
@onready var king_label: Label = $Root/Panel/KingLabel
@onready var lure_label: Label = $Root/Panel/LureLabel
@onready var rod_label: Label = $Root/Panel/RodLabel
@onready var tech_label: Label = $Root/Panel/TechLabel
@onready var save_debug_label: Label = $Root/Panel/SaveDebugLabel
@onready var status_label: Label = $Root/Panel/StatusLabel

var _loadout = null
var _settings = null
var _progress: FishingProgress = null
var _fish_zone: Node = null
var _encounter: Node = null
var _regression_harness: FishingRegressionHarness = null
var _last_regression_summary: String = "NOT RUN"
var _economy_simulator = EconomyProgressionSimulatorScript.new()
var _last_economy_summary: String = "NOT RUN"
var _selected_row: int = Row.PROFILE
var _profile_index: int = 0
var _profile_database: Array[FishingQAProfile] = []
var _spot_index: int = -1
var _fish_index: int = 0
var _economy_telemetry: Node = null
var _telemetry_button: Button
var _telemetry_status := ""
var _playtest_page := false
var _playtest_row := 0
var _travel_index := 0
var _playtest_panel: VBoxContainer
var _playtest_rows: Array[Label] = []
var _playtest_status := "Access is transient; loadouts require isolated mobile save."
var _travel_submenu := false
const PLAYTEST_ROW_COUNT := 7


func _ready() -> void:
	root.hide()
	var tab := Button.new()
	tab.text = "PLAYTEST / FISHING QA (START / Space)"
	tab.position = Vector2(28, 43)
	tab.size = Vector2(564, 26)
	tab.focus_mode = Control.FOCUS_NONE
	tab.pressed.connect(_toggle_playtest_page)
	$Root/Panel.add_child(tab)
	_playtest_panel = VBoxContainer.new()
	_playtest_panel.position = Vector2(28, 74)
	_playtest_panel.size = Vector2(564, 430)
	_playtest_panel.add_theme_constant_override("separation", 18)
	for index in range(PLAYTEST_ROW_COUNT):
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 18)
		_playtest_rows.append(label)
		_playtest_panel.add_child(label)
	$Root/Panel.add_child(_playtest_panel)
	_playtest_panel.hide()
	_telemetry_button = Button.new()
	_telemetry_button.position = Vector2(28, 372)
	_telemetry_button.size = Vector2(564, 28)
	_telemetry_button.focus_mode = Control.FOCUS_NONE
	_telemetry_button.pressed.connect(_toggle_economy_recording)
	$Root/Panel.add_child(_telemetry_button)
	$Root/Panel/DividerLabel2.hide()
	_update_telemetry_button()
	_toggle_playtest_page()
	if not get_viewport() is SubViewport:
		var fitter := ResponsiveWindow.new()
		fitter.name = "MobilePlaytestWindow"
		add_child(fitter)
		fitter.configure(root)


func configure_economy_telemetry(telemetry: Node) -> void:
	_economy_telemetry = telemetry
	_update_telemetry_button()


func _update_telemetry_button() -> void:
	if _telemetry_button != null:
		_telemetry_button.disabled = _economy_telemetry == null
		_telemetry_button.text = ("> " if _selected_row == Row.TELEMETRY else "") + ("Stop Recording & Save Report" if _economy_telemetry != null and _economy_telemetry.recorder.active else "Start Economy Playtest Recording")
		_telemetry_button.tooltip_text = _telemetry_status


func _toggle_economy_recording() -> void:
	if _economy_telemetry == null:
		return
	if _economy_telemetry.recorder.active:
		var output: Dictionary = _economy_telemetry.stop_recording()
		_telemetry_status = "Saved: " + str(output.get("raw_path", "")) if output.get("ok", false) else "Save failed; report retained in memory"
	else:
		_telemetry_status = "Recording started" if _economy_telemetry.start_recording() else "Recording could not start"
	_update_telemetry_button()
	_refresh()


func configure(
	loadout,
	settings,
	progress: FishingProgress = null,
	encounter: Node = null,
	regression_harness: FishingRegressionHarness = null
) -> void:
	_loadout = loadout
	_settings = settings
	_progress = progress
	_encounter = encounter
	_regression_harness = regression_harness
	_load_qa_profiles()

	if _progress != null:
		var callback := Callable(self, "_on_progress_changed")
		if not _progress.changed.is_connected(callback):
			_progress.changed.connect(callback)

	_sync_from_runtime()
	_refresh()


func set_fish_zone(zone: Node) -> void:
	_fish_zone = zone
	_sync_spot_from_runtime()
	_refresh()


func open_menu() -> bool:
	if not _playtest_page: _toggle_playtest_page()
	_playtest_row = 0
	_travel_submenu = false
	_update_telemetry_button()
	if _loadout == null or _settings == null:
		return false

	_sync_from_runtime()
	_refresh()
	root.show()
	return true


func close_menu() -> void:
	root.hide()

func _toggle_playtest_page() -> void:
	_playtest_page = not _playtest_page
	$Root/Panel/TitleLabel.text = "PLAYTEST" if _playtest_page else "FISHING QA / DEBUG"
	for child in $Root/Panel.get_children():
		if child == _playtest_panel or child is Button or child.name in ["TitleLabel", "DividerLabel"]: continue
		child.visible = not _playtest_page
	_telemetry_button.visible = not _playtest_page
	_playtest_panel.visible = _playtest_page
	_refresh()

func _refresh_playtest() -> void:
	var developer := DeveloperPlaytestService.current()
	var locations := get_node_or_null("/root/WorldLocations")
	var authored: Array = locations.get_all_locations() if locations != null else []
	_travel_index = clampi(_travel_index, 0, maxi(0, authored.size() - 1))
	var destination: String = authored[_travel_index].display_name if not authored.is_empty() else "No authored locations"
	var rows := ["Developer Mode: %s" % ("ON" if developer != null and developer.enabled else "OFF"), "Travel To...", "Grant Fishing Test Loadout", "Grant Card Test Loadout", "Grant Economy Test Wallet", "Economy Recording...", "Other Debug Pages..."]
	if _travel_submenu:
		rows.clear()
		for location in authored: rows.append(location.display_name)
	for index in range(_playtest_rows.size()):
		_playtest_rows[index].visible = index < rows.size()
		if index < rows.size(): _playtest_rows[index].text = ("> " if index == (_travel_index if _travel_submenu else _playtest_row) else "  ") + rows[index]
	status_label.visible = true
	status_label.text = _playtest_status

func _playtest_change(step: int) -> void:
	if _playtest_row == 0:
		var developer := DeveloperPlaytestService.current()
		if developer != null: developer.set_enabled(not developer.enabled)
	elif _playtest_row == 1:
		var locations := get_node_or_null("/root/WorldLocations")
		if locations != null and not locations.get_all_locations().is_empty():
			_travel_index = posmod(_travel_index + step, locations.get_all_locations().size())

func _playtest_activate() -> void:
	var developer := DeveloperPlaytestService.current()
	if developer == null: return
	if _playtest_row == 0: developer.set_enabled(not developer.enabled)
	elif _playtest_row == 1:
		if not developer.enabled:
			_playtest_status = "Enable DEV for the authored location selector."
			return
		var locations := get_node_or_null("/root/WorldLocations")
		var authored: Array = locations.get_all_locations()
		if authored.is_empty(): return
		if not _travel_submenu:
			_travel_submenu = true
			return
		# Release the exploration debug modal before normal travel validates pause
		# and transfers scene ownership. Never teleport transforms around it.
		get_parent().close(false)
		var result: Dictionary = locations.request_travel(authored[_travel_index].location_id)
		_playtest_status = str(result.reason)
	elif _playtest_row == 5:
		_toggle_economy_recording()
		_playtest_status = _telemetry_status
	elif _playtest_row == 6:
		_toggle_playtest_page()
	elif _playtest_row in [2, 3, 4]:
		var result := developer.grant_loadout(["fishing", "cards", "wallet"][_playtest_row - 2])
		_playtest_status = str(result.reason)


func is_open() -> bool:
	return root.visible


## Returns true when the menu requests to close.
func handle_input(event: InputEvent) -> bool:
	if not is_open():
		return false
	if event is InputEventKey and event.echo: return false
	if _is_key_press(event, KEY_SPACE):
		_toggle_playtest_page()
		return false
	if _playtest_page:
		if event.is_action_pressed("cancel_fishing"):
			if _travel_submenu:
				_travel_submenu = false
				_refresh_playtest()
				return false
			return true
		var step := 0
		if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"): step = -1
		elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"): step = 1
		elif event.is_action_pressed("ui_left") or event.is_action_pressed("ds_left"):
			if get_viewport() is SubViewport or _travel_submenu: step = -1
			else: _playtest_change(-1)
		elif event.is_action_pressed("ui_right") or event.is_action_pressed("ds_right"):
			if get_viewport() is SubViewport or _travel_submenu: step = 1
			else: _playtest_change(1)
		elif event.is_action_pressed("enter_fishing"): _playtest_activate()
		if step != 0:
			if _travel_submenu: _travel_index = posmod(_travel_index + step, get_node("/root/WorldLocations").get_all_locations().size())
			else: _playtest_row = posmod(_playtest_row + step, PLAYTEST_ROW_COUNT)
		_refresh_playtest()
		return false
	if _selected_row == Row.TELEMETRY and event is InputEventKey and event.echo:
		return false

	if _is_key_press(event, KEY_F7):
		_run_economy_progression_simulator()
		return false

	if _is_key_press(event, KEY_F9):
		_run_regression_suite()
		return false

	# Deliberately require Shift+R because this is a destructive QA action.
	# It resets records/points/inventory back to a clean new-player fishing state.
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.pressed
			and not key_event.echo
			and key_event.shift_pressed
			and (key_event.keycode == KEY_R or key_event.physical_keycode == KEY_R)
		):
			reset_fishing_progress_requested.emit()
			return false

	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		_selected_row = posmod(_selected_row - 1, ROW_COUNT)
		_refresh()
		return false

	if event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		_selected_row = posmod(_selected_row + 1, ROW_COUNT)
		_refresh()
		return false

	if event.is_action_pressed("ui_left") or event.is_action_pressed("ds_left"):
		_change_value(-1)
		return false

	if event.is_action_pressed("ui_right") or event.is_action_pressed("ds_right"):
		_change_value(1)
		return false

	if event.is_action_pressed("enter_fishing") or event.is_action_pressed("cancel_fishing"):
		return true

	return false


func _change_value(step: int) -> void:
	match _selected_row:
		Row.PROFILE:
			_change_profile(step)
		Row.SPOT:
			_change_spot(step)
		Row.FISH:
			_change_fish(step)
		Row.SPECIMEN:
			_change_specimen(step)
		Row.SHADOWS:
			_change_shadow_count(step)
		Row.KING:
			_change_king(step)
		Row.LURE:
			_change_lure(step)
		Row.ROD:
			_change_rod(step)
		Row.TECH:
			_change_tech(step)
		Row.SAVE_DEBUG:
			_change_save_debug()
		Row.TELEMETRY:
			_toggle_economy_recording()

	_refresh()


func _load_qa_profiles() -> void:
	_profile_database.clear()

	var directory := DirAccess.open(QA_PROFILE_DIRECTORY)
	if directory == null:
		push_warning("FishingDebugMenu: QA profile directory could not be opened.")
		return

	var file_names := directory.get_files()
	for file_name in file_names:
		if not file_name.ends_with(".tres") and not file_name.ends_with(".res"):
			continue

		var resource = load(QA_PROFILE_DIRECTORY.path_join(file_name))
		if resource is FishingQAProfile:
			_profile_database.append(resource as FishingQAProfile)

	_profile_database.sort_custom(_qa_profile_less)
	_profile_index = clampi(_profile_index, 0, _profile_database.size())


func _qa_profile_less(a: FishingQAProfile, b: FishingQAProfile) -> bool:
	if a.sort_order == b.sort_order:
		return a.profile_name.naturalnocasecmp_to(b.profile_name) < 0
	return a.sort_order < b.sort_order


func _change_profile(step: int) -> void:
	_profile_index = posmod(_profile_index + step, _profile_database.size() + 1)

	# Index zero is intentionally a no-op. It means "keep the current manually
	# edited configuration" rather than silently restoring some hidden defaults.
	if _profile_index <= 0:
		return

	_apply_profile(_profile_database[_profile_index - 1])


func _apply_profile(profile: FishingQAProfile) -> void:
	if profile == null:
		return

	_settings.set_forced_fish(profile.forced_fish)
	_settings.set_specimen_mode(DebugSettingsScript.SpecimenMode.DEFAULT)
	_settings.set_shadow_fish_override(profile.shadow_fish_override)
	_settings.set_shadow_count_override(profile.shadow_count_override)
	_settings.set_king_mode(profile.king_mode)
	_settings.set_forced_tech_level(profile.forced_tech_level)
	_settings.set_record_debug_catches(profile.record_debug_catches)

	if _loadout != null:
		if profile.lure != null:
			_loadout.equip_lure(profile.lure)
		if profile.rod != null:
			_loadout.equip_rod(profile.rod)

	if profile.fishing_spot != null:
		_spot_index = CONTENT_CATALOG.spots.find(profile.fishing_spot)
		spot_requested.emit(profile.fishing_spot)

	_sync_fish_index()
	debug_environment_changed.emit()


func _change_spot(step: int) -> void:
	if CONTENT_CATALOG.spots.is_empty():
		return

	if _spot_index < 0:
		_spot_index = 0
	else:
		_spot_index = posmod(_spot_index + step, CONTENT_CATALOG.spots.size())

	# A manual spot change means "test this ecosystem". Clear a previous
	# targeted fish/shadow override so the selected spot population becomes the
	# source of truth immediately. The FISH row can still override it afterward.
	_settings.set_forced_fish(null)
	_settings.set_shadow_fish_override(null)
	_fish_index = 0

	_mark_custom_profile()
	spot_requested.emit(CONTENT_CATALOG.spots[_spot_index])
	debug_environment_changed.emit()


func _change_fish(step: int) -> void:
	# Index 0 means normal encounter RNG and normal shadow population.
	_fish_index = posmod(_fish_index + step, CONTENT_CATALOG.fish.size() + 1)

	var fish: FishData = null
	if _fish_index > 0:
		fish = CONTENT_CATALOG.fish[_fish_index - 1]

	_settings.set_forced_fish(fish)
	# Manual FISH selection intentionally mirrors into ambient/pre-bite shadows.
	_settings.set_shadow_fish_override(fish)
	_mark_custom_profile()
	debug_environment_changed.emit()


func _change_specimen(step: int) -> void:
	if _settings == null:
		return

	var next_mode := posmod(
		_settings.get_specimen_mode() + step,
		DebugSettingsScript.SpecimenMode.KING + 1
	)
	_settings.set_specimen_mode(next_mode)

	# Exact specimen forcing owns size classification for this test. Clear the
	# legacy King override so two QA controls cannot fight over the same fish.
	if next_mode != DebugSettingsScript.SpecimenMode.DEFAULT:
		_settings.set_king_mode(DebugSettingsScript.KingMode.DEFAULT)

	_mark_custom_profile()


func _change_shadow_count(step: int) -> void:
	if _settings == null:
		return

	var current: int = int(_settings.get_shadow_count_override())
	var next_count: int = int(posmod(
		current + step,
		MAX_DEBUG_SHADOW_COUNT + 1
	))
	_settings.set_shadow_count_override(next_count)
	_mark_custom_profile()
	debug_environment_changed.emit()


func _change_king(step: int) -> void:
	var next_mode: int = posmod(_settings.get_king_mode() + step, 3)
	_settings.set_king_mode(next_mode)
	if next_mode != DebugSettingsScript.KingMode.DEFAULT:
		_settings.set_specimen_mode(DebugSettingsScript.SpecimenMode.DEFAULT)
	_mark_custom_profile()


func _change_lure(step: int) -> void:
	if _loadout == null or _loadout.lure_catalog == null:
		return

	var count: int = _loadout.get_lure_count()
	if count <= 0:
		return

	var current_index: int = _loadout.get_selected_lure_index()
	if current_index < 0:
		current_index = 0

	_loadout.select_lure_index(current_index + step)
	_mark_custom_profile()


func _change_rod(step: int) -> void:
	if _loadout == null or CONTENT_CATALOG.tackle.rods.is_empty():
		return

	var current_index := CONTENT_CATALOG.tackle.rods.find(_loadout.get_selected_rod())
	if current_index < 0:
		current_index = 0

	var next_index := posmod(current_index + step, CONTENT_CATALOG.tackle.rods.size())
	_loadout.equip_rod(CONTENT_CATALOG.tackle.rods[next_index])
	_mark_custom_profile()


func _change_tech(step: int) -> void:
	if _settings == null:
		return

	var next_level := posmod(_settings.get_forced_tech_level() + step, 5)
	_settings.set_forced_tech_level(next_level)
	_mark_custom_profile()


func _change_save_debug() -> void:
	if _settings == null:
		return

	_settings.set_record_debug_catches(not _settings.should_record_debug_catches())
	_mark_custom_profile()


func _mark_custom_profile() -> void:
	_profile_index = 0


func _sync_from_runtime() -> void:
	_sync_fish_index()
	_sync_spot_from_runtime()


func _sync_fish_index() -> void:
	_fish_index = 0
	if _settings == null:
		return

	var forced_fish = _settings.get_forced_fish()
	if forced_fish == null:
		return

	var found_index := CONTENT_CATALOG.fish.find(forced_fish)
	if found_index >= 0:
		_fish_index = found_index + 1


func _sync_spot_from_runtime() -> void:
	_spot_index = -1
	if _fish_zone == null:
		return

	var current_spot: FishingSpotData = null
	if _fish_zone.has_method("get_fishing_spot"):
		current_spot = _fish_zone.get_fishing_spot() as FishingSpotData
	else:
		current_spot = _fish_zone.get("fishing_spot") as FishingSpotData

	if current_spot != null:
		_spot_index = CONTENT_CATALOG.spots.find(current_spot)


func _refresh() -> void:
	if _playtest_page:
		_refresh_playtest()
		return
	_update_telemetry_button()
	if _loadout == null or _settings == null:
		return

	var profile_text := "CUSTOM / CURRENT"
	var profile_purpose := "Manual debug configuration."
	if _profile_index > 0:
		var profile: FishingQAProfile = _profile_database[_profile_index - 1]
		profile_text = profile.profile_name
		profile_purpose = profile.purpose

	var spot_text := "CURRENT ZONE"
	if _spot_index >= 0 and _spot_index < CONTENT_CATALOG.spots.size():
		spot_text = CONTENT_CATALOG.spots[_spot_index].spot_name
	elif _fish_zone != null:
		var runtime_spot = _fish_zone.get("fishing_spot")
		if runtime_spot is FishingSpotData:
			spot_text = runtime_spot.spot_name

	var fish_text := "ANY / SPOT RNG"
	if _fish_index > 0:
		var fish: FishData = CONTENT_CATALOG.fish[_fish_index - 1]
		fish_text = fish.fish_name

	var lure_text := "NONE"
	var selected_lure = _loadout.get_selected_lure()
	if selected_lure != null:
		lure_text = selected_lure.display_name

		var selected_action: LureActionProfile = (
			selected_lure.get_action_profile()
		)

		if selected_action != null:
			lure_text += " [" + selected_action.get_style_label() + "]"

	var rod_text := "NONE"
	var selected_rod = _loadout.get_selected_rod()
	if selected_rod != null:
		rod_text = selected_rod.rod_name

	var selected_specimen_fish: FishData = null
	if _fish_index > 0:
		selected_specimen_fish = CONTENT_CATALOG.fish[_fish_index - 1]

	profile_label.text = _row_text(Row.PROFILE, "PROFILE", profile_text)
	spot_label.text = _row_text(Row.SPOT, "SPOT", spot_text)
	fish_label.text = _row_text(Row.FISH, "FISH", fish_text)
	specimen_label.text = _row_text(
		Row.SPECIMEN,
		"SPECIMEN",
		_settings.get_specimen_mode_label(selected_specimen_fish)
	)
	shadow_count_label.text = _row_text(
		Row.SHADOWS,
		"SHADOWS",
		_settings.get_shadow_count_label()
	)
	king_label.text = _row_text(Row.KING, "KING", _settings.get_king_mode_label())
	lure_label.text = _row_text(Row.LURE, "LURE", lure_text)
	rod_label.text = _row_text(Row.ROD, "ROD", rod_text)
	tech_label.text = _row_text(Row.TECH, "TECH", _settings.get_forced_tech_label())
	save_debug_label.text = _row_text(Row.SAVE_DEBUG, "SAVE DBG", _settings.get_record_debug_label())

	var progress_text := "Progress: not connected"
	if _progress != null:
		var fishing_points := _progress.get_fishing_points()
		var rank_name := _progress.get_rank_name()
		var next_rank_points := _progress.get_next_rank_threshold()
		progress_text = "Rank: %s   Progress: %d / %d pts   Catches: %d" % [
			rank_name,
			fishing_points,
			next_rank_points,
			_progress.get_total_catches(),
		]

		if _fish_index > 0:
			var selected_fish: FishData = CONTENT_CATALOG.fish[_fish_index - 1]
			var record := _progress.get_species_record(selected_fish)
			if not record.is_empty():
				progress_text += "\n%s record: %d cm / %d pts / %d caught / King: %s" % [
					selected_fish.fish_name,
					roundi(float(record.get("best_size", 0.0))),
					int(record.get("best_points", 0)),
					int(record.get("caught_count", 0)),
					("YES" if bool(record.get("king_caught", false)) else "NO"),
				]

	var shadow_text := "SPOT POPULATION"
	var shadow_override: FishData = _settings.get_shadow_fish_override()
	if shadow_override != null:
		shadow_text = shadow_override.fish_name

	var shadow_population_text := "runtime unavailable"
	if (
		_fish_zone != null
		and _fish_zone.has_method("get_shadow_population_debug_counts")
	):
		var counts: Vector2i = _fish_zone.get_shadow_population_debug_counts()
		shadow_population_text = "%d alive / %d readable" % [counts.x, counts.y]

	var lure_backend_text := _get_lure_backend_debug_text(
		selected_lure
	)
	var lure_runtime_text := _get_lure_runtime_debug_text()
	var rod_backend_text := _get_rod_backend_debug_text(
		selected_rod
	)

	var selected_fish_data: FishData = null
	if _fish_index > 0:
		selected_fish_data = CONTENT_CATALOG.fish[_fish_index - 1]

	var fish_backend_text := _get_fish_backend_debug_text(selected_fish_data)
	var fish_runtime_text := _get_fish_runtime_debug_text()
	var spot_backend_text := _get_spot_backend_debug_text()
	var tech_backend_text := _get_tech_backend_debug_text()
	var tech_runtime_text := _get_tech_runtime_debug_text()
	var spatial_runtime_text := _get_spatial_runtime_debug_text()
	var tension_runtime_text := _get_tension_runtime_debug_text()

	status_label.text = (
		profile_purpose
		+ "\nShadow QA: " + shadow_text
		+ " | " + shadow_population_text
		+ "\n"
		+ progress_text
		+ "\nLure DB: " + lure_backend_text
		+ "\nLure RT: " + lure_runtime_text
		+ "\nRod DB: " + rod_backend_text
		+ "\nFish DB: " + fish_backend_text
		+ "\nFish RT: " + fish_runtime_text
		+ "\nSpot DB: " + spot_backend_text
		+ "\nTech DB: " + tech_backend_text
		+ "\nTech RT: " + tech_runtime_text
		+ "\nSpatial: " + spatial_runtime_text
		+ "\nTension: " + tension_runtime_text
		+ "\nECON: " + _last_economy_summary
		+ " | F7 run 0-12h simulator"
		+ "\nQA: " + _last_regression_summary
		+ " | F9 run regression"
		+ "\nSPECIMEN forcing uses real catch pipeline; SAVE DBG ON persists it"
		+ "\nShift+R RESET fishing progress"
		+ "\nF10/K/I close   W/S row   A/D change"
	)


func _run_economy_progression_simulator() -> void:
	if _economy_simulator == null:
		_last_economy_summary = "SIMULATOR NOT AVAILABLE"
		_refresh()
		return

	var report: Dictionary = _economy_simulator.run_default_suite(true)
	_last_economy_summary = str(report.get("summary", "NO RESULT"))
	_refresh()


func _run_regression_suite() -> void:
	if _regression_harness == null:
		_last_regression_summary = "HARNESS NOT CONNECTED"
		_refresh()
		return

	var report: Dictionary = _regression_harness.run_all()
	_last_regression_summary = str(
		report.get(
			"summary",
			"NO RESULT"
		)
	)
	_refresh()


func _is_key_press(
	event: InputEvent,
	key: Key
) -> bool:
	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false

	return (
		key_event.keycode == key
		or key_event.physical_keycode == key
	)


func _get_lure_backend_debug_text(
	lure: BaitData
) -> String:
	if lure == null:
		return "NONE"

	return "%s | %s | sink %.2f @ %.2f | reel %.3f rise %.2f steer %.2f" % [
		lure.get_type_label(),
		lure.get_action_debug_summary(),
		lure.sink_depth,
		lure.sink_speed,
		lure.reel_speed,
		lure.reel_rise_speed,
		lure.reel_steer_strength,
	]


func _get_rod_backend_debug_text(
	rod: RodData
) -> String:
	if rod == null:
		return "NONE"

	return rod.get_debug_summary()


func _get_fish_backend_debug_text(fish: FishData) -> String:
	if fish == null:
		return "ANY / SPOT RNG"

	var average_score: Dictionary = CatchScoring.evaluate(
		fish,
		fish.average_size
	)

	return (
		"%s | avg %.0f crown %.0fcm | max %d | avg tier %d/%d=%dpts | "
		+ "stam %.1f str %.2f rounds %d | depth %.2f-%.2f | %s"
	) % [
		fish.fish_name,
		fish.average_size,
		fish.king_size,
		fish.max_points,
		int(average_score.get("score_tier", 0)),
		int(average_score.get("score_tier_count", 10)),
		int(average_score.get("points", 0)),
		fish.base_stamina,
		fish.base_strength,
		fish.resistance_rounds,
		fish.preferred_depth_min,
		fish.preferred_depth_max,
		fish.get_behavior_debug_summary(),
	]


func _get_fish_runtime_debug_text() -> String:
	if _encounter == null:
		return "NO ENCOUNTER"
	if not _encounter.has_method("get_fish_debug_snapshot"):
		return "NO SNAPSHOT"

	var snapshot: Dictionary = _encounter.get_fish_debug_snapshot()
	var species_name: String = str(snapshot.get("species", "NONE"))

	if species_name == "NONE":
		var pending_name: String = str(snapshot.get("pending_fish", "NONE"))
		if pending_name != "NONE":
			return "PENDING %s | bite %s" % [
				pending_name,
				("OPEN" if bool(snapshot.get("bite_active", false)) else "WAIT"),
			]
		return "NO ACTIVE FISH"

	var behavior_state: String = "NONE"
	var behavior_value: Variant = snapshot.get("behavior", {})
	if behavior_value is Dictionary:
		var behavior_snapshot: Dictionary = behavior_value
		behavior_state = str(behavior_snapshot.get("state", "NONE"))

	return (
		"%s %s%s | %.0fcm | %d/%dpts tier %d/10 | "
		+ "stam %.1f/%.1f | str %.2f | %s/%s | rounds %d | "
		+ "pressure %.2f lat %.2f"
	) % [
		species_name,
		("KING " if bool(snapshot.get("is_king", false)) else ""),
		str(snapshot.get("profile", "NONE")),
		float(snapshot.get("size", 0.0)),
		int(snapshot.get("points", 0)),
		int(snapshot.get("max_points", 0)),
		int(snapshot.get("score_tier", 0)),
		float(snapshot.get("stamina", 0.0)),
		float(snapshot.get("max_stamina", 0.0)),
		float(snapshot.get("strength", 0.0)),
		str(snapshot.get("fight_state", "NONE")),
		behavior_state,
		int(snapshot.get("rounds_remaining", 0)),
		float(snapshot.get("pressure", 0.0)),
		float(snapshot.get("lateral", 0.0)),
	]


func _get_tension_runtime_debug_text() -> String:
	if _encounter == null:
		return "NO ENCOUNTER"

	if not _encounter.has_method(
		"get_tension_debug_snapshot"
	):
		return "NO SNAPSHOT"

	var snapshot: Dictionary = (
		_encounter.get_tension_debug_snapshot()
	)

	if snapshot.is_empty():
		return "NONE"

	return (
		"%.2f %s | target %.2f fish %.2f | "
		+ "snap %.0f%% %.2fs x%.2f | escape %.0f%%"
	) % [
		float(snapshot.get("value", 0.0)),
		str(snapshot.get("state_label", "SAFE")),
		float(snapshot.get("target", 0.0)),
		float(snapshot.get("fish_resistance", 0.0)),
		float(snapshot.get("break_progress", 0.0)) * 100.0,
		float(
			snapshot.get(
				"effective_line_break_delay",
				0.0
			)
		),
		float(
			snapshot.get(
				"line_tolerance_multiplier",
				1.0
			)
		),
		float(snapshot.get("escape_progress", 0.0)) * 100.0,
	]


func _get_spatial_runtime_debug_text() -> String:
	if _encounter == null:
		return "NO ENCOUNTER"

	if not _encounter.has_method(
		"get_spatial_debug_snapshot"
	):
		return "NO SNAPSHOT"

	var snapshot: Dictionary = (
		_encounter.get_spatial_debug_snapshot()
	)

	if snapshot.is_empty():
		return "NO ACTIVE BAIT SAMPLE"

	var uv: Vector2 = snapshot.get(
		"uv",
		Vector2(0.5, 0.5)
	)
	var hotspots_value: Variant = snapshot.get(
		"active_hotspots",
		PackedStringArray()
	)
	var hotspots_text: String = "-"

	if hotspots_value is PackedStringArray:
		var hotspot_names: PackedStringArray = hotspots_value
		if not hotspot_names.is_empty():
			hotspots_text = ",".join(hotspot_names)

	return "uv %.2f,%.2f | depth %.2f | density x%.2f | %s" % [
		uv.x,
		uv.y,
		float(snapshot.get("depth_ratio", 0.0)),
		float(
			snapshot.get(
				"bite_density_multiplier",
				1.0
			)
		),
		hotspots_text,
	]


func _get_tech_backend_debug_text() -> String:
	if TECHNIQUE_CATALOG == null:
		return "NONE"

	var definitions: Array[FishingTechniqueDefinition] = (
		TECHNIQUE_CATALOG.get_techniques_descending()
	)
	definitions.reverse()

	var parts := PackedStringArray()

	for definition in definitions:
		parts.append(
			"T%d %s x%.2f" % [
				definition.level,
				definition.get_rhythm_label(),
				definition.attraction_multiplier,
			]
		)

	return " | ".join(parts)


func _get_tech_runtime_debug_text() -> String:
	if _encounter == null:
		return "NO ENCOUNTER"

	if not _encounter.has_method(
		"get_technique_debug_snapshot"
	):
		return "NO SNAPSHOT"

	var snapshot: Dictionary = (
		_encounter.get_technique_debug_snapshot()
	)

	var effective_level: int = int(
		snapshot.get(
			"effective_level",
			0
		)
	)

	if effective_level <= 0:
		return "NONE"

	return "T%d %s | x%.2f | %.2fs%s%s" % [
		effective_level,
		str(snapshot.get("rhythm", "")),
		float(
			snapshot.get(
				"attraction_multiplier",
				1.0
			)
		),
		float(snapshot.get("time_left", 0.0)),
		(
			" | BROAD"
			if bool(
				snapshot.get(
					"broad_attraction",
					false
				)
			)
			else ""
		),
		(
			" | FORCED"
			if bool(snapshot.get("forced", false))
			else ""
		),
	]


func _get_spot_backend_debug_text() -> String:
	if _fish_zone == null:
		return "NO FISH ZONE"

	if not _fish_zone.has_method("get_spot_debug_snapshot"):
		return "NO SNAPSHOT"

	var snapshot: Dictionary = (
		_fish_zone.get_spot_debug_snapshot()
	)
	var species_value: Variant = snapshot.get(
		"species",
		PackedStringArray()
	)
	var species_count: int = 0

	if species_value is PackedStringArray:
		species_count = species_value.size()

	return "%s | depth %.2fm | %d species runtime" % [
		str(snapshot.get("summary", "NO SPOT")),
		float(snapshot.get("water_depth_m", 0.0)),
		species_count,
	]


func _get_lure_runtime_debug_text() -> String:
	# F10 refreshes only on explicit debug/menu changes, so this one SceneTree
	# lookup is observability work, not a gameplay hot loop.
	var bait := get_tree().get_first_node_in_group("bait")

	if bait == null:
		return "NO ACTIVE BAIT"

	if not bait.has_method("get_lure_debug_snapshot"):
		return "ACTIVE BAIT / NO SNAPSHOT"

	var snapshot: Dictionary = bait.get_lure_debug_snapshot()
	var depth_m: float = float(
		snapshot.get("depth_m", 0.0)
	)
	var total_depth_m: float = float(
		snapshot.get("total_depth_m", 0.0)
	)

	return (
		"%s | %s | depth %.2f/%.2f | action %s"
		+ " | steer %.2f->%.2f | S %.3f"
	) % [
		str(snapshot.get("state", "?")),
		("REEL" if bool(snapshot.get("reeling", false)) else "IDLE"),
		depth_m,
		total_depth_m,
		str(snapshot.get("action_mode", "NONE")),
		float(snapshot.get("steering", 0.0)),
		float(snapshot.get("steering_target", 0.0)),
		float(snapshot.get("manual_pull_remaining", 0.0)),
	]


func _on_progress_changed() -> void:
	_refresh()


func _row_text(row: int, label: String, value: String) -> String:
	var cursor := "  "
	if _selected_row == row:
		cursor = "> "

	return "%s%-8s < %s >" % [cursor, label, value]
