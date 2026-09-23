extends CanvasLayer

signal spot_requested(spot: FishingSpotData)
signal debug_environment_changed

const FISH_DATABASE = [
	preload("res://data/bof4/fish/acheron.tres"),
	preload("res://data/bof4/fish/angelfish.tres"),
	preload("res://data/bof4/fish/angler.tres"),
	preload("res://data/bof4/fish/barandy.tres"),
	preload("res://data/bof4/fish/bass.tres"),
	preload("res://data/bof4/fish/black_bass.tres"),
	preload("res://data/bof4/fish/black_porgy.tres"),
	preload("res://data/bof4/fish/blowfish.tres"),
	preload("res://data/bof4/fish/blue_gill.tres"),
	preload("res://data/bof4/fish/bonito.tres"),
	preload("res://data/bof4/fish/browntail.tres"),
	preload("res://data/bof4/fish/bullcat.tres"),
	preload("res://data/bof4/fish/dorado.tres"),
	preload("res://data/bof4/fish/flatfish.tres"),
	preload("res://data/bof4/fish/flying_fish.tres"),
	preload("res://data/bof4/fish/jellyfish.tres"),
	preload("res://data/bof4/fish/man_o_war.tres"),
	preload("res://data/bof4/fish/martian_squid.tres"),
	preload("res://data/bof4/fish/moorfish.tres"),
	preload("res://data/bof4/fish/octopus.tres"),
	preload("res://data/bof4/fish/piranha.tres"),
	preload("res://data/bof4/fish/rainbow_trout.tres"),
	preload("res://data/bof4/fish/salmon.tres"),
	preload("res://data/bof4/fish/sea_bass.tres"),
	preload("res://data/bof4/fish/sea_bream.tres"),
	preload("res://data/bof4/fish/spearfish.tres"),
	preload("res://data/bof4/fish/sturgeon.tres"),
	preload("res://data/bof4/fish/sweetfish.tres"),
	preload("res://data/bof4/fish/trout.tres"),
	preload("res://data/bof4/fish/whale.tres"),
]

const ROD_DATABASE = [
	preload("res://data/bof4/rods/wooden_rod.tres"),
	preload("res://data/bof4/rods/bamboo_rod.tres"),
	preload("res://data/bof4/rods/deluxe_rod.tres"),
	preload("res://data/bof4/rods/spanner.tres"),
	preload("res://data/bof4/rods/angling_rod.tres"),
	preload("res://data/bof4/rods/masters_rod.tres"),
]

const SPOT_DATABASE = [
	preload("res://data/bof4/spots/river_1.tres"),
	preload("res://data/bof4/spots/river_2.tres"),
	preload("res://data/bof4/spots/river_3.tres"),
	preload("res://data/bof4/spots/lake_1.tres"),
	preload("res://data/bof4/spots/lake_2.tres"),
	preload("res://data/bof4/spots/lake_3.tres"),
	preload("res://data/bof4/spots/ocean_1.tres"),
	preload("res://data/bof4/spots/ocean_2.tres"),
	preload("res://data/bof4/spots/ocean_3.tres"),
	preload("res://data/bof4/spots/chamba.tres"),
	preload("res://data/bof4/spots/saldine.tres"),
]

const QA_PROFILE_DIRECTORY := "res://data/debug/qa_profiles"


enum Row {
	PROFILE,
	SPOT,
	FISH,
	KING,
	LURE,
	ROD,
	TECH,
	SAVE_DEBUG,
}

const ROW_COUNT := 8

@onready var root: Control = $Root
@onready var profile_label: Label = $Root/Panel/ProfileLabel
@onready var spot_label: Label = $Root/Panel/SpotLabel
@onready var fish_label: Label = $Root/Panel/FishLabel
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
var _selected_row: int = Row.PROFILE
var _profile_index: int = 0
var _profile_database: Array[FishingQAProfile] = []
var _spot_index: int = -1
var _fish_index: int = 0


func _ready() -> void:
	root.hide()


func configure(
	loadout,
	settings,
	progress: FishingProgress = null
) -> void:
	_loadout = loadout
	_settings = settings
	_progress = progress
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
	if _loadout == null or _settings == null:
		return false

	_sync_from_runtime()
	_refresh()
	root.show()
	return true


func close_menu() -> void:
	root.hide()


func is_open() -> bool:
	return root.visible


## Returns true when the menu requests to close.
func handle_input(event: InputEvent) -> bool:
	if not is_open():
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
	_settings.set_shadow_fish_override(profile.shadow_fish_override)
	_settings.set_king_mode(profile.king_mode)
	_settings.set_forced_tech_level(profile.forced_tech_level)
	_settings.set_record_debug_catches(profile.record_debug_catches)

	if _loadout != null:
		if profile.lure != null:
			_loadout.equip_lure(profile.lure)
		if profile.rod != null:
			_loadout.equip_rod(profile.rod)

	if profile.fishing_spot != null:
		_spot_index = SPOT_DATABASE.find(profile.fishing_spot)
		spot_requested.emit(profile.fishing_spot)

	_sync_fish_index()
	debug_environment_changed.emit()


