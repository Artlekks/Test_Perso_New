extends Node

signal animation_finished(animation_name: StringName)

@export var sprite: AnimatedSprite3D


func _ready() -> void:
	if sprite != null:
		sprite.animation_finished.connect(_on_animation_finished)


func play(animation_name: StringName) -> void:
	if sprite == null:
		return

	if not sprite.sprite_frames.has_animation(animation_name):
		return

	if sprite.animation == animation_name and sprite.is_playing():
		return

	sprite.flip_h = false
	sprite.play(animation_name)


func play_directional(base_name: String, direction: String) -> void:
	play(StringName(base_name + "_" + direction))


func _on_animation_finished() -> void:
	animation_finished.emit(sprite.animation)
	
func is_locomotion_animation() -> bool:
	if sprite == null:
		return false

	var current := String(sprite.animation)

	return (
		current.begins_with("Idle_")
		or current.begins_with("Walk_")
	)

func play_backwards(animation_name: StringName) -> void:
	if sprite == null:
		return

	if not sprite.sprite_frames.has_animation(animation_name):
		return

	sprite.flip_h = false
	sprite.play_backwards(animation_name)


func show_animation_frame(animation_name: StringName, frame_index: int = 0) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(animation_name):
		return

	var frame_count: int = sprite.sprite_frames.get_frame_count(animation_name)
	if frame_count <= 0:
		return

	sprite.flip_h = false
	sprite.play(animation_name)
	sprite.pause()
	sprite.frame = clampi(frame_index, 0, frame_count - 1)
	sprite.frame_progress = 0.0
