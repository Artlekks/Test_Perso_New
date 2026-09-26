extends CanvasLayer
class_name FishingMenu

const EQUIP_LEFT_SELECTOR_FILLED: Texture2D = preload("res://assets/ui/fishing_menu/Menu_Equip_Selector_Left_Filled.png")
const EQUIP_LEFT_SELECTOR_OUTLINE: Texture2D = preload("res://assets/ui/fishing_menu/Menu_Equip_Selector_Left.png")

# BOF4 Guide-panel lure icons.
# Explicit lure-by-lure mapping keeps the menu deterministic and avoids
# depending on a generic lure_type classification for presentation.
const LURE_GUIDE_ICONS: Dictionary = {
	&"straight": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Worm.png"),
	&"tail": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Worm.png"),
	&"crab": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Worm.png"),

	&"baby_frog": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Frogger.png"),
	&"toad": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Frogger.png"),
	&"fat_frog": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Frogger.png"),
	&"king_frog": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Frogger.png"),

	&"popper": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Topper.png"),
	&"flattop": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Topper.png"),
	&"swisher": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Topper.png"),

	&"floater": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Minnow.png"),
	&"hanger": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Minnow.png"),
	&"deep_diver": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Minnow.png"),

	&"twister": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Winder.png"),
	&"warbler": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Winder.png"),
	&"dancer": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Winder.png"),

	&"silver_top": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Spinner.png"),
	&"gold_top": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Spinner.png"),
	&"platinum_top": preload("res://assets/ui/fishing_menu/lure_icons/Icon_Spinner.png"),
}


const ROD_GUIDE_TITLES: Dictionary = {
	&"wooden_rod": "For beginners",
	&"deluxe_rod": "Fancy rod",
	&"bamboo_rod": "Bamboo rod",
	&"spanner": "Super Rod",
	&"angling_rod": "Good range",
	&"masters_rod": "Ultimate Rod",
}

const LURE_GUIDE_TYPE_LABELS: Dictionary = {
	LureType.Type.WORM: "Worm",
	LureType.Type.FROG: "Frogger",
	LureType.Type.TOPPER: "Topper",
	LureType.Type.MINNOW: "Minnow",
	LureType.Type.WINDER: "Winder",
	LureType.Type.SPINNER: "Spinner",
}


signal opened
signal closed
signal page_changed(page_name: StringName)
signal exit_requested

enum Page {
	MAIN,
	EQUIP,
	DATA,
	HELP,
	HINTS,
	OPTIONS,
}

enum EquipFocus {
	SLOT,
	ACCESSORY,
}

const COMMANDS: PackedStringArray = [
	"Equip",
	"Data",
	"Help",
	"Hints",
	"Option",
	"Exit",
]

const MAIN_INFO_TEXT: PackedStringArray = [
	"Equip Rod and Lure.",
	"View Fish Data.",
	"Learn how to fish.",
	"Hints to help you fish better.",
	"Change Game Options.",
	"Stop Fishing.",
]

const HELP_TOPICS: PackedStringArray = [
	"Casting",
	"Moving the lure",
	"Getting a bite",
	"Reeling in a catch",
	"Exit",
]

const HINT_TOPICS: PackedStringArray = [
	"The Controller",
	"Rods and Lures",
	"Types of Lures",
	"Terrain and Range",
	"Hooking",
	"Uses of Fish",
	"Lure Actions",
]

# BOF4 Data-menu species order. Only discovered species are shown, but they
# always retain this canonical ordering as the journal grows.
const DATA_SPECIES_ORDER: PackedStringArray = [
	"Jellyfish",
	"Piranha",
	"Bass",
	"Bluegill",
	"Sweetfish",
	"Browntail",
	"Black Bass",
	"Angelfish",
	"Trout",
	"Rainbow Trout",
	"Bull Cat",
	"Martian Squid",
	"Dorado",
	"Salmon",
	"Barundi",
	"Sturgeon",
	"Man-o'-War",
	"Flying Fish",
	"Blowfish",
	"Moonfish",
	"Sea Bass",
	"Flatfish",
	"Sea Bream",
	"Bream",
	"Octopus",
	"Bonito",
	"Black Porgy",
	"Angler",
	"Spearfish",
	"Whale",
	"Acheron",
]

# Canonical Data preview source: the menu resolves the selected name back to
# FishData, whose portrait is the authoritative Atlas_Fishes.png region.
const DATA_FISH_BY_KEY: Dictionary = {
	"jellyfish": preload("res://data/bof4/fish/jellyfish.tres"),
	"piranha": preload("res://data/bof4/fish/piranha.tres"),
	"bass": preload("res://data/bof4/fish/bass.tres"),
	"bluegill": preload("res://data/bof4/fish/blue_gill.tres"),
	"sweetfish": preload("res://data/bof4/fish/sweetfish.tres"),
	"browntail": preload("res://data/bof4/fish/browntail.tres"),
	"blackbass": preload("res://data/bof4/fish/black_bass.tres"),
	"angelfish": preload("res://data/bof4/fish/angelfish.tres"),
	"trout": preload("res://data/bof4/fish/trout.tres"),
	"rainbowtrout": preload("res://data/bof4/fish/rainbow_trout.tres"),
	"bullcat": preload("res://data/bof4/fish/bullcat.tres"),
	"martiansquid": preload("res://data/bof4/fish/martian_squid.tres"),
	"dorado": preload("res://data/bof4/fish/dorado.tres"),
	"salmon": preload("res://data/bof4/fish/salmon.tres"),
	"barundi": preload("res://data/bof4/fish/barandy.tres"),
	"sturgeon": preload("res://data/bof4/fish/sturgeon.tres"),
	"manowar": preload("res://data/bof4/fish/man_o_war.tres"),
	"flyingfish": preload("res://data/bof4/fish/flying_fish.tres"),
	"blowfish": preload("res://data/bof4/fish/blowfish.tres"),
	"moonfish": preload("res://data/bof4/fish/moorfish.tres"),
	"seabass": preload("res://data/bof4/fish/sea_bass.tres"),
	"flatfish": preload("res://data/bof4/fish/flatfish.tres"),
	"seabream": preload("res://data/bof4/fish/sea_bream.tres"),
	"octopus": preload("res://data/bof4/fish/octopus.tres"),
	"bonito": preload("res://data/bof4/fish/bonito.tres"),
	"blackporgy": preload("res://data/bof4/fish/black_porgy.tres"),
	"angler": preload("res://data/bof4/fish/angler.tres"),
	"spearfish": preload("res://data/bof4/fish/spearfish.tres"),
	"whale": preload("res://data/bof4/fish/whale.tres"),
	"acheron": preload("res://data/bof4/fish/acheron.tres"),
}

@export_category("Selector Calibration LIVE (screen pixels)")
## These selectors live outside the 2x-scaled 320x240 menu root, so every
## selector PNG renders at its authored pixel size with no stretching.
@export var main_selector_screen_position: Vector2 = Vector2(42.0, 122.0)
## Live calibration: move the Equip-left selector relative to its selected row.
@export var equip_left_selector_offset: Vector2 = Vector2(-44.0, 1.0)
## Live calibration: move the Accessory selector relative to its selected row.
@export var equip_right_selector_offset: Vector2 = Vector2(-2.0, 1.0)
## Live calibration: move the Data selector relative to its selected row.
@export var data_selector_offset: Vector2 = Vector2(-39.0, 0.0)
## Live calibration: move the Hints selector relative to its selected row.
@export var hints_selector_offset: Vector2 = Vector2(-51.0, 0.0)
## Live calibration: move the Yes/No selector relative to its selected row.
@export var exit_selector_offset: Vector2 = Vector2(6.0, 6.0)
## Extra vertical correction applied only to the Yes row. No keeps the calibrated position.
@export var exit_yes_extra_y: float = -4.0

@export_category("Menu State Colors LIVE")
## Multiplier applied to the bitmap font for inactive/disabled text.
## Keep this above 1.0 because the glyph artwork itself is dark gray.
@export var disabled_text_tint: Color = Color8(0xE1, 0xE1, 0xE1, 0x74)
## Independent highlight for the accessory that is currently equipped.
## This sits behind the row text and below the pink cursor selector.
@export var equipped_accessory_highlight_color: Color = Color(0.68, 0.60, 0.22, 0.28)

@export_category("Equip QA")
## Development-only convenience. When enabled, the Equip page lists every rod
## and lure in the tackle catalog even when the save inventory does not own it.
## Unowned entries are shown as quantity 01 and may be equipped for testing,
## but the real FishingInventory is not modified.
@export var show_full_tackle_catalog_for_testing: bool = true

