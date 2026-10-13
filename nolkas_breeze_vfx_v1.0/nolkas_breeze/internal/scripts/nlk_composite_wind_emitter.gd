@tool
class_name NlkCompositeWindEmitter
extends NlkWeatherEmitter

@export_range(0.0, 2.0, 0.001, "or_greater") var amount_ratio: float = 1.0:
	set(value):
		amount_ratio = value
		for i in range(composees.size()):
			var c := composees[i]
			c.particles_amount = roundi(_default_amounts[i] * amount_ratio)

var composees: Array[NlkWeatherEmitter] = []
var _default_amounts: Array[int] = []


func _ready() -> void:
	for child in get_children():
		var emitter := child as NlkWeatherEmitter
		if emitter:
			composees.append(emitter)
			_default_amounts.append(emitter.particles_amount)


func _on_emitting_updated() -> void:
	for c in composees:
		c.emitting = emitting


func _on_area_updated() -> void:
	for c in composees:
		c.area = area


func _on_amount_updated() -> void:
	push_warning("Particles amount is not applicable on a composite effect. Use amount_ratio instead.")


func _on_speed_scale_updated() -> void:
	for c in composees:
		c.speed_scale = speed_scale
