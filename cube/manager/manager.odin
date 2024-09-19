package manager

import "../http"
import "../task"
import "../worker"
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
		m.worker_task_map[w] = make([dynamic]uuid.Identifier)
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
	for worker in m.workers {
		fmt.printfln("Checking worker %v for task updates", worker)
		sb: strings.Builder
		url := fmt.sbprintf(&sb, "http://%s/tasks", worker)
		resp, err := http.get(url)
		if err != nil {
			fmt.eprintfln("Error connecting to %v: %v", worker, err)
		} else {
			if http.Status_Code(resp.status) != .HTTP_OK {
				fmt.eprintfln("Error sending request: %v", err)
			} else {
				tasks: []task.Task
				merr := json.unmarshal_string(resp.body, &tasks)
				if merr != nil {
					fmt.printfln("Error marshalling tasks: %v", err)
				} else {
					for t in tasks {
						fmt.printfln("Attempting to update task %v", t.id)

						if t.id not_in m.task_db {
							fmt.printfln("Task with id %s not found", t.id)
							return
						}

						if m.task_db[t.id].state != t.state {
							m.task_db[t.id].state = t.state
						}

						m.task_db[t.id].start_time = t.start_time
						m.task_db[t.id].finish_time = t.finish_time
						m.task_db[t.id].container_id = t.container_id
					}
				}
			}
		}
	}
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
			log.warnf("Error connecting to %v: %v", w, err)
			queue.push_back(&m.pending, e)
			return
		}
		if http.Status_Code(resp.status) != .HTTP_CREATED {
			e := worker.Error_Response{}
			err := json.unmarshal_string(resp.body, &e)
			if err != nil {
				fmt.eprintfln("Error decoding response: %v", err)
				return
			}
			fmt.eprintf("Response error (%d): %s", e.status_code, e.message)
			return
		}

		t = task.Task{}
		merr := json.unmarshal_string(resp.body, &t)
		if merr != nil {
			fmt.eprintfln("Error decoding response: %s", merr)
			return
		}
		fmt.println(t)
	} else {
		fmt.println("No work in the queue")
	}
}

add_task :: proc(m: ^Manager, e: task.Event) {
	queue.push_back(&m.pending, e)
}

