extends Node

const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")

@export_range(0.05, 1.0, 0.01) var deal_travel_seconds: float = 0.44
@export_range(0.01, 0.5, 0.01) var deal_stagger_seconds: float = 0.15
@export_range(0.05, 1.0, 0.01) var placement_lift_seconds: float = 0.34
@export_range(0.05, 1.0, 0.01) var placement_drop_seconds: float = 0.20
@export_range(0.0, 1.0, 0.01) var placement_hold_seconds: float = 0.04


func deal_hands(player_views: Array, opponent_views: Array, hand_step_y: float) -> void:
	var count: int = mini(player_views.size(), opponent_views.size())
	for index in range(count):
		var player_view: Control = player_views[index]
		var opponent_view: Control = opponent_views[index]
		_prepare_deal_card(player_view, index)
		_prepare_deal_card(opponent_view, index)
		_start_deal_card(player_view, index, hand_step_y)
		_start_deal_card(opponent_view, index, hand_step_y)
		await get_tree().create_timer(deal_stagger_seconds, true).timeout
	await get_tree().create_timer(deal_travel_seconds + 0.05, true).timeout


func animate_placement(
	presentation_root: Control,
	source_view: Control,
	target_view: Control,
	card_definition,
	card_owner: int
) -> void:
	if presentation_root == null or source_view == null or target_view == null:
		return

	var ghost: Control = CardViewScene.instantiate()
	presentation_root.add_child(ghost)
	ghost.configure(card_definition, card_owner, false)
	ghost.set_selected(false)
	ghost.z_index = 500
	ghost.global_position = source_view.global_position
	ghost.pivot_offset = ghost.size * 0.5
	source_view.visible = false

	var target_position: Vector2 = target_view.global_position
	var lift_position := Vector2(
		target_position.x,
		-ghost.size.y - 20.0
	)

	var tween: Tween = ghost.create_tween()
	var lift_move = tween.tween_property(
		ghost,
		"global_position",
		lift_position,
		placement_lift_seconds
	)
	lift_move.set_trans(Tween.TRANS_QUINT)
	lift_move.set_ease(Tween.EASE_OUT)
	var lift_scale = tween.parallel().tween_property(
		ghost,
		"scale",
		Vector2(1.06, 1.06),
		placement_lift_seconds
	)
	lift_scale.set_trans(Tween.TRANS_QUINT)
	lift_scale.set_ease(Tween.EASE_OUT)

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
		Vector2.ONE,
		placement_drop_seconds
	)
	drop_scale.set_trans(Tween.TRANS_QUAD)
	drop_scale.set_ease(Tween.EASE_IN)
	await tween.finished

	if placement_hold_seconds > 0.0:
		await get_tree().create_timer(placement_hold_seconds, true).timeout
	ghost.queue_free()


func _prepare_deal_card(view: Control, index: int) -> void:
	view.position = Vector2(0.0, 520.0 + float(index) * 10.0)
	view.modulate = Color(1, 1, 1, 0)


func _start_deal_card(view: Control, index: int, hand_step_y: float) -> void:
	var target_position := Vector2(0.0, float(index) * hand_step_y)
	var tween: Tween = view.create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", target_position, deal_travel_seconds)
	tween.parallel().tween_property(view, "modulate", Color.WHITE, deal_travel_seconds * 0.88)
