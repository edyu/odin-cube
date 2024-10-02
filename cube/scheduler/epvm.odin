package scheduler

import "core:log"
import "core:math"
import "core:time"

import "../http"
import "../node"
import "../stats"
import "../task"

Epvm :: struct {
	using _: Scheduler,
}

epvm_select_nodes :: proc(e: ^Epvm, t: task.Task, nodes: []^node.Node) -> []^node.Node {
	candidates := make([dynamic]^node.Node)
	for n in nodes {
		if check_disk(t, n.disk - n.disk_allocated) {
			append(&candidates, n)
		}
	}
	return candidates[:]
}

check_disk :: proc(t: task.Task, disk_available: u64) -> bool {
	return t.disk <= disk_available
}

// LIEB square ice constant
LIEB: f64 : 1.53960071783900203869

epvm_score :: proc(e: ^Epvm, t: task.Task, nodes: []^node.Node) -> map[string]f64 {
	scores := make(map[string]f64)
	max_jobs: f64 = 4.0

	for n in nodes {
		cpu_usage, err := calculate_cpu_usage(n)
		if err != nil {
			log.errorf("Error calculating CPU usage for node %s, skipping: %v", n.name, err)
			continue
		}
		cpu_load := calculate_load(cpu_usage, math.pow_f64(2.0, 0.8))
		new_cpu_load := calculate_load(cpu_usage + t.cpu, math.pow_f64(2.0, 0.8))

		memory_allocated := f64(stats.mem_used_kb(&n.stats)) + f64(n.memory_allocated)
		mem_pct := memory_allocated / f64(n.memory)

		new_mem_pct := calculate_load(memory_allocated + f64(t.memory / 1000), f64(n.memory))
		job_cost_diff :=
			math.pow_f64(LIEB, f64(n.task_count + 1) / max_jobs) -
			math.pow_f64(LIEB, f64(n.task_count) / max_jobs)
		mem_cost := math.pow_f64(LIEB, new_mem_pct) - math.pow_f64(LIEB, mem_pct)
		cpu_cost := math.pow_f64(LIEB, new_cpu_load) - math.pow_f64(LIEB, cpu_load)

		scores[n.name] = mem_cost + cpu_cost + job_cost_diff
	}
	return scores
}

calculate_cpu_usage :: proc(n: ^node.Node) -> (usage: f64, err: node.Node_Error) {
	stat1, err1 := node.get_stats(n)
	if err1 != nil {
		return usage, err1
	}
	time.sleep(3 * time.Second)
	stat2, err2 := node.get_stats(n)
	if err2 != nil {
		return usage, err2
	}

	stat1_idle := stat1.cpu_stats.idle + stat1.cpu_stats.io_wait
	stat2_idle := stat2.cpu_stats.idle + stat2.cpu_stats.io_wait

	stat1_nonidle :=
		stat1.cpu_stats.user +
		stat1.cpu_stats.nice +
		stat1.cpu_stats.system +
		stat1.cpu_stats.irq +
		stat1.cpu_stats.soft_irq +
		stat1.cpu_stats.steal

	stat2_nonidle :=
		stat2.cpu_stats.user +
		stat2.cpu_stats.nice +
		stat2.cpu_stats.system +
		stat2.cpu_stats.irq +
		stat2.cpu_stats.soft_irq +
		stat2.cpu_stats.steal

	stat1_total := stat1_idle + stat1_nonidle
	stat2_total := stat2_idle + stat2_nonidle

	total := stat2_total - stat1_total
	non_idle := stat2_nonidle - stat1_nonidle

	if total != 0 {
		usage = f64(non_idle) / f64(total)
	}
	return usage, nil
}

calculate_load :: proc(usage: f64, capacity: f64) -> f64 {
	return usage / capacity
}

epvm_pick :: proc(s: ^Epvm, scores: map[string]f64, nodes: []^node.Node) -> ^node.Node {
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

