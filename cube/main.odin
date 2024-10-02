package cube

import "base:runtime"
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
import "scheduler"
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

	mhost := os.get_env("CUBE_MANAGER_HOST")
	if mhost == "" {
		mhost = "localhost"
	}

	mport_str := os.get_env("CUBE_MANAGER_PORT")
	mport: u16 = 5555
	if mport_str != "" {
		mport = u16(strconv.atoi(mport_str))
	}

	whost := os.get_env("CUBE_WORKER_HOST")
	if whost == "" {
		whost = "localhost"
	}

	wport_str := os.get_env("CUBE_WORKER_PORT")
	wport: u16 = 5556
	if wport_str != "" {
		wport = u16(strconv.atoi(wport_str))
	}

	w1 := worker.init("worker-1")
	defer worker.deinit(&w1)

	w2 := worker.init("worker-2")
	defer worker.deinit(&w2)

	w3 := worker.init("worker-3")
	defer worker.deinit(&w3)

	w1_task_thread := thread.create_and_start_with_data(&w1, worker_run_tasks, context)
	defer thread.destroy(w1_task_thread)

	w1_stat_thread := thread.create_and_start_with_data(&w1, worker_collect_stats, context)
	defer thread.destroy(w1_stat_thread)

	w1_update_thread := thread.create_and_start_with_data(&w1, worker_update_tasks, context)
	defer thread.destroy(w1_update_thread)

	fmt.printfln("Starting Cube worker %s:%d", whost, wport)
	wapi1 := worker.start(whost, wport, &w1)
	defer worker.stop(&wapi1)

	w2_task_thread := thread.create_and_start_with_data(&w2, worker_run_tasks, context)
	defer thread.destroy(w2_task_thread)

	w2_stat_thread := thread.create_and_start_with_data(&w2, worker_collect_stats, context)
	defer thread.destroy(w2_stat_thread)

	w2_update_thread := thread.create_and_start_with_data(&w2, worker_update_tasks, context)
	defer thread.destroy(w2_update_thread)

	fmt.printfln("Starting Cube worker %s:%d", whost, wport + 1)
	wapi2 := worker.start(whost, wport + 1, &w2)
	defer worker.stop(&wapi2)

	w3_task_thread := thread.create_and_start_with_data(&w3, worker_run_tasks, context)
	defer thread.destroy(w3_task_thread)

	w3_stat_thread := thread.create_and_start_with_data(&w3, worker_collect_stats, context)
	defer thread.destroy(w3_stat_thread)

	w3_update_thread := thread.create_and_start_with_data(&w3, worker_update_tasks, context)
	defer thread.destroy(w3_update_thread)

	fmt.printfln("Starting Cube worker %s:%d", whost, wport + 2)
	wapi3 := worker.start(whost, wport + 2, &w3)
	defer worker.stop(&wapi3)

	workers := []string {
		fmt.tprintf("%s:%d", whost, wport),
		fmt.tprintf("%s:%d", whost, wport + 1),
		fmt.tprintf("%s:%d", whost, wport + 2),
	}

	m := manager.init(workers, scheduler.ROUND_ROBIN)
	defer manager.deinit(&m)

	m_process_thread := thread.create_and_start_with_data(&m, manager_process_tasks, context)
	defer thread.destroy(m_process_thread)

	m_update_thread := thread.create_and_start_with_data(&m, manager_update_tasks, context)
	defer thread.destroy(m_update_thread)

	m_health_thread := thread.create_and_start_with_data(&m, manager_health_check, context)
	defer thread.destroy(m_health_thread)

	fmt.printfln("Starting Cube manager %s:%d", mhost, mport)
	mapi := manager.start(mhost, mport, &m)
	defer manager.stop(&mapi)

	time.sleep(10 * time.Minute)
}

worker_collect_stats :: proc(data: rawptr) {
	w := transmute(^worker.Worker)data
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	worker.collect_stats(w)
}

worker_run_tasks :: proc(data: rawptr) {
	w := transmute(^worker.Worker)data
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	worker.run_tasks(w)
}

worker_update_tasks :: proc(data: rawptr) {
	w := transmute(^worker.Worker)data
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	worker.update_tasks(w)
}

manager_process_tasks :: proc(data: rawptr) {
	m := transmute(^manager.Manager)data
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	manager.process_tasks(m)
}

manager_update_tasks :: proc(data: rawptr) {
	m := transmute(^manager.Manager)data
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	manager.update_tasks(m)
}

manager_health_check :: proc(data: rawptr) {
	m := transmute(^manager.Manager)data
	defer runtime.default_temp_allocator_destroy(auto_cast context.temp_allocator.data)
	// context.random_generator = crypto.random_generator()
	manager.check_health(m)
}

