extends CanvasLayer
class_name FishingCardMakerMenu

signal opened
signal closed

const ROW_COUNT := 5
const ROW_START_Y := 133.0
const ROW_HEIGHT := 31.0

const ICON_RAMHORN := preload("res://assets/ui/card_maker/cards/ramhorn.png")
const ICON_GLOW_RAM := preload("res://assets/ui/card_maker/cards/glow_ram.png")
const ICON_SAND_HOUND := preload("res://assets/ui/card_maker/cards/sand_hound.png")
const ICON_STRAY_CAT := preload("res://assets/ui/card_maker/cards/stray_cat.png")
const ICON_HARBOR_CAT := preload("res://assets/ui/card_maker/cards/harbor_cat.png")

const READY_COLOR := Color(0.16, 0.10, 0.13, 1.0)
const BLOCKED_COLOR := Color(0.40, 0.35, 0.36, 1.0)
const SELECTED_COLOR := Color(0.12, 0.07, 0.10, 1.0)

@onready var root: Control = $Root
@onready var zenny_label: Label = $Root/Panel/ZennyLabel
@onready var selection_bar: ColorRect = $Root/Panel/SelectionBar
@onready var selection_cursor: Polygon2D = $Root/Panel/SelectionCursor
@onready var mode_label: Label = $Root/Panel/ModeLabel
@onready var requirement_label: Label = $Root/Panel/RequirementLabel
@onready var owned_label: Label = $Root/Panel/OwnedLabel
@onready var status_label: Label = $Root/Panel/StatusLabel
@onready var help_label: Label = $Root/Panel/HelpLabel
@onready var selected_name_label: Label = $Root/Panel/SelectedNameLabel
@onready var selected_description_label: Label = $Root/Panel/SelectedDescriptionLabel
@onready var selected_preview: TextureRect = $Root/Panel/SelectedPreview
@onready var selected_small_preview: TextureRect = $Root/Panel/SelectedSmallPreview
@onready var fee_value_label: Label = $Root/Panel/FeeValueLabel
@onready var confirm_panel: Panel = $Root/ConfirmPanel
@onready var confirm_prompt: Label = $Root/ConfirmPanel/PromptLabel
@onready var confirm_choice: Label = $Root/ConfirmPanel/ChoiceLabel

@onready var row_name_labels: Array[Label] = [
	$Root/Panel/Rows/Row1Name,
	$Root/Panel/Rows/Row2Name,
	$Root/Panel/Rows/Row3Name,
	$Root/Panel/Rows/Row4Name,
	$Root/Panel/Rows/Row5Name,
]
@onready var row_cost_labels: Array[Label] = [
	$Root/Panel/Rows/Row1Cost,
	$Root/Panel/Rows/Row2Cost,
	$Root/Panel/Rows/Row3Cost,
	$Root/Panel/Rows/Row4Cost,
	$Root/Panel/Rows/Row5Cost,
]
@onready var row_owned_labels: Array[Label] = [
	$Root/Panel/Rows/Row1Owned,
	$Root/Panel/Rows/Row2Owned,
	$Root/Panel/Rows/Row3Owned,
	$Root/Panel/Rows/Row4Owned,
	$Root/Panel/Rows/Row5Owned,
]

@onready var row_icons: Array[TextureRect] = [
	$Root/Panel/Rows/Row1Icon,
	$Root/Panel/Rows/Row2Icon,
	$Root/Panel/Rows/Row3Icon,
	$Root/Panel/Rows/Row4Icon,
	$Root/Panel/Rows/Row5Icon,
]

var _service: FishingCardMakerService = null
var _entries: Array[Dictionary] = []
var _index: int = 0
var _open: bool = false
var _previous_pause: bool = false
var _input_ready: bool = false
var _confirm_active: bool = false
var _confirm_yes: bool = false
var _message: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.visible = false
	confirm_panel.visible = false

	preload("res://scripts/mobile/responsive_menu_surface.gd").attach(self, root, "card_maker")

func configure(service: FishingCardMakerService) -> void:
	_service = service
	# The menu is hidden while binding. Avoid eager recipe evaluation here:
	# FishingSessionServices may still be waiting for its deferred SceneTree
	# attachment. open_menu() performs the authoritative refresh when the
	# player actually interacts with the Card Maker.
	if _open:
		_refresh()


func is_open() -> bool:
	return _open


func open_menu() -> bool:
	if _open or _service == null:
		return false

	_entries = _service.get_all_recipe_snapshots()
	if _entries.is_empty():
		return false

	var tree := get_tree()
	if tree == null or tree.paused:
		return false

	_previous_pause = tree.paused
	_open = true
	_input_ready = false
	_confirm_active = false
	_confirm_yes = false
	_message = ""
	_index = clampi(_index, 0, _entries.size() - 1)
	root.visible = true
	confirm_panel.visible = false
	_refresh()

	tree.paused = true
	call_deferred("_arm_input")
	opened.emit()
	return true


