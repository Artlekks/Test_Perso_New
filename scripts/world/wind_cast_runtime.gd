extends Node
## Non-invasive wind influence on fishing casts. A caster's existing
## active_bait_changed signal fires before perform_cast finishes assembling
## its air_path; therefore apply the modification on the deferred idle step.
## No caster/bait/camera/scene scripts are replaced.

const WindCastPath = preload("res://scripts/world/wind_cast_path.gd")
var _wind_enabled: bool = true


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_scan_existing_casters.call_deferred()


func _exit_tree() -> void:
	var callback: Callable = Callable(self, "_on_node_added")
	if get_tree().node_added.is_connected(callback):
		get_tree().node_added.disconnect(callback)


func _scan_existing_casters() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().root.find_children("Caster", "", true, false):
		_bind_caster(node)


func _on_node_added(node: Node) -> void:
	if node.name == "Caster":
		_bind_caster(node)


func _bind_caster(node: Node) -> void:
	if node == null or not node.has_signal("active_bait_changed"):
		return
	var callback: Callable = Callable(self, "_on_active_bait_changed")
	if not node.is_connected("active_bait_changed", callback):
		node.connect("active_bait_changed", callback)


func _on_active_bait_changed(bait: Node3D) -> void:
	if not _wind_enabled or not is_instance_valid(bait):
		return
	# Defer until Caster.perform_cast has assigned its final predicted path.
	_apply_to_bait.call_deferred(bait.get_instance_id())


func _apply_to_bait(instance_id: int) -> void:
	if not _wind_enabled:
		return
	var bait: Node3D = instance_from_id(instance_id) as Node3D
	if not is_instance_valid(bait) or not bait.is_inside_tree():
		return
	if not bait.has_method("is_cast_flying") or not bait.is_cast_flying():
		return
	# Late callbacks must not rewind a cast in progress.
	if float(bait.get("air_path_progress")) > 0.05:
		return
	var path_value: Variant = bait.get("air_path")
	if not path_value is PackedVector3Array:
		return
	var air_path: PackedVector3Array = path_value
	if air_path.size() < 3:
		return
	var wind: Node = get_node_or_null("/root/GameWind")
	if wind == null or not wind.has_method("get_snapshot"):
		return
	var snapshot: Dictionary = wind.call("get_snapshot")
	if not bool(snapshot.get("available", false)):
		return
	var wind_value: Variant = snapshot.get("velocity_xz", Vector2.ZERO)
	if not wind_value is Vector2:
		return
	var wind_velocity: Vector2 = wind_value
	# Only the path's intermediate points are affected. No snapping/resetting
	# of travel progress; no modification to the final landing point.
	bait.set("air_path", WindCastPath.bend_path(air_path, wind_velocity))
