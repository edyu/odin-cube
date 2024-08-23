package cube

import "core:container/queue"
import "core:crypto"
import "core:encoding/uuid"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:time"
import "docker/client"
import "manager"
import "node"
import "task"
import "worker"

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

	t := task.new("Task-1", "Image-1", 1024, 1)

	te := task.new_event(t)

	fmt.printf("task: %v\n", t)
	fmt.printf("task event: %v\n", te)

	w := worker.init("worker-1")
	defer worker.deinit(&w)
	fmt.printf("worker: %v\n", w)
	worker.collect_stats(&w)
	worker.run_task(&w)
	worker.start_task(&w, &t)
	worker.stop_task(&w, &t)

	m := manager.init([]string{w.name})
	defer manager.deinit(&m)

	fmt.printf("manager: %v\n", m)
	manager.select_worker(&m)
	manager.update_tasks(&m)
	manager.send_work(&m)

	n := node.new("Node-1", "192.168.1.1", 1024, 25, "worker")

	fmt.printf("node: %v\n", n)

	fmt.printf("create a test container\n")
	docker_task, create_result := create_container()
	if create_result.error != nil {
		fmt.printf("%v", create_result.error)
		os.exit(1)
	}

	time.sleep(time.Second * 5)
	fmt.printf("stopping container %s\n", create_result.container_id)
	_ = stop_container(&docker_task, create_result.container_id)
}

create_container :: proc() -> (docker: task.Docker, result: task.Docker_Result) {
	c := task.new_test_config(
		"test-container-1",
		"postgres:13",
		[]string{"POSTGRES_USER=cube", "POSTGRES_PASSWORD=secret"},
	)

	dc, _ := client.new_env_client()
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

