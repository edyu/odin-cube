package worker

import "core:container/queue"
import "core:fmt"
import "core:time"

import "../lib"
import "../stats"
import "../task"

Worker_Error :: struct {
	reason: string,
}

Worker :: struct {
	name:       string,
	queue:      queue.Queue(task.Task) `fmt:"-"`,
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

add_task :: proc(w: ^Worker, t: task.Task) {
	queue.push_back(&w.queue, t)
}

collect_stats :: proc(w: ^Worker) {
	for {
		fmt.println("Collecting stats")
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
		fmt.println("No tasks in the queue")
		return result
	}

	task_queued := t

	task_persisted, found := w.db[task_queued.id]
	if !found {
		task_persisted = &task_queued
		w.db[task_queued.id] = &task_queued
	}

	if task.valid_state_transition(task_persisted.state, task_queued.state) {
		#partial switch task_queued.state {
		case .Scheduled:
			result = start_task(w, &task_queued)
		case .Completed:
			result = stop_task(w, &task_queued)
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
			fmt.println("No tasks to process currently.")
		}
		fmt.println("Sleeping for 10 seconds.")
		time.sleep(10 * time.Second)
	}
}

start_task :: proc(w: ^Worker, t: ^task.Task) -> (result: task.Docker_Result) {
	t.start_time = time.now()
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
	t.finish_time = time.now()
	t.state = .Completed
	w.db[t.id] = t
	fmt.printf("Stopped and removed container %v for task %s\n", t.container_id, t.id)

	return result
}

