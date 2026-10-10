extends RefCounted
## World projection is independent of device chrome and menu canvases.
const SIZE := Vector2i(640, 480)
const MENU_SIZE := Vector2i(640, 864)

static func prepare(game: Node) -> void:
	# Preserve authored camera FOV, aspect policy, offsets and HUD positions.
	for camera in game.find_children("*", "Camera3D", true, false):
		if not camera.has_meta("mobile_original_projection"):
			camera.set_meta("mobile_original_projection", {"aspect": camera.keep_aspect, "fov": camera.fov, "size": camera.size})
