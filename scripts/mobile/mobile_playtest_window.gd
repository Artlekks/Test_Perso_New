extends Node
## Fits authored UI coordinates into the gameplay viewport without resampling
## fonts or changing node paths. Short viewports scroll the same content.
var surface: Control
var bar: VScrollBar
var original_position: Vector2
var last_size := Vector2.ZERO
var content_min := Vector2.ZERO
var content_max := Vector2(640, 480)
var dragging := -1
var drag_y := 0.0
const MARGIN := 8.0

func configure(root_control: Control) -> void:
	surface = root_control
	original_position = surface.position
	bar = VScrollBar.new()
	bar.name = "MobileWindowScroll"
	bar.process_mode = Node.PROCESS_MODE_ALWAYS
	bar.value_changed.connect(_place)
	get_parent().add_child(bar)
	surface.visibility_changed.connect(_visibility_changed)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fit()

func _process(_delta: float) -> void:
	for view in surface.find_children("ResponsiveMenuSurface", "Control", true, false):
		if view.is_visible_in_tree():
			bar.visible = false
			return
	_visibility_changed_without_reset()
	if last_size != get_viewport().get_visible_rect().size: _fit()

func _fit() -> void:
	last_size = get_viewport().get_visible_rect().size
	content_min = Vector2.ZERO
	content_max = Vector2(640, 480)
	for child in surface.get_children():
		if child is Control:
			content_min = content_min.min(child.position)
			content_max = content_max.max(child.position + child.size)
	var height := content_max.y - content_min.y
	bar.min_value = 0
	bar.max_value = height
	bar.page = maxf(1, last_size.y - MARGIN * 2)
	bar.position = Vector2(last_size.x - 16, MARGIN)
	bar.size = Vector2(14, bar.page)
	bar.step = 1
	_visibility_changed()
	_place(bar.value)

func _visibility_changed_without_reset() -> void:
	bar.visible = surface.visible and bar.max_value > bar.page

func _visibility_changed() -> void:
	bar.visible = surface.visible and bar.max_value > bar.page
	if surface.visible: bar.value = 0

func _place(value: float) -> void:
	var height := content_max.y - content_min.y
	var top := maxf(MARGIN, (last_size.y - height) * 0.5)
	surface.position = Vector2(original_position.x, top - content_min.y - value)

func _input(event: InputEvent) -> void:
	if not bar.visible: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			bar.value += -32 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 32
			get_viewport().set_input_as_handled()
	# Touching the right scroll gutter never competes with menu A/B navigation.
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x >= last_size.x - 64:
			dragging = event.index
			drag_y = event.position.y
		elif not event.pressed and event.index == dragging: dragging = -1
	if event is InputEventScreenDrag and event.index == dragging:
		bar.value += drag_y - event.position.y
		drag_y = event.position.y
		get_viewport().set_input_as_handled()
