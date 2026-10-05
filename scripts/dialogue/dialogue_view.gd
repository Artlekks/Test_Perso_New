extends CanvasLayer
class_name DialogueView

## Presentation-only view for the reusable dialogue runtime.
##
## v2 adds optional speaker portraits while keeping the dialogue runtime itself
## independent from NPC/gameplay logic.

@onready var root: Control = $Root
@onready var portrait_frame: Panel = $Root/DialoguePanel/PortraitFrame
@onready var portrait_rect: TextureRect = $Root/DialoguePanel/PortraitFrame/Portrait
@onready var speaker_label: Label = $Root/DialoguePanel/SpeakerLabel
@onready var body_label: Label = $Root/DialoguePanel/BodyLabel
@onready var hint_label: Label = $Root/DialoguePanel/HintLabel

const TEXT_LEFT_WITH_PORTRAIT: float = 84.0
const TEXT_LEFT_WITHOUT_PORTRAIT: float = 18.0


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

	var speaker_name := str(snapshot.get("speaker_name", ""))
	speaker_label.text = speaker_name
	speaker_label.visible = not speaker_name.is_empty()
	body_label.text = str(snapshot.get("text", ""))

	var is_last := bool(snapshot.get("is_last_line", false))
	var can_cancel := bool(snapshot.get("allow_cancel", true))
	if is_last:
		hint_label.text = "K : Close"
	else:
		hint_label.text = "K : Next"
	if can_cancel:
		hint_label.text += "    I : Back"


func _apply_portrait_layout(has_portrait: bool) -> void:
	var text_left := TEXT_LEFT_WITH_PORTRAIT if has_portrait else TEXT_LEFT_WITHOUT_PORTRAIT
	speaker_label.offset_left = text_left
	body_label.offset_left = text_left


func hide_dialogue() -> void:
	if portrait_rect != null:
		portrait_rect.texture = null
	if root != null:
		root.visible = false
