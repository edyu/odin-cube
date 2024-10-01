package manager

import "core:container/queue"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:strings"
import "core:time"

import "../docker/connection"
import "../http"
import "../lib"
import "../task"
import "../worker"

Manager :: struct {
	pending:         queue.Queue(^task.Event) `fmt:"-"`,
	task_db:         map[lib.UUID]^task.Task,
	event_db:        map[lib.UUID]^task.Event,
	workers:         [dynamic]string,
	worker_task_map: map[string][dynamic]lib.UUID `fmt:"-"`,
	task_worker_map: map[lib.UUID]string `fmt:"-"`,
	last_worker:     int,
}

init :: proc(workers: []string) -> (m: Manager) {
	http.client_init()
	queue.init(&m.pending)
	m.task_db = make(map[lib.UUID]^task.Task)
	m.event_db = make(map[lib.UUID]^task.Event)
	m.worker_task_map = make(map[string][dynamic]lib.UUID)
	m.task_worker_map = make(map[lib.UUID]string)
	m.workers = make([dynamic]string)
	for w in workers {
		append(&m.workers, w)
		m.worker_task_map[w] = make([dynamic]lib.UUID)
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

do_update_tasks :: proc(m: ^Manager) {
	for worker in m.workers {
		fmt.printfln("[manager]: Checking worker %v for task updates", worker)
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
						fmt.printfln("[manager]: Attempting to update task %v", t.id)

						if t.id not_in m.task_db {
							fmt.printfln("[manager]: Task with id %s not found", t.id)
							return
						}

						ut := m.task_db[t.id]
						if ut.state != t.state {
							ut.state = t.state
						}

						ut.start_time = t.start_time
						ut.finish_time = t.finish_time
						ut.container_id = t.container_id
						ut.host_ports = t.host_ports

						m.task_db[ut.id] = ut
					}
				}
			}
		}
	}
}

update_tasks :: proc(m: ^Manager) {
	for {
		fmt.println("[manager]: Checking for task updates from workers")
		do_update_tasks(m)
		fmt.println("[manager]: Task updates completed")
		fmt.println("[manager]: Update: Sleeping for 15 seconds")
		time.sleep(15 * time.Second)
	}
}

send_work :: proc(m: ^Manager) {
	if queue.len(m.pending) > 0 {
		w := select_worker(m)

		e := queue.pop_front(&m.pending)
		t := &e.task

		m.event_db[e.id] = e
		append(&m.worker_task_map[w], e.task.id)
		m.task_worker_map[t.id] = w

		t.state = .Scheduled
		m.task_db[t.id] = t

		data, jerr := json.marshal(e^)
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

		rt := task.Task{}
		merr := json.unmarshal_string(resp.body, &rt)
		if merr != nil {
			fmt.eprintfln("Error decoding response: %s", merr)
			return
		}
		// w.task_count += 1
		fmt.println(rt)
	} else {
		fmt.println("[manager]: No work in the queue")
	}
}

process_tasks :: proc(m: ^Manager) {
	for {
		fmt.println("[manager]: Processing any tasks in the queue")
		send_work(m)
		fmt.println("[manager]: Send: Sleeping for 10 seconds")
		time.sleep(10 * time.Second)
	}
}

add_task :: proc(m: ^Manager, e: ^task.Event) {
	queue.push_back(&m.pending, e)
}

get_tasks :: proc(m: ^Manager) -> (tasks: []task.Task) {
	tasks = make([]task.Task, len(m.task_db))
	i := 0
	for _, t in m.task_db {
		tasks[i] = t^
		i += 1
	}
	return tasks
}

get_host_port :: proc(ports: connection.Port_Map) -> string {
	for k, _ in ports {
		return ports[k][0].host_port
	}
	// for k, v in ports {
	// 	return v
	// }

	return ""
}

Manager_Error :: union {
	Health_Check_Error,
}

Health_Check_Error :: struct {
	message: string,
}

check_task_health :: proc(m: ^Manager, t: ^task.Task) -> Manager_Error {
	fmt.printfln("[manager]: Calling health check for task %s: %s", t.id, t.health_check)

	w := m.task_worker_map[t.id]
	host_port := get_host_port(t.host_ports)
	if host_port == "" {
		fmt.printfln("[manager]: Have not collected task %s host port yet. Skipping", t.id)
		return nil
	}
	worker := strings.split(w, ":")
	sb: strings.Builder
	defer strings.builder_destroy(&sb)
	url := fmt.sbprintf(&sb, "http://%s:%s%s", worker[0], host_port, t.health_check)
	fmt.printf("[manager]: Calling health check for task %s: %s\n", t.id, url)
	resp, err := http.get(url)
	if err != nil {
		fmt.eprintln("Health check error:", err)
		mb: strings.Builder
		// defer strings.builder_destroy(&mb)
		msg := fmt.sbprintf(&mb, "Error connecting to health check %s", url)
		return Health_Check_Error{"Error connecting to health check"}
	}

	if http.Status_Code(resp.status) != .HTTP_OK {
		mb: strings.Builder
		// defer strings.builder_destroy(&mb)
		msg := fmt.sbprintf(&mb, "Error health check for task %s did not return 200", t.id)
		fmt.println(msg)
		return Health_Check_Error{"Non-200 error returned from health check"}
	}

	fmt.printfln("Task %s health check responese: %v", t.id, resp.status)

	return nil
}

do_health_checks :: proc(m: ^Manager) {
	for _, &t in m.task_db {
		if t.state == .Running && t.restart_count < 3 {
			err := check_task_health(m, t)
			if err != nil {
				if t.restart_count < 3 {
					restart_task(m, t)
				}
			}
		} else if t.state == .Failed && t.restart_count < 3 {
			restart_task(m, t)
		}
	}
}

restart_task :: proc(m: ^Manager, t: ^task.Task) {
	w := m.task_worker_map[t.id]
	t.state = .Scheduled
	t.restart_count += 1
	m.task_db[t.id] = t

	e := task.new_event(t^)
	// te.task.id = lib.new_uuid()
	e.state = .Running
	data, err := json.marshal(e^)
	if err != nil {
		fmt.printfln("Unable to marshal task object: %v", err)
		return
	}

	sb: strings.Builder
	defer strings.builder_destroy(&sb)
	url := fmt.sbprintf(&sb, "http://%s/tasks", w)
	resp, rerr := http.post(url, "application/json", string(data))
	if rerr != nil {
		fmt.eprintfln("Error connecting to %s: %v", w, err)
		queue.push_back(&m.pending, e)
		return
	}

	if http.Status_Code(resp.status) != .HTTP_CREATED {
		e: worker.Error_Response
		derr := json.unmarshal_string(resp.body, &e)
		if derr != nil {
			fmt.eprintfln("Error decoding response: %v", derr)
			return
		}
		fmt.printfln("Response error (%d): %s", e.status_code, e.message)
		return
	}

	new_task: task.Task
	derr := json.unmarshal_string(resp.body, &new_task)
	if derr != nil {
		fmt.eprintfln("Error decoding response: %v", err)
		return
	}
	fmt.printfln("[manager]: Response from worker: %#v", t)
}

check_health :: proc(m: ^Manager) {
	for {
		fmt.println("[manager]: Performing task health check")
		do_health_checks(m)
		fmt.println("[manager]: Task health checks completed")
		fmt.println("[manager]: Health: Sleeping for 60 seconds")
		time.sleep(60 * time.Second)
	}
}

