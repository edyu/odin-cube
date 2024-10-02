package scheduler

import "../node"
import "../task"

Epvm :: struct {
	using _: Scheduler,
}

epvm_select_nodes :: proc(e: ^Epvm, t: task.Task, nodes: []^node.Node) -> []^node.Node {
	return nodes
}

epvm_score :: proc(e: ^Epvm, t: task.Task, nodes: []^node.Node) -> map[string]f64 {
	return nil
}

epvm_pick :: proc(s: ^Epvm, scores: map[string]f64, candidates: []^node.Node) -> ^node.Node {
	return candidates[0]
}

