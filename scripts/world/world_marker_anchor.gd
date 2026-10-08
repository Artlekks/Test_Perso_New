extends Node3D
class_name WorldMarkerAnchor

## Root-space overhead stance. Labels billboard; their translation never does.
## Keep public marker paths intact for existing interaction/request controllers.
var actor: Node3D
var height := 0.72
var markers: Array[Node3D] = []

func configure(owner_actor: Node3D, profile: WorldActorPresentationProfile) -> void:
	actor = owner_actor
	height = profile.marker_height
	for path in ["PromptLabel3D", "RequestMarker"]:
		var marker := actor.get_node_or_null(path) as Node3D
		if marker != null:
			markers.append(marker)
			marker.top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 245
	update_anchor()

func _process(_delta: float) -> void:
	update_anchor()

func update_anchor() -> void:
	if not is_instance_valid(actor): return
	global_transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3.UP * height)
	for marker in markers:
		if is_instance_valid(marker):
			marker.global_transform = global_transform
