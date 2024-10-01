package worker

import "core:container/queue"
import "core:fmt"
import "core:log"
import "core:time"

import "../docker/container"
import "../lib"
import "../stats"
import "../task"

Worker_Error :: struct {
	reason: string,
}

Worker :: struct {
	name:       string,
	queue:      queue.Queue(^task.Task) `fmt:"-"`,
	db:         map[lib.UUID]^task.Task `fmt:"-"`,
	task_count: uint,
	stats:      stats.Stats,
}

init :: proc(name: string) -> (w: Worker) {
	w.name = name
	queue.init(&w.queue)
	w.db = make(map[lib.UUID]^task.Task)
	w.task_count = 0
	return w
}

deinit :: proc(w: ^Worker) {
	queue.destroy(&w.queue)
	delete_map(w.db)
}

add_task :: proc(w: ^Worker, t: ^task.Task) {
	queue.push_back(&w.queue, t)
}

collect_stats :: proc(w: ^Worker) {
	for {
		fmt.println("[worker]: Collecting stats")
		w.stats = stats.get_stats()
		w.stats.task_count = w.task_count
		// w.task_count = w.stats.task_count
		time.sleep(15 * time.Second)
	}
}

get_tasks :: proc(w: ^Worker) -> (tasks: []task.Task) {
	tasks = make([]task.Task, len(w.db))
	i := 0
	for _, t in w.db {
		tasks[i] = t^
		i += 1
	}
	return tasks
}

run_task :: proc(w: ^Worker) -> (result: task.Docker_Result) {
	t, ok := queue.pop_front_safe(&w.queue)
	if !ok {
		fmt.println("[worker]: No tasks in the queue")
		return result
	}

	task_queued := t
	fmt.printfln("[worker]: Found task in queue: %v", task_queued)

	task_persisted, found := w.db[task_queued.id]
	if !found {
		task_persisted = task_queued
		w.db[task_queued.id] = task_queued
	}
	fmt.println("[worker]: PERSISTED(%s).state=%v", task_persisted.id, task_persisted.state)

	if task.valid_state_transition(task_persisted.state, task_queued.state) {
		#partial switch task_queued.state {
		case .Scheduled:
			result = start_task(w, task_queued)
		case .Completed:
			result = stop_task(w, task_queued)
		case:
			result.error = task.Unreachable_Error{}
		}
	} else {
		result.error = task.Invalid_Transition_Error{task_persisted.state, task_queued.state}
	}

	return result
}

run_tasks :: proc(w: ^Worker) {
	for {
		if w.queue.len != 0 {
			result := run_task(w)
			if result.error != nil {
				fmt.eprintfln("Error running task: %v", result.error)
			}
		} else {
			fmt.println("[worker]: No tasks to process currently")
		}
		fmt.println("[worker]: Run: Sleeping for 10 seconds")
		time.sleep(10 * time.Second)
	}
}

start_task :: proc(w: ^Worker, t: ^task.Task) -> (result: task.Docker_Result) {
	t.start_time = lib.new_time()
	config := task.new_config(t)
	d := task.new_docker(&config)
	result = task.docker_run(&d)
	if result.error != nil {
		fmt.eprintf("Error running task %s: %v\n", t.id, result.error)
		t.state = .Failed
		w.db[t.id] = t
		return result
	}

	t.container_id = result.container_id
	t.state = .Running
	w.db[t.id] = t

	return result
}

stop_task :: proc(w: ^Worker, t: ^task.Task) -> (result: task.Docker_Result) {
	config := task.new_config(t)
	d := task.new_docker(&config)

	result = task.docker_stop(&d, t.container_id)
	if result.error != nil {
		fmt.printf("Error stopping container %v: %v\n", t.container_id, result.error)
	}
	result = task.docker_remove(&d, t.container_id)
	if result.error != nil {
		fmt.printf("Error removing container %v: %v\n", t.container_id, result.error)
	}
	t.finish_time = lib.new_time()
	t.state = .Completed
	w.db[t.id] = t
	fmt.printf("[worker]: Stopped and removed container %v for task %s\n", t.container_id, t.id)

	return result
}

inspect_task :: proc(w: ^Worker, t: ^task.Task) -> (result: task.Docker_Result) {
	config := task.new_config(t)
	d := task.new_docker(&config)
	return task.docker_inspect(&d, t.container_id)
}

do_update_tasks :: proc(w: ^Worker) {
	for id, &t in w.db {
		if t.state == .Running {
			result := inspect_task(w, t)
			if result.error != nil {
				fmt.eprintfln("ERROR: %v", result.error)
			}

			if result.response == nil {
				fmt.printfln("No container for running task %s", id)
				t.state = .Failed
			}

			#partial switch r in result.response {
			case container.Inspect_Response:
				if r.state.status == "exited" {
					fmt.printfln(
						"Container for task %s in non-running state %s",
						id,
						r.state.status,
					)
					t.state = .Failed
				}

				t.exposed_ports = r.config.exposed_ports
				t.host_ports = r.network_settings.ports
				t.port_bindings = r.host_config.port_bindings
			}
		}
	}
}

update_tasks :: proc(w: ^Worker) {
	for {
		fmt.println("[worker]: Checking status of tasks")
		do_update_tasks(w)
		fmt.println("[worker]: Task updates completed")
		fmt.println("[worker]: Update: Sleeping for 15 seconds")
		time.sleep(15 * time.Second)
	}
}

