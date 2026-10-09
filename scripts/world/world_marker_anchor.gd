extends Node3D
class_name WorldMarkerAnchor

## Physical root-space anchor plus camera-facing screen presentation.
## A world-height point has strong lateral parallax in the exploration camera;
## project the visual above the feet on a screen-aligned plane instead. This
## never changes the physical anchor or the actor. Public marker paths remain
## state sources for existing interaction/request controllers.
var actor: Node3D
var height := 0.72
var markers: Array[Node3D] = []
var profile: WorldActorPresentationProfile
var source_labels: Array[Label3D] = []
var visuals: Array[Label] = []
var canvas: CanvasLayer

func configure(owner_actor: Node3D, profile: WorldActorPresentationProfile) -> void:
	actor = owner_actor
	self.profile = profile
	height = profile.marker_height
	if canvas != null:
		update_anchor()
		return
	canvas = CanvasLayer.new()
	canvas.name = "MarkerCanvas"
	canvas.layer = 1 # World feedback, below gameplay/dialogue HUDs.
	add_child(canvas)
	for path in ["PromptLabel3D", "RequestMarker"]:
		var marker := actor.get_node_or_null(path) as Node3D
		if marker != null:
			markers.append(marker)
			marker.top_level = true
			var label := marker as Label3D
			if label == null: label = marker.get_node_or_null("Label3D") as Label3D
			if label != null:
				# Keep visibility/text readable by controllers, without rendering a
				# second icon. Layer exclusion does not mutate their request state.
				label.layers = 0
				source_labels.append(label)
				var visual := Label.new()
				visual.name = path + "Visual"
				visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
				visual.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				visual.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				visual.add_theme_color_override("font_color", Color.WHITE)
				visuals.append(visual)
				canvas.add_child(visual)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 245
	update_anchor()

func _process(_delta: float) -> void:
	update_anchor()

func update_anchor() -> void:
	if not is_instance_valid(actor): return
	if profile != null: height = profile.marker_height
	global_transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3.UP * height)
	for marker in markers:
		if is_instance_valid(marker):
			marker.global_transform = global_transform
	var camera := get_viewport().get_camera_3d()
	for i in source_labels.size():
		var source := source_labels[i]
		var visual := visuals[i]
		visual.visible = is_instance_valid(source) and source.is_visible_in_tree() and camera != null
		if not visual.visible: continue
		if camera.is_position_behind(actor.global_position):
			visual.hide()
			continue
		_sync_style(source, visual)
		# This is a projection sample, not a moving Node3D/anchor. Camera-up
		# gives exactly vertical screen placement even with camera pitch/roll.
		var feet := camera.unproject_position(actor.global_position)
		var above := camera.unproject_position(actor.global_position + camera.global_basis.y * height)
		var pixel := camera.unproject_position(actor.global_position + camera.global_basis.x * source.pixel_size)
		var world_pixel_scale := feet.distance_to(pixel)
		visual.scale = Vector2.ONE * world_pixel_scale
		visual.size = visual.get_minimum_size()
		visual.position = above - visual.size * world_pixel_scale * 0.5

func _sync_style(source: Label3D, visual: Label) -> void:
	var style := [source.text, source.font, source.font_size, source.outline_size, source.outline_modulate]
	if visual.get_meta("source_style", []) != style:
		visual.text = source.text
		visual.add_theme_font_override("font", source.font if source.font != null else ThemeDB.fallback_font)
		visual.add_theme_font_size_override("font_size", source.font_size)
		visual.add_theme_constant_override("outline_size", source.outline_size)
		visual.add_theme_color_override("font_outline_color", source.outline_modulate)
		visual.set_meta("source_style", style)
	visual.modulate = source.modulate
