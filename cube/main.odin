package cube

import "core:c"
import "core:container/queue"
import "core:crypto"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:time"
import "docker/client"
import "libmhd"
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

PAGE: cstring : "<html><head><title>blahblahblah</title></head><body>blah blah blah</body></html>"

ahc_echo :: proc "c" (
	cls: rawptr,
	connection: ^libmhd.Connection,
	url: cstring,
	method: cstring,
	version: cstring,
	upload_data: cstring,
	upload_data_size: ^c.size_t,
	ptr: ^rawptr,
) -> libmhd.Result {
	@(static) dummy: int
	page := cstring(cls)
	if method != "GET" {
		return .NO
	}
	if &dummy != ptr^ {
		ptr^ = &dummy
		return .YES
	}
	if upload_data_size^ != 0 {
		return .NO
	}
	ptr^ = nil

	response := libmhd.MHD_create_response_from_buffer(
		len(page),
		rawptr(page),
		.RESPMEM_PERSISTENT,
	)

	ret := libmhd.MHD_queue_response(connection, .HTTP_OK, response)
	libmhd.MHD_destroy_response(response)
	return ret
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

	d := libmhd.MHD_start_daemon(
		.USE_THREAD_PER_CONNECTION,
		8080,
		nil,
		nil,
		ahc_echo,
		transmute([^]u8)PAGE,
		.OPTION_END,
	)
	if d == nil {
		fmt.eprintf("can't start http daemon\n")
		os.exit(1)
	}
	defer libmhd.MHD_stop_daemon(d)

	w := worker.init("worker-1")
	defer worker.deinit(&w)

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

