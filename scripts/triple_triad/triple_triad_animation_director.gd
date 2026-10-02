extends Node

const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")

# The opening deal starts readable, then accelerates hard into cards 3/4/5.
# This gives the FF-style one-two-then-boom-boom-boom cadence without making
# the whole intro feel slow.
@export_range(0.05, 1.0, 0.01) var deal_travel_seconds: float = 0.40
@export_range(0.01, 0.5, 0.01) var deal_stagger_start_seconds: float = 0.16
@export_range(0.01, 0.5, 0.01) var deal_stagger_end_seconds: float = 0.018

# Once a card is committed to a grid cell it should move decisively. The first
# leg still reads as the card leaving the hand, while the final drop snaps in.
@export_range(0.05, 1.0, 0.01) var placement_lift_seconds: float = 0.20
@export_range(0.05, 1.0, 0.01) var placement_drop_seconds: float = 0.12
@export_range(0.0, 1.0, 0.01) var placement_hold_seconds: float = 0.02


func deal_hands(player_views: Array, opponent_views: Array, hand_step_y: float) -> void:
	var count: int = mini(player_views.size(), opponent_views.size())
	for index in range(count):
		var player_view: Control = player_views[index]
		var opponent_view: Control = opponent_views[index]
		_prepare_deal_card(player_view, index)
		_prepare_deal_card(opponent_view, index)

	for index in range(count):
		_start_deal_card(player_views[index], index, hand_step_y)
		_start_deal_card(opponent_views[index], index, hand_step_y)
		if index < count - 1:
			var progress: float = 0.0 if count <= 2 else float(index) / float(count - 2)
			var stagger: float = lerpf(deal_stagger_start_seconds, deal_stagger_end_seconds, progress)
			await get_tree().create_timer(stagger, true).timeout

	await get_tree().create_timer(deal_travel_seconds + 0.05, true).timeout


func animate_placement(
	presentation_root: Control,
	source_view: Control,
	target_view: Control,
	card_definition,
	card_owner: int,
	rotation_quarters: int = 0,
	rank_bonus: int = 0
) -> void:
	if presentation_root == null or source_view == null or target_view == null:
		return

	var ghost: Control = CardViewScene.instantiate()
	presentation_root.add_child(ghost)
	ghost.configure(card_definition, card_owner, false, false, rotation_quarters, rank_bonus)
	ghost.set_selected(false)
	ghost.z_index = 1200

	# IMPORTANT: hand cards are locally scaled, while board cards inherit their
	# visual scale from the Board container. Using target_view.scale therefore
	# made the placement ghost jump to 1.0x just before it settled, then shrink
	# back to the board's ~0.64x visual scale when the real card appeared. Work
	# in visual/global scale instead so the travelling card remains the same size.
	var source_visual_scale: Vector2 = _visual_scale(source_view)
	var target_visual_scale: Vector2 = _visual_scale(target_view)
	# CardView sets a centered pivot in _ready() for flip animations. Placement
	# ghosts need a top-left pivot so their global position matches the hand/board
	# slots exactly while scaling.
	ghost.pivot_offset = Vector2.ZERO
	ghost.scale = source_visual_scale
	ghost.global_position = source_view.global_position
	source_view.visible = false

	var target_position: Vector2 = target_view.global_position
	var lift_position := Vector2(
		target_position.x,
		-ghost.size.y * source_visual_scale.y - 20.0
	)

	var tween: Tween = ghost.create_tween()
	var lift_move = tween.tween_property(
		ghost,
		"global_position",
		lift_position,
		placement_lift_seconds
	)
	lift_move.set_trans(Tween.TRANS_QUART)
	lift_move.set_ease(Tween.EASE_OUT)

	var drop_move = tween.tween_property(
		ghost,
		"global_position",
		target_position,
		placement_drop_seconds
	)
	drop_move.set_trans(Tween.TRANS_QUAD)
	drop_move.set_ease(Tween.EASE_IN)
	var drop_scale = tween.parallel().tween_property(
		ghost,
		"scale",
		target_visual_scale,
		placement_drop_seconds
	)
	drop_scale.set_trans(Tween.TRANS_QUAD)
	drop_scale.set_ease(Tween.EASE_IN)
	await tween.finished

	if placement_hold_seconds > 0.0:
		await get_tree().create_timer(placement_hold_seconds, true).timeout
	ghost.queue_free()


func _visual_scale(control: Control) -> Vector2:
	# get_global_transform() is explicitly typed here because Godot 4.7's
	# static analyzer cannot infer a stable type from Control.global_transform
	# in this helper when warnings/errors are promoted during reload.
	var global_xform: Transform2D = control.get_global_transform()
	return Vector2(global_xform.x.length(), global_xform.y.length())


func _prepare_deal_card(view: Control, index: int) -> void:
	view.position = Vector2(0.0, 520.0 + float(index) * 10.0)
	view.modulate = Color(1, 1, 1, 0)


func _start_deal_card(view: Control, index: int, hand_step_y: float) -> void:
	var target_position := Vector2(0.0, float(index) * hand_step_y)
	var tween: Tween = view.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", target_position, deal_travel_seconds)
	tween.parallel().tween_property(view, "modulate", Color.WHITE, deal_travel_seconds * 0.92)


func reset_transition_fade(fade: ColorRect) -> void:
	if fade == null:
		return
	fade.visible = false
	fade.modulate = Color(1, 1, 1, 0)


func fade_to_cover(fade: ColorRect, duration_seconds: float) -> void:
	if fade == null:
		return
	fade.visible = true
	fade.modulate = Color(1, 1, 1, 0)
	var tween: Tween = fade.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		fade,
		"modulate",
		Color.WHITE,
		maxf(duration_seconds, 0.0)
	)
	await tween.finished


func fade_from_cover(fade: ColorRect, duration_seconds: float) -> void:
	if fade == null:
		return
	fade.visible = true
	fade.modulate = Color.WHITE
	var tween: Tween = fade.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		fade,
		"modulate",
		Color(1, 1, 1, 0),
		maxf(duration_seconds, 0.0)
	)
	await tween.finished
	fade.visible = false


func wait_for_settle(duration_seconds: float) -> void:
	if duration_seconds <= 0.0:
		return
	await get_tree().create_timer(duration_seconds, true).timeout
