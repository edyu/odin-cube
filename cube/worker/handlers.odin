package worker

import "../http"
import "../lib"
import "../task"
import "core:encoding/json"
import "core:fmt"
import "core:strings"

start_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	worker := transmute(^Worker)ctx
	te := task.Event{}
	er := json.unmarshal(r.body[:], &te)
	if er != nil {
		fmt.eprintfln("Error unmarshalling body: %v", er)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error unmarshalling body: %v", er, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		append(&w.buffer, '\n')
		return
	}

	t := task.clone_task(&te.task)
	add_task(worker, t)
	fmt.printf("Added task %v\n", te.task.id)
	data, err := json.marshal(te.task)
	if err != nil {
		fmt.eprintfln("Error marshalling data: %v", err)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error marshalling data: %v", err, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(er)
		append(&w.buffer, ..m)
		append(&w.buffer, '\n')
	} else {
		w.header["Content-Type"] = "application/json"
		http.set_response_status(w, .HTTP_CREATED)
		append(&w.buffer, ..data)
		append(&w.buffer, '\n')
	}
}

get_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	worker := transmute(^Worker)ctx
	tasks := get_tasks(worker)
	defer delete(tasks)
	data, err := json.marshal(tasks)
	if err != nil {
		fmt.eprintfln("Error marshalling data: %v", err)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error marshalling data: %v", err, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		append(&w.buffer, '\n')
		return
	} else {
		w.header["Content-Type"] = "application/json"
		http.set_response_status(w, .HTTP_OK)
		append(&w.buffer, ..data)
		append(&w.buffer, '\n')
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
		fmt.eprintln("No task id passed in request.")
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		return
	} else {
		fmt.printfln("Stopping %s.", task_id)
	}

	t_id, ok := lib.parse_uuid(task_id)
	if !ok {
		fmt.eprintfln("Cannot parse task id %s", task_id)
		http.set_response_status(w, .HTTP_NOT_FOUND)
		sb: strings.Builder
		defer strings.builder_destroy(&sb)
		fmt.sbprintf(&sb, "Cannot parse task id %s", task_id, newline = true)
		e := Error_Response{.HTTP_NOT_FOUND, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}
	stopping_task, found := worker.db[t_id]
	if !found {
		fmt.eprintfln("No task with id %s found", t_id)
		sb: strings.Builder
		defer strings.builder_destroy(&sb)
		fmt.sbprintf(&sb, "No task with task id %s found", t_id, newline = true)
		http.set_response_status(w, .HTTP_NOT_FOUND)
		e := Error_Response{.HTTP_NOT_FOUND, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		append(&w.buffer, '\n')
		return
	}

	task_copy := task.clone_task(stopping_task)
	task_copy.state = .Completed
	add_task(worker, task_copy)

	fmt.printfln(
		"Added task %v to stop container %v",
		stopping_task.id,
		stopping_task.container_id,
	)
	http.set_response_status(w, .HTTP_NO_CONTENT)
}

get_stats_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	worker := transmute(^Worker)ctx
	w.header["Content-Type"] = "application/json"
	http.set_response_status(w, .HTTP_OK)
	m, _ := json.marshal(worker.stats)
	append(&w.buffer, ..m)
}

