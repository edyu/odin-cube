package worker

import "core:container/queue"
import "core:fmt"
import "core:log"
import "core:time"

import "../docker/client"
import "../docker/container"
import "../lib"
import "../stats"
import "../store"
import "../task"

Worker_Error :: struct {
	message: string,
}

Worker :: struct {
	name:       string,
	queue:      queue.Queue(^task.Task),
	db:         ^store.Store(task.Task),
	task_count: uint,
	stats:      stats.Stats,
}

init :: proc(name: string, db_type: store.Db_Type) -> (w: Worker) {
	w.name = name
	queue.init(&w.queue)
	switch db_type {
	case .MEMORY:
		w.db, _ = store.new_store(store.Memory(task.Task), task.Task)
	case .PERSISTENT:
		filename := fmt.tprintf("%s_tasks.db", name)
		err: store.Store_Error
		w.db, err = store.new_store(store.Db(task.Task), task.Task, filename)
		if err != nil {
			log.fatalf("Unable to create task store %s: %v", filename, err)
		}
	case:
		msg := fmt.tprintf("invalid db: %s", db_type)
		panic(msg)
	}
	return w
}

deinit :: proc(w: ^Worker) {
	queue.destroy(&w.queue)
	store.destroy_store(w.db)
	free(w.db)
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

	err := store.put(w.db, t.id, t)
	if err != nil {
		msg := fmt.aprintf("Error storing task %s: %v", t.id, err)
		log.error(msg)
		result.error = err
		return result
	}

	t, err = store.get(w.db, t.id)
	if err != nil {
		msg := fmt.aprintf("Error sgetting task %s from database: %v", t.id, err)
		log.error(msg)
		result.error = err
		return result
	}
	if t.state == .Completed {
		return stop_task(w, t)
	}

	if task.valid_state_transition(t.state, t.state) {
		#partial switch t.state {
		case .Scheduled:
			if t.container_id != "" {
				result = stop_task(w, t)
				if result.error != nil {
					log.errorf("[%s] Error: %v", w.name, result.error)
				}
			}
			result = start_task(w, t)
			// existing container with same name from previous run
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
			log.warnf("[%s] This is a mistake. task: %v", w.name, t)
			result.error = task.Unreachable_Error{}
		}
	} else {
		log.warnf("[%s] Invalid transition from %v to %v", w.name, t.state, t.state)
		result.error = task.Invalid_Transition_Error{t.state, t.state}
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
		store.put(w.db, t.id, t)
		return result
	}

	t.container_id = result.container_id
	t.state = .Running
	store.put(w.db, t.id, t)
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
	store.put(w.db, t.id, t)
	log.debugf("[%s] Stopped and removed container %v for task %s", w.name, t.container_id, t.id)

	return result
}

get_tasks :: proc(w: ^Worker) -> (tasks: []task.Task) {
	ts, err := store.list(w.db)
	defer delete(ts)
	if err != nil {
		log.errorf("[%s] Error getting list of tasks: %v", w.name, err)
		return nil
	}
	tasks = make([]task.Task, len(ts))
	for t, i in ts {
		tasks[i] = t^
	}
	return tasks
}

inspect_task :: proc(w: ^Worker, t: ^task.Task) -> (result: task.Docker_Result) {
	config := task.new_config(t)
	d := task.new_docker(&config)
	return task.docker_inspect(&d, t.container_id)
}

do_update_tasks :: proc(w: ^Worker) {
	tasks, err := store.list(w.db)
	defer delete(tasks)
	if err != nil {
		log.error("[%s] Error getting list of tasks: %v", w.name, err)
		return
	}
	for t in tasks {
		if t.state == .Running {
			result := inspect_task(w, t)
			if result.error != nil {
				log.errorf("[%s] ERROR: %v", w.name, result.error)
			}

			if result.response == nil {
				log.warnf("[%s] No container for running task %s", w.name, t.id)
				t.state = .Failed
			}

			#partial switch r in result.response {
			case container.Inspect_Response:
				if r.state.status == "exited" {
					log.warnf(
						"[%s] Container for task %s in non-running state %s",
						w.name,
						t.id,
						r.state.status,
					)
					t.state = .Failed
					store.put(w.db, t.id, t)
				}

				t.exposed_ports = r.config.exposed_ports
				t.host_ports = r.network_settings.ports
				t.port_bindings = r.host_config.port_bindings
				store.put(w.db, t.id, t)
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