const BOF_STANDARD_ADVANCE_PX: int = 8
const BOF_NARROW_ADVANCE_PX: int = 4
const ACCESSORY_NAME_COLUMN_WIDTH_PX: int = 104
const ACCESSORY_HALF_SPACE: String = " "

const NAV_REPEAT_DELAY: float = 0.28
const NAV_REPEAT_INTERVAL: float = 0.085

const TRANSITION_OUT_TIME: float = 0.16
const TRANSITION_IN_TIME: float = 0.18
const MAIN_COMMAND_X: float = 16.0
const MAIN_TIME_X: float = 16.0
const MAIN_EQUIP_X: float = 98.0
const MAIN_STATUS_X: float = 98.0
const EQUIP_SLOT_X: float = 16.0
const EQUIP_GUIDE_Y: float = 104.0
const EQUIP_ACCESSORY_X: float = 167.0
const DATA_NAME_X: float = 16.0
const DATA_DETAILS_X: float = 0.0
const HINT_X: float = 63.0
const OFF_LEFT_X: float = -160.0
const OFF_RIGHT_X: float = 330.0
const OFF_BOTTOM_Y: float = 250.0

@onready var root: Control = $Root
@onready var selector_layer: Control = $SelectorLayer
@onready var info_label: Label = $Root/InfoPanel/InfoLabel

@onready var main_page: Control = $Root/MainPage
@onready var command_panel: Control = $Root/MainPage/LeftMask/CommandPanel
@onready var command_selector: TextureRect = $SelectorLayer/MainCommand
@onready var command_disabled_overlay: ColorRect = $Root/MainPage/LeftMask/CommandPanel/DisabledOverlay
@onready var command_list: ItemList = $Root/MainPage/LeftMask/CommandPanel/CommandList
@onready var main_equip_panel: Control = $Root/MainPage/EquipPanel
@onready var main_status_panel: Control = $Root/MainPage/StatusPanel
@onready var main_time_panel: Control = $Root/MainPage/LeftMask/TimePanel
@onready var main_rod_label: Label = $Root/MainPage/EquipPanel/RodLabel
@onready var main_lure_label: Label = $Root/MainPage/EquipPanel/LureLabel
@onready var rank_label: Label = $Root/MainPage/StatusPanel/RankLabel
@onready var points_label: Label = $Root/MainPage/StatusPanel/PointsLabel
@onready var time_label: Label = $Root/MainPage/LeftMask/TimePanel/TimeLabel

@onready var equip_page: Control = $Root/EquipPage
@onready var equip_slot_panel: Control = $Root/EquipPage/SlotPanel
@onready var equip_slot_selector: TextureRect = $SelectorLayer/EquipLeft
@onready var equip_guide_panel: Control = $Root/EquipPage/GuidePanel
@onready var equip_accessory_panel: Control = $Root/EquipPage/AccessoryPanel
@onready var equip_slot_list: ItemList = $Root/EquipPage/SlotPanel/SlotList
@onready var equip_rod_slot_label: Label = $Root/EquipPage/SlotPanel/RodSlotLabel
@onready var equip_lure_slot_label: Label = $Root/EquipPage/SlotPanel/LureSlotLabel
@onready var equip_accessory_list: ItemList = $Root/EquipPage/AccessoryPanel/AccessoryList
@onready var equip_equipped_highlight: ColorRect = $Root/EquipPage/AccessoryPanel/EquippedHighlight
@onready var equip_accessory_selector: TextureRect = $SelectorLayer/EquipRight
@onready var equip_accessory_count_label: Label = $Root/EquipPage/AccessoryPanel/AccessoryCountLabel
@onready var equip_scroll_thumb: TextureRect = $Root/EquipPage/AccessoryPanel/ScrollThumb
@onready var equip_guide_icon: TextureRect = $Root/EquipPage/GuidePanel/GuideIcon
@onready var equip_guide_title_label: Label = $Root/EquipPage/GuidePanel/GuideTitleLabel
@onready var equip_guide_description_label: Label = $Root/EquipPage/GuidePanel/GuideDescriptionLabel

@onready var data_page: Control = $Root/DataPage
@onready var data_species_panel: Control = $Root/DataPage/SpeciesPanel
@onready var data_details_panel: Control = $Root/DataPage/DetailsPanel
@onready var data_species_selector: TextureRect = $SelectorLayer/DataName
@onready var data_species_list: ItemList = $Root/DataPage/SpeciesPanel/SpeciesList
@onready var data_scroll_thumb: TextureRect = $Root/DataPage/SpeciesPanel/ScrollThumb
@onready var data_caught_count_label: Label = $Root/DataPage/SpeciesPanel/CaughtCountLabel
@onready var data_portrait: TextureRect = $Root/DataPage/DetailsPanel/PreviewPanel/FishPortrait
@onready var data_size_label: Label = $Root/DataPage/DetailsPanel/RecordPanel/SizeLabel
@onready var data_points_label: Label = $Root/DataPage/DetailsPanel/RecordPanel/PointsLabel
@onready var data_point_label: Label = $Root/DataPage/DetailsPanel/RecordPanel/PointLabel

@onready var help_page: Control = $Root/HelpPage
@onready var help_list: ItemList = $Root/HelpPage/TopicPanel/TopicList
@onready var help_text_label: Label = $Root/HelpPage/TextPanel/TextLabel

@onready var hints_page: Control = $Root/HintsPage
@onready var hints_topic_panel: Control = $Root/HintsPage/TopicPanel
@onready var hints_selector: TextureRect = $SelectorLayer/Hints
@onready var hints_list: ItemList = $Root/HintsPage/TopicPanel/TopicList
@onready var hints_text_label: Label = $Root/HintsPage/TextPanel/TextLabel

@onready var options_page: Control = $Root/OptionsPage
@onready var exit_confirm: Control = $Root/ExitConfirm
@onready var exit_panel: Control = $Root/ExitConfirm/Panel
@onready var exit_selector: TextureRect = $SelectorLayer/YesNo
@onready var exit_list: ItemList = $Root/ExitConfirm/Panel/ChoiceList

var _game_mode: Node = null
var _loadout: FishingLoadout = null
var _inventory: FishingInventory = null
var _journal: FishingJournalService = null
var _tackle_catalog: FishingTackleCatalog = null

var _is_open: bool = false
var _page: int = Page.MAIN
var _command_index: int = 0
var _equip_focus: int = EquipFocus.SLOT
var _equip_slot_index: int = 0
var _equip_accessory_index: int = 0
var _equip_window_start: int = 0
var _equip_entries: Array[Dictionary] = []
var _data_index: int = 0
var _data_window_start: int = 0
var _data_entries: Array[Dictionary] = []
var _help_index: int = 0
var _hint_index: int = 0
var _exit_index: int = 1
var _pause_was_active: bool = false
var _session_time_seconds: float = 0.0
var _transitioning: bool = false
var _hidden_hud_visibility: Dictionary = {}
var _nav_repeat_direction: int = 0
var _nav_repeat_timer: float = 0.0
var _exit_closing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	selector_layer.visible = false

	_fill_static_lists()
	_configure_equip_accessory_list_visuals()
	_configure_data_list_visuals()
	_configure_hint_list_visuals()
	_configure_selector_overlays()
	call_deferred("_configure_exit_list_visuals")
	_set_page(Page.MAIN)
	_reset_panel_positions()
	_sync_selector_visibility()


func configure(
	game_mode: Node,
	loadout: FishingLoadout,
	inventory: FishingInventory,
	journal: FishingJournalService,
	tackle_catalog: FishingTackleCatalog
) -> void:
	_game_mode = game_mode
	_loadout = loadout
	_inventory = inventory
	_journal = journal
	_tackle_catalog = tackle_catalog

	if is_instance_valid(_loadout):
		if not _loadout.lure_changed.is_connected(_on_loadout_changed):
			_loadout.lure_changed.connect(_on_loadout_changed)
		if not _loadout.rod_changed.is_connected(_on_loadout_changed):
			_loadout.rod_changed.connect(_on_loadout_changed)

	if is_instance_valid(_journal):
		if not _journal.changed.is_connected(_on_journal_changed):
			_journal.changed.connect(_on_journal_changed)

	_refresh_all()


func is_open() -> bool:
	return _is_open


func open_menu() -> void:
	if _is_open or not _can_open_menu():
		return

	_is_open = true
	_pause_was_active = get_tree().paused
	_hide_gameplay_hud()
	selector_layer.visible = true
	root.visible = true
	_command_index = 0
	main_equip_panel.visible = true
	_set_page(Page.MAIN)
	_reset_panel_positions()
	_refresh_all()
	get_tree().paused = true
	opened.emit()


