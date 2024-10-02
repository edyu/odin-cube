package worker

import "core:container/queue"
import "core:fmt"
import "core:log"
import "core:time"

import "../docker/client"
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
		log.debugf("[%s] Collecting stats", w.name)
		w.stats = stats.get_stats()
		w.task_count = w.stats.task_count
		time.sleep(15 * time.Second)
	}
}

run_task :: proc(w: ^Worker) -> (result: task.Docker_Result) {
	t, ok := queue.pop_front_safe(&w.queue)
	if !ok {
		log.debugf("[%s] No tasks in the queue", w.name)
		return result
	}

	log.debugf("[%s] Found task in queue: %v", w.name, t)

	w.db[t.id] = t

	pt, found := w.db[t.id]
	if !found {
		pt = t
		w.db[t.id] = t
	}
	if pt.state == .Completed {
		return stop_task(w, pt)
	}

	if task.valid_state_transition(pt.state, t.state) {
		#partial switch t.state {
		case .Scheduled:
			if t.container_id != "" {
				result = stop_task(w, t)
				if result.error != nil {
					log.errorf("[%s] Error: %v", w.name, result.error)
				}
			}
			result = start_task(w, t)
			if result.error != nil && t.container_id == "" {
				#partial switch r in result.error {
				case client.Client_Error:
					#partial switch e in r {
					case client.Response_Error:
						if e.code == 409 {
							log.warnf("[%s] Got existing conflict container; stopping", w.name)
							err := client.container_stop(t.name, container.Stop_Options{})
							if err != nil {
								log.errorf(
									"[%s] Error stopping existing container: %v",
									w.name,
									err,
								)
							}
							err = client.container_remove(t.name, container.Remove_Options{})
							if err != nil {
								log.errorf(
									"[%s] Error removing existing container: %v",
									w.name,
									err,
								)
							}
						}
					}
				}
			}
		case .Completed:
			result = stop_task(w, t)
		case:
			log.warnf("[%s] This is a mistake. persisted task: %v, queued task: %v", w.name, pt, t)
			result.error = task.Unreachable_Error{}
		}
	} else {
		log.warnf("[%s] Invalid transition from %v to %v", w.name, pt.state, t.state)
		result.error = task.Invalid_Transition_Error{pt.state, t.state}
	}

	return result
}

run_tasks :: proc(w: ^Worker) {
	for {
		if w.queue.len != 0 {
			result := run_task(w)
			if result.error != nil {
				log.errorf("[%s] Error running task: %v", w.name, result.error)
			}
		} else {
			log.debugf("[%s] No tasks to process currently", w.name)
		}
		log.debugf("[%s] Sleeping for 10 seconds", w.name)
		time.sleep(10 * time.Second)
	}
}

start_task :: proc(w: ^Worker, t: ^task.Task) -> (result: task.Docker_Result) {
	t.start_time = lib.new_time()
	config := task.new_config(t)
	d := task.new_docker(&config)
	result = task.docker_run(&d)
	if result.error != nil {
		log.errorf("[%s] Error running task %s: %v", w.name, t.id, result.error)
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
		log.errorf("[%s] Error stopping container %v: %v", w.name, t.container_id, result.error)
	}
	result = task.docker_remove(&d, t.container_id)
	if result.error != nil {
		log.errorf("[%s] Error removing container %v: %v", w.name, t.container_id, result.error)
	}
	t.finish_time = lib.new_time()
	t.state = .Completed
	w.db[t.id] = t
	log.debugf("[%s] Stopped and removed container %v for task %s", w.name, t.container_id, t.id)

	return result
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
				log.errorf("[%s] ERROR: %v", w.name, result.error)
			}

			if result.response == nil {
				log.warnf("[%s] No container for running task %s", w.name, id)
				t.state = .Failed
			}

			#partial switch r in result.response {
			case container.Inspect_Response:
				if r.state.status == "exited" {
					log.warnf(
						"[%s] Container for task %s in non-running state %s",
						w.name,
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
		log.debugf("[%s] Checking status of tasks", w.name)
		do_update_tasks(w)
		log.debugf("[%s] Task updates completed", w.name)
		log.debugf("[%s] Sleeping for 15 seconds", w.name)
		time.sleep(15 * time.Second)
	}
}

