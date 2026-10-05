extends RefCounted
class_name WorldRequestState

## Presentation-neutral state resolver for small world requests.
##
## This class deliberately owns no objectives, rewards, inventory, or saves.
## Callers supply the durable facts owned by those systems and receive one
## stable state for dialogue / prompt presentation.

enum State {
	LOCKED,
	AVAILABLE,
	ACCEPTED,
	READY_TO_TURN_IN,
	COMPLETED,
	SOURCE_COMPLETE,
}


static func resolve(
	unlocked: bool,
	accepted: bool,
	objective_complete: bool,
	reward_claimed: bool,
	source_complete: bool
) -> int:
	if not unlocked:
		return State.LOCKED
	if reward_claimed:
		return State.COMPLETED
	if source_complete:
		return State.SOURCE_COMPLETE
	if not accepted:
		return State.AVAILABLE
	if objective_complete:
		return State.READY_TO_TURN_IN
	return State.ACCEPTED


static func state_id(state: int) -> StringName:
	match state:
		State.LOCKED:
			return &"locked"
		State.AVAILABLE:
			return &"available"
		State.ACCEPTED:
			return &"accepted"
		State.READY_TO_TURN_IN:
			return &"ready_to_turn_in"
		State.COMPLETED:
			return &"completed"
		State.SOURCE_COMPLETE:
			return &"source_complete"
	return &"locked"
