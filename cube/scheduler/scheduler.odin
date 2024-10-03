package scheduler

import "../node"
import "../task"

Scheduler_Type :: enum {
	ROUND_ROBIN  = 1,
	ENHANCED_PVM = 2,
}

Scheduler :: struct {
	variant: union {
		^Round_Robin,
		^Epvm,
	},
}

new_scheduler :: proc($T: typeid) -> ^T {
	s := new(T)
	s.variant = s
	return s
}

select_nodes :: proc(s: ^Scheduler, t: task.Task, nodes: []^node.Node) -> []^node.Node {
	switch v in s.variant {
	case ^Round_Robin:
		return rr_select_nodes(v, t, nodes)
	case ^Epvm:
		return epvm_select_nodes(v, t, nodes)
	case:
		return nil
	}
}

score :: proc(s: ^Scheduler, t: task.Task, nodes: []^node.Node) -> map[string]f64 {
	switch v in s.variant {
	case ^Round_Robin:
		return rr_score(v, t, nodes)
	case ^Epvm:
		return epvm_score(v, t, nodes)
	case:
		return nil
	}
}

pick :: proc(s: ^Scheduler, scores: map[string]f64, nodes: []^node.Node) -> ^node.Node {
	switch v in s.variant {
	case ^Round_Robin:
		return rr_pick(v, scores, nodes)
	case ^Epvm:
		return epvm_pick(v, scores, nodes)
	case:
		return nil
	}
}

