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
import "core:thread"
import "core:time"
import "docker/client"
import "http"
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
	defer delete(formatters)
	fmt.set_user_formatters(&formatters)
	err := fmt.register_user_formatter(type_info_of(uuid.Identifier).id, User_Formatter)
	assert(err == .None)

	whost := os.get_env("CUBE_WORKER_HOST")
	if whost == "" {
		whost = "localhost"
	}

	wport_str := os.get_env("CUBE_WORKER_PORT")
	wport: u16 = 5555
	if wport_str != "" {
		wport = u16(strconv.atoi(wport_str))
	}

	w := worker.init("worker-1")
	defer worker.deinit(&w)

	task_thread := thread.create(thread_run_tasks)
	defer thread.destroy(task_thread)
	task_thread.data = &w
	thread.start(task_thread)

	stat_thread := thread.create(thread_collect_stats)
	defer thread.destroy(stat_thread)
	stat_thread.data = &w
	thread.start(stat_thread)

	fmt.printfln("Starting Cube worker %s:%d", whost, wport)
	wapi := worker.start(whost, wport, &w)
	defer worker.stop(&wapi)

	mhost := os.get_env("CUBE_MANAGER_HOST")
	if mhost == "" {
		mhost = "localhost"
	}

	mport_str := os.get_env("CUBE_MANAGER_PORT")
	mport: u16 = 5556
	if mport_str != "" {
		mport = u16(strconv.atoi(mport_str))
	}

	sb: strings.Builder
	defer strings.builder_destroy(&sb)
	wname := fmt.sbprintf(&sb, "%s:%d", whost, wport)
	workers := []string{wname}

	m := manager.init(workers)
	defer manager.deinit(&m)

	process_thread := thread.create(thread_process_tasks)
	defer thread.destroy(process_thread)
	process_thread.data = &m
	thread.start(process_thread)

	update_thread := thread.create(thread_update_tasks)
	defer thread.destroy(update_thread)
	update_thread.data = &m
	thread.start(update_thread)

	fmt.printfln("Starting Cube manager %s:%d", mhost, mport)
	mapi := manager.start(mhost, mport, &m)
	defer manager.stop(&mapi)

	time.sleep(5 * time.Minute)
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

thread_collect_stats :: proc(t: ^thread.Thread) {
	w := transmute(^worker.Worker)t.data
	worker.collect_stats(w)
}

thread_run_tasks :: proc(t: ^thread.Thread) {
	w := transmute(^worker.Worker)t.data
	worker.run_tasks(w)
}

thread_process_tasks :: proc(t: ^thread.Thread) {
	m := transmute(^manager.Manager)t.data
	manager.process_tasks(m)
}

thread_update_tasks :: proc(t: ^thread.Thread) {
	m := transmute(^manager.Manager)t.data
	manager.update_tasks(m)
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

