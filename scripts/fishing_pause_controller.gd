extends Node
class_name FishingPauseController

## Owns the manual Space-bar pause and its presentation.
##
## Important:
## - This node runs while the SceneTree is paused so the same key can resume.
## - It only unpauses pauses that IT created.
## - If another system already paused the tree (for example FishingMenu),
##   Space does nothing instead of stealing that system's pause ownership.
## - Pause presentation is isolated here: no camera/gameplay/menu dependency.

signal pause_changed(paused: bool)

const PauseTexture = preload(
	"res://assets/ui/Button_Pause.png"
)

const PAUSE_IMAGE_SCALE: float = 3.0
const PAUSE_DIM_ALPHA: float = 0.12
const PAUSE_CANVAS_LAYER: int = 100

var _pause_owned: bool = false

var _pause_canvas: CanvasLayer = null
var _pause_root: Control = null
var _pause_dim: ColorRect = null
var _pause_image: TextureRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_presentation()
	_set_pause_presentation_visible(false)


func _input(event: InputEvent) -> void:
	if not _is_space_toggle(event):
		return

	var tree := get_tree()
	if tree == null:
		return

	if _pause_owned:
		tree.paused = false
		_pause_owned = false
		_set_pause_presentation_visible(false)
		pause_changed.emit(false)
		get_viewport().set_input_as_handled()
		return

	# Another system already owns the pause. Leave it alone.
	if tree.paused:
		return

	tree.paused = true
	_pause_owned = true
	_set_pause_presentation_visible(true)
	pause_changed.emit(true)
	get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	# Never leave the application globally paused because this owner disappeared.
	if _pause_owned:
		var tree := get_tree()

		if tree != null:
			tree.paused = false

	_pause_owned = false
	_set_pause_presentation_visible(false)


func is_manual_pause_active() -> bool:
	return _pause_owned


func _build_pause_presentation() -> void:
	if _pause_canvas != null:
		return

	_pause_canvas = CanvasLayer.new()
	_pause_canvas.name = "ManualPauseCanvas"
	_pause_canvas.layer = PAUSE_CANVAS_LAYER
	add_child(_pause_canvas)

	_pause_root = Control.new()
	_pause_root.name = "PauseRoot"
	_pause_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.anchor_left = 0.0
	_pause_root.anchor_top = 0.0
	_pause_root.anchor_right = 1.0
	_pause_root.anchor_bottom = 1.0
	_pause_root.offset_left = 0.0
	_pause_root.offset_top = 0.0
	_pause_root.offset_right = 0.0
	_pause_root.offset_bottom = 0.0
	_pause_canvas.add_child(_pause_root)

	_pause_dim = ColorRect.new()
	_pause_dim.name = "PauseDim"
	_pause_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_dim.anchor_left = 0.0
	_pause_dim.anchor_top = 0.0
	_pause_dim.anchor_right = 1.0
	_pause_dim.anchor_bottom = 1.0
	_pause_dim.offset_left = 0.0
	_pause_dim.offset_top = 0.0
	_pause_dim.offset_right = 0.0
	_pause_dim.offset_bottom = 0.0
	_pause_dim.color = Color(
		0.0,
		0.0,
		0.0,
		PAUSE_DIM_ALPHA
	)
	_pause_root.add_child(_pause_dim)

	_pause_image = TextureRect.new()
	_pause_image.name = "PauseImage"
	_pause_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pause_image.texture = PauseTexture
	_pause_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pause_image.stretch_mode = TextureRect.STRETCH_SCALE

	var image_size := Vector2(
		float(PauseTexture.get_width()),
		float(PauseTexture.get_height())
	) * PAUSE_IMAGE_SCALE

	_pause_image.anchor_left = 0.5
	_pause_image.anchor_top = 0.5
	_pause_image.anchor_right = 0.5
	_pause_image.anchor_bottom = 0.5
	_pause_image.offset_left = -image_size.x * 0.5
	_pause_image.offset_top = -image_size.y * 0.5
	_pause_image.offset_right = image_size.x * 0.5
	_pause_image.offset_bottom = image_size.y * 0.5

	_pause_root.add_child(_pause_image)


func _set_pause_presentation_visible(visible: bool) -> void:
	if _pause_canvas == null:
		return

	_pause_canvas.visible = visible


func _is_space_toggle(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false

	var key_event := event as InputEventKey

	if not key_event.pressed or key_event.echo:
		return false

	return (
		key_event.keycode == KEY_SPACE
		or key_event.physical_keycode == KEY_SPACE
	)