func close_menu() -> void:
	if not _is_open:
		return

	_is_open = false
	_transitioning = false
	_exit_closing = false
	exit_confirm.visible = false
	selector_layer.visible = false
	_hide_all_selector_overlays()
	_set_command_confirm_colors(false)
	command_disabled_overlay.visible = false
	_reset_nav_repeat()
	_hide_all_selector_overlays()
	root.visible = false
	_restore_gameplay_hud()
	get_tree().paused = _pause_was_active
	closed.emit()


func _process(delta: float) -> void:
	if not _is_open:
		_session_time_seconds += delta
		_update_time_label()
		return

	_process_vertical_repeat(delta)
	_update_visible_native_selectors()


func _unhandled_input(event: InputEvent) -> void:
	if _is_menu_toggle(event):
		if _is_open:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
		return

	if not _is_open:
		return

	if _transitioning:
		get_viewport().set_input_as_handled()
		return

	# Ignore OS key-repeat echoes. Menu repeat is handled at a stable,
	# frame-rate-independent cadence in _process_vertical_repeat().
	if event is InputEventKey and (event as InputEventKey).echo:
		get_viewport().set_input_as_handled()
		return

	if _is_cancel(event):
		_handle_cancel()
		_reset_nav_repeat()
		get_viewport().set_input_as_handled()
		return

	var vertical_step: int = _vertical_step(event)
	if vertical_step != 0:
		_handle_vertical_navigation(vertical_step)
		_arm_nav_repeat(vertical_step)
		get_viewport().set_input_as_handled()
		return

	if exit_confirm.visible:
		_handle_exit_confirm_input(event)
		get_viewport().set_input_as_handled()
		return

	match _page:
		Page.MAIN:
			_handle_main_input(event)
		Page.EQUIP:
			_handle_equip_input(event)
		Page.DATA:
			_handle_data_input(event)
		Page.HELP:
			_handle_help_input(event)
		Page.HINTS:
			_handle_hints_input(event)
		Page.OPTIONS:
			_handle_options_input(event)

	get_viewport().set_input_as_handled()


func _handle_vertical_navigation(step: int) -> void:
	if step == 0 or _transitioning:
		return

	if exit_confirm.visible:
		_exit_index = clampi(_exit_index + step, 0, 1)
		exit_list.select(_exit_index)
		_update_exit_selector()
		return

	match _page:
		Page.MAIN:
			_command_index = posmod(_command_index + step, COMMANDS.size())
			command_list.select(_command_index)
			_update_command_selector()
			_update_main_info()

		Page.EQUIP:
			if _equip_focus == EquipFocus.SLOT:
				_equip_slot_index = clampi(_equip_slot_index + step, 0, 1)
				_equip_accessory_index = 0
				_equip_window_start = 0
				_refresh_equip_page()
				_update_equip_slot_selector()
			elif not _equip_entries.is_empty():
				_equip_accessory_index = clampi(
					_equip_accessory_index + step,
					0,
					_equip_entries.size() - 1
				)
				_refresh_equip_selection()

		Page.DATA:
			if not _data_entries.is_empty():
				_data_index = clampi(_data_index + step, 0, _data_entries.size() - 1)
				data_species_list.select(_data_index)
				data_species_list.ensure_current_is_visible()
				_sync_data_selector_window()
				_update_data_selector()
				_update_data_scroll_thumb()
				_update_data_details()

		Page.HELP:
			_help_index = clampi(_help_index + step, 0, HELP_TOPICS.size() - 1)
			help_list.select(_help_index)
			help_list.ensure_current_is_visible()
			_update_help_text()

		Page.HINTS:
			_hint_index = clampi(_hint_index + step, 0, HINT_TOPICS.size() - 1)
			hints_list.select(_hint_index)
			hints_list.ensure_current_is_visible()
			_update_hint_selector()
			_update_hint_text()


func _arm_nav_repeat(direction: int) -> void:
	_nav_repeat_direction = direction
	_nav_repeat_timer = NAV_REPEAT_DELAY


func _reset_nav_repeat() -> void:
	_nav_repeat_direction = 0
	_nav_repeat_timer = 0.0


func _process_vertical_repeat(delta: float) -> void:
	if _transitioning:
		_reset_nav_repeat()
		return

	var held_direction: int = 0
	var up_held: bool = (
		Input.is_action_pressed("move_forward")
		or Input.is_action_pressed("ui_up")
	)
	var down_held: bool = (
		Input.is_action_pressed("move_back")
		or Input.is_action_pressed("ui_down")
	)

	if up_held != down_held:
		held_direction = -1 if up_held else 1

	if held_direction == 0:
		_reset_nav_repeat()
		return

	if held_direction != _nav_repeat_direction:
		_nav_repeat_direction = held_direction
		_nav_repeat_timer = NAV_REPEAT_DELAY
		return

	_nav_repeat_timer -= delta
	if _nav_repeat_timer > 0.0:
		return

	_handle_vertical_navigation(held_direction)
	_nav_repeat_timer += NAV_REPEAT_INTERVAL


func _fill_static_lists() -> void:
	command_list.clear()
	for command in COMMANDS:
		command_list.add_item(command)
	command_list.select(0)

	help_list.clear()
	for topic in HELP_TOPICS:
		help_list.add_item(topic)
	help_list.select(0)

	hints_list.clear()
	for topic in HINT_TOPICS:
		hints_list.add_item(topic)
	hints_list.select(0)

	exit_list.clear()
	exit_list.add_item("Yes")
	exit_list.add_item("No")
	exit_list.select(1)
	_update_command_selector()
	_update_equip_slot_selector()
	_update_hint_selector()
	_update_exit_selector()


func _can_open_menu() -> bool:
	if _game_mode == null:
		return true
	if _game_mode.has_method("is_fishing"):
		return not bool(_game_mode.call("is_fishing"))
	return true


func _set_page(page: int) -> void:
	_page = page
	main_page.visible = page == Page.MAIN
	equip_page.visible = page == Page.EQUIP
	data_page.visible = page == Page.DATA
	help_page.visible = page == Page.HELP
	hints_page.visible = page == Page.HINTS
	options_page.visible = page == Page.OPTIONS
	exit_confirm.visible = false
	_set_command_confirm_colors(false)
	command_disabled_overlay.visible = false
	_transitioning = false

	match page:
		Page.MAIN:
			command_list.select(_command_index)
			_update_command_selector()
			_update_main_info()
		Page.EQUIP:
			info_label.text = "Equip a rod and lure."
			_refresh_equip_page()
		Page.DATA:
			_refresh_data_page()
		Page.HELP:
			info_label.text = "Learn How To Fish - Select a topic."
			_update_help_text()
		Page.HINTS:
			info_label.text = "Using the Fishing Controller"
			_update_hint_text()
		Page.OPTIONS:
			info_label.text = "Fishing options are not implemented yet."

	_sync_selector_visibility()
	page_changed.emit(_page_name(page))

func _page_name(page: int) -> StringName:
	match page:
		Page.EQUIP:
			return &"equip"
		Page.DATA:
			return &"data"
		Page.HELP:
			return &"help"
		Page.HINTS:
			return &"hints"
		Page.OPTIONS:
			return &"options"
		_:
			return &"main"


func _handle_cancel() -> void:
	if exit_confirm.visible:
		_hide_exit_confirm()
		return

	if _page == Page.MAIN:
		close_menu()
		return

	if _page == Page.EQUIP and _equip_focus == EquipFocus.ACCESSORY:
		_equip_focus = EquipFocus.SLOT
		_refresh_equip_selection()
		_sync_selector_visibility()
		return

	_transition_to_main()


func _handle_main_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step != 0:
		_command_index = posmod(_command_index + step, COMMANDS.size())
		command_list.select(_command_index)
		_update_command_selector()
		_update_main_info()
		return

	if not _is_confirm(event):
		return

	match _command_index:
		0:
			_transition_from_main(Page.EQUIP)
		1:
			_transition_from_main(Page.DATA)
		2:
			_transition_from_main(Page.HELP)
		3:
			_transition_from_main(Page.HINTS)
		4:
			_transition_from_main(Page.OPTIONS)
		5:
			_show_exit_confirm()


