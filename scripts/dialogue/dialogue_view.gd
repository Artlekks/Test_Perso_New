extends CanvasLayer
class_name DialogueView

## Presentation-only view for the reusable dialogue runtime.
##
## Shared larger bitmap typography; measured content expands the box upward.

@onready var root: Control = $Root
@onready var dialogue_panel: Panel = $Root/DialoguePanel
@onready var portrait_frame: Panel = $Root/DialoguePanel/PortraitFrame
@onready var portrait_rect: TextureRect = $Root/DialoguePanel/PortraitFrame/Portrait
@onready var speaker_label: Label = $Root/DialoguePanel/SpeakerLabel
@onready var content_scroll: ScrollContainer = $Root/DialoguePanel/ContentScroll
@onready var body_label: Label = $Root/DialoguePanel/ContentScroll/TextStack/BodyLabel
@onready var choice_label: Label = $Root/DialoguePanel/ContentScroll/TextStack/ChoiceLabel
@onready var hint_label: Label = $Root/DialoguePanel/HintLabel

const TEXT_LEFT_WITH_PORTRAIT: float = 84.0
const TEXT_LEFT_WITHOUT_PORTRAIT: float = 18.0
const BOTTOM_MARGIN: float = 38.0
const TEXT_TOP: float = 40.0
const FOOTER_HEIGHT: float = 30.0
const PanelStyle = preload("res://scripts/dialogue/dialogue_panel_style.gd")
const PANEL_ATLAS = preload("res://assets/ui/Panel.png")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var authored_style := PanelStyle.create(PANEL_ATLAS)
	dialogue_panel.add_theme_stylebox_override("panel", authored_style)
	portrait_frame.add_theme_stylebox_override("panel", authored_style)
	root.resized.connect(_reflow)
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
	_reflow()


func _apply_portrait_layout(has_portrait: bool) -> void:
	var text_left := TEXT_LEFT_WITH_PORTRAIT if has_portrait else TEXT_LEFT_WITHOUT_PORTRAIT
	speaker_label.offset_left = text_left
	content_scroll.offset_left = text_left


func _text_height(label: Label, width: float, text: String) -> float:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var height := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size,
		-1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	var line_height := font.get_multiline_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).y
	var line_count := maxi(1, roundi(height / maxf(line_height, 1.0)))
	return ceilf(height + (line_count - 1) * label.get_theme_constant("line_spacing"))

func _reflow() -> void:
	if dialogue_panel == null:
		return
	var view_size := get_viewport().get_visible_rect().size
	var panel_width := minf(512.0, view_size.x - 32.0)
	# Reserve the scrollbar width before measuring, avoiding a wrap feedback loop.
	var text_width := panel_width - content_scroll.offset_left - 28.0
	var body_height := _text_height(body_label, text_width, body_label.text)
	var choice_height := _text_height(choice_label, text_width, choice_label.text) if choice_label.visible else 0.0
	var content_height := body_height + (8.0 + choice_height if choice_label.visible else 0.0)
	var panel_height := minf(maxf(100.0, TEXT_TOP + content_height + FOOTER_HEIGHT), view_size.y - BOTTOM_MARGIN - 24.0)
	dialogue_panel.position = Vector2((view_size.x - panel_width) * 0.5, view_size.y - BOTTOM_MARGIN - panel_height)
	dialogue_panel.size = Vector2(panel_width, panel_height)
	speaker_label.offset_right = panel_width - 20.0
	content_scroll.offset_top = TEXT_TOP
	content_scroll.offset_right = panel_width - 20.0
	content_scroll.offset_bottom = panel_height - FOOTER_HEIGHT
	hint_label.position = Vector2(18.0, panel_height - 24.0)
	hint_label.size = Vector2(panel_width - 38.0, 18.0)
	body_label.custom_minimum_size.y = body_height
	choice_label.custom_minimum_size.y = choice_height
	content_scroll.scroll_vertical = 0
	# Keep the selected choice visible if unusually long authored text scrolls.
	if choice_label.visible:
		var lines := choice_label.text.split("\n")
		for index in range(lines.size()):
			if lines[index].begins_with("> "):
				var through_selected := "\n".join(lines.slice(0, index + 1))
				var selected_bottom := body_height + 8.0 + _text_height(choice_label, text_width, through_selected)
				content_scroll.set_deferred("scroll_vertical", maxi(0, ceili(selected_bottom - content_scroll.size.y)))
				break


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
	if root != null:
		root.visible = false
