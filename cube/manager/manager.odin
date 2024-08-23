package manager

import "../task"
import "core:fmt"

import "core:container/queue"
import "core:encoding/uuid"

Manager :: struct {
	pending:         queue.Queue(task.Task),
	task_db:         map[string][]^task.Task,
	event_db:        map[string][]^task.Event,
	workers:         [dynamic]string,
	worker_task_map: map[string][]uuid.Identifier,
	task_worker_map: map[uuid.Identifier]string,
}

new :: proc(workers: []string) -> (manager: Manager) {
	queue.init(&manager.pending)
	manager.task_db = make(map[string][]^task.Task)
	manager.event_db = make(map[string][]^task.Event)
	manager.worker_task_map = make(map[string][]uuid.Identifier)
	manager.task_worker_map = make(map[uuid.Identifier]string)
	manager.workers = make([dynamic]string)
	for w in workers {
		append(&manager.workers, w)
	}

	return manager
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

