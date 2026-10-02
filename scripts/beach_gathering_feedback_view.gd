extends CanvasLayer
class_name BeachGatheringFeedbackView

@onready var root: Control = $Root
@onready var panel: Panel = $Root/Panel
@onready var message_label: Label = $Root/Panel/MessageLabel
@onready var progress_label: Label = $Root/Panel/ProgressLabel

var _queue: Array[Dictionary] = []
var _showing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root.hide()


func enqueue_gathered(
	display_name: String,
	amount: int,
	total_owned: int,
	circuit_progress: int = 0,
	circuit_total: int = 0
) -> void:
	_queue.append({
		"display_name": display_name,
		"amount": maxi(1, amount),
		"total_owned": maxi(0, total_owned),
		"circuit_progress": maxi(0, circuit_progress),
		"circuit_total": maxi(0, circuit_total),
	})
	if not _showing:
		_show_next()


func clear_queue() -> void:
	_queue.clear()
	_showing = false
	root.hide()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		root.hide()
		return

	_showing = true
	var entry: Dictionary = _queue.pop_front()
	message_label.text = "+%d %s    TOTAL %d" % [
		int(entry.get("amount", 1)),
		str(entry.get("display_name", "Material")),
		int(entry.get("total_owned", 0)),
	]

	var gathered: int = int(entry.get("circuit_progress", 0))
	var circuit_total: int = int(entry.get("circuit_total", 0))
	if circuit_total > 0:
		progress_label.text = "BEACH VISIT   %d / %d NODES" % [
			gathered,
			circuit_total,
		]
	else:
		progress_label.text = ""

	root.show()
	panel.modulate.a = 0.0
	panel.position.y = 10.0

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(panel, "modulate:a", 1.0, 0.10)
	tween.parallel().tween_property(panel, "position:y", 0.0, 0.14)
	tween.tween_interval(0.80)
	tween.tween_property(panel, "modulate:a", 0.0, 0.22)
	tween.finished.connect(_on_feedback_finished)


func _on_feedback_finished() -> void:
	_show_next()