func _handle_equip_input(event: InputEvent) -> void:
	if _equip_focus == EquipFocus.SLOT:
		var slot_step: int = _vertical_step(event)
		if slot_step != 0:
			_equip_slot_index = clampi(_equip_slot_index + slot_step, 0, 1)
			_equip_accessory_index = 0
			_equip_window_start = 0
			_refresh_equip_page()
			_update_equip_slot_selector()
			return

		if _horizontal_step(event) > 0 or _is_confirm(event):
			_equip_focus = EquipFocus.ACCESSORY
			_refresh_equip_selection()
			_sync_selector_visibility()
			return

		return

	var accessory_step: int = _vertical_step(event)
	if accessory_step != 0 and not _equip_entries.is_empty():
		_equip_accessory_index = clampi(
			_equip_accessory_index + accessory_step,
			0,
			_equip_entries.size() - 1
		)
		_refresh_equip_selection()
		return

	if _horizontal_step(event) < 0:
		_equip_focus = EquipFocus.SLOT
		_refresh_equip_selection()
		_sync_selector_visibility()
		return

	if _is_confirm(event):
		_equip_selected_accessory()


func _handle_data_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step == 0 or _data_entries.is_empty():
		return

	_data_index = clampi(_data_index + step, 0, _data_entries.size() - 1)
	data_species_list.select(_data_index)
	data_species_list.ensure_current_is_visible()
	_sync_data_selector_window()
	_update_data_selector()
	_update_data_scroll_thumb()
	_update_data_details()


func _handle_help_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step == 0:
		return

	_help_index = clampi(_help_index + step, 0, HELP_TOPICS.size() - 1)
	help_list.select(_help_index)
	help_list.ensure_current_is_visible()
	_update_help_text()


func _handle_hints_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step == 0:
		return

	_hint_index = clampi(_hint_index + step, 0, HINT_TOPICS.size() - 1)
	hints_list.select(_hint_index)
	hints_list.ensure_current_is_visible()
	_update_hint_selector()
	_update_hint_text()


func _handle_options_input(_event: InputEvent) -> void:
	# Intentionally a placeholder. Keeping it as a page now means Options can be
	# implemented later without changing the menu router or command layout.
	pass


func _show_exit_confirm() -> void:
	if _transitioning:
		return
	_exit_closing = false
	_configure_exit_list_visuals()
	_exit_index = 1
	exit_list.select(_exit_index)
	_update_exit_selector()
	_set_command_confirm_colors(true)
	command_disabled_overlay.visible = false
	exit_confirm.visible = true
	_sync_selector_visibility()
	exit_panel.scale = Vector2(0.06, 0.06)
	info_label.text = "Quit fishing?"

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(exit_panel, "scale", Vector2.ONE, 0.14)

func _handle_exit_confirm_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step == 0:
		step = _horizontal_step(event)

	if step != 0:
		_exit_index = clampi(_exit_index + step, 0, 1)
		exit_list.select(_exit_index)
		_update_exit_selector()
		return

	if not _is_confirm(event):
		return

	if _exit_index == 0:
		exit_requested.emit()
		close_menu()
	else:
		_hide_exit_confirm()


func _reset_panel_positions() -> void:
	command_panel.position.x = MAIN_COMMAND_X
	main_time_panel.position.x = MAIN_TIME_X
	main_equip_panel.position.x = MAIN_EQUIP_X
	main_status_panel.position.x = MAIN_STATUS_X

	equip_slot_panel.position.x = EQUIP_SLOT_X
	equip_guide_panel.position.y = EQUIP_GUIDE_Y
	equip_accessory_panel.position.x = EQUIP_ACCESSORY_X

	data_species_panel.position.x = DATA_NAME_X
	data_details_panel.position.x = DATA_DETAILS_X
	hints_topic_panel.position.x = HINT_X

	exit_panel.scale = Vector2.ONE
	_update_command_selector()
	_update_equip_slot_selector()
	_update_exit_selector()


func _transition_from_main(target_page: int) -> void:
	if _transitioning or _page != Page.MAIN:
		return

	if target_page == Page.HELP or target_page == Page.OPTIONS:
		# These pages are intentionally placeholders for now. Keep navigation
		# functional without spending animation work on screens the user has
		# explicitly deferred.
		_set_page(target_page)
		return

	_transitioning = true

	match target_page:
		Page.EQUIP:
			equip_page.visible = true
			equip_slot_panel.visible = false
			equip_guide_panel.position.y = OFF_BOTTOM_Y
			equip_accessory_panel.position.x = OFF_RIGHT_X
			_refresh_equip_page()
		Page.DATA:
			data_page.visible = true
			data_species_panel.position.x = OFF_LEFT_X
			data_details_panel.position.x = OFF_RIGHT_X
			_refresh_data_page()
		Page.HINTS:
			hints_page.visible = true
			hints_topic_panel.position.x = OFF_RIGHT_X
			_update_hint_selector()
			_update_hint_text()

	var outgoing := create_tween()
	outgoing.set_trans(Tween.TRANS_CUBIC)
	outgoing.set_ease(Tween.EASE_IN)
	outgoing.set_parallel(true)
	outgoing.tween_property(command_panel, "position:x", OFF_LEFT_X, TRANSITION_OUT_TIME)
	outgoing.tween_property(main_time_panel, "position:x", OFF_LEFT_X, TRANSITION_OUT_TIME)
	outgoing.tween_property(main_status_panel, "position:x", OFF_RIGHT_X, TRANSITION_OUT_TIME)

	if target_page == Page.EQUIP:
		outgoing.tween_property(main_equip_panel, "position:x", EQUIP_SLOT_X, TRANSITION_OUT_TIME)
	else:
		outgoing.tween_property(main_equip_panel, "position:x", OFF_RIGHT_X, TRANSITION_OUT_TIME)

	await outgoing.finished

	if target_page == Page.EQUIP:
		# Swap the shared main Equip panel for the submenu copy at the exact
		# same position, so visually it is one panel that moved left.
		equip_slot_panel.position.x = EQUIP_SLOT_X
		equip_slot_panel.visible = true
		main_equip_panel.visible = false

	var incoming := create_tween()
	incoming.set_trans(Tween.TRANS_CUBIC)
	incoming.set_ease(Tween.EASE_OUT)
	incoming.set_parallel(true)

	match target_page:
		Page.EQUIP:
			incoming.tween_property(equip_guide_panel, "position:y", EQUIP_GUIDE_Y, TRANSITION_IN_TIME)
			incoming.tween_property(equip_accessory_panel, "position:x", EQUIP_ACCESSORY_X, TRANSITION_IN_TIME)
		Page.DATA:
			incoming.tween_property(data_species_panel, "position:x", DATA_NAME_X, TRANSITION_IN_TIME)
			incoming.tween_property(data_details_panel, "position:x", DATA_DETAILS_X, TRANSITION_IN_TIME)
		Page.HINTS:
			incoming.tween_property(hints_topic_panel, "position:x", HINT_X, TRANSITION_IN_TIME)

	await incoming.finished
	_page = target_page
	main_page.visible = false
	_transitioning = false

	match target_page:
		Page.EQUIP:
			info_label.text = "Equip a rod and lure."
		Page.DATA:
			_update_data_details()
		Page.HINTS:
			info_label.text = "Using the Fishing Controller"

	page_changed.emit(_page_name(target_page))


func _transition_to_main() -> void:
	if _transitioning or _page == Page.MAIN:
		return

	if _page == Page.HELP or _page == Page.OPTIONS:
		_set_page(Page.MAIN)
		_reset_panel_positions()
		return

	_transitioning = true
	var previous_page: int = _page

	var outgoing := create_tween()
	outgoing.set_trans(Tween.TRANS_CUBIC)
	outgoing.set_ease(Tween.EASE_IN)
	outgoing.set_parallel(true)

	match previous_page:
		Page.EQUIP:
			outgoing.tween_property(equip_guide_panel, "position:y", OFF_BOTTOM_Y, TRANSITION_OUT_TIME)
			outgoing.tween_property(equip_accessory_panel, "position:x", OFF_RIGHT_X, TRANSITION_OUT_TIME)
			outgoing.tween_property(equip_slot_panel, "position:x", MAIN_EQUIP_X, TRANSITION_OUT_TIME)
		Page.DATA:
			outgoing.tween_property(data_species_panel, "position:x", OFF_LEFT_X, TRANSITION_OUT_TIME)
			outgoing.tween_property(data_details_panel, "position:x", OFF_RIGHT_X, TRANSITION_OUT_TIME)
		Page.HINTS:
			outgoing.tween_property(hints_topic_panel, "position:x", OFF_RIGHT_X, TRANSITION_OUT_TIME)

	await outgoing.finished

	if previous_page == Page.EQUIP:
		main_equip_panel.position.x = MAIN_EQUIP_X
		main_equip_panel.visible = true

	equip_page.visible = false
	data_page.visible = false
	hints_page.visible = false
	main_page.visible = true

	# Main panels begin where their exit animation left them.
	command_panel.position.x = OFF_LEFT_X
	main_time_panel.position.x = OFF_LEFT_X
	main_status_panel.position.x = OFF_RIGHT_X
	if previous_page != Page.EQUIP:
		main_equip_panel.position.x = OFF_RIGHT_X

	var incoming := create_tween()
	incoming.set_trans(Tween.TRANS_CUBIC)
	incoming.set_ease(Tween.EASE_OUT)
	incoming.set_parallel(true)
	incoming.tween_property(command_panel, "position:x", MAIN_COMMAND_X, TRANSITION_IN_TIME)
	incoming.tween_property(main_time_panel, "position:x", MAIN_TIME_X, TRANSITION_IN_TIME)
	incoming.tween_property(main_status_panel, "position:x", MAIN_STATUS_X, TRANSITION_IN_TIME)
	incoming.tween_property(main_equip_panel, "position:x", MAIN_EQUIP_X, TRANSITION_IN_TIME)

	await incoming.finished
	_page = Page.MAIN
	_transitioning = false
	_update_command_selector()
	_update_main_info()
	page_changed.emit(&"main")


