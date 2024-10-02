package scheduler

import "../node"
import "../task"

Round_Robin :: struct {
	using _:     Scheduler,
	last_worker: int,
}

rr_select_nodes :: proc(r: ^Round_Robin, t: task.Task, nodes: []^node.Node) -> []^node.Node {
	return nodes
}

rr_score :: proc(r: ^Round_Robin, t: task.Task, nodes: []^node.Node) -> map[string]f64 {
	node_scores := make(map[string]f64)
	new_worker: int
	if r.last_worker + 1 < len(nodes) {
		new_worker = r.last_worker + 1
		r.last_worker += 1
	} else {
		new_worker = 0
		r.last_worker = 0
	}

	for n, i in nodes {
		if i == new_worker {
			node_scores[n.name] = 0.1
		} else {
			node_scores[n.name] = 1.0
		}
	}

	return node_scores
}

rr_pick :: proc(r: ^Round_Robin, scores: map[string]f64, nodes: []^node.Node) -> ^node.Node {
	best: ^node.Node
	lowest: f64
	for n, i in nodes {
		if i == 0 {
			best = n
			lowest = scores[n.name]
			continue
		}

		if scores[n.name] < lowest {
			best = n
			lowest = scores[n.name]
		}
	}

	return best
}

