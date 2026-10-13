@tool
@abstract
class_name NlkWeatherEmitter
extends Node3D

## If the true, the particles are emitted
@export var emitting: bool = true:
	set(value):
		emitting = value
		_on_emitting_updated.call_deferred()

## The 3D area covered by the vfx.
@export var area: Vector3 = Vector3.ONE * 50:
	set(value):
		area = value
		_on_area_updated.call_deferred()

## The maximum amount of particles that can be emitted.
@export_range(1, 1000, 1, "or_greater") var particles_amount: int = 50:
	set(value):
		particles_amount = maxi(1, value)
		_on_amount_updated.call_deferred()

@export_range(0, 2.0, 0.01, "or_greater") var speed_scale: float = 1.0:
	set(value):
		speed_scale = value
		_on_speed_scale_updated.call_deferred()


@abstract
func _on_emitting_updated() -> void


@abstract
func _on_area_updated() -> void


@abstract
func _on_amount_updated() -> void

@abstract
func _on_speed_scale_updated() -> void
