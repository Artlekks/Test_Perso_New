extends RefCounted
## Headless DisplayServer reports a 64x64 dummy window. Declare the phone canvas
## in fixtures instead of relying on production portrait scaling to hide it.
static func prepare(tree: SceneTree) -> void:
	if DisplayServer.get_name() != "headless": return
	tree.root.content_scale_size = Vector2i(390,844)
	tree.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	tree.root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
