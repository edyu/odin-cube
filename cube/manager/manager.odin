package manager

import "../http"
import "../task"
import "core:container/queue"
import "core:encoding/json"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:strings"

Manager :: struct {
	pending:         queue.Queue(task.Event) `fmt:"-"`,
	task_db:         map[uuid.Identifier]^task.Task `fmt:"-"`,
	event_db:        map[uuid.Identifier]^task.Event `fmt:"-"`,
	workers:         [dynamic]string,
	worker_task_map: map[string][dynamic]uuid.Identifier `fmt:"-"`,
	task_worker_map: map[uuid.Identifier]string `fmt:"-"`,
	last_worker:     int,
}

init :: proc(workers: []string) -> (m: Manager) {
	http.client_init()
	queue.init(&m.pending)
	m.task_db = make(map[uuid.Identifier]^task.Task)
	m.event_db = make(map[uuid.Identifier]^task.Event)
	m.worker_task_map = make(map[string][dynamic]uuid.Identifier)
	m.task_worker_map = make(map[uuid.Identifier]string)
	m.workers = make([dynamic]string)
	for w in workers {
		append(&m.workers, w)
	}

	return m
}

deinit :: proc(m: ^Manager) {
	http.client_deinit()
	queue.destroy(&m.pending)
	delete_map(m.task_db)
	delete_map(m.event_db)
	delete_map(m.worker_task_map)
	delete_map(m.task_worker_map)
	delete(m.workers)
}

select_worker :: proc(m: ^Manager) -> string {
	new_worker: int
	if m.last_worker + 1 < len(m.workers) {
		new_worker = m.last_worker + 1
		m.last_worker += 1
	} else {
		new_worker = 0
		m.last_worker = 0
	}

	return m.workers[new_worker]
}

update_tasks :: proc(m: ^Manager) {
	fmt.println("I will update tasks")
}

send_work :: proc(m: ^Manager) {
	if queue.len(m.pending) > 0 {
		w := select_worker(m)

		e := queue.pop_front(&m.pending)
		t := e.task

		m.event_db[e.id] = &e
		append(&m.worker_task_map[w], e.task.id)
		m.task_worker_map[t.id] = w

		t.state = .Scheduled
		m.task_db[t.id] = &t

		data, jerr := json.marshal(e)
		if jerr != nil {
			log.warnf("Unable to marshal task object: %v: %v.", t, jerr)
		}
		sb: strings.Builder
		url := fmt.sbprintf(&sb, "http://%s/tasks", w)
		resp, err := http.post(url, "application/json", string(data))
		if err != nil {
			log.warnf("Unable to send work: %v.", err)
		} else {
			log.debugf("work sent: %v", resp)
		}
	}
}

