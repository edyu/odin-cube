package scheduler

import "../node"
import "../task"

ROUND_ROBIN: string : "roundrobin"

Scheduler :: struct {
	name: string,
}

Round_Robin :: struct {
	using _:     Scheduler,
	last_worker: int,
}

init_round_robin :: proc() -> (s: Round_Robin) {
	s.name = ROUND_ROBIN
	return s
}

select_candidate_nodes :: proc(r: ^Scheduler, t: task.Task, nodes: []^node.Node) -> []^node.Node {
	return nodes
}

score :: proc(s: ^Scheduler, t: task.Task, nodes: []^node.Node) -> map[string]f64 {
	r := transmute(^Round_Robin)s
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

pick :: proc(s: ^Scheduler, scores: map[string]f64, candidates: []^node.Node) -> ^node.Node {
	best: ^node.Node
	lowest: f64
	for n, i in candidates {
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

