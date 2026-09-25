extends CanvasLayer
class_name FishingMenu

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
@onready var info_label: Label = $Root/InfoPanel/InfoLabel

@onready var main_page: Control = $Root/MainPage
@onready var command_panel: Control = $Root/MainPage/LeftMask/CommandPanel
@onready var command_selector: Control = $Root/MainPage/LeftMask/CommandPanel/CommandSelector
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
@onready var equip_slot_selector: Control = $Root/EquipPage/SlotPanel/SlotSelector
@onready var equip_guide_panel: Control = $Root/EquipPage/GuidePanel
@onready var equip_accessory_panel: Control = $Root/EquipPage/AccessoryPanel
@onready var equip_slot_list: ItemList = $Root/EquipPage/SlotPanel/SlotList
@onready var equip_accessory_list: ItemList = $Root/EquipPage/AccessoryPanel/AccessoryList
@onready var equip_guide_label: Label = $Root/EquipPage/GuidePanel/GuideLabel

@onready var data_page: Control = $Root/DataPage
@onready var data_species_panel: Control = $Root/DataPage/SpeciesPanel
@onready var data_details_panel: Control = $Root/DataPage/DetailsPanel
@onready var data_species_list: ItemList = $Root/DataPage/SpeciesPanel/SpeciesList
@onready var data_portrait: TextureRect = $Root/DataPage/DetailsPanel/PreviewPanel/FishPortrait
@onready var data_record_label: Label = $Root/DataPage/DetailsPanel/RecordPanel/RecordLabel
@onready var data_point_label: Label = $Root/DataPage/DetailsPanel/RecordPanel/PointLabel
@onready var data_lure_label: Label = $Root/DataPage/DetailsPanel/RecordPanel/LureLabel
@onready var data_habitat_label: Label = $Root/DataPage/DetailsPanel/RecordPanel/HabitatLabel

@onready var help_page: Control = $Root/HelpPage
@onready var help_list: ItemList = $Root/HelpPage/TopicPanel/TopicList
@onready var help_text_label: Label = $Root/HelpPage/TextPanel/TextLabel

@onready var hints_page: Control = $Root/HintsPage
@onready var hints_topic_panel: Control = $Root/HintsPage/TopicPanel
@onready var hints_list: ItemList = $Root/HintsPage/TopicPanel/TopicList
@onready var hints_text_label: Label = $Root/HintsPage/TextPanel/TextLabel

@onready var options_page: Control = $Root/OptionsPage
@onready var exit_confirm: Control = $Root/ExitConfirm
@onready var exit_panel: Control = $Root/ExitConfirm/Panel
@onready var exit_selector: Control = $Root/ExitConfirm/Panel/ChoiceSelector
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
var _equip_entries: Array[Dictionary] = []
var _data_index: int = 0
var _data_entries: Array[Dictionary] = []
var _help_index: int = 0
var _hint_index: int = 0
var _exit_index: int = 1
var _pause_was_active: bool = false
var _session_time_seconds: float = 0.0
var _transitioning: bool = false
var _hidden_hud_visibility: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false

	_fill_static_lists()
	_set_page(Page.MAIN)
	_reset_panel_positions()


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
	exit_confirm.visible = false
	root.visible = false
	_restore_gameplay_hud()
	get_tree().paused = _pause_was_active
	closed.emit()


func _process(delta: float) -> void:
	if not _is_open:
		_session_time_seconds += delta
		_update_time_label()


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

	if _is_cancel(event):
		_handle_cancel()
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
			_equip_slot_index = posmod(_equip_slot_index + slot_step, 2)
			_equip_accessory_index = 0
			_refresh_equip_page()
			_update_equip_slot_selector()
			return

		if _horizontal_step(event) > 0 or _is_confirm(event):
			_equip_focus = EquipFocus.ACCESSORY
			_refresh_equip_selection()
			return

		return

	var accessory_step: int = _vertical_step(event)
	if accessory_step != 0 and not _equip_entries.is_empty():
		_equip_accessory_index = posmod(
			_equip_accessory_index + accessory_step,
			_equip_entries.size()
		)
		_refresh_equip_selection()
		return

	if _horizontal_step(event) < 0:
		_equip_focus = EquipFocus.SLOT
		_refresh_equip_selection()
		return

	if _is_confirm(event):
		_equip_selected_accessory()


func _handle_data_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step == 0 or _data_entries.is_empty():
		return

	_data_index = posmod(_data_index + step, _data_entries.size())
	data_species_list.select(_data_index)
	data_species_list.ensure_current_is_visible()
	_update_data_details()


func _handle_help_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step == 0:
		return

	_help_index = posmod(_help_index + step, HELP_TOPICS.size())
	help_list.select(_help_index)
	help_list.ensure_current_is_visible()
	_update_help_text()


func _handle_hints_input(event: InputEvent) -> void:
	var step: int = _vertical_step(event)
	if step == 0:
		return

	_hint_index = posmod(_hint_index + step, HINT_TOPICS.size())
	hints_list.select(_hint_index)
	hints_list.ensure_current_is_visible()
	_update_hint_text()


func _handle_options_input(_event: InputEvent) -> void:
	# Intentionally a placeholder. Keeping it as a page now means Options can be
	# implemented later without changing the menu router or command layout.
	pass


func _show_exit_confirm() -> void:
	if _transitioning:
		return
	_exit_index = 1
	exit_list.select(_exit_index)
	_update_exit_selector()
	exit_confirm.visible = true
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
		_exit_index = posmod(_exit_index + step, 2)
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
	command_selector.position.y = 9.0 + float(_command_index) * 17.0