func _update_main_info() -> void:
	if not is_instance_valid(info_label):
		return
	if _command_index < 0 or _command_index >= MAIN_INFO_TEXT.size():
		info_label.text = ""
		return
	info_label.text = MAIN_INFO_TEXT[_command_index]


func _update_command_selector() -> void:
	if not is_instance_valid(command_selector):
		return
	command_selector.position = (
		main_selector_screen_position
		+ Vector2(0.0, float(_command_index) * 34.0)
	)
	command_selector.visible = (
		_is_open
		and _page == Page.MAIN
		and not exit_confirm.visible
		and not _transitioning
	)


func _update_equip_slot_selector() -> void:
	if not is_instance_valid(equip_slot_list):
		return
	if equip_slot_list.item_count <= 0:
		if is_instance_valid(equip_slot_selector):
			equip_slot_selector.visible = false
		return

	_equip_slot_index = clampi(
		_equip_slot_index,
		0,
		equip_slot_list.item_count - 1
	)
	equip_slot_list.select(_equip_slot_index)
	equip_slot_list.ensure_current_is_visible()
	call_deferred("_place_equip_left_selector")


func _configure_selector_overlays() -> void:
	# All custom selectors are authored at final 640x480 display scale and live
	# in an unscaled sibling layer. Never resize them in code.
	for selector in [
		command_selector,
		equip_slot_selector,
		equip_accessory_selector,
		data_species_selector,
		hints_selector,
		exit_selector,
	]:
		if is_instance_valid(selector):
			selector.visible = false


func _configure_exit_list_visuals() -> void:
	# Yes / No has only two rows and should never show a scrollbar. Keep the
	# ItemList for navigation, but make its internal scrollbar fully invisible.
	if not is_instance_valid(exit_list):
		return
	var scrollbar: VScrollBar = exit_list.get_v_scroll_bar()
	if is_instance_valid(scrollbar):
		scrollbar.modulate = Color(1.0, 1.0, 1.0, 0.0)
		scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _item_screen_position(list: ItemList, index: int) -> Vector2:
	if not is_instance_valid(list) or index < 0 or index >= list.item_count:
		return Vector2.ZERO

	var item_rect: Rect2 = list.get_item_rect(index, false)
	var local_position: Vector2 = item_rect.position
	var scrollbar: VScrollBar = list.get_v_scroll_bar()
	if is_instance_valid(scrollbar) and scrollbar.visible:
		local_position.y -= float(scrollbar.value)

	return list.get_global_transform_with_canvas() * local_position


func _place_native_selector_on_item(
	list: ItemList,
	selector: TextureRect,
	index: int,
	screen_offset: Vector2
) -> void:
	if (
		not _is_open
		or _transitioning
		or not is_instance_valid(list)
		or not is_instance_valid(selector)
		or index < 0
		or index >= list.item_count
	):
		if is_instance_valid(selector):
			selector.visible = false
		return

	selector.position = _item_screen_position(list, index) + screen_offset
	selector.visible = true


func _place_equip_left_selector() -> void:
	# BOF4 uses two visual states on the left:
	# - SLOT focus: warm filled selector.
	# - ACCESSORY focus: outline-only selector remains on the chosen category.
	if _page != Page.EQUIP:
		equip_slot_selector.visible = false
		return

	if _equip_focus == EquipFocus.SLOT:
		equip_slot_selector.texture = EQUIP_LEFT_SELECTOR_FILLED
	else:
		equip_slot_selector.texture = EQUIP_LEFT_SELECTOR_OUTLINE

	_place_native_selector_on_item(
		equip_slot_list,
		equip_slot_selector,
		_equip_slot_index,
		equip_left_selector_offset
	)


func _place_equip_right_selector() -> void:
	if (
		_page != Page.EQUIP
		or _equip_focus != EquipFocus.ACCESSORY
		or _equip_entries.is_empty()
	):
		equip_accessory_selector.visible = false
		return

	var visible_row: int = _equip_accessory_index - _equip_window_start
	if visible_row < 0 or visible_row >= equip_accessory_list.item_count:
		equip_accessory_selector.visible = false
		return

	_place_native_selector_on_item(
		equip_accessory_list,
		equip_accessory_selector,
		visible_row,
		equip_right_selector_offset
	)


func _place_data_selector() -> void:
	if _page != Page.DATA or _data_entries.is_empty():
		data_species_selector.visible = false
		return
	_place_native_selector_on_item(
		data_species_list,
		data_species_selector,
		_data_index,
		data_selector_offset
	)


func _place_hints_selector() -> void:
	if _page != Page.HINTS:
		hints_selector.visible = false
		return
	_place_native_selector_on_item(
		hints_list,
		hints_selector,
		_hint_index,
		hints_selector_offset
	)


func _place_exit_selector() -> void:
	if not exit_confirm.visible or _exit_closing:
		exit_selector.visible = false
		return

	var row_offset := exit_selector_offset
	if _exit_index == 0:
		row_offset.y += exit_yes_extra_y

	_place_native_selector_on_item(
		exit_list,
		exit_selector,
		_exit_index,
		row_offset
	)


func _update_visible_native_selectors() -> void:
	if not _is_open or _transitioning:
		_hide_all_selector_overlays()
		return

	if _page == Page.MAIN and not exit_confirm.visible:
		_update_command_selector()
	elif _page == Page.EQUIP:
		_place_equip_left_selector()
		_place_equip_right_selector()
	elif _page == Page.DATA:
		_place_data_selector()
	elif _page == Page.HINTS:
		_place_hints_selector()

	if exit_confirm.visible:
		_place_exit_selector()


func _hide_all_selector_overlays() -> void:
	for selector in [
		command_selector,
		equip_slot_selector,
		equip_accessory_selector,
		data_species_selector,
		hints_selector,
		exit_selector,
	]:
		if is_instance_valid(selector):
			selector.visible = false


func _sync_selector_visibility() -> void:
	_hide_all_selector_overlays()
	if not _is_open or _transitioning:
		return
	call_deferred("_update_visible_native_selectors")


func _update_exit_selector() -> void:
	if not is_instance_valid(exit_list) or exit_list.item_count <= 0:
		if is_instance_valid(exit_selector):
			exit_selector.visible = false
		return
	_exit_index = clampi(_exit_index, 0, exit_list.item_count - 1)
	exit_list.select(_exit_index)
	exit_list.ensure_current_is_visible()
	call_deferred("_place_exit_selector")


func _set_command_confirm_colors(confirming: bool) -> void:
	if not is_instance_valid(command_list):
		return

	var normal_color := Color(1.0, 1.0, 1.0, 1.0)
	var disabled_color: Color = disabled_text_tint

	for item_index in range(command_list.item_count):
		var color := normal_color
		if confirming and item_index < COMMANDS.size() - 1:
			color = disabled_color
		command_list.set_item_custom_fg_color(item_index, color)

	# Force the ItemList to repaint immediately when Exit confirmation opens/closes.
	command_list.queue_redraw()

func _hide_exit_confirm() -> void:
	if not exit_confirm.visible or _exit_closing:
		return

	# Stop the screen-space selector immediately. The confirmation panel may
	# still animate closed, but its selector must never linger over Main.
	_exit_closing = true
	if is_instance_valid(exit_selector):
		exit_selector.visible = false

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(exit_panel, "scale", Vector2(0.06, 0.06), 0.10)
	await tween.finished
	exit_confirm.visible = false
	_exit_closing = false
	_set_command_confirm_colors(false)
	command_disabled_overlay.visible = false
	exit_panel.scale = Vector2.ONE
	_update_main_info()
	_sync_selector_visibility()


