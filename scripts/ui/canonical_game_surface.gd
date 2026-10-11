extends RefCounted
## World projection is independent of device chrome and menu canvases.
const SIZE := Vector2i(640, 480)
const MENU_SIZE := Vector2i(640, 864)

static func prepare(game: Node) -> void:
	# Preserve authored camera FOV, aspect policy, offsets and HUD positions.
	for camera in game.find_children("*", "Camera3D", true, false):
		if not camera.has_meta("mobile_original_projection"):
			camera.set_meta("mobile_original_projection", {"aspect": camera.keep_aspect, "fov": camera.fov, "size": camera.size})

const MOBILE_LANDSCAPE_SIZE := Vector2i(960,480)

static func configure_css_window(window: Window, css_size: Vector2i) -> void:
	# Web backing pixels can be 3x CSS pixels on an iPhone. Only the shell
	# scales with DPI; its controls remain authored in actual CSS-sized units.
	if window.content_scale_size == css_size and window.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS: return
	window.content_scale_size = css_size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE

static func resize_mobile_world(game: Node, viewport: SubViewport, resolution: Vector2i) -> void:
	if viewport.size == resolution: return
	var previous := viewport.size
	var rig := game.get_node_or_null("CameraRig") if is_instance_valid(game) else null
	if rig != null and rig.fishing_player_anchor != Vector2.ZERO:
		# KEEP_HEIGHT reveals additional horizontal world about the same optical
		# center. Remap a cached reference, never rotate/translate the live camera.
		rig.fishing_player_anchor.x = .5+(rig.fishing_player_anchor.x-.5)*float(previous.x)/resolution.x
	viewport.size = resolution
