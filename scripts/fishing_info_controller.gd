extends Node

@export var encounter: Node
@export var info_view: Node	
@export var screen_transition: Node

func _ready() -> void:
	encounter.fish_resistance_started.connect(
		_on_fish_resistance_started
	)

	encounter.fish_spent.connect(
		_on_fish_spent
	)

	encounter.hook_off.connect(
		_on_hook_off
	)

	encounter.line_broken.connect(
		_on_line_broken
	)

	screen_transition.covered.connect(
		_on_screen_covered
	)
	
func _on_fish_resistance_started() -> void:
	info_view.show_message(
		"The fish is thrashing about!"
	)

	# The fish jump is intentionally fired from the SAME code path as the message.
	# If the message is visible, the presentation event is guaranteed to be sent.
	# Deferred execution gives FishingLineView one frame to refresh its exact
	# water-entry point before the visual resolves its screen anchor.
	var thrash_visual: Node = get_node_or_null("../FishThrashVisual")
	if thrash_visual != null and thrash_visual.has_method("play_resistance_jump"):
		thrash_visual.call_deferred("play_resistance_jump")


func _on_fish_spent() -> void:
	info_view.show_message(
		"The fish has calmed down."
	)

func _on_hook_off() -> void:
	info_view.show_message(
		"The fish got away with the lure!",
		2.0,
		FishingInfoView.Priority.CRITICAL
	)


func _on_line_broken() -> void:
	info_view.show_message(
		"Your line broke!",
		2.0,
		FishingInfoView.Priority.CRITICAL
	)

func _on_screen_covered() -> void:
	info_view.clear()
