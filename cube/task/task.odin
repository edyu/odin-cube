package task

import "core:fmt"
import "core:io"
import "core:log"
import "core:os"
import "core:time"

import "core:encoding/uuid"

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
	id:             uuid.Identifier `fmt:"q"`,
	container_id:   string,
	name:           string,
	state:          State,
	image:          string,
	cpu:            f64 `fmt:"-"`,
	memory:         i64 `fmt:"-"`,
	disk:           i64 `fmt:"-"`,
	exposed_ports:  connection.Port_Set `fmt:"-"`,
	host_ports:     connection.Port_Map `fmt:"-"`,
	port_bindings:  map[string]string `fmt:"-"`,
	restart_policy: string,
	start_time:     time.Time `fmt:"-"`,
	finish_time:    time.Time `fmt:"-"`,
	restart_count:  int `fmt:"-"`,
}

new :: proc(name: string, image: string, memory: i64, disk: i64) -> (task: Task) {
	task.id = uuid.generate_v4()
	task.name = name
	task.state = .Pending
	task.image = image
	task.memory = memory
	task.disk = disk

	return task
}

Event :: struct {
	id:        string,
	state:     State,
	timestamp: time.Time `fmt:"-"`,
	task:      Task,
}

new_event :: proc(task: Task) -> (event: Event) {
	event.id = uuid.to_string(uuid.generate_v4())
	event.state = .Pending
	event.timestamp = time.now()
	event.task = task

	return event
}

Config :: struct {
	name:           string,
	attach_stdin:   bool `fmt:"-"`,
	attach_stdout:  bool `fmt:"-"`,
	attach_stderr:  bool `fmt:"-"`,
	cmd:            []string `fmt:"-"`,
	image:          string,
	memory:         i64 `fmt:"-"`,
	disk:           i64 `fmt:"-"`,
	env:            []string,
	restart_policy: string `fmt:"-"`,
}

new_config :: proc(t: ^Task) -> (config: Config) {
	config.name = t.name
	config.image = t.image
	config.restart_policy = t.restart_policy

	return config
}

new_test_config :: proc(name: string, image: string, env: []string) -> (config: Config) {
	config.name = name
	config.image = image
	config.env = env

	return config
}

Docker :: struct {
	client: ^client.Client,
	config: Config,
}

Docker_Result :: struct {
	error:        Task_Error,
	action:       string,
	container_id: string,
	result:       string,
}

new_docker :: proc(config: ^Config) -> (docker: Docker) {
	dc, _ := client.init()
	docker.client = &dc
	docker.config = config^

	return docker
}

docker_run :: proc(d: ^Docker) -> Docker_Result {
	reader, err := client.image_pull(d.config.image, image.Pull_Options{})
	if err != nil {
		fmt.printf("Error pulling image %s: %v\n", d.config.image, err)
		return Docker_Result{err, "", "", ""}
	}
	stdout := os.stream_from_handle(os.stdout)
	io.copy(stdout, reader)

	options := container.Create_Options{}

	options.env = d.config.env
	options.image = d.config.image
	rp := container.Restart_Policy{d.config.restart_policy, 0}
	hc := container.Host_Config{d.config.memory, true, rp}
	options.host_config = hc

	resp, cerr := client.container_create(d.config.name, options)
	if cerr != nil {
		fmt.printf("Error creating container using image %s: %v\n", d.config.image, cerr)
		return Docker_Result{cerr, "create", "", "failure"}
	}

	serr := client.container_start(resp.id, container.Start_Options{})
	if serr != nil {
		fmt.printf("Error starting container %s: %v\n", resp.id, serr)
		return Docker_Result{serr, "start", resp.id, "failure"}
	}

	out, lerr := client.container_logs(resp.id, container.Logs_Options{true, true})
	if lerr != nil {
		fmt.printf("Error getting logs for container %s: %v\n", resp.id, lerr)
		return Docker_Result{lerr, "logs", resp.id, "failure"}
	}

	stderr := os.stream_from_handle(os.stderr)
	client.std_copy(stdout, stderr, out)

	return Docker_Result{nil, "start", resp.id, "success"}
}

docker_stop :: proc(d: ^Docker, id: string) -> Docker_Result {
	// ctx := context.Background()
	fmt.printf("Attempting to stop container %s\n", id)
	err := client.container_stop(id, container.Stop_Options{})
	if err != nil {
		fmt.printf("Error stopping container %s: %v\n", id, err)
		return Docker_Result{err, "stop", id, "failure"}
	}

	err = client.container_remove(id, container.Remove_Options{true, false, false})
	if err != nil {
		fmt.printf("Error removing container %s: %v\n", id, err)
		return Docker_Result{err, "remove", id, "failure"}
	}

	return Docker_Result{nil, "stop", id, "success"}
}

