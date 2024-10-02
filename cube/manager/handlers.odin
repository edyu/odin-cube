package manager

import "../http"
import "../lib"
import "../task"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

start_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	manager := transmute(^Manager)ctx
	te := new(task.Event)
	er := json.unmarshal(r.body[:], te)
	if er != nil {
		free(te)
		msg := fmt.tprintf("Error unmarshalling body: %v", er, newline = true)
		fmt.eprint(msg)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	add_task(manager, te)
	fmt.printf("Added task %v\n", te.task.id)
	data, err := json.marshal(te.task)
	if err != nil {
		msg := fmt.tprintf("Error marshalling data: %v", err, newline = true)
		fmt.eprint(msg)
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
	manager := transmute(^Manager)ctx
	tasks := get_tasks(manager)
	defer delete(tasks)
	data, err := json.marshal(tasks)
	if err != nil {
		msg := fmt.tprintf("Error marshalling data: %v", err, newline = true)
		fmt.eprint(msg)
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
	manager := transmute(^Manager)ctx
	parts := strings.split(strings.trim_right(r.url, "/"), "/")
	task_id: string
	if len(parts) >= 1 {
		task_id = parts[len(parts) - 1]
	}
	if task_id == "" {
		fmt.eprintln("No task id passed in request")
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		return
	} else {
		fmt.printfln("Stopping %s", task_id)
	}

	t_id, ok := lib.parse_uuid(task_id)
	if !ok {
		msg := fmt.tprintf("Cannot parse task id %s", task_id, newline = true)
		fmt.eprint(msg)
		http.set_response_status(w, .HTTP_NOT_FOUND)
		e := Error_Response{.HTTP_NOT_FOUND, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}
	stopping_task, found := manager.task_db[t_id]
	if !found {
		msg := fmt.tprintf("No task with task id %s found", t_id, newline = true)
		fmt.eprint(msg)
		http.set_response_status(w, .HTTP_NOT_FOUND)
		e := Error_Response{.HTTP_NOT_FOUND, msg}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	task_copy := stopping_task^
	task_copy.state = .Completed
	te := task.new_event(task_copy)
	te.state = .Completed
	add_task(manager, te)

	fmt.printfln("Added task event %v to stop task %v", te.id, stopping_task.id)
	http.set_response_status(w, .HTTP_NO_CONTENT)
}