func _refresh_all() -> void:
	_refresh_main_page()
	if _page == Page.EQUIP:
		_refresh_equip_page()
	elif _page == Page.DATA:
		_refresh_data_page()


func _refresh_main_page() -> void:
	var rod_name: String = "---"
	var lure_name: String = "---"

	if is_instance_valid(_loadout):
		var rod: RodData = _loadout.get_selected_rod()
		var lure: BaitData = _loadout.get_selected_lure()
		if rod != null:
			rod_name = rod.rod_name
		if lure != null:
			lure_name = lure.display_name

	main_rod_label.text = rod_name
	main_lure_label.text = lure_name

	var rank_name: String = "Beginner"
	var points: int = 0
	if is_instance_valid(_journal):
		var progression: Dictionary = _journal.get_progression_snapshot()
		rank_name = str(progression.get("rank_name", rank_name))
		points = int(progression.get("fishing_points", 0))

	rank_label.text = rank_name
	points_label.text = "%d" % points
	_update_time_label()


func _refresh_equip_page() -> void:
	equip_slot_list.clear()

	var rod_name: String = "---"
	var lure_name: String = "---"
	if is_instance_valid(_loadout):
		var rod: RodData = _loadout.get_selected_rod()
		var lure: BaitData = _loadout.get_selected_lure()
		if rod != null:
			rod_name = rod.rod_name
		if lure != null:
			lure_name = lure.display_name

	equip_slot_list.add_item(rod_name)
	equip_slot_list.add_item(lure_name)
	equip_rod_slot_label.text = rod_name
	equip_lure_slot_label.text = lure_name
	equip_slot_list.select(_equip_slot_index)
	_update_equip_slot_selector()

	_rebuild_equip_entries()
	_refresh_equip_selection()


func _rebuild_equip_entries() -> void:
	_equip_entries.clear()
	equip_accessory_list.clear()

	if _tackle_catalog == null:
		return

	if _equip_slot_index == 0:
		for rod in _tackle_catalog.rods:
			if rod == null:
				continue
			var count: int = 1
			if is_instance_valid(_inventory):
				count = _inventory.get_rod_count(rod.rod_id)
			if count <= 0:
				if not show_full_tackle_catalog_for_testing:
					continue
				count = 1
			_equip_entries.append({"kind": "rod", "resource": rod, "count": count})
	else:
		if _tackle_catalog.lure_catalog != null:
			for lure in _tackle_catalog.lure_catalog.lures:
				if lure == null:
					continue
				var count: int = 1
				if is_instance_valid(_inventory):
					count = _inventory.get_lure_count(lure.lure_id)
				if count <= 0:
					if not show_full_tackle_catalog_for_testing:
						continue
					count = 1
				_equip_entries.append({"kind": "lure", "resource": lure, "count": count})

	if _equip_entries.is_empty():
		_equip_accessory_index = 0
		_equip_window_start = 0
	else:
		_equip_accessory_index = clampi(
			_equip_accessory_index,
			0,
			_equip_entries.size() - 1
		)

	_sync_equip_selector_window()
	_refresh_equip_visible_rows()
	_update_equip_scroll_thumb()
	_update_equip_accessory_counter()
	_update_equipped_accessory_highlight()
	call_deferred("_place_equip_right_selector")


func _format_accessory_row(display_name: String, count: int) -> String:
	# BOF4's live text is mostly 8 px advance, but narrow glyphs (I/i/l) use
	# 4 px. Preserve the original 104 px name column instead of padding by
	# character count, otherwise names containing narrow letters would make the
	# two-digit quantity column wobble left. U+00A0 is a private 4 px blank
	# glyph in BOF_Font_Refined.fnt and is used only when half-cell padding is
	# needed.
	var padded_name: String = display_name
	var remaining_px: int = ACCESSORY_NAME_COLUMN_WIDTH_PX - _bof_text_advance_px(display_name)

	while remaining_px >= BOF_STANDARD_ADVANCE_PX:
		padded_name += " "
		remaining_px -= BOF_STANDARD_ADVANCE_PX

	if remaining_px >= BOF_NARROW_ADVANCE_PX:
		padded_name += ACCESSORY_HALF_SPACE

	return "%s%02d" % [padded_name, maxi(count, 0)]


func _bof_text_advance_px(value: String) -> int:
	var width_px := 0
	for character_index in range(value.length()):
		var character := value.substr(character_index, 1)
		if character == "I" or character == "i" or character == "l":
			width_px += BOF_NARROW_ADVANCE_PX
		else:
			width_px += BOF_STANDARD_ADVANCE_PX
	return width_px


func _refresh_equip_selection() -> void:
	equip_slot_list.select(_equip_slot_index)
	_update_equip_slot_selector()

	if not _equip_entries.is_empty():
		_sync_equip_selector_window()
		_refresh_equip_visible_rows()
		_update_equip_scroll_thumb()

	call_deferred("_place_equip_right_selector")

	if _equip_focus == EquipFocus.SLOT:
		equip_slot_list.grab_focus()
	else:
		equip_accessory_list.grab_focus()

	_update_equip_slot_colors()
	_update_equip_accessory_counter()
	_update_equip_guide()
	_update_equipped_accessory_highlight()


func _update_equip_slot_colors() -> void:
	if not is_instance_valid(equip_slot_list):
		return

	var normal_color := Color(1.0, 1.0, 1.0, 1.0)
	var inactive_color: Color = disabled_text_tint

	# SlotList is navigation-only; the dedicated labels let rod and lure have
	# independent one-pixel placement without disturbing row geometry.
	if is_instance_valid(equip_rod_slot_label):
		equip_rod_slot_label.add_theme_color_override("font_color", normal_color)
	if is_instance_valid(equip_lure_slot_label):
		equip_lure_slot_label.add_theme_color_override("font_color", normal_color)

	if _equip_focus == EquipFocus.ACCESSORY:
		if _equip_slot_index == 0 and is_instance_valid(equip_lure_slot_label):
			equip_lure_slot_label.add_theme_color_override("font_color", inactive_color)
		elif _equip_slot_index == 1 and is_instance_valid(equip_rod_slot_label):
			equip_rod_slot_label.add_theme_color_override("font_color", inactive_color)


func _equipped_accessory_index() -> int:
	if not is_instance_valid(_loadout) or _equip_entries.is_empty():
		return -1

	var selected_rod: RodData = _loadout.get_selected_rod()
	var selected_lure: BaitData = _loadout.get_selected_lure()

	for item_index in range(_equip_entries.size()):
		var entry: Dictionary = _equip_entries[item_index]
		var resource: Resource = entry.get("resource", null) as Resource

		if _equip_slot_index == 0 and resource is RodData and selected_rod != null:
			var rod: RodData = resource as RodData
			if rod.rod_id == selected_rod.rod_id:
				return item_index

		elif _equip_slot_index == 1 and resource is BaitData and selected_lure != null:
			var lure: BaitData = resource as BaitData
			if lure.lure_id == selected_lure.lure_id:
				return item_index

	return -1


func _update_equipped_accessory_highlight() -> void:
	# BOF4 does not use a second independent equipped-row rectangle here.
	# The left rod/lure category keeps its outline selector, while the Accessory
	# list uses its own warm filled cursor selector.
	if is_instance_valid(equip_equipped_highlight):
		equip_equipped_highlight.visible = false


func _update_equip_accessory_counter() -> void:
	if not is_instance_valid(equip_accessory_count_label):
		return

	var total_entries: int = _equip_entries.size()
	if total_entries <= 0:
		equip_accessory_count_label.text = "0/0"
		return

	# BOF4 shows 0 / total before entering the accessory list, then the
	# selected entry number once the list owns focus.
	var current_entry: int = 0
	if _equip_focus == EquipFocus.ACCESSORY:
		current_entry = clampi(_equip_accessory_index + 1, 1, total_entries)

	equip_accessory_count_label.text = "%d/%d" % [
		current_entry,
		total_entries,
	]


func _update_equip_guide() -> void:
	equip_guide_icon.texture = null
	equip_guide_title_label.text = ""
	equip_guide_description_label.text = ""

	if _equip_entries.is_empty():
		equip_guide_description_label.text = "No owned tackle in this category."
		return

	var entry: Dictionary = _equip_entries[_equip_accessory_index]
	var resource: Resource = entry.get("resource", null) as Resource

	if resource is RodData:
		var rod: RodData = resource as RodData
		equip_guide_title_label.text = str(
			ROD_GUIDE_TITLES.get(rod.rod_id, rod.rod_name)
		)
		equip_guide_description_label.text = "%s
