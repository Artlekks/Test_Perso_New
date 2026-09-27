extends RefCounted

## Pass 3 page controller extracted from FishingMenu.
##
## The coordinator still owns scene references/state in this conservative
## pass. Keeping that ownership stable lets us modularize behavior without
## changing the scene graph, selector calibration, transitions or save/UI
## semantics during the architecture cleanup.

static func handle_equip_input(menu, event: InputEvent) -> void:
	if menu._equip_focus == menu.EquipFocus.SLOT:
		var slot_step: int = menu._vertical_step(event)
		if slot_step != 0:
			menu._equip_slot_index = clampi(menu._equip_slot_index + slot_step, 0, 1)
			menu._equip_accessory_index = 0
			menu._equip_window_start = 0
			menu._refresh_equip_page()
			menu._update_equip_slot_selector()
			return

		if menu._horizontal_step(event) > 0 or menu._is_confirm(event):
			menu._equip_focus = menu.EquipFocus.ACCESSORY
			menu._refresh_equip_selection()
			menu._sync_selector_visibility()
			return

		return

	var accessory_step: int = menu._vertical_step(event)
	if accessory_step != 0 and not menu._equip_entries.is_empty():
		menu._equip_accessory_index = clampi(
			menu._equip_accessory_index + accessory_step,
			0,
			menu._equip_entries.size() - 1
		)
		menu._refresh_equip_selection()
		return

	if menu._horizontal_step(event) < 0:
		menu._equip_focus = menu.EquipFocus.SLOT
		menu._refresh_equip_selection()
		menu._sync_selector_visibility()
		return

	if menu._is_confirm(event):
		menu._equip_selected_accessory()


static func refresh_equip_page(menu) -> void:
	menu.equip_slot_list.clear()

	var rod_name: String = "---"
	var lure_name: String = "---"
	if is_instance_valid(menu._loadout):
		var rod: RodData = menu._loadout.get_selected_rod()
		var lure: BaitData = menu._loadout.get_selected_lure()
		if rod != null:
			rod_name = rod.rod_name
		if lure != null:
			lure_name = lure.display_name

	menu.equip_slot_list.add_item(rod_name)
	menu.equip_slot_list.add_item(lure_name)
	menu.equip_rod_slot_label.text = rod_name
	menu.equip_lure_slot_label.text = lure_name
	menu.equip_slot_list.select(menu._equip_slot_index)
	menu._update_equip_slot_selector()

	menu._rebuild_equip_entries()
	menu._refresh_equip_selection()


static func qa_fake_tackle_count(menu, tackle_id: StringName) -> int:
	# Stable pseudo-random-looking quantity for menu layout testing.
	# It does not touch FishingInventory and stays the same each time the menu
	# opens, so quantities do not visibly flicker around between visits.
	var value: int = abs(String(tackle_id).hash())
	return (value % 99) + 1


static func rebuild_equip_entries(menu) -> void:
	menu._equip_entries.clear()
	menu.equip_accessory_list.clear()

	if menu._tackle_catalog == null:
		return

	if menu._equip_slot_index == 0:
		for rod in menu._tackle_catalog.rods:
			if rod == null:
				continue
			var count: int = 1
			if is_instance_valid(menu._inventory):
				count = menu._inventory.get_rod_count(rod.rod_id)
			if count <= 0:
				if not menu.show_full_tackle_catalog_for_testing:
					continue
				count = menu._qa_fake_tackle_count(rod.rod_id)
			menu._equip_entries.append({"kind": "rod", "resource": rod, "count": count})
	else:
		if menu._tackle_catalog.lure_catalog != null:
			for lure in menu._tackle_catalog.lure_catalog.lures:
				if lure == null:
					continue
				var count: int = 1
				if is_instance_valid(menu._inventory):
					count = menu._inventory.get_lure_count(lure.lure_id)
				if count <= 0:
					if not menu.show_full_tackle_catalog_for_testing:
						continue
					count = menu._qa_fake_tackle_count(lure.lure_id)
				menu._equip_entries.append({"kind": "lure", "resource": lure, "count": count})

	if menu._equip_entries.is_empty():
		menu._equip_accessory_index = 0
		menu._equip_window_start = 0
	else:
		menu._equip_accessory_index = clampi(
			menu._equip_accessory_index,
			0,
			menu._equip_entries.size() - 1
		)

	menu._sync_equip_selector_window()
	menu._refresh_equip_visible_rows()
	menu._update_equip_scroll_thumb()
	menu._update_equip_accessory_counter()
	menu._update_equipped_accessory_highlight()
	menu.call_deferred("_place_equip_right_selector")