func _change_spot(step: int) -> void:
	if SPOT_DATABASE.is_empty():
		return

	if _spot_index < 0:
		_spot_index = 0
	else:
		_spot_index = posmod(_spot_index + step, SPOT_DATABASE.size())

	_mark_custom_profile()
	spot_requested.emit(SPOT_DATABASE[_spot_index])
	debug_environment_changed.emit()


func _change_fish(step: int) -> void:
	# Index 0 means normal encounter RNG and normal shadow population.
	_fish_index = posmod(_fish_index + step, FISH_DATABASE.size() + 1)

	var fish: FishData = null
	if _fish_index > 0:
		fish = FISH_DATABASE[_fish_index - 1]

	_settings.set_forced_fish(fish)
	# Manual FISH selection intentionally mirrors into ambient/pre-bite shadows.
	_settings.set_shadow_fish_override(fish)
	_mark_custom_profile()
	debug_environment_changed.emit()


func _change_king(step: int) -> void:
	var next_mode: int = posmod(_settings.get_king_mode() + step, 3)
	_settings.set_king_mode(next_mode)
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
	if _loadout == null or ROD_DATABASE.is_empty():
		return

	var current_index := ROD_DATABASE.find(_loadout.get_selected_rod())
	if current_index < 0:
		current_index = 0

	var next_index := posmod(current_index + step, ROD_DATABASE.size())
	_loadout.equip_rod(ROD_DATABASE[next_index])
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

	var found_index := FISH_DATABASE.find(forced_fish)
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
		_spot_index = SPOT_DATABASE.find(current_spot)


func _refresh() -> void:
	if _loadout == null or _settings == null:
		return

	var profile_text := "CUSTOM / CURRENT"
	var profile_purpose := "Manual debug configuration."
	if _profile_index > 0:
		var profile: FishingQAProfile = _profile_database[_profile_index - 1]
		profile_text = profile.profile_name
		profile_purpose = profile.purpose

	var spot_text := "CURRENT ZONE"
	if _spot_index >= 0 and _spot_index < SPOT_DATABASE.size():
		spot_text = SPOT_DATABASE[_spot_index].spot_name
	elif _fish_zone != null:
		var runtime_spot = _fish_zone.get("fishing_spot")
		if runtime_spot is FishingSpotData:
			spot_text = runtime_spot.spot_name

	var fish_text := "ANY / SPOT RNG"
	if _fish_index > 0:
		var fish: FishData = FISH_DATABASE[_fish_index - 1]
		fish_text = fish.fish_name

	var lure_text := "NONE"
	var selected_lure = _loadout.get_selected_lure()
	if selected_lure != null:
		lure_text = selected_lure.display_name

	var rod_text := "NONE"
	var selected_rod = _loadout.get_selected_rod()
	if selected_rod != null:
		rod_text = selected_rod.rod_name

	profile_label.text = _row_text(Row.PROFILE, "PROFILE", profile_text)
	spot_label.text = _row_text(Row.SPOT, "SPOT", spot_text)
	fish_label.text = _row_text(Row.FISH, "FISH", fish_text)
	king_label.text = _row_text(Row.KING, "KING", _settings.get_king_mode_label())
	lure_label.text = _row_text(Row.LURE, "LURE", lure_text)
	rod_label.text = _row_text(Row.ROD, "ROD", rod_text)
	tech_label.text = _row_text(Row.TECH, "TECH", _settings.get_forced_tech_label())
	save_debug_label.text = _row_text(Row.SAVE_DEBUG, "SAVE DBG", _settings.get_record_debug_label())

	var progress_text := "Progress: not connected"
	if _progress != null:
		progress_text = "Progress: %d / 9999 pts   Catches: %d" % [
			_progress.get_fishing_points(),
			_progress.get_total_catches(),
		]

		if _fish_index > 0:
			var selected_fish: FishData = FISH_DATABASE[_fish_index - 1]
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

	status_label.text = (
		profile_purpose
		+ "\nShadow QA: " + shadow_text
		+ "\n"
		+ progress_text
		+ "\nF10/K/I close   W/S row   A/D change"
	)


func _on_progress_changed() -> void:
	_refresh()


func _row_text(row: int, label: String, value: String) -> String:
	var cursor := "  "
	if _selected_row == row:
		cursor = "> "

	return "%s%-8s < %s >" % [cursor, label, value]
