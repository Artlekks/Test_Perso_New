extends Node3D
class_name BeachGatheringCircuit

@export var circuit_id: StringName = &"ocean_2_beach_visit"

var _nodes: Array[BeachGatheringNode3D] = []


func _ready() -> void:
	_collect_nodes()
	_register_visit()


func get_node_count() -> int:
	return _nodes.size()


func get_yield_snapshot() -> Dictionary:
	var yields: Dictionary = {}
	for node in _nodes:
		if node == null:
			continue
		var key: String = String(node.material_id)
		yields[key] = int(yields.get(key, 0)) + maxi(1, node.amount)
	return {
		"circuit_id": String(circuit_id),
		"node_count": _nodes.size(),
		"yields": yields,
	}


func reset_for_qa() -> void:
	if not OS.is_debug_build():
		return
	for node in _nodes:
		if node != null:
			node.reset_gather_node()
	var services := _find_session_services()
	if (
		services != null
		and services.has_method("reset_beach_gathering_circuit_progress")
	):
		services.call(
			"reset_beach_gathering_circuit_progress",
			circuit_id
		)


func _collect_nodes() -> void:
	_nodes.clear()
	var found := find_children(
		"*",
		"",
		true,
		false
	)
	for child in found:
		if child is BeachGatheringNode3D:
			_nodes.append(child as BeachGatheringNode3D)

	for index in range(_nodes.size()):
		var node: BeachGatheringNode3D = _nodes[index]
		node.configure_circuit(
			circuit_id,
			StringName("%s_%02d" % [node.name, index])
		)


func _register_visit() -> void:
	var services := _find_session_services()
	if (
		services == null
		or not services.has_method("register_beach_gathering_circuit")
	):
		return
	services.call(
		"register_beach_gathering_circuit",
		circuit_id,
		_nodes.size()
	)


func _find_session_services() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var services := tree.root.get_node_or_null(
		"FishingSessionServices"
	)
	if services != null:
		return services

	var scene := tree.current_scene
	if scene == null:
		return null
	var fishing := scene.find_child("Fishing", true, false)
	if fishing != null:
		var candidate = fishing.get("session_services")
		if candidate is Node:
			return candidate
	return null
