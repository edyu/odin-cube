package task

contains :: proc(states: []State, state: State) -> bool {
	for s in states {
		if s == state {
			return true
		}
	}
	return false
}


valid_state_transition :: proc(src: State, dst: State) -> bool {
	State_Transition_Map := map[State][]State {
		.Pending   = []State{.Scheduled},
		.Scheduled = []State{.Scheduled, .Running, .Failed},
		.Running   = []State{.Running, .Completed, .Failed},
		.Completed = []State{},
		.Failed    = []State{},
	}
	return contains(State_Transition_Map[src], dst)
}

