package manager

import "../http"
import "../task"
import "core:encoding/json"
import "core:encoding/uuid"
import "core:fmt"
import "core:strings"

Task :: struct {
	state: task.State,
	id:    string,
	name:  string,
	image: string,
}

Task_Event :: struct {
	id:    string,
	state: task.State,
	task:  Task,
}

start_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	manager := transmute(^Manager)ctx
	te := Task_Event{}
	err := json.unmarshal(r.body[:], &te)
	if err != nil {
		fmt.eprintfln("Error unmarshalling body: %v", err)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error unmarshalling body: %v", err, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	id, rerr := uuid.read(te.task.id)
	if rerr != nil {
		fmt.eprintfln("Error unmarshalling id: %v", err)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error unmarshalling id: %v", err, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	t := task.make(id, te.task.name, te.task.state, te.task.image)

	e_id, uerr := uuid.read(te.id)
	if uerr != nil {
		fmt.eprintfln("Error reading id: %v", uerr)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error reading id: %v", uerr, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	event := task.make_event(e_id, te.state, t)

	add_task(manager, event)
	fmt.printf("Added task %v\n", event.task.id)
	http.set_response_status(w, .HTTP_CREATED)
	m, e := json.marshal(event.task)
	append(&w.buffer, ..m)
	append(&w.buffer, '\n')
}

get_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	manager := transmute(^Manager)ctx
	data, err := json.marshal(get_tasks(manager))
	if err != nil {
		fmt.eprintfln("Error marshalling data: %v", err)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error marshalling data: %v", err, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	} else {
		w.header["Content-Type"] = "application/json"
		http.set_response_status(w, .HTTP_OK)
		append(&w.buffer, ..data)
		append(&w.buffer, '\n')
	}
}

stop_task_handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request) {
	manager := transmute(^Manager)ctx
	fmt.println("URL is", r.url)
	parts := strings.split(strings.trim_right(r.url, "/"), "/")
	task_id: string
	if len(parts) >= 1 {
		task_id = parts[len(parts) - 1]
	}
	fmt.printf("Task id=%s\n", task_id)
	if task_id == "" {
		fmt.eprintln("No task id passed in request.")
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		return
	} else {
		fmt.printfln("Stopping %s.", task_id)
	}

	t_id, err := uuid.read(task_id)
	if err != nil {
		fmt.eprintfln("Error reading id: %v", err)
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error reading id: %v", err, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	stopping_task := manager.task_db[t_id]^
	stopping_task.state = task.State.Completed
	te := task.new_event(stopping_task)
	add_task(manager, te)

	fmt.printfln("Added task event %v to stop task %v", te.id, stopping_task.id)
	http.set_response_status(w, .HTTP_NO_CONTENT)
}

