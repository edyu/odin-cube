package manager

import "../task"
import "core:fmt"

import "core:container/queue"
import "core:encoding/uuid"

Manager :: struct {
	pending:         queue.Queue(task.Task) `fmt:"-"`,
	task_db:         map[string][]^task.Task `fmt:"-"`,
	event_db:        map[string][]^task.Event `fmt:"-"`,
	workers:         [dynamic]string,
	worker_task_map: map[string][]uuid.Identifier `fmt:"-"`,
	task_worker_map: map[uuid.Identifier]string `fmt:"-"`,
}

init :: proc(workers: []string) -> (m: Manager) {
	queue.init(&m.pending)
	m.task_db = make(map[string][]^task.Task)
	m.event_db = make(map[string][]^task.Event)
	m.worker_task_map = make(map[string][]uuid.Identifier)
	m.task_worker_map = make(map[uuid.Identifier]string)
	m.workers = make([dynamic]string)
	for w in workers {
		append(&m.workers, w)
	}

	return m
}

deinit :: proc(m: ^Manager) {
	queue.destroy(&m.pending)
	delete_map(m.task_db)
	delete_map(m.event_db)
	delete_map(m.worker_task_map)
	delete_map(m.task_worker_map)
	delete(m.workers)
}


select_worker :: proc(m: ^Manager) {
	fmt.println("I will select an appropriate worker")
}

update_tasks :: proc(m: ^Manager) {
	fmt.println("I will update tasks")
}

send_work :: proc(m: ^Manager) {
	fmt.println("I will send work to workers")
}

