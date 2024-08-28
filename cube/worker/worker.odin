package worker

import "core:container/queue"
import "core:encoding/uuid"
import "core:fmt"
import "core:time"

import "../task"

Worker_Error :: struct {
	reason: string,
}

Worker :: struct {
	name:       string,
	queue:      queue.Queue(task.Task) `fmt:"-"`,
	db:         map[uuid.Identifier]task.Task `fmt:"-"`,
	task_count: int,
}

init :: proc(name: string) -> (w: Worker) {
	w.name = name
	queue.init(&w.queue)
	w.db = make(map[uuid.Identifier]task.Task)
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
	fmt.println("I will collect stats")
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
		task_persisted = task_queued
		w.db[task_queued.id] = task_queued
	}

	if task.valid_state_transition(task_persisted.state, task_queued.state) {
		#partial switch task_queued.state {
		case task.State.Scheduled:
			result = start_task(w, &task_queued)
		case task.State.Completed:
			result = stop_task(w, &task_queued)
		case:
			result.error = task.Unreachable_Error{}
		}
	} else {
		result.error = task.Invalid_Transition_Error{task_persisted.state, task_queued.state}
	}

	return result
}

start_task :: proc(w: ^Worker, t: ^task.Task) -> (result: task.Docker_Result) {
	t.start_time = time.now()
	config := task.new_config(t)
	d := task.new_docker(&config)
	result = task.docker_run(&d)
	if result.error != nil {
		id := uuid.to_string(t.id)
		defer delete_string(id)
		fmt.eprintf("Error running task %s: %v\n", id, result.error)
		t.state = .Failed
		w.db[t.id] = t^
		return result
	}

	t.container_id = result.container_id
	t.state = .Running
	w.db[t.id] = t^

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
	w.db[t.id] = t^
	id := uuid.to_string(t.id)
	defer delete_string(id)
	fmt.printf("Stopped and removed container %v for task %s\n", t.container_id, id)

	return result
}

