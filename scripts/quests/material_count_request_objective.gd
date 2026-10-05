extends Node
class_name MaterialCountRequestObjective

## Read-only objective adapter for material-backed requests.
##
## It watches BeachGatheringInventory-style APIs/signals, exposes progress, and
## never removes materials or writes saves. Turn-in/reward policy stays with the
## owning NPC/request system.

signal progress_changed(current_count: int, required_count: int, complete: bool)

@export var material_id: StringName = &"sea_glass"
@export var required_count: int = 3

var _inventory: Node = null
var _last_count: int = -1


func configure(inventory: Node) -> void:
	if _inventory == inventory:
		return
	_disconnect_inventory()
	_inventory = inventory
	_connect_inventory()
	_emit_if_changed(true)


func get_current_count() -> int:
	if _inventory == null or not _inventory.has_method("get_count"):
		return 0
	return maxi(0, int(_inventory.call("get_count", material_id)))


func get_required_count() -> int:
	return maxi(1, required_count)


func is_complete() -> bool:
	return get_current_count() >= get_required_count()


func get_progress_snapshot() -> Dictionary:
	return progress_snapshot_for_count(get_current_count(), get_required_count())


static func progress_snapshot_for_count(current: int, required: int) -> Dictionary:
	var safe_required := maxi(1, required)
	var safe_current := maxi(0, current)
	return {
		"current": safe_current,
		"required": safe_required,
		"remaining": maxi(0, safe_required - safe_current),
		"complete": safe_current >= safe_required,
		"progress_text": "%d/%d" % [mini(safe_current, safe_required), safe_required],
	}


func _connect_inventory() -> void:
	if _inventory == null:
		return
	if _inventory.has_signal("material_changed"):
		var callback := Callable(self, "_on_material_changed")
		if not _inventory.is_connected("material_changed", callback):
			_inventory.connect("material_changed", callback)
	if _inventory.has_signal("changed"):
		var changed_callback := Callable(self, "_on_inventory_changed")
		if not _inventory.is_connected("changed", changed_callback):
			_inventory.connect("changed", changed_callback)


func _disconnect_inventory() -> void:
	if _inventory == null or not is_instance_valid(_inventory):
		_inventory = null
		return
	if _inventory.has_signal("material_changed"):
		var callback := Callable(self, "_on_material_changed")
		if _inventory.is_connected("material_changed", callback):
			_inventory.disconnect("material_changed", callback)
	if _inventory.has_signal("changed"):
		var changed_callback := Callable(self, "_on_inventory_changed")
		if _inventory.is_connected("changed", changed_callback):
			_inventory.disconnect("changed", changed_callback)
	_inventory = null


func _on_material_changed(changed_material_id: StringName, _count: int) -> void:
	if changed_material_id != material_id:
		return
	_emit_if_changed()


func _on_inventory_changed(_snapshot: Dictionary) -> void:
	_emit_if_changed()


func _emit_if_changed(force: bool = false) -> void:
	var current := get_current_count()
	if not force and current == _last_count:
		return
	_last_count = current
	progress_changed.emit(current, get_required_count(), is_complete())


func _exit_tree() -> void:
	_disconnect_inventory()