static func format_accessory_row(menu, display_name: String, _count: int) -> String:
	# Names and quantities are deliberately rendered separately.
	# Putting both into one ItemList string makes Godot replace the clipped
	# right edge with "..." when the row is wider than the control.
	return display_name


static func bof_text_advance_px(menu, value: String) -> int:
	var width_px := 0
	for character_index in range(value.length()):
		var character := value.substr(character_index, 1)
		if character == "I" or character == "i" or character == "l":
			width_px += menu.BOF_NARROW_ADVANCE_PX
		else:
			width_px += menu.BOF_STANDARD_ADVANCE_PX
	return width_px


static func refresh_equip_selection(menu) -> void:
	menu.equip_slot_list.select(menu._equip_slot_index)
	menu._update_equip_slot_selector()

	if not menu._equip_entries.is_empty():
		menu._sync_equip_selector_window()
		menu._refresh_equip_visible_rows()
		menu._update_equip_scroll_thumb()

	menu.call_deferred("_place_equip_right_selector")

	if menu._equip_focus == menu.EquipFocus.SLOT:
		menu.equip_slot_list.grab_focus()
	else:
		menu.equip_accessory_list.grab_focus()

	menu._update_equip_slot_colors()
	menu._update_equip_accessory_counter()
	menu._update_equip_guide()
	menu._update_equipped_accessory_highlight()


static func update_equip_slot_colors(menu) -> void:
	if not is_instance_valid(menu.equip_slot_list):
		return

	var normal_color := Color(1.0, 1.0, 1.0, 1.0)
	var inactive_color: Color = menu.disabled_text_tint

	# SlotList is navigation-only; the dedicated labels let rod and lure have
	# independent one-pixel placement without disturbing row geometry.
	if is_instance_valid(menu.equip_rod_slot_label):
		menu.equip_rod_slot_label.add_theme_color_override("font_color", normal_color)
	if is_instance_valid(menu.equip_lure_slot_label):
		menu.equip_lure_slot_label.add_theme_color_override("font_color", normal_color)

	if menu._equip_focus == menu.EquipFocus.ACCESSORY:
		if menu._equip_slot_index == 0 and is_instance_valid(menu.equip_lure_slot_label):
			menu.equip_lure_slot_label.add_theme_color_override("font_color", inactive_color)
		elif menu._equip_slot_index == 1 and is_instance_valid(menu.equip_rod_slot_label):
			menu.equip_rod_slot_label.add_theme_color_override("font_color", inactive_color)


static func equipped_accessory_index(menu) -> int:
	if not is_instance_valid(menu._loadout) or menu._equip_entries.is_empty():
		return -1

	var selected_rod: RodData = menu._loadout.get_selected_rod()
	var selected_lure: BaitData = menu._loadout.get_selected_lure()

	for item_index in range(menu._equip_entries.size()):
		var entry: Dictionary = menu._equip_entries[item_index]
		var resource: Resource = entry.get("resource", null) as Resource

		if menu._equip_slot_index == 0 and resource is RodData and selected_rod != null:
			var rod: RodData = resource as RodData
			if rod.rod_id == selected_rod.rod_id:
				return item_index

		elif menu._equip_slot_index == 1 and resource is BaitData and selected_lure != null:
			var lure: BaitData = resource as BaitData
			if lure.lure_id == selected_lure.lure_id:
				return item_index

	return -1


static func update_equipped_accessory_highlight(menu) -> void:
	# BOF4 does not use a second independent equipped-row rectangle here.
	# The left rod/lure category keeps its outline selector, while the Accessory
	# list uses its own warm filled cursor selector.
	if is_instance_valid(menu.equip_equipped_highlight):
		menu.equip_equipped_highlight.visible = false


static func update_equip_accessory_counter(menu) -> void:
	if not is_instance_valid(menu.equip_accessory_count_label):
		return

	var total_entries: int = menu._equip_entries.size()
	if total_entries <= 0:
		menu.equip_accessory_count_label.text = "00/00"
		return

	# BOF4 shows 0 / total before entering the accessory list, then the
	# selected entry number once the list owns focus.
	var current_entry: int = 0
	if menu._equip_focus == menu.EquipFocus.ACCESSORY:
		current_entry = clampi(menu._equip_accessory_index + 1, 1, total_entries)

	menu.equip_accessory_count_label.text = "%02d/%02d" % [
		current_entry,
		total_entries,
	]


