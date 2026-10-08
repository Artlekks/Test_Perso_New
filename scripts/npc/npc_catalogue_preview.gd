extends Node3D
const CATALOG = preload("res://data/npc/catalog/npc_catalog.tres")
var actors: Array[CatalogueNPCActor] = []
var angle := 0.0

func _ready() -> void:
	for index in range(CATALOG.entries.size()):
		var entry = CATALOG.entries[index]
		var actor := entry.scene.instantiate() as CatalogueNPCActor
		actor.position = Vector3((index % 4) * 2.5 - 3.75, 0, (index / 4) * 3.0 - 1.5)
		add_child(actor)
		actors.append(actor)
		var label := Label3D.new()
		label.text = entry.profile.development_name + "\n" + String(entry.id)
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
			$Camera3D.size = clampf($Camera3D.size + (-0.5 if event.keycode == KEY_EQUAL else 0.5), 2, 14)

func _update_camera() -> void:
	$Camera3D.position = Vector3(sin(angle) * 9, 7, cos(angle) * 9)
	$Camera3D.look_at(Vector3.ZERO)
