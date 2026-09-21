extends CanvasLayer
class_name FishingTechniqueView

@onready var label: Label = $Root/TechniqueLabel

@export var display_time: float = 0.65
@export var fade_time: float = 0.15

var _tween: Tween = null


func _ready() -> void:
	label.hide()


func show_tech(level: int) -> void:
	if level < 1 or level > 4:
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	label.text = "TEC. %d" % level
	label.modulate.a = 1.0
	label.show()

	_tween = create_tween()
	_tween.tween_interval(display_time)
	_tween.tween_property(
		label,
		"modulate:a",
		0.0,
		fade_time
	)
	_tween.tween_callback(_hide)


func clear() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = null
	_hide()


func _hide() -> void:
	label.hide()
	label.modulate.a = 1.0