func close_menu() -> void:
	if not _open:
		return

	_open = false
	_input_ready = false
	_confirm_active = false
	confirm_panel.visible = false
	root.visible = false

	var tree := get_tree()
	if tree != null:
		tree.paused = _previous_pause
	closed.emit()


func _arm_input() -> void:
	_input_ready = true


func _input(event: InputEvent) -> void:
	if not _open or not _input_ready or not _pressed(event):
		return

	if _confirm_active:
		_handle_confirmation_input(event)
		return

	if _is_back(event):
		close_menu()
		_accept_input()
		return

	var step: int = _vertical_step(event)
	if step != 0:
		_move_selection(step)
		_accept_input()
		return

	if _is_confirm(event):
		_begin_confirmation()
		_accept_input()


func _move_selection(step: int) -> void:
	if _entries.is_empty():
		return
	_index = posmod(_index + step, _entries.size())
	_message = ""
	_refresh()


func _begin_confirmation() -> void:
	var quote: Dictionary = _current_quote()
	if quote.is_empty():
		return
	if not bool(quote.get("can_make", false)):
		_message = _reason_text(quote)
		_refresh()
		return

	_confirm_active = true
	_confirm_yes = false
	confirm_panel.visible = true
	_refresh_confirmation(quote)


func _handle_confirmation_input(event: InputEvent) -> void:
	if _is_back(event):
		_cancel_confirmation()
		_accept_input()
		return

	if (
		_is_left(event)
		or _is_right(event)
		or _is_up(event)
		or _is_down(event)
	):
		_confirm_yes = not _confirm_yes
		_refresh_confirmation(_current_quote())
		_accept_input()
		return

	if not _is_confirm(event):
		return

	if _confirm_yes:
		_execute_current_recipe()
	else:
		_cancel_confirmation()
	_accept_input()


func _cancel_confirmation() -> void:
	_confirm_active = false
	_confirm_yes = false
	confirm_panel.visible = false


func _execute_current_recipe() -> void:
	var quote: Dictionary = _current_quote()
	if quote.is_empty() or _service == null:
		_cancel_confirmation()
		return

	var recipe_id := StringName(str(quote.get("recipe_id", "")))
	var result: Dictionary = _service.make_card(recipe_id, &"card_maker_npc")
	_cancel_confirmation()

	if bool(result.get("success", false)):
		_message = "%s created.  Owned x%d." % [
			str(result.get("card_display_name", quote.get("card_display_name", "Card"))),
			int(result.get("card_quantity_after", 1)),
		]
	else:
		_message = _reason_text(result if not result.is_empty() else quote)
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return

	if _service != null:
		_entries = _service.get_all_recipe_snapshots()

	if _entries.is_empty():
		_index = 0
		zenny_label.text = "Zenny ---"
		status_label.text = "Card Maker unavailable."
		for i in range(ROW_COUNT):
			_clear_row(i)
		selection_bar.visible = false
		selection_cursor.visible = false
		selected_name_label.text = ""
		selected_description_label.text = ""
		selected_preview.texture = null
		selected_small_preview.texture = null
		fee_value_label.text = "---"
		return

	_index = clampi(_index, 0, _entries.size() - 1)
	var selected: Dictionary = _entries[_index]
	zenny_label.text = "Zenny %d" % int(selected.get("zenny_owned", 0))

	for i in range(ROW_COUNT):
		if i >= _entries.size():
			_clear_row(i)
			continue
		var quote: Dictionary = _entries[i]
		var is_ready: bool = bool(quote.get("can_make", false))
		var row_color: Color = READY_COLOR if is_ready else BLOCKED_COLOR
		if i == _index:
			row_color = SELECTED_COLOR if is_ready else BLOCKED_COLOR
		var display_name: String = str(
			quote.get("card_display_name", quote.get("display_name", "Card"))
		)
		row_name_labels[i].text = display_name
		row_owned_labels[i].text = "x%d" % int(quote.get("card_quantity_before", 0))
		row_cost_labels[i].text = _short_cost_text(quote)
		row_icons[i].texture = _icon_for_card(display_name)
		row_name_labels[i].modulate = row_color
		row_owned_labels[i].modulate = row_color
		row_cost_labels[i].modulate = row_color

	selection_bar.visible = true
	selection_cursor.visible = true
	selection_bar.position.y = ROW_START_Y + float(_index) * ROW_HEIGHT
	selection_cursor.position.y = ROW_START_Y + 15.0 + float(_index) * ROW_HEIGHT

	var selected_name: String = str(
		selected.get("card_display_name", selected.get("display_name", "Card"))
	)
	selected_name_label.text = selected_name
	selected_description_label.text = str(selected.get("description", ""))
	selected_preview.texture = _icon_for_card(selected_name)
	selected_small_preview.texture = selected_preview.texture

	var duplicate_print: bool = bool(selected.get("is_duplicate_print", false))
	mode_label.text = "DUPLICATE PRINT" if duplicate_print else "FIRST CREATION"
	owned_label.text = "Owned x%d" % int(selected.get("card_quantity_before", 0))
	var fish_required: int = int(selected.get("fish_required", 0))
	var fish_owned: int = int(selected.get("fish_owned", 0))
	var fish_name: String = str(selected.get("fish_display_name", selected.get("fish_species_id", "Fish")))
	var fee: int = int(selected.get("zenny_required", 0))
	if fish_required > 0:
		requirement_label.text = "%s\n%d / %d" % [
			fish_name,
			fish_owned,
			fish_required,
		]
	else:
		requirement_label.text = "No specimen\nneeded"
	fee_value_label.text = "%dz" % fee

	if not _message.is_empty():
		status_label.text = _message
	else:
		status_label.text = _reason_text(selected)
	help_label.text = ""


