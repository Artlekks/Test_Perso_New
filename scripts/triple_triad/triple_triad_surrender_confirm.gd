extends Control
class_name TripleTriadSurrenderConfirm

@onready var selector: Polygon2D = $Panel/Selector
@onready var yes_label: Label = $Panel/YesLabel
@onready var no_label: Label = $Panel/NoLabel

var _yes_selected: bool = false


func _ready() -> void:
	var ui = preload("res://scripts/ui/portrait_ui.gd")
	ui.typography(self)
	$Panel.add_theme_stylebox_override("panel", ui.panel_style())
	$Panel/HelpLabel.text = ui.hints(self, "A/D: Choose   K: Confirm   I: Back")
	visible = false
	_refresh()


func open_confirm() -> void:
	# Safe default: an accidental extra K does not surrender.
	_yes_selected = false
	visible = true
	_refresh()


func close_confirm() -> void:
	visible = false


func move_selection(step: int) -> void:
	if step == 0:
		return
	_yes_selected = not _yes_selected
	_refresh()


func is_yes_selected() -> bool:
	return _yes_selected


func _refresh() -> void:
	if not is_instance_valid(selector):
		return
	yes_label.modulate = (
		Color(1, 1, 1, 1)
		if _yes_selected
		else Color(0.58, 0.58, 0.58, 1)
	)
	no_label.modulate = (
		Color(1, 1, 1, 1)
		if not _yes_selected
		else Color(0.58, 0.58, 0.58, 1)
	)
	selector.position = Vector2(
		112.0 if _yes_selected else 224.0,
		84.0
	)
