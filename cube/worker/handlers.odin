package worker

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:strings"

import "../http"
import "../lib"
import "../store"
import "../task"

start_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	worker := transmute(^Worker)ctx
	te := task.Event{}
	er := json.unmarshal(r.body[:], &te)
	if er != nil {
		msg := fmt.tprintf("Error unmarshalling body: %v", er)
		log.error(msg)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	t := task.clone_task(&te.task)
	add_task(worker, t)
	log.debugf("Added task %v", te.task.id)
	data, err := json.marshal(te.task)
	if err != nil {
		msg := fmt.tprintf("Error marshalling data: %v", err)
		log.error(msg)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
	} else {
		w.header["Content-Type"] = "application/json"
		http.set_response_status(w, .HTTP_CREATED)
		append(&w.buffer, ..data)
	}
}

get_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	worker := transmute(^Worker)ctx
	tasks := get_tasks(worker)
	defer delete(tasks)
	data, err := json.marshal(tasks)
	if err != nil {
		msg := fmt.tprintf("Error marshalling data: %v", err)
		log.error(msg)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	} else {
		w.header["Content-Type"] = "application/json"
		http.set_response_status(w, .HTTP_OK)
		append(&w.buffer, ..data)
	}
}

stop_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	worker := transmute(^Worker)ctx
	parts := strings.split(strings.trim_right(r.url, "/"), "/")
	task_id: string
	if len(parts) >= 1 {
		task_id = parts[len(parts) - 1]
	}
	if task_id == "" {
		log.warn("No task id passed in request")
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		return
	}

	t_id, ok := lib.parse_uuid(task_id)
	if !ok {
		msg := fmt.tprintf("Cannot parse task id %s", task_id)
		log.warn(msg)
		http.set_response_status(w, .HTTP_NOT_FOUND)
		e := Error_Response{.HTTP_NOT_FOUND, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}
	stopping_task, err := store.get(worker.db, t_id)
	if err != nil {
		msg := fmt.tprintf("No task with task id %s found: %v", t_id, err)
		log.error(msg)
		http.set_response_status(w, .HTTP_NOT_FOUND)
		e := Error_Response{.HTTP_NOT_FOUND, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	task_copy := task.clone_task(stopping_task)
	task_copy.state = .Completed
	add_task(worker, task_copy)

	log.debugf("Added task %v to stop container %v", stopping_task.id, stopping_task.container_id)
	http.set_response_status(w, .HTTP_NO_CONTENT)
}

get_stats_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	worker := transmute(^Worker)ctx
	w.header["Content-Type"] = "application/json"
	http.set_response_status(w, .HTTP_OK)
	m, _ := json.marshal(worker.stats)
	append(&w.buffer, ..m)
}

