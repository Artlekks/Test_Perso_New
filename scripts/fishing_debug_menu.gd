extends CanvasLayer

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

enum Row {
	FISH,
	KING,
	LURE,
	ROD,
	TECH
}

@onready var root: Control = $Root
@onready var fish_label: Label = $Root/Panel/FishLabel
@onready var king_label: Label = $Root/Panel/KingLabel
@onready var lure_label: Label = $Root/Panel/LureLabel
@onready var rod_label: Label = $Root/Panel/RodLabel
@onready var tech_label: Label = $Root/Panel/TechLabel
@onready var status_label: Label = $Root/Panel/StatusLabel

var _loadout = null
var _settings = null
var _selected_row: int = Row.FISH
var _fish_index: int = 0


func _ready() -> void:
	root.hide()


func configure(loadout, settings) -> void:
	_loadout = loadout
	_settings = settings
	_sync_from_runtime()
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

	if (
		event.is_action_pressed("ui_up")
		or event.is_action_pressed("move_forward")
	):
		_selected_row = posmod(_selected_row - 1, 5)
		_refresh()
		return false

	if (
		event.is_action_pressed("ui_down")
		or event.is_action_pressed("move_back")
	):
		_selected_row = posmod(_selected_row + 1, 5)
		_refresh()
		return false

	if (
		event.is_action_pressed("ui_left")
		or event.is_action_pressed("ds_left")
	):
		_change_value(-1)
		return false

	if (
		event.is_action_pressed("ui_right")
		or event.is_action_pressed("ds_right")
	):
		_change_value(1)
		return false

	if (
		event.is_action_pressed("enter_fishing")
		or event.is_action_pressed("cancel_fishing")
	):
		return true

	return false


func _change_value(step: int) -> void:
	match _selected_row:
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

	_refresh()


func _change_fish(step: int) -> void:
	# Index 0 means normal spot RNG. Fish begin at index 1.
	_fish_index = posmod(
		_fish_index + step,
		FISH_DATABASE.size() + 1
	)

	if _fish_index == 0:
		_settings.set_forced_fish(null)
		return

	_settings.set_forced_fish(
		FISH_DATABASE[_fish_index - 1]
	)


func _change_king(step: int) -> void:
	var next_mode: int = posmod(
		_settings.get_king_mode() + step,
		3
	)

	_settings.set_king_mode(next_mode)


func _change_lure(step: int) -> void:
	if _loadout == null or _loadout.lure_catalog == null:
		return

	var count: int = _loadout.get_lure_count()

	if count <= 0:
		return

	var current_index: int = _loadout.get_selected_lure_index()

	if current_index < 0:
		current_index = 0

	_loadout.select_lure_index(
		current_index + step
	)


func _change_rod(step: int) -> void:
	if _loadout == null or ROD_DATABASE.is_empty():
		return

	var current_index := ROD_DATABASE.find(
		_loadout.get_selected_rod()
	)

	if current_index < 0:
		current_index = 0

	var next_index := posmod(
		current_index + step,
		ROD_DATABASE.size()
	)

	_loadout.equip_rod(
		ROD_DATABASE[next_index]
	)


func _change_tech(step: int) -> void:
	if _settings == null:
		return

	var next_level := posmod(
		_settings.get_forced_tech_level() + step,
		5
	)

	_settings.set_forced_tech_level(next_level)


func _sync_from_runtime() -> void:
	_fish_index = 0

	if _settings != null:
		var forced_fish = _settings.get_forced_fish()

		if forced_fish != null:
			var found_index := FISH_DATABASE.find(forced_fish)

			if found_index >= 0:
				_fish_index = found_index + 1


func _refresh() -> void:
	if _loadout == null or _settings == null:
		return

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

	fish_label.text = _row_text(
		Row.FISH,
		"FISH",
		fish_text
	)

	king_label.text = _row_text(
		Row.KING,
		"KING",
		_settings.get_king_mode_label()
	)

	lure_label.text = _row_text(
		Row.LURE,
		"LURE",
		lure_text
	)

	rod_label.text = _row_text(
		Row.ROD,
		"ROD",
		rod_text
	)

	tech_label.text = _row_text(
		Row.TECH,
		"TECH",
		_settings.get_forced_tech_label()
	)

	status_label.text = (
		"F10 close   W/S or arrows: row   A/D or arrows: change\n"
		+ "K/I close   Overrides are runtime-only; database files are untouched."
	)


func _row_text(
	row: int,
	label: String,
	value: String
) -> String:
	var cursor := "  "

	if _selected_row == row:
		cursor = "> "

	return "%s%-7s  < %s >" % [
		cursor,
		label,
		value
	]
