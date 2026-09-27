extends RefCounted

## Pass 3 page controller extracted from FishingMenu.
##
## The coordinator still owns scene references/state in this conservative
## pass. Keeping that ownership stable lets us modularize behavior without
## changing the scene graph, selector calibration, transitions or save/UI
## semantics during the architecture cleanup.

static func handle_help_input(menu, event: InputEvent) -> void:
	var step: int = menu._vertical_step(event)
	if step == 0:
		return

	menu._help_index = clampi(menu._help_index + step, 0, menu.HELP_TOPICS.size() - 1)
	menu.help_list.select(menu._help_index)
	menu.help_list.ensure_current_is_visible()
	menu._update_help_text()


static func update_help_text(menu) -> void:
	menu.help_list.select(menu._help_index)
	match menu._help_index:
		0:
			menu.help_text_label.text = "Casting\n\nK enters the cast sequence. Set power, then adjust the curve before release."
		1:
			menu.help_text_label.text = "Moving the lure\n\nUse the fishing controls to steer, reel and work the lure after it lands."
		2:
			menu.help_text_label.text = "Getting a bite\n\nWatch the fish and react to bite opportunities before the window closes."
		3:
			menu.help_text_label.text = "Reeling in a catch\n\nBalance reeling, steering and tension until the fish is exhausted."
		_:
			menu.help_text_label.text = "I returns to the previous menu."
