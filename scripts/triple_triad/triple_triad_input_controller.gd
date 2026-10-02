extends RefCounted

const ACTION_NONE := &""
const ACTION_CONFIRM := &"confirm"
const ACTION_BACK := &"back"
const ACTION_LEFT := &"left"
const ACTION_RIGHT := &"right"
const ACTION_UP := &"up"
const ACTION_DOWN := &"down"
const ACTION_ROTATE := &"rotate"
const ACTION_DEBUG := &"debug"
const ACTION_CAMPAIGN_QA := &"campaign_qa"


func action_for_event(event: InputEvent, allow_campaign_qa: bool) -> StringName:
	if not is_pressed_event(event):
		return ACTION_NONE
	var key_event := event as InputEventKey
	if _matches_key(key_event, KEY_F10):
		if allow_campaign_qa and key_event.shift_pressed:
			return ACTION_CAMPAIGN_QA
		return ACTION_DEBUG
	if _matches_key(key_event, KEY_K) or _matches_key(key_event, KEY_ENTER):
		return ACTION_CONFIRM
	if _matches_key(key_event, KEY_I) or _matches_key(key_event, KEY_ESCAPE):
		return ACTION_BACK
	if _matches_key(key_event, KEY_A) or _matches_key(key_event, KEY_LEFT):
		return ACTION_LEFT
	if _matches_key(key_event, KEY_D) or _matches_key(key_event, KEY_RIGHT):
		return ACTION_RIGHT
	if _matches_key(key_event, KEY_W) or _matches_key(key_event, KEY_UP):
		return ACTION_UP
	if _matches_key(key_event, KEY_S) or _matches_key(key_event, KEY_DOWN):
		return ACTION_DOWN
	if _matches_key(key_event, KEY_R):
		return ACTION_ROTATE
	return ACTION_NONE


func is_pressed_event(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
	)


func is_direction(action: StringName) -> bool:
	return action in [ACTION_LEFT, ACTION_RIGHT, ACTION_UP, ACTION_DOWN]


func hand_step(action: StringName) -> int:
	if action == ACTION_UP:
		return -1
	if action == ACTION_DOWN:
		return 1
	return 0


func move_board_cursor(current: int, action: StringName) -> int:
	var row: int = floori(float(current) / 3.0)
	var column: int = current % 3
	match action:
		ACTION_LEFT:
			column -= 1
		ACTION_RIGHT:
			column += 1
		ACTION_UP:
			row -= 1
		ACTION_DOWN:
			row += 1
		_:
			return current
	column = clampi(column, 0, 2)
	row = clampi(row, 0, 2)
	return row * 3 + column


func _matches_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key
