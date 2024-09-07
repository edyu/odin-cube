package worker

import "../http"
import "../task"
import "core:encoding/json"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:strings"

start_task_handler :: proc(a: ^Api, w: ^http.Response_Writer, r: ^http.Request) {
	te := task.Event{}
	err := json.unmarshal(r.body[:], &te)
	if err != nil {
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error unmarshalling body: %v\n", err, newline = true)
		http.set_response_status(w, .HTTP_BAD_REQUEST)
		e := Error_Response{.HTTP_BAD_REQUEST, strings.to_string(sb)}
		m, _ := json.marshal(e)
		append(&w.buffer, ..m)
		return
	}

	add_task(a.worker, te.task)
	log.debugf("Added task %v\n", te.task.id)
	http.set_response_status(w, .HTTP_CREATED)
	m, e := json.marshal(te.task)
	append(&w.buffer, ..m)
}

get_task_handler :: proc(a: ^Api, w: ^http.Response_Writer, r: ^http.Request) {
	w.header["Content-Type"] = "application/json"
	http.set_response_status(w, .HTTP_OK)
	json.marshal(get_tasks(a.worker))
}

stop_task_handler :: proc(a: ^Api, w: ^http.Response_Writer, r: ^http.Request) {
	task_id := r.url
	if task_id == "" {
		log.debugf("No task id passed in request.\n")
		http.set_response_status(w, .HTTP_BAD_REQUEST)
	}

	t_id, err := uuid.read(task_id)

	stopping_task := a.worker.db[t_id]
	stopping_task.state = task.State.Completed
	add_task(a.worker, stopping_task)

	log.debugf(
		"Added task %v to stop container %v\n",
		stopping_task.id,
		stopping_task.container_id,
	)
	http.set_response_status(w, .HTTP_NO_CONTENT)
}

