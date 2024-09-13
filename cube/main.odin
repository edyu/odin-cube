package cube

import "core:c"
import "core:container/queue"
import "core:crypto"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "docker/client"
import "manager"
import "node"
import "task"
import "worker"

User_Formatter :: proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
	m := cast(^uuid.Identifier)arg.data
	switch verb {
	case 'v', 's':
		id_str := uuid.to_string(m^)
		defer delete(id_str)
		fmt.fmt_string(fi, id_str, 's')
	case:
		return false
	}
	return true
}

main :: proc() {
	context.logger = log.create_console_logger()
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	context.random_generator = crypto.random_generator()

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	formatters: map[typeid]fmt.User_Formatter
	// formatters := new(map[typeid]fmt.User_Formatter)
	// defer free(formatters)
	defer delete(formatters)
	fmt.set_user_formatters(&formatters)
	err := fmt.register_user_formatter(type_info_of(uuid.Identifier).id, User_Formatter)
	assert(err == .None)

	host := os.get_env("CUBE_HOST")
	if host == "" {
		host = "localhost"
	}

	port_str := os.get_env("CUBE_PORT")
	port: u16 = 5555
	if port_str != "" {
		port = u16(strconv.atoi(port_str))
	}

	fmt.println("Starting Cube worker")

	w := worker.init("worker-1")
	defer worker.deinit(&w)

	api := worker.start(host, port, &w)
	defer worker.stop(&api)

	run_tasks(&w)

	/*
	t := task.new("test-container-1", .Scheduled, "strm/helloworld-http")

	fmt.println("starting task")
	worker.add_task(&w, t)
	result := worker.run_task(&w)
	fmt.printf("post run_task: worker is %v\n", w)
	if result.error != nil {
		fmt.eprintf("%v\n", result.error)
		panic("error starting task")
	}
	fmt.printf("task: %v\n", t)

	t.container_id = result.container_id
	fmt.printf("task %s is running in container %s\n", t.id, t.container_id)
	fmt.println("sleepy time")
	fmt.printf("before sleep: worker is %v\n", w)
	time.sleep(time.Second * 30)

	fmt.printf("worker is now %v\n", w)
	fmt.printf("stopping task %s\n", t.id)
	fmt.printf("task before set: %v\n", t)
	t.state = .Completed
	fmt.printf("task before stop: %v\n", t)
	worker.add_task(&w, t)
	result = worker.run_task(&w)
	if result.error != nil {
		fmt.eprintf("%v\n", result.error)
		panic("error stopping task")
	}
	fmt.printf("task after stop: %s\n", t)
	*/

	// m := manager.init([]string{w.name})
	// defer manager.deinit(&m)

	// fmt.printf("manager: %v\n", m)
	// manager.select_worker(&m)
	// manager.update_tasks(&m)
	// manager.send_work(&m)

	// n := node.new("Node-1", "192.168.1.1", 1024, 25, "worker")

	// fmt.printf("node: %v\n", n)

	// fmt.printf("create a test container\n")
	// docker_task, create_result := create_container()
	// if create_result.error != nil {
	// 	fmt.printf("%v", create_result.error)
	// 	os.exit(1)
	// }

	// time.sleep(time.Second * 5)
	// fmt.printf("stopping container %s\n", create_result.container_id)
	// _ = stop_container(&docker_task, create_result.container_id)
}

run_tasks :: proc(w: ^worker.Worker) {
	for {
		if w.queue.len != 0 {
			result := worker.run_task(w)
			if result.error != nil {
				log.debugf("Error running task: %v", result.error)
			}
		} else {
			log.debug("No tasks to process currently.")
		}
		log.debug("Sleeping for 10 seconds.")
		time.sleep(10 * time.Second)
	}
}

create_container :: proc() -> (docker: task.Docker, result: task.Docker_Result) {
	c := task.new_test_config(
		"test-container-1",
		"postgres:13",
		[]string{"POSTGRES_USER=cube", "POSTGRES_PASSWORD=secret"},
	)

	dc, _ := client.init()
	docker.client = &dc
	docker.config = c

	result = task.docker_run(&docker)
	if result.error != nil {
		fmt.printf("%v\n", result.error)
		return
	}

	fmt.printf("Container %s is running with config %v\n", result.container_id, c)

	return
}

stop_container :: proc(d: ^task.Docker, id: string) -> (result: task.Docker_Result) {
	result = task.docker_stop(d, id)
	if result.error != nil {
		fmt.printf("%v\n", result.error)
		return
	}

	fmt.printf("Container %s has been stopped and removed\n", result.container_id)
	return result
}