func _update_equip_slot_selector() -> void:
	if not is_instance_valid(equip_slot_selector):
		return
	equip_slot_selector.position.y = 12.0 + float(_equip_slot_index) * 17.0


func _update_exit_selector() -> void:
	if not is_instance_valid(exit_selector):
		return
	exit_selector.position.y = 9.0 + float(_exit_index) * 13.0


func _hide_exit_confirm() -> void:
	if not exit_confirm.visible:
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(exit_panel, "scale", Vector2(0.06, 0.06), 0.10)
	await tween.finished
	exit_confirm.visible = false
	exit_panel.scale = Vector2.ONE
	_update_main_info()


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
				continue
			_equip_entries.append({"kind": "rod", "resource": rod, "count": count})
			equip_accessory_list.add_item("%s  x%d" % [rod.rod_name, count])
	else:
		if _tackle_catalog.lure_catalog != null:
			for lure in _tackle_catalog.lure_catalog.lures:
				if lure == null:
					continue
				var count: int = 1
				if is_instance_valid(_inventory):
					count = _inventory.get_lure_count(lure.lure_id)
				if count <= 0:
					continue
				_equip_entries.append({"kind": "lure", "resource": lure, "count": count})
				equip_accessory_list.add_item("%s  x%d" % [lure.display_name, count])

	if _equip_entries.is_empty():
		_equip_accessory_index = 0
	else:
		_equip_accessory_index = clampi(
			_equip_accessory_index,
			0,
			_equip_entries.size() - 1
		)
		equip_accessory_list.select(_equip_accessory_index)


func _refresh_equip_selection() -> void:
	equip_slot_list.select(_equip_slot_index)
	_update_equip_slot_selector()
	if not _equip_entries.is_empty():
		equip_accessory_list.select(_equip_accessory_index)
		equip_accessory_list.ensure_current_is_visible()

	if _equip_focus == EquipFocus.SLOT:
		equip_slot_list.grab_focus()
	else:
		equip_accessory_list.grab_focus()

	_update_equip_guide()


func _update_equip_guide() -> void:
	if _equip_entries.is_empty():
		equip_guide_label.text = "No owned tackle in this category."
		return

	var entry: Dictionary = _equip_entries[_equip_accessory_index]
	var resource: Resource = entry.get("resource", null) as Resource
	if resource is RodData:
		var rod: RodData = resource as RodData
		equip_guide_label.text = "%s\nPower Level: %s" % [
			rod.description,
			rod.power_level_label,
		]
	elif resource is BaitData:
		var lure: BaitData = resource as BaitData
		equip_guide_label.text = "%s\n%s  Lv.%d" % [
			lure.description,
			lure.get_type_label(),
			lure.level,
		]
	else:
		equip_guide_label.text = ""


func _equip_selected_accessory() -> void:
	if _equip_entries.is_empty() or not is_instance_valid(_loadout):
		return

	var entry: Dictionary = _equip_entries[_equip_accessory_index]
	var resource: Resource = entry.get("resource", null) as Resource
	var equipped: bool = false

	if resource is RodData:
		equipped = _loadout.equip_owned_rod(resource as RodData)
	elif resource is BaitData:
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

	var snapshot: Dictionary = _journal.get_data_menu_snapshot(true, false)
	var raw_species: Variant = snapshot.get("species", [])
	if raw_species is Array:
		var source_species: Array = raw_species
		for value in source_species:
			if value is Dictionary:
				_data_entries.append((value as Dictionary).duplicate(true))

	for entry in _data_entries:
		data_species_list.add_item(str(entry.get("display_name", "????")))

	if _data_entries.is_empty():
		_data_index = 0
	else:
		_data_index = clampi(_data_index, 0, _data_entries.size() - 1)
		data_species_list.select(_data_index)
		data_species_list.ensure_current_is_visible()

	_update_data_details()


func _update_data_details() -> void:
	data_portrait.texture = null
	data_record_label.text = "-- cm      -- pts."
	data_point_label.text = "---"
	data_lure_label.text = "---"
	data_habitat_label.text = "---"

	if _data_entries.is_empty():
		info_label.text = "No fishing data."
		return

	var entry: Dictionary = _data_entries[_data_index]
	var discovered: bool = bool(entry.get("discovered", false))
	var name: String = str(entry.get("display_name", "????"))

	if not discovered:
		info_label.text = "No data on this fish yet."
		return

	info_label.text = "View data on %s" % name

	var portrait_value: Variant = entry.get("portrait", null)
	if portrait_value is Texture2D:
		data_portrait.texture = portrait_value as Texture2D

	data_record_label.text = "%d cm      %d pts." % [
		int(round(float(entry.get("best_size", 0.0)))),
		int(entry.get("best_points", 0)),
	]

	data_point_label.text = _join_location_names(entry)
	data_lure_label.text = _join_lure_names(entry)

	var habitat_types: Variant = entry.get("habitat_types", PackedStringArray())
	if habitat_types is PackedStringArray:
		var habitats: PackedStringArray = habitat_types
		data_habitat_label.text = (
			", ".join(habitats) if not habitats.is_empty() else "---"
		)


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


func _update_hint_text() -> void:
	hints_list.select(_hint_index)
	hints_text_label.text = "%s\n\nReference text will be filled from your BOF4 screenshots." % HINT_TOPICS[_hint_index]


func _update_time_label() -> void:
	if not is_instance_valid(time_label):
		return
	# Temporary game-time source until a global save/play-time service exists.
	# Engine ticks keep counting from game launch and do not reset when this menu opens.
	var total_seconds: int = int(Time.get_ticks_msec() / 1000)
	var hours: int = total_seconds / 3600
	var minutes: int = (total_seconds % 3600) / 60
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
