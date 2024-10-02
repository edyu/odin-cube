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
import "../node"
import "../scheduler"
import "../task"
import "../worker"

ROUND_ROBIN :: "round_robin"
EPVM :: "epvm"

Manager_Error :: union {
	Health_Check_Error,
	Scheduler_Error,
}

Health_Check_Error :: struct {
	message: string,
}

Scheduler_Error :: struct {
	message: string,
}

Manager :: struct {
	pending:         queue.Queue(^task.Event) `fmt:"-"`,
	task_db:         map[lib.UUID]^task.Task,
	event_db:        map[lib.UUID]^task.Event,
	workers:         [dynamic]string,
	worker_task_map: map[string][dynamic]lib.UUID `fmt:"-"`,
	task_worker_map: map[lib.UUID]string `fmt:"-"`,
	last_worker:     int,
	worker_nodes:    []^node.Node,
	scheduler:       ^scheduler.Scheduler,
}

init :: proc(workers: []string, scheduler_type: string) -> (m: Manager) {
	http.client_init()
	queue.init(&m.pending)
	m.task_db = make(map[lib.UUID]^task.Task)
	m.event_db = make(map[lib.UUID]^task.Event)
	m.worker_task_map = make(map[string][dynamic]lib.UUID)
	m.task_worker_map = make(map[lib.UUID]string)
	m.workers = make([dynamic]string)
	m.worker_nodes = make([]^node.Node, len(workers))
	for w, i in workers {
		append(&m.workers, w)
		m.worker_task_map[w] = make([dynamic]lib.UUID)
		n_api := fmt.aprintf("http://%s", w)
		n := node.new(w, n_api, "worker")
		m.worker_nodes[i] = n
	}

	switch scheduler_type {
	case "round_robin":
		m.scheduler = scheduler.new_scheduler(scheduler.Round_Robin)
	case:
		msg := fmt.tprintf("unknown scheduler: %s", scheduler_type)
		panic(msg)
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
	for &n in m.worker_nodes {
		delete(n.api)
		free(n)
	}
	delete(m.worker_nodes)
	free(m.scheduler)
}

select_worker :: proc(m: ^Manager, t: task.Task) -> (node: ^node.Node, err: Manager_Error) {
	candidates := scheduler.select_nodes(m.scheduler, t, m.worker_nodes)
	if len(candidates) == 0 {
		msg := fmt.aprintf("No available candidates match resource request for task %s", t.id)
		return nil, Scheduler_Error{msg}
	}

	scores := scheduler.score(m.scheduler, t, candidates)
	log.debugf("Scheduler scores: %v", scores)
	node = scheduler.pick(m.scheduler, scores, candidates)
	log.debugf("Scheduler picked: %v", node)

	return node, nil
}

do_update_tasks :: proc(m: ^Manager) {
	for worker in m.workers {
		log.debugf("Checking worker %v for task updates", worker)
		url := fmt.tprintf("http://%s/tasks", worker)
		resp, err := http.get(url)
		if err != nil {
			log.errorf("Error connecting to %v: %v", worker, err)
		} else {
			if http.Status_Code(resp.status) != .HTTP_OK {
				log.errorf("Error sending request: %v", err)
			} else {
				tasks: []task.Task
				merr := json.unmarshal_string(resp.body, &tasks)
				if merr != nil {
					log.errorf("Error marshalling tasks: %v", err)
				} else {
					for t in tasks {
						log.debugf("Attempting to update task %v", t.id)

						if t.id not_in m.task_db {
							log.warnf("Task with id %s not found", t.id)
							continue
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
		log.debug("Checking for task updates from workers")
		do_update_tasks(m)
		log.debug("Task updates completed")
		log.debug("Sleeping for 15 seconds")
		time.sleep(15 * time.Second)
	}
}

send_work :: proc(m: ^Manager) {
	if queue.len(m.pending) > 0 {
		e := queue.pop_front(&m.pending)
		t := &e.task

		m.event_db[e.id] = e
		log.debugf("Pulled %v off pending queue", e)

		task_worker, ok := m.task_worker_map[t.id]
		if ok {
			persisted_task := m.task_db[t.id]
			if e.state == .Completed &&
			   task.valid_state_transition(persisted_task.state, e.state) {
				stop_task(m, task_worker, t.id)
				return
			}

			log.warnf(
				"Invalid request: existing task %s is in state %s and cannot transition to the completed state",
				persisted_task.id,
				persisted_task.state,
			)
			return
		}

		w, err := select_worker(m, t^)
		if err != nil {
			log.errorf("Error selecting worker for task %s: %v", t.id, err)
		}

		append(&m.worker_task_map[w.name], e.task.id)
		m.task_worker_map[t.id] = w.name

		t.state = .Scheduled
		m.task_db[t.id] = t

		data, jerr := json.marshal(e^)
		if jerr != nil {
			log.warnf("Unable to marshal task object: %v: %v.", t, jerr)
		}
		url := fmt.tprintf("http://%s/tasks", w.name)
		resp, rerr := http.post(url, "application/json", string(data))
		if rerr != nil {
			log.errorf("Error connecting to %v: %v", w, rerr)
			queue.push_back(&m.pending, e)
			return
		}
		if http.Status_Code(resp.status) != .HTTP_CREATED {
			e := worker.Error_Response{}
			err := json.unmarshal_string(resp.body, &e)
			if err != nil {
				log.errorf("Error decoding response: %v", err)
				return
			}
			log.warnf("Response error (%d): %s", e.status_code, e.message)
			return
		}

		rt := task.Task{}
		merr := json.unmarshal_string(resp.body, &rt)
		if merr != nil {
			log.errorf("Error decoding response: %v", merr)
			return
		}
		w.task_count += 1
		log.debugf("Received response from worker: %#v", rt)
	} else {
		log.debug("No work in the queue")
	}
}

process_tasks :: proc(m: ^Manager) {
	for {
		log.debug("Processing any tasks in the queue")
		send_work(m)
		log.debug("Sleeping for 10 seconds")
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
		log.errorf("Unable to marshal task object: %v", err)
		return
	}

	url := fmt.tprintf("http://%s/tasks", w)
	resp, rerr := http.post(url, "application/json", string(data))
	if rerr != nil {
		log.errorf("Error connecting to %s: %v", w, rerr)
		queue.push_back(&m.pending, e)
		return
	}

	if http.Status_Code(resp.status) != .HTTP_CREATED {
		e: worker.Error_Response
		derr := json.unmarshal_string(resp.body, &e)
		if derr != nil {
			log.errorf("Error decoding response: %v", derr)
			return
		}
		log.warnf("Response error (%d): %s", e.status_code, e.message)
		return
	}

	new_task: task.Task
	derr := json.unmarshal_string(resp.body, &new_task)
	if derr != nil {
		log.errorf("Error decoding response: %v", err)
		return
	}
	log.debugf("Response from worker: %#v", t)
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

check_health :: proc(m: ^Manager) {
	for {
		log.debug("Performing task health check")
		do_health_checks(m)
		log.debug("Task health checks completed")
		log.debug("Sleeping for 60 seconds")
		time.sleep(60 * time.Second)
	}
}

get_host_port :: proc(ports: connection.Port_Map) -> string {
	for k, _ in ports {
		return ports[k][0].host_port
	}
	return ""
}

check_task_health :: proc(m: ^Manager, t: ^task.Task) -> Manager_Error {
	log.debugf("Calling health check for task %s: %s", t.id, t.health_check)

	w := m.task_worker_map[t.id]
	host_port := get_host_port(t.host_ports)
	if host_port == "" {
		log.warnf("Have not collected task %s host port yet. Skipping", t.id)
		return nil
	}
	worker := strings.split(w, ":")
	url := fmt.tprintf("http://%s:%s%s", worker[0], host_port, t.health_check)
	log.debugf("Calling health check for task %s: %s", t.id, url)
	resp, err := http.get(url)
	if err != nil {
		msg := fmt.aprintf("Error connecting to health check %s", url)
		log.errorf("%s: %v", msg, err)
		return Health_Check_Error{msg}
	}

	if http.Status_Code(resp.status) != .HTTP_OK {
		msg := fmt.aprintf("Error health check for task %s did not return 200", t.id)
		log.warnf(msg)
		return Health_Check_Error{msg}
	}

	log.debugf("Task %s health check responese: %v", t.id, resp.status)

	return nil
}

stop_task :: proc(m: ^Manager, worker: string, task_id: lib.UUID) {
	url := fmt.tprintf("http://%s/tasks/%s", worker, task_id)
	resp, err := http.delete(url)
	if err != nil {
		log.errorf("Error connecting to worker at %s: %v", url, err)
		return
	}
	if http.Status_Code(resp.status) != .HTTP_NO_CONTENT {
		log.warnf("Error processing request: %v", resp)
		return
	}
	log.debugf("Task %s has been scheduled to be stopped", task_id)
}