func _clear_row(index: int) -> void:
	row_name_labels[index].text = ""
	row_cost_labels[index].text = ""
	row_owned_labels[index].text = ""
	row_icons[index].texture = null


func _current_quote() -> Dictionary:
	if _entries.is_empty() or _index < 0 or _index >= _entries.size():
		return {}
	return _entries[_index]


func _short_cost_text(quote: Dictionary) -> String:
	var fish_required: int = int(quote.get("fish_required", 0))
	var fee: int = int(quote.get("zenny_required", 0))
	if fish_required > 0:
		return "1 fish + %dz" % fee
	return "%dz" % fee



func _icon_for_card(display_name: String) -> Texture2D:
	match display_name:
		"Ramhorn":
			return ICON_RAMHORN
		"Glow Ram":
			return ICON_GLOW_RAM
		"Sand Hound":
			return ICON_SAND_HOUND
		"Stray Cat":
			return ICON_STRAY_CAT
		"Harbor Cat":
			return ICON_HARBOR_CAT
		_:
			return null


func _reason_text(quote: Dictionary) -> String:
	var reason: String = str(quote.get("reason", ""))
	match reason:
		"ok", "completed":
			return "Ready."
		"card_game_locked":
			return "Find the Saltworn Card Case before using the Card Maker."
		"not_enough_fish":
			return "You need the matching fish specimen first."
		"not_enough_zenny":
			return "Not enough Zenny."
		"duel_rank_too_low":
			return "Duel Rank %d required." % int(quote.get("minimum_duel_rank", 1))
		"pending_recovery_blocked":
			return "A previous Card Maker transaction still needs recovery."
		"triple_triad_game_unavailable", "triple_triad_card_api_unavailable":
			return "Triple Triad backend unavailable."
		"card_grant_failed":
			return "Card creation failed; the fish and Zenny were restored."
		"fishing_inventory_save_failed":
			return "Card creation cancelled because the inventory could not be saved."
		"unknown_recipe", "recipe_disabled":
			return "This recipe is unavailable."
		_:
			if bool(quote.get("can_make", false)):
				return "Ready."
			return "Card Maker unavailable."


func _refresh_confirmation(quote: Dictionary) -> void:
	if quote.is_empty():
		confirm_prompt.text = "Create this card?"
	else:
		var card_name: String = str(
			quote.get("card_display_name", quote.get("display_name", "Card"))
		)
		var fish_required: int = int(quote.get("fish_required", 0))
		var fish_name: String = str(quote.get("fish_display_name", "fish"))
		var fee: int = int(quote.get("zenny_required", 0))
		var cost_text: String = "%dz" % fee
		if fish_required > 0:
			cost_text = "%d %s + %dz" % [fish_required, fish_name, fee]
		confirm_prompt.text = "Create %s?\nCost: %s" % [card_name, cost_text]

	confirm_choice.text = (
		"> YES <      NO"
		if _confirm_yes
		else "YES      > NO <"
	)


func _pressed(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.pressed and not key_event.echo


func _is_key(event: InputEvent, keycode: int) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == keycode or key_event.physical_keycode == keycode


func _is_confirm(event: InputEvent) -> bool:
	return _is_key(event, KEY_K) or _is_key(event, KEY_ENTER)


func _is_back(event: InputEvent) -> bool:
	return _is_key(event, KEY_I) or _is_key(event, KEY_ESCAPE)


func _is_up(event: InputEvent) -> bool:
	return _is_key(event, KEY_W) or _is_key(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _is_key(event, KEY_S) or _is_key(event, KEY_DOWN)


func _is_left(event: InputEvent) -> bool:
	return _is_key(event, KEY_A) or _is_key(event, KEY_LEFT)


func _is_right(event: InputEvent) -> bool:
	return _is_key(event, KEY_D) or _is_key(event, KEY_RIGHT)


func _vertical_step(event: InputEvent) -> int:
	if _is_up(event):
		return -1
	if _is_down(event):
		return 1
	return 0


func _accept_input() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