Power Level: %s" % [
			rod.description,
			rod.power_level_label,
		]

	elif resource is BaitData:
		var lure: BaitData = resource as BaitData
		if lure.lure_id == &"spoon" or lure.lure_id == &"king_frog":
			equip_guide_title_label.text = "Ultimate Lure"
		else:
			var lure_type_label: String = str(
				LURE_GUIDE_TYPE_LABELS.get(
					lure.lure_type,
					lure.get_type_label()
				)
			)
			equip_guide_title_label.text = "LV %d %s" % [
				lure.level,
				lure_type_label,
			]

		equip_guide_icon.texture = LURE_GUIDE_ICONS.get(
			lure.lure_id,
			null
		) as Texture2D
		equip_guide_description_label.text = lure.description


func _equip_selected_accessory() -> void:
	if _equip_entries.is_empty() or not is_instance_valid(_loadout):
		return

	var entry: Dictionary = _equip_entries[_equip_accessory_index]
	var resource: Resource = entry.get("resource", null) as Resource
	var equipped: bool = false

	if resource is RodData:
		if show_full_tackle_catalog_for_testing:
			_loadout.equip_rod(resource as RodData)
			equipped = _loadout.get_selected_rod() == resource
		else:
			equipped = _loadout.equip_owned_rod(resource as RodData)
	elif resource is BaitData:
		if show_full_tackle_catalog_for_testing:
			_loadout.equip_lure(resource as BaitData)
			equipped = _loadout.get_selected_lure() == resource
		else:
			equipped = _loadout.equip_owned_lure(resource as BaitData)

	if equipped:
		info_label.text = "Equipped %s." % _resource_display_name(resource)
		_refresh_main_page()
		_refresh_equip_page()


func _refresh_data_page() -> void:
	_data_entries.clear()
	data_species_list.clear()

	if not is_instance_valid(_journal):
		info_label.text = "Fishing data is unavailable."
		_update_data_details()
		return

	# Keep every species in its canonical BOF4 slot. Undiscovered fish stay in
	# the list so later catches never collapse upward and change row order.
	var snapshot: Dictionary = _journal.get_data_menu_snapshot(true, false)
	var entries_by_key: Dictionary = {}
	var raw_species: Variant = snapshot.get("species", [])
	if raw_species is Array:
		for value in raw_species:
			if not (value is Dictionary):
				continue
			var entry: Dictionary = (value as Dictionary).duplicate(true)
			var source_name: String = str(entry.get("display_name", ""))
			entries_by_key[_canonical_species_key(source_name)] = entry

	for canonical_name in DATA_SPECIES_ORDER:
		var canonical_key: String = _canonical_species_key(canonical_name)
		var entry: Dictionary
		if entries_by_key.has(canonical_key):
			entry = (entries_by_key[canonical_key] as Dictionary).duplicate(true)
		else:
			# A reserved slot (currently Bream if it is not in the content catalog)
			# still stays in the correct list position.
			entry = {
				"display_name": canonical_name,
				"discovered": false,
				"current_owned_count": 0,
			}

		# Display the canonical BOF4/reference spelling regardless of the
		# project's internal resource spelling (Barandy/Barundi, Moorfish, etc.).
		entry["display_name"] = canonical_name
		_data_entries.append(entry)
		data_species_list.add_item(canonical_name)

	if _data_entries.is_empty():
		_data_index = 0
		_data_window_start = 0
	else:
		_data_index = clampi(_data_index, 0, _data_entries.size() - 1)
		data_species_list.select(_data_index)
		data_species_list.ensure_current_is_visible()
		_sync_data_selector_window()

	_update_data_selector()
	_update_data_scroll_thumb()
	_update_data_details()


func _update_data_details() -> void:
	data_portrait.texture = null
	data_size_label.text = "--"
	data_points_label.text = "--"
	data_point_label.text = "---"
	data_caught_count_label.text = "00"

	if _data_entries.is_empty():
		info_label.text = "No fishing data."
		return

	var entry: Dictionary = _data_entries[_data_index]
	var fish_name: String = str(entry.get("display_name", "????"))
	info_label.text = "View data on %s" % fish_name

	# Preview identity comes directly from the FishData database. FishData owns
	# the AtlasTexture region, so every canonical name always resolves to the
	# correct sprite instead of inheriting a stale/fallback Jellyfish texture.
	var fish_key: String = _canonical_species_key(fish_name)
	var fish_data: FishData = DATA_FISH_BY_KEY.get(fish_key) as FishData
	if fish_data != null and fish_data.portrait != null:
		data_portrait.texture = fish_data.portrait

	if not bool(entry.get("discovered", false)):
		return

	data_size_label.text = "%d" % int(round(float(entry.get("best_size", 0.0))))
	data_points_label.text = "%d" % int(entry.get("best_points", 0))
	data_point_label.text = _get_primary_location_name(entry)
	data_caught_count_label.text = "%02d" % int(entry.get("current_owned_count", 0))


func _sync_data_selector_window() -> void:
	const visible_rows: int = 8
	if _data_entries.is_empty():
		_data_window_start = 0
		return

	if _data_index < _data_window_start:
		_data_window_start = _data_index
	elif _data_index >= _data_window_start + visible_rows:
		_data_window_start = _data_index - visible_rows + 1

	_data_window_start = clampi(
		_data_window_start,
		0,
		maxi(_data_entries.size() - visible_rows, 0)
	)


func _canonical_species_key(display_name: String) -> String:
	var normalized: String = display_name.to_lower()
	normalized = normalized.replace(" ", "").replace("-", "").replace("'", "")

	# Map project/internal spellings onto the reference names used by the menu.
	var aliases: Dictionary = {
		"bluegill": "bluegill",
		"bullcat": "bullcat",
		"barandy": "barundi",
		"barundi": "barundi",
		"manowar": "manowar",
		"moorfish": "moonfish",
		"moafish": "moonfish",
		"moonfish": "moonfish",
	}
	if aliases.has(normalized):
		return str(aliases[normalized])
	return normalized


func _update_data_selector() -> void:
	data_species_list.select(_data_index)
	data_species_list.ensure_current_is_visible()
	call_deferred("_place_data_selector")


func _configure_equip_accessory_list_visuals() -> void:
	# Keep ItemList scrolling logic, but hide Godot's native grey scrollbar.
	# BOF4 uses the same thin yellow custom thumb as the Data page.
	if is_instance_valid(equip_accessory_list):
		var native_scrollbar: VScrollBar = equip_accessory_list.get_v_scroll_bar()
		if is_instance_valid(native_scrollbar):
			native_scrollbar.modulate = Color(1.0, 1.0, 1.0, 0.0)
			native_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			native_scrollbar.value = 0.0

	_update_equip_scroll_thumb()


func _sync_equip_selector_window() -> void:
	const visible_rows: int = 8

	if _equip_entries.is_empty():
		_equip_window_start = 0
		return

	if _equip_accessory_index < _equip_window_start:
		_equip_window_start = _equip_accessory_index
	elif _equip_accessory_index >= _equip_window_start + visible_rows:
		_equip_window_start = _equip_accessory_index - visible_rows + 1

	_equip_window_start = clampi(
		_equip_window_start,
		0,
		maxi(_equip_entries.size() - visible_rows, 0)
	)


func _refresh_equip_visible_rows() -> void:
	# Equip deliberately does NOT use ItemList's native scrolling anymore.
	# Only the current eight-row BOF4 window exists in the ItemList. This keeps
	# fast W/S hold-repeat deterministic and prevents the selector from being
	# displaced by a hidden Godot scrollbar that is one frame out of sync.
	const visible_rows: int = 8

	equip_accessory_list.clear()

	if _equip_entries.is_empty():
		return

	var window_end: int = mini(
		_equip_window_start + visible_rows,
		_equip_entries.size()
	)

	for global_index in range(_equip_window_start, window_end):
		var entry: Dictionary = _equip_entries[global_index]
		var resource: Resource = entry.get("resource", null) as Resource
		var count: int = int(entry.get("count", 0))
		var display_name: String = _resource_display_name(resource)
		equip_accessory_list.add_item(
			_format_accessory_row(display_name, count)
		)

	var visible_index: int = _equip_accessory_index - _equip_window_start
	if visible_index >= 0 and visible_index < equip_accessory_list.item_count:
		equip_accessory_list.select(visible_index)