static func update_equip_guide(menu) -> void:
	var is_lure_page: bool = menu._equip_slot_index == 1

	# Rod uses its own panel with the rod icon baked into the texture.
	# Lure uses the clean panel plus the dynamic lure-family icon.
	if is_lure_page:
		menu.equip_guide_panel.texture = menu.EQUIP_LURE_GUIDE_PANEL
		menu.equip_guide_icon.visible = true
	else:
		menu.equip_guide_panel.texture = menu.EQUIP_ROD_GUIDE_PANEL
		menu.equip_guide_icon.visible = false

	menu.equip_guide_icon.texture = null
	menu.equip_guide_title_label.text = ""
	menu.equip_guide_description_label.text = ""

	if menu._equip_entries.is_empty():
		menu.equip_guide_description_label.text = "No owned tackle in this category."
		return

	var entry: Dictionary = menu._equip_entries[menu._equip_accessory_index]
	var resource: Resource = entry.get("resource", null) as Resource

	if resource is RodData:
		var rod: RodData = resource as RodData
		menu.equip_guide_title_label.text = str(
			menu.ROD_GUIDE_TITLES.get(rod.rod_id, rod.rod_name)
		)
		menu.equip_guide_description_label.text = "%s
Power Level: %s" % [
			rod.description,
			rod.power_level_label,
		]

	elif resource is BaitData:
		var lure: BaitData = resource as BaitData
		if lure.lure_id == &"spoon" or lure.lure_id == &"king_frog":
			menu.equip_guide_title_label.text = "Ultimate Lure"
		else:
			var lure_type_label: String = str(
				menu.LURE_GUIDE_TYPE_LABELS.get(
					lure.lure_type,
					lure.get_type_label()
				)
			)
			menu.equip_guide_title_label.text = "LV %d %s" % [
				lure.level,
				lure_type_label,
			]

		menu.equip_guide_icon.texture = menu.LURE_GUIDE_ICONS.get(
			lure.lure_id,
			null
		) as Texture2D
		menu.equip_guide_description_label.text = lure.description


static func equip_selected_accessory(menu) -> void:
	if menu._equip_entries.is_empty() or not is_instance_valid(menu._loadout):
		return

	var entry: Dictionary = menu._equip_entries[menu._equip_accessory_index]
	var resource: Resource = entry.get("resource", null) as Resource
	var equipped: bool = false

	if resource is RodData:
		if menu.show_full_tackle_catalog_for_testing:
			menu._loadout.equip_rod(resource as RodData)
			equipped = menu._loadout.get_selected_rod() == resource
		else:
			equipped = menu._loadout.equip_owned_rod(resource as RodData)
	elif resource is BaitData:
		if menu.show_full_tackle_catalog_for_testing:
			menu._loadout.equip_lure(resource as BaitData)
			equipped = menu._loadout.get_selected_lure() == resource
		else:
			equipped = menu._loadout.equip_owned_lure(resource as BaitData)

	if equipped:
		menu.info_label.text = "Equipped %s." % menu._resource_display_name(resource)
		menu._refresh_main_page()
		menu._refresh_equip_page()


static func configure_equip_accessory_list_visuals(menu) -> void:
	# Names occupy only the left part of the row. Quantities are separate labels.
	# This prevents Godot's ItemList text-overrun ellipsis from hiding numbers.
	menu.equip_accessory_list.size.x = 96.0

	# Keep ItemList scrolling logic, but hide Godot's native grey scrollbar.
	# BOF4 uses the same thin yellow custom thumb as the Data page.
	if is_instance_valid(menu.equip_accessory_list):
		var native_scrollbar: VScrollBar = menu.equip_accessory_list.get_v_scroll_bar()
		if is_instance_valid(native_scrollbar):
			native_scrollbar.modulate = Color(1.0, 1.0, 1.0, 0.0)
			native_scrollbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			native_scrollbar.value = 0.0

	menu._update_equip_scroll_thumb()


static func sync_equip_selector_window(menu) -> void:
	const visible_rows: int = 8

	if menu._equip_entries.is_empty():
		menu._equip_window_start = 0
		return

	if menu._equip_accessory_index < menu._equip_window_start:
		menu._equip_window_start = menu._equip_accessory_index
	elif menu._equip_accessory_index >= menu._equip_window_start + visible_rows:
		menu._equip_window_start = menu._equip_accessory_index - visible_rows + 1

	menu._equip_window_start = clampi(
		menu._equip_window_start,
		0,
		maxi(menu._equip_entries.size() - visible_rows, 0)
	)


