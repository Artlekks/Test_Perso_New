extends Node
class_name FishingCatchCountRequestObjective

## Read-only objective adapter for fishing-journal catch-count requests.
##
## FishingJournalService remains the only owner of permanent catch records. This
## adapter observes one species record, exposes deterministic request progress,
## and never writes fishing progress, inventory, rewards, or save state.

signal progress_changed(current_count: int, required_count: int, complete: bool)

@export var species_id: StringName = &"sea_bass"
@export var required_count: int = 3

var _journal: Node = null
var _last_count: int = -1


func configure(journal: Node) -> void:
	if _journal == journal:
		return
	_disconnect_journal()
	_journal = journal
	_connect_journal()
	_emit_if_changed(true)


func get_current_count() -> int:
	if _journal == null or not _journal.has_method("get_record_snapshot"):
		return 0
	var raw_snapshot = _journal.call("get_record_snapshot", String(species_id))
	if not (raw_snapshot is Dictionary):
		return 0
	return maxi(0, int((raw_snapshot as Dictionary).get("caught_count", 0)))


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


func _connect_journal() -> void:
	if _journal == null or not _journal.has_signal("changed"):
		return
	var callback := Callable(self, "_on_journal_changed")
	if not _journal.is_connected("changed", callback):
		_journal.connect("changed", callback)


func _disconnect_journal() -> void:
	if _journal == null or not is_instance_valid(_journal):
		_journal = null
		return
	if _journal.has_signal("changed"):
		var callback := Callable(self, "_on_journal_changed")
		if _journal.is_connected("changed", callback):
			_journal.disconnect("changed", callback)
	_journal = null


func _on_journal_changed() -> void:
	_emit_if_changed()


func _emit_if_changed(force: bool = false) -> void:
	var current := get_current_count()
	if not force and current == _last_count:
		return
	_last_count = current
	progress_changed.emit(current, get_required_count(), is_complete())


func _exit_tree() -> void:
	_disconnect_journal()