func _update_equip_scroll_thumb() -> void:
	if not is_instance_valid(equip_scroll_thumb):
		return

	var total_entries: int = _equip_entries.size()
	if total_entries <= 0:
		equip_scroll_thumb.visible = false
		return

	equip_scroll_thumb.visible = true

	# BOF4 track geometry inside the Accessory panel.
	const visible_rows: int = 8
	const track_top_y: float = 45.0
	const track_end_y: float = 152.0
	const scrolling_thumb_height: float = 34.0
	const scrolling_thumb_bottom_y: float = (
		track_end_y - scrolling_thumb_height
	)

	if total_entries <= visible_rows:
		# All rods fit on one page. A full-height yellow bar communicates that
		# this IS the complete page and there is nowhere further to scroll.
		equip_scroll_thumb.position.y = track_top_y
		equip_scroll_thumb.size.y = track_end_y - track_top_y
		return

	# Lures have multiple pages. Restore the normal BOF4 thumb size and move it
	# according to our explicit eight-row window.
	equip_scroll_thumb.size.y = scrolling_thumb_height

	var max_window_start: int = maxi(total_entries - visible_rows, 0)
	var ratio: float = 0.0
	if max_window_start > 0:
		ratio = clampf(
			float(_equip_window_start) / float(max_window_start),
			0.0,
			1.0
		)

	equip_scroll_thumb.position.y = roundf(
		lerpf(track_top_y, scrolling_thumb_bottom_y, ratio)
	)


func _configure_data_list_visuals() -> void:
	# ItemList keeps its internal scrollbar for scrolling logic, but BOF4 draws
	# its own thin L1/R1 indicator. Hide only the native Godot visual.
	if is_instance_valid(data_species_list):
		var native_scrollbar: VScrollBar = data_species_list.get_v_scroll_bar()
		if is_instance_valid(native_scrollbar):
			native_scrollbar.modulate = Color(1.0, 1.0, 1.0, 0.0)
			native_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_update_data_scroll_thumb()



func _configure_hint_list_visuals() -> void:
	# Seven categories fit in the Hint panel. Hide Godot's native scroll bar.
	if is_instance_valid(hints_list):
		var native_scrollbar: VScrollBar = hints_list.get_v_scroll_bar()
		if is_instance_valid(native_scrollbar):
			native_scrollbar.modulate = Color(1.0, 1.0, 1.0, 0.0)
			native_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _update_data_scroll_thumb() -> void:
	if not is_instance_valid(data_scroll_thumb):
		return

	data_scroll_thumb.visible = _data_entries.size() > 8
	if not data_scroll_thumb.visible:
		return

	# The thumb has a fixed 2x34 native-pixel size. It represents the current
	# eight-row viewport, so it moves only when the list itself scrolls.
	const visible_rows: int = 8
	const track_top_y: float = 45.0
	const track_bottom_y: float = 118.0
	var max_window_start: int = maxi(_data_entries.size() - visible_rows, 0)
	var ratio: float = 0.0
	if max_window_start > 0:
		ratio = clampf(float(_data_window_start) / float(max_window_start), 0.0, 1.0)

	data_scroll_thumb.position.y = roundf(lerpf(track_top_y, track_bottom_y, ratio))


func _get_primary_location_name(entry: Dictionary) -> String:
	var preferred_fields: PackedStringArray = [
		"best_size_spot_name",
		"best_points_spot_name",
		"last_catch_spot_name",
	]

	for field_name in preferred_fields:
		var spot_name: String = str(entry.get(field_name, "")).strip_edges()
		if not spot_name.is_empty():
			return spot_name

	var raw_locations: Variant = entry.get("locations", [])
	if raw_locations is Array:
		for value in raw_locations:
			if not (value is Dictionary):
				continue
			var spot_name: String = str((value as Dictionary).get("spot_name", "")).strip_edges()
			if not spot_name.is_empty():
				return spot_name

	return "---"


func _join_location_names(entry: Dictionary) -> String:
	var names: PackedStringArray = PackedStringArray()
	var raw_locations: Variant = entry.get("locations", [])
	if raw_locations is Array:
		var source_locations: Array = raw_locations
		for value in source_locations:
			if not (value is Dictionary):
				continue
			var location: Dictionary = value as Dictionary
			var spot_name: String = str(location.get("spot_name", ""))
			if not spot_name.is_empty():
				names.append(spot_name)

	return ", ".join(names) if not names.is_empty() else "---"


func _join_lure_names(entry: Dictionary) -> String:
	var names: PackedStringArray = PackedStringArray()
	var raw_successful: Variant = entry.get("successful_lures", [])
	if raw_successful is Array:
		var source_lures: Array = raw_successful
		for value in source_lures:
			if not (value is Dictionary):
				continue
			var lure_name: String = str((value as Dictionary).get("lure_name", ""))
			if not lure_name.is_empty() and not names.has(lure_name):
				names.append(lure_name)

	if names.is_empty():
		var preferred: Variant = entry.get("preferred_lure_ids", PackedStringArray())
		if preferred is PackedStringArray:
			var preferred_ids: PackedStringArray = preferred
			for lure_id in preferred_ids:
				names.append(str(lure_id))

	return ", ".join(names) if not names.is_empty() else "---"


func _update_help_text() -> void:
	help_list.select(_help_index)
	match _help_index:
		0:
			help_text_label.text = "Casting\n\nK enters the cast sequence. Set power, then adjust the curve before release."
		1:
			help_text_label.text = "Moving the lure\n\nUse the fishing controls to steer, reel and work the lure after it lands."
		2:
			help_text_label.text = "Getting a bite\n\nWatch the fish and react to bite opportunities before the window closes."
		3:
			help_text_label.text = "Reeling in a catch\n\nBalance reeling, steering and tension until the fish is exhausted."
		_:
			help_text_label.text = "I returns to the previous menu."


func _update_hint_selector() -> void:
	hints_list.select(_hint_index)
	hints_list.ensure_current_is_visible()
	call_deferred("_place_hints_selector")


func _update_hint_text() -> void:
	hints_list.select(_hint_index)
	_update_hint_selector()
	hints_text_label.text = "%s\n\nReference text will be filled from your BOF4 screenshots." % HINT_TOPICS[_hint_index]


func _update_time_label() -> void:
	if not is_instance_valid(time_label):
		return
	# Temporary game-time source until a global save/play-time service exists.
	# Engine ticks keep counting from game launch and do not reset when this menu opens.
	var total_seconds: int = int(Time.get_ticks_msec() / 1000.0)
	var hours: int = int(total_seconds / 3600.0)
	var minutes: int = int((total_seconds % 3600) / 60.0)
	time_label.text = "%02d:%02d" % [hours, minutes]



func _hide_gameplay_hud() -> void:
	_hidden_hud_visibility.clear()
	var ui_root: Node = get_parent()
	if ui_root == null:
		return

	# The fishing menu owns the whole screen. Preserve the previous visibility
	# so closing the menu restores exploration exactly as it was.
	for hud_name in [&"ExplorationHud", &"FishingHud"]:
		var hud: Node = ui_root.get_node_or_null(NodePath(String(hud_name)))
		if hud is CanvasItem:
			var canvas_item := hud as CanvasItem
			_hidden_hud_visibility[hud_name] = canvas_item.visible
			canvas_item.visible = false


func _restore_gameplay_hud() -> void:
	var ui_root: Node = get_parent()
	if ui_root == null:
		_hidden_hud_visibility.clear()
		return

	for hud_name in _hidden_hud_visibility.keys():
		var hud: Node = ui_root.get_node_or_null(NodePath(String(hud_name)))
		if hud is CanvasItem:
			(hud as CanvasItem).visible = bool(
				_hidden_hud_visibility.get(hud_name, false)
			)

	_hidden_hud_visibility.clear()

func _resource_display_name(resource: Resource) -> String:
	if resource is RodData:
		return (resource as RodData).rod_name
	if resource is BaitData:
		return (resource as BaitData).display_name
	return "item"


func _on_loadout_changed(_value = null) -> void:
	_refresh_all()


func _on_journal_changed() -> void:
	_refresh_all()


func _is_menu_toggle(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	return key_event.physical_keycode == KEY_J or key_event.keycode == KEY_J


func _is_confirm(event: InputEvent) -> bool:
	return event.is_action_pressed("enter_fishing")


func _is_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("cancel_fishing")


func _vertical_step(event: InputEvent) -> int:
	if event.is_action_pressed("move_forward") or event.is_action_pressed("ui_up"):
		return -1
	if event.is_action_pressed("move_back") or event.is_action_pressed("ui_down"):
		return 1
	return 0


func _horizontal_step(event: InputEvent) -> int:
	if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		return -1
	if event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		return 1
	return 0
