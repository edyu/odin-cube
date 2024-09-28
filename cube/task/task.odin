package task

import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:strings"
import "core:time"

import "../lib"

import "../docker/client"
import "../docker/connection"
import "../docker/container"
import "../docker/image"

Unreachable_Error :: struct {}

Invalid_Transition_Error :: struct {
	from: State,
	to:   State,
}

Task_Error :: union {
	client.Client_Error,
	Unreachable_Error,
	Invalid_Transition_Error,
}

State :: enum u8 {
	Pending,
	Scheduled,
	Running,
	Completed,
	Failed,
}

Task :: struct {
	id:             lib.UUID,
	container_id:   string `json:"containerId,omitempty"`,
	name:           string,
	state:          State,
	image:          string,
	cpu:            f64 `json:",omitempty"`,
	memory:         i64 `json:",omitempty"`,
	disk:           i64 `json:",omitempty"`,
	exposed_ports:  connection.Port_Set `json:"exposedPorts,omitempty"`,
	host_ports:     connection.Port_Map `json:"hostPorts,omitempty"`,
	port_bindings:  connection.Port_Map `json:"portBindings,omitempty"`,
	restart_policy: string `json:"restartPolicy,omitempty"`,
	start_time:     time.Time `json:"startTime,omitempty"`,
	finish_time:    time.Time `json:"finishTime,omitempty"`,
	health_check:   string `json:"healthCheck,omitempty"`,
	restart_count:  int `json:"restartCount,omitempty"`,
}

new_task_with_id :: proc(
	id: lib.UUID,
	name: string,
	state: State,
	image: string,
) -> (
	task: ^Task,
) {
	task = new(Task)
	task.id = id
	task.name = name
	task.state = state
	task.image = image
	return task
}

new_task :: proc(name: string, state: State, image: string) -> (task: ^Task) {
	return new_task_with_id(lib.new_uuid(), name, state, image)
}

clone_task :: proc(from: ^Task) -> (task: ^Task) {
	task = new_task_with_id(lib.clone_uuid(from.id), from.name, from.state, from.image)
	task.container_id = from.container_id
	task.cpu = from.cpu
	task.memory = from.memory
	task.disk = from.disk
	task.start_time = from.start_time
	task.finish_time = from.finish_time
	task.exposed_ports = from.exposed_ports
	task.host_ports = from.host_ports
	task.port_bindings = from.port_bindings
	task.restart_policy = from.restart_policy
	task.restart_count = from.restart_count
	return task
}

free_task :: proc(task: ^Task) {
	delete(string(task.id))
	free(task)
}

Event :: struct {
	id:        lib.UUID,
	state:     State,
	timestamp: time.Time `json:"timestamp,omitempty"`,
	task:      Task,
}

new_event_with_id :: proc(id: lib.UUID, state: State, task: Task) -> (event: ^Event) {
	event = new(Event)
	event.id = id
	event.state = state
	event.timestamp = time.now()
	event.task = task
	return event
}

new_event :: proc(task: Task) -> (event: ^Event) {
	return new_event_with_id(lib.new_uuid(), .Pending, task)
}

free_event :: proc(event: ^Event) {
	delete(string(event.id))
	free(event)
}

Docker_Config :: struct {
	name:           string,
	attach_stdin:   bool,
	attach_stdout:  bool,
	attach_stderr:  bool,
	cmd:            []string,
	image:          string,
	memory:         i64,
	disk:           i64,
	env:            []string,
	restart_policy: string,
}

new_config :: proc(t: ^Task) -> (config: Docker_Config) {
	config.name = t.name
	config.image = t.image
	config.restart_policy = t.restart_policy

	return config
}

Docker :: struct {
	client: ^client.Client,
	config: Docker_Config,
}

Docker_Result :: struct {
	error:        Task_Error,
	action:       string,
	container_id: string,
	response:     container.Container_Response,
}

new_docker :: proc(config: ^Docker_Config) -> (docker: Docker) {
	dc, _ := client.init()
	docker.client = &dc
	docker.config = config^

	return docker
}

docker_run :: proc(d: ^Docker) -> Docker_Result {
	reader, err := client.image_pull(d.config.image, image.Pull_Options{})
	if err != nil {
		fmt.printf("Error pulling image %s: %v\n", d.config.image, err)
		return Docker_Result{err, "", "", nil}
	}
	stdout := os.stream_from_handle(os.stdout)
	io.copy(stdout, reader)

	options: container.Create_Options

	options.env = d.config.env
	options.image = d.config.image
	rp := container.Restart_Policy{d.config.restart_policy, 0}

	// r := container.Resources{d.config.memory}

	// cc: container.Config
	// cc.image = d.config.image
	// cc.env = d.config.env

	hc: container.Host_Config
	hc.restart_policy = rp
	// hc.resources = r
	hc.publish_all_ports = true

	// options: container.Create_Options
	// options.config = cc
	options.host_config = hc

	fmt.println("creating image name=", d.config.name)
	resp, cerr := client.container_create(d.config.name, options)
	if cerr != nil {
		fmt.printf("Error creating container using image %s: %v\n", d.config.image, cerr)
		return Docker_Result{cerr, "create", "", nil}
	}

	serr := client.container_start(resp.id, container.Start_Options{})
	if serr != nil {
		fmt.printf("Error starting container %s: %v\n", resp.id, serr)
		return Docker_Result{serr, "start", resp.id, resp}
	}

	out, lerr := client.container_logs(resp.id, container.Logs_Options{true, true})
	if lerr != nil {
		fmt.printf("Error getting logs for container %s: %v\n", resp.id, lerr)
		return Docker_Result{lerr, "logs", resp.id, resp}
	}

	stderr := os.stream_from_handle(os.stderr)
	client.std_copy(stdout, stderr, out)

	return Docker_Result{nil, "start", resp.id, resp}
}

docker_stop :: proc(d: ^Docker, id: string) -> Docker_Result {
	// ctx := context.Background()
	fmt.printf("Attempting to stop container %s\n", id)
	err := client.container_stop(id, container.Stop_Options{})
	if err != nil {
		fmt.printf("Error stopping container %s: %v\n", id, err)
		return Docker_Result{err, "stop", id, nil}
	}

	err = client.container_remove(id, container.Remove_Options{true, false, false})
	if err != nil {
		fmt.printf("Error removing container %s: %v\n", id, err)
		return Docker_Result{err, "remove", id, nil}
	}

	return Docker_Result{nil, "stop", id, nil}
}

docker_inspect :: proc(d: ^Docker, id: string) -> Docker_Result {
	fmt.printf("Attempting to inspect container %s\n", id)
	resp, err := client.container_inspect(id)
	if err != nil {
		fmt.printf("Error inspecting container %s: %v\n", id, err)
		return Docker_Result{err, "inspect", id, nil}
	}
	fmt.println("INSPECT resp:", resp)

	return Docker_Result{nil, "inspect", id, resp}
}

