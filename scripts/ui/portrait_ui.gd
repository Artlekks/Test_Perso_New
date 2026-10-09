extends RefCounted
## Shared presentation only. Controllers retain input, transactions and ownership.
const SIZE := Vector2i(640, 864)
const FONT = preload("res://assets/fonts/BOF_Font_Refined.fnt")
const PANEL = preload("res://assets/ui/Panel.png")
const PanelStyle = preload("res://scripts/dialogue/dialogue_panel_style.gd")
const MIN_FONT := 18
static var _panel: StyleBoxTexture

static func panel_style() -> StyleBoxTexture:
	if _panel == null: _panel = PanelStyle.create(PANEL)
	return _panel

static func mobile(node: Node) -> bool:
	var ancestor := node
	while ancestor != null:
		if ancestor.name == "GameplayViewport": return ancestor.get_meta("input_hint_device", "touch") == "touch"
		ancestor = ancestor.get_parent()
	return OS.has_feature("web") or OS.get_name() in ["iOS", "Android"]

static func hints(node: Node, text: String) -> String:
	if not mobile(node): return text
	return text.replace("ENTER", "START").replace("K:", "A:").replace("I:", "B:").replace("J:", "MENU:").replace("Q/E", "L/R").replace("WASD", "Stick")

static func rect(node: Control, box: Rect2) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	node.position = box.position
	node.size = box.size
	node.scale = Vector2.ONE

static func typography(root: Node) -> void:
	if root is Control:
		root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		root.add_theme_font_override("font", FONT)
		root.add_theme_font_size_override("font_size", MIN_FONT)
	if root is Label:
		root.scale = Vector2.ONE
		root.add_theme_constant_override("outline_size", 0)
		root.add_theme_color_override("font_color", Color.WHITE)
	for child in root.get_children(): typography(child)

static func panel(parent: Node, name: String, box: Rect2) -> Panel:
	var result := Panel.new()
	result.name = name
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.add_theme_stylebox_override("panel", panel_style())
	parent.add_child(result)
	rect(result, box)
	parent.move_child(result, 0)
	return result
