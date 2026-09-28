extends RefCounted
class_name FishingFightLifecycle

## Small, deterministic state machine for one cast's encounter lifecycle.
##
## This object deliberately owns only bite/fight legality. It does not know
## anything about camera, UI, animation, fish movement, or tension values.
## Those systems can represent the state, but they cannot invent transitions.

enum State {
	IDLE,
	WAITING_BITE,
	BITE_WINDOW,
	HOOKED,
	LANDING,
	RESOLVED,
}

enum Resolution {
	NONE,
	CATCH,
	HOOK_OFF,
	LINE_BREAK,
	CANCELLED,
}

var state: State = State.IDLE
var resolution: Resolution = Resolution.NONE
var cast_serial: int = 0


func begin_cast() -> bool:
	if state != State.IDLE:
		return false

	cast_serial += 1
	state = State.WAITING_BITE
	resolution = Resolution.NONE
	return true


func open_bite_window() -> bool:
	if state != State.WAITING_BITE:
		return false

	state = State.BITE_WINDOW
	return true


func confirm_hook() -> bool:
	if (
		state != State.WAITING_BITE
		and state != State.BITE_WINDOW
	):
		return false

	state = State.HOOKED
	return true


func miss_bite() -> bool:
	if state != State.BITE_WINDOW:
		return false

	state = State.WAITING_BITE
	return true


func begin_landing() -> bool:
	if state == State.LANDING:
		return true

	if state != State.HOOKED:
		return false

	state = State.LANDING
	return true


func resolve_catch() -> bool:
	if state != State.LANDING:
		return false

	state = State.RESOLVED
	resolution = Resolution.CATCH
	return true


func resolve_hook_off() -> bool:
	return _resolve_failure(Resolution.HOOK_OFF)


func resolve_line_break() -> bool:
	return _resolve_failure(Resolution.LINE_BREAK)


func cancel_cast() -> bool:
	# A terminal result is immutable. Cleanup may finish it, but must never
	# rewrite CATCH/HOOK_OFF/LINE_BREAK into CANCELLED.
	if state == State.IDLE or state == State.RESOLVED:
		return false

	state = State.RESOLVED
	resolution = Resolution.CANCELLED
	return true


func finish_cast() -> void:
	state = State.IDLE
	resolution = Resolution.NONE


func is_waterborne() -> bool:
	return (
		state == State.WAITING_BITE
		or state == State.BITE_WINDOW
		or state == State.HOOKED
		or state == State.LANDING
	)


func is_waiting_for_bite() -> bool:
	return state == State.WAITING_BITE


func is_bite_window_open() -> bool:
	return state == State.BITE_WINDOW


func is_hooked() -> bool:
	return state == State.HOOKED


func is_landing() -> bool:
	return state == State.LANDING


func is_resolved() -> bool:
	return state == State.RESOLVED


func get_state_label() -> String:
	match state:
		State.WAITING_BITE:
			return "WAITING_BITE"
		State.BITE_WINDOW:
			return "BITE_WINDOW"
		State.HOOKED:
			return "HOOKED"
		State.LANDING:
			return "LANDING"
		State.RESOLVED:
			return "RESOLVED"
		_:
			return "IDLE"


func get_resolution_label() -> String:
	match resolution:
		Resolution.CATCH:
			return "CATCH"
		Resolution.HOOK_OFF:
			return "HOOK_OFF"
		Resolution.LINE_BREAK:
			return "LINE_BREAK"
		Resolution.CANCELLED:
			return "CANCELLED"
		_:
			return "NONE"


func get_debug_snapshot() -> Dictionary:
	return {
		"state": state,
		"state_label": get_state_label(),
		"resolution": resolution,
		"resolution_label": get_resolution_label(),
		"cast_serial": cast_serial,
	}


func _resolve_failure(reason: Resolution) -> bool:
	if state != State.HOOKED:
		return false

	state = State.RESOLVED
	resolution = reason
	return true
