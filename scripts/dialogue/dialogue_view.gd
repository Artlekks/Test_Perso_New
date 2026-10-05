extends CanvasLayer
class_name DialogueView

## Presentation-only view for the reusable dialogue runtime.
##
## Normal conversations keep the compact v2 box. A choice line expands upward
## only while choices are visible, leaving the established dialogue footprint
## unchanged for every existing NPC conversation.

@onready var root: Control = $Root
@onready var dialogue_panel: Panel = $Root/DialoguePanel
@onready var portrait_frame: Panel = $Root/DialoguePanel/PortraitFrame
@onready var portrait_rect: TextureRect = $Root/DialoguePanel/PortraitFrame/Portrait
@onready var speaker_label: Label = $Root/DialoguePanel/SpeakerLabel
@onready var body_label: Label = $Root/DialoguePanel/BodyLabel
@onready var choice_label: Label = $Root/DialoguePanel/ChoiceLabel
@onready var hint_label: Label = $Root/DialoguePanel/HintLabel

const TEXT_LEFT_WITH_PORTRAIT: float = 84.0
const TEXT_LEFT_WITHOUT_PORTRAIT: float = 18.0
const PANEL_NORMAL_TOP: float = 356.0
const PANEL_CHOICE_TOP: float = 326.0
const PANEL_BOTTOM: float = 442.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide_dialogue()


func present(snapshot: Dictionary) -> void:
	if root == null:
		return
	var active := bool(snapshot.get("active", false))
	root.visible = active
	if not active:
		return

	var portrait = snapshot.get("portrait", null)
	var has_portrait := portrait is Texture2D
	portrait_frame.visible = has_portrait
	portrait_rect.texture = portrait if has_portrait else null
	_apply_portrait_layout(has_portrait)

	var choices: Array = snapshot.get("choices", [])
	var has_choices := not choices.is_empty()
	_apply_choice_layout(has_choices)

	var speaker_name := str(snapshot.get("speaker_name", ""))
	speaker_label.text = speaker_name
	speaker_label.visible = not speaker_name.is_empty()
	body_label.text = str(snapshot.get("text", ""))

	choice_label.visible = has_choices
	if has_choices:
		choice_label.text = _format_choices(
			choices,
			int(snapshot.get("selected_choice_index", -1))
		)
	else:
		choice_label.text = ""

	var is_last := bool(snapshot.get("is_last_line", false))
	var can_cancel := bool(snapshot.get("allow_cancel", true))
	if has_choices:
		hint_label.text = "W/S : Select    K : Choose"
	elif is_last:
		hint_label.text = "K : Close"
	else:
		hint_label.text = "K : Next"
	if can_cancel:
		hint_label.text += "    I : Back"


func _apply_portrait_layout(has_portrait: bool) -> void:
	var text_left := TEXT_LEFT_WITH_PORTRAIT if has_portrait else TEXT_LEFT_WITHOUT_PORTRAIT
	speaker_label.offset_left = text_left
	body_label.offset_left = text_left
	choice_label.offset_left = text_left


func _apply_choice_layout(has_choices: bool) -> void:
	if dialogue_panel == null:
		return
	dialogue_panel.offset_top = PANEL_CHOICE_TOP if has_choices else PANEL_NORMAL_TOP
	dialogue_panel.offset_bottom = PANEL_BOTTOM
	if has_choices:
		body_label.offset_bottom = 50.0
		choice_label.offset_top = 52.0
		choice_label.offset_bottom = 94.0
		hint_label.offset_top = 97.0
		hint_label.offset_bottom = 111.0
	else:
		body_label.offset_bottom = 62.0
		hint_label.offset_top = 65.0
		hint_label.offset_bottom = 80.0


func _format_choices(choices: Array, selected_index: int) -> String:
	var lines := PackedStringArray()
	for index in range(choices.size()):
		var raw_choice = choices[index]
		if not (raw_choice is Dictionary):
			continue
		var choice: Dictionary = raw_choice
		var enabled := bool(choice.get("enabled", true))
		var marker := "> " if index == selected_index and enabled else "  "
		var label := str(choice.get("text", ""))
		if not enabled:
			label = "[%s]" % label
		lines.append(marker + label)
	return "\n".join(lines)


func hide_dialogue() -> void:
	if portrait_rect != null:
		portrait_rect.texture = null
	if choice_label != null:
		choice_label.text = ""
	if dialogue_panel != null:
		dialogue_panel.offset_top = PANEL_NORMAL_TOP
		dialogue_panel.offset_bottom = PANEL_BOTTOM
	if root != null:
		root.visible = false
