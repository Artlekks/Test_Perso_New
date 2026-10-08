extends Node3D
const CATALOG = preload("res://data/npc/catalog/npc_catalog.tres")
var actors: Array[CatalogueNPCActor] = []
var angle := 0.0
var focus := Vector3.ZERO
var selected := -1

func _ready() -> void:
	var entries: Array = Array(CATALOG.entries)
	entries.sort_custom(func(a, b):
		if a.importance_tier != b.importance_tier: return a.importance_tier < b.importance_tier
		return String(a.id) < String(b.id))
	var columns := ceili(sqrt(float(CATALOG.entries.size())))
	var rows := ceili(float(CATALOG.entries.size()) / columns)
	$Camera3D.size = maxf(7.5, rows * 3.0 + 2)
	for index in range(CATALOG.entries.size()):
		var entry = entries[index]
		var actor := entry.scene.instantiate() as CatalogueNPCActor
		actor.position = Vector3((index % columns - (columns - 1) * 0.5) * 2.5, 0, (floori(float(index) / columns) - (rows - 1) * 0.5) * 3.0)
		add_child(actor)
		actors.append(actor)
		var footprint := MeshInstance3D.new()
		footprint.name = "ColliderPreview"
		var capsule := CapsuleMesh.new()
		capsule.radius = entry.profile.collider_profile.radius
		capsule.height = entry.profile.collider_profile.height
		footprint.mesh = capsule
		footprint.position.y = capsule.height * 0.5
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.2, 0.9, 1, 0.25)
		footprint.material_override = material
		footprint.visible = false
		actor.add_child(footprint)
		var label := Label3D.new()
		label.text = "Tier " + entry.importance_tier + " / " + ", ".join(entry.placeholder_roles) + "\n" + entry.profile.development_name + "\n" + String(entry.id) + "\n" + entry.art_status
		label.font_size = 24
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = actor.position + Vector3(0, 0.95, 0)
		add_child(label)
	_update_camera()

func _process(delta: float) -> void:
	var axis := Input.get_axis("cam_left", "cam_right")
	angle += axis * delta
	_update_camera()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			for actor in actors: actor.set_preview_pose("walk")
		if event.keycode == KEY_I:
			for actor in actors: actor.set_preview_pose("idle")
		if event.keycode in [KEY_EQUAL, KEY_MINUS]:
			$Camera3D.size = clampf($Camera3D.size + (-0.5 if event.keycode == KEY_EQUAL else 0.5), 2, 32)
		if event.keycode == KEY_TAB:
			selected = posmod(selected + 1, actors.size())
			focus = actors[selected].position
			$Camera3D.size = 2.5
		if event.keycode == KEY_R:
			for actor in ([actors[selected]] if selected >= 0 else actors):
				var poses: Array = actor.visual_profile.directional_animation_prefixes.keys()
				if not poses.is_empty():
					var presenter: GroundPresentation = actor.get_node("GroundPresentation")
					actor.set_preview_pose(poses[posmod(poses.find(presenter.directional_pose) + 1, poses.size())])
					continue
				var sprite: AnimatedSprite3D = actor.get_node("GroundPresentation/VisualAnchor/AnimatedSprite3D")
				var names := sprite.sprite_frames.get_animation_names()
				sprite.play(names[posmod(names.find(sprite.animation) + 1, names.size())])
		if event.keycode == KEY_C:
			for actor in actors:
				var mesh := actor.get_node_or_null("ColliderPreview") as MeshInstance3D
				if mesh != null: mesh.visible = not mesh.visible

func _update_camera() -> void:
	$Camera3D.position = focus + Vector3(sin(angle) * 18, 14, cos(angle) * 18)
	$Camera3D.look_at(focus)