static func create_equip_quantity_labels(menu) -> void:
	if not is_instance_valid(menu.equip_accessory_panel):
		return

	# Eight fixed BOF4 rows. The quantity column is independent from ItemList
	# text, so it can never be truncated into an ellipsis.
	for row_index in range(8):
		var label := Label.new()
		label.name = "Quantity%02d" % row_index
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override(
			"font",
			menu.equip_accessory_list.get_theme_font("font")
		)
		label.add_theme_font_size_override(
			"font_size",
			menu.equip_accessory_list.get_theme_font_size("font_size")
		)
		label.add_theme_color_override(
			"font_color",
			Color(1.0, 1.0, 1.0, 1.0)
		)

		# Fixed right-aligned quantity column immediately before the scrollbar.
		# Two digits occupy 16 native pixels with the BOF font.
		label.position = Vector2(98.0, 5.0 + float(row_index * 17))
		label.size = Vector2(21.0, 17.0)
		label.text = ""
		label.visible = false

		menu.equip_accessory_panel.add_child(label)
		menu._equip_quantity_labels.append(label)


static func refresh_equip_quantity_labels(menu) -> void:
	for label in menu._equip_quantity_labels:
		if is_instance_valid(label):
			label.text = ""
			label.visible = false

	if menu._equip_entries.is_empty():
		return

	var visible_count: int = mini(
		8,
		menu._equip_entries.size() - menu._equip_window_start
	)

	for local_row in range(visible_count):
		if local_row >= menu._equip_quantity_labels.size():
			break

		var global_index: int = menu._equip_window_start + local_row
		var entry: Dictionary = menu._equip_entries[global_index]
		var count: int = clampi(int(entry.get("count", 0)), 0, 99)
		var label: Label = menu._equip_quantity_labels[local_row]

		label.text = "%02d" % count
		label.visible = true


static func refresh_equip_visible_rows(menu) -> void:
	# Equip deliberately does NOT use ItemList's native scrolling anymore.
	# Only the current eight-row BOF4 window exists in the ItemList. This keeps
	# fast W/S hold-repeat deterministic and prevents the selector from being
	# displaced by a hidden Godot scrollbar that is one frame out of sync.
	const visible_rows: int = 8

	menu.equip_accessory_list.clear()

	if menu._equip_entries.is_empty():
		return

	var window_end: int = mini(
		menu._equip_window_start + visible_rows,
		menu._equip_entries.size()
	)

	for global_index in range(menu._equip_window_start, window_end):
		var entry: Dictionary = menu._equip_entries[global_index]
		var resource: Resource = entry.get("resource", null) as Resource
		var count: int = int(entry.get("count", 0))
		var display_name: String = menu._resource_display_name(resource)
		menu.equip_accessory_list.add_item(
			menu._format_accessory_row(display_name, count)
		)

	var visible_index: int = menu._equip_accessory_index - menu._equip_window_start
	if visible_index >= 0 and visible_index < menu.equip_accessory_list.item_count:
		menu.equip_accessory_list.select(visible_index)

	menu._refresh_equip_quantity_labels()


static func update_equip_scroll_thumb(menu) -> void:
	if not is_instance_valid(menu.equip_scroll_thumb):
		return

	var total_entries: int = menu._equip_entries.size()
	if total_entries <= 0:
		menu.equip_scroll_thumb.visible = false
		return

	menu.equip_scroll_thumb.visible = true

	# BOF4 track geometry inside the Accessory panel.
	const visible_rows: int = 8
	const track_top_y: float = 45.0
	const track_end_y: float = 152.0
	const scrolling_thumb_height: float = 34.0
	const scrolling_thumb_bottom_y: float = (
		track_end_y - scrolling_thumb_height
	)

	if total_entries <= visible_rows:
		# All rods fit on one page. A full-height yellow bar communicates that
		# this IS the complete page and there is nowhere further to scroll.
		menu.equip_scroll_thumb.position.y = track_top_y
		menu.equip_scroll_thumb.size.y = track_end_y - track_top_y
		return

	# Lures have multiple pages. Restore the normal BOF4 thumb size and move it
	# according to our explicit eight-row window.
	menu.equip_scroll_thumb.size.y = scrolling_thumb_height

	var max_window_start: int = maxi(total_entries - visible_rows, 0)
	var ratio: float = 0.0
	if max_window_start > 0:
		ratio = clampf(
			float(menu._equip_window_start) / float(max_window_start),
			0.0,
			1.0
		)

	menu.equip_scroll_thumb.position.y = roundf(
		lerpf(track_top_y, scrolling_thumb_bottom_y, ratio)
	)
