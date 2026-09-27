extends RefCounted

## Pass 3 page controller extracted from FishingMenu.
##
## The coordinator still owns scene references/state in this conservative
## pass. Keeping that ownership stable lets us modularize behavior without
## changing the scene graph, selector calibration, transitions or save/UI
## semantics during the architecture cleanup.

static func handle_hints_input(menu, event: InputEvent) -> void:
	if menu._hint_detail_open:
		return

	if menu._is_confirm(event):
		menu._open_hint_detail()


static func configure_hint_list_visuals(menu) -> void:
	# Seven categories fit in the Hint panel. Hide Godot's native scroll bar.
	if is_instance_valid(menu.hints_list):
		var native_scrollbar: VScrollBar = menu.hints_list.get_v_scroll_bar()
		if is_instance_valid(native_scrollbar):
			native_scrollbar.modulate = Color(1.0, 1.0, 1.0, 0.0)
			native_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func update_hint_selector(menu) -> void:
	menu.hints_list.select(menu._hint_index)
	menu.hints_list.ensure_current_is_visible()
	menu.call_deferred("_place_hints_selector")


static func update_hint_text(menu) -> void:
	menu.hints_list.select(menu._hint_index)
	menu._update_hint_selector()

	menu._hint_text_line_start = 0
	menu._hint_text_lines = menu._wrap_hint_text(
		menu.HINT_DETAIL_TEXT[menu._hint_index],
		menu.HINT_TEXT_MAX_WIDTH_PX
	)
	menu._refresh_hint_text_page()


static func open_hint_detail(menu) -> void:
	if menu._hint_detail_open:
		return

	menu._hint_detail_open = true
	menu._hint_text_line_start = 0
	menu.hints_text_panel.visible = true
	menu._set_hint_detail_colors(true)
	menu._update_hint_text()
	menu._sync_selector_visibility()


static func close_hint_detail(menu) -> void:
	if not menu._hint_detail_open:
		return

	menu._hint_detail_open = false
	menu._hint_text_line_start = 0
	menu.hints_text_panel.visible = false
	menu.hints_scroll_arrow.visible = false
	menu._set_hint_detail_colors(false)
	menu._update_hint_selector()
	menu._sync_selector_visibility()


static func set_hint_detail_colors(menu, detail_open: bool) -> void:
	var normal_color := Color(1.0, 1.0, 1.0, 1.0)
	var inactive_color: Color = menu.disabled_text_tint

	for item_index in range(menu.hints_list.item_count):
		var item_color := normal_color
		if detail_open and item_index != menu._hint_index:
			item_color = inactive_color
		menu.hints_list.set_item_custom_fg_color(item_index, item_color)

	menu.hints_list.queue_redraw()


static func scroll_hint_text(menu, step: int) -> void:
	if not menu._hint_detail_open or step == 0:
		return

	if step > 0:
		if (
			menu._hint_text_line_start + menu.HINT_TEXT_LINES_PER_PAGE
			< menu._hint_text_lines.size()
		):
			menu._hint_text_line_start += menu.HINT_TEXT_LINES_PER_PAGE
	else:
		menu._hint_text_line_start = maxi(
			menu._hint_text_line_start - menu.HINT_TEXT_LINES_PER_PAGE,
			0
		)

	menu._refresh_hint_text_page()


static func refresh_hint_text_page(menu) -> void:
	if menu._hint_text_lines.is_empty():
		menu.hints_text_label.text = ""
		menu.hints_scroll_arrow.visible = false
		return

	var end_index: int = mini(
		menu._hint_text_line_start + menu.HINT_TEXT_LINES_PER_PAGE,
		menu._hint_text_lines.size()
	)

	var visible_lines := PackedStringArray()
	for line_index in range(menu._hint_text_line_start, end_index):
		visible_lines.append(menu._hint_text_lines[line_index])

	menu.hints_text_label.text = "\n".join(visible_lines)
	menu.hints_scroll_arrow.visible = (
		menu._hint_detail_open
		and end_index < menu._hint_text_lines.size()
	)


static func wrap_hint_text(
	menu,
	value: String,
	max_width_px: int
) -> Array[String]:
	var result: Array[String] = []

	for paragraph in value.split("\n", true):
		if paragraph.is_empty():
			result.append("")
			continue

		var current_line := ""
		for word in paragraph.split(" ", false):
			var candidate := word
			if not current_line.is_empty():
				candidate = current_line + " " + word

			if (
				current_line.is_empty()
				or menu._bof_text_advance_px(candidate) <= max_width_px
			):
				current_line = candidate
			else:
				result.append(current_line)
				current_line = word

		if not current_line.is_empty():
			result.append(current_line)

	return result
