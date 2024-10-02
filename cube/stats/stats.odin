package stats

import "core:fmt"
import "core:log"

Stats :: struct {
	mem_stats:  Mem_Info,
	disk_stats: Disk,
	cpu_stats:  Cpu_Stat,
	load_stats: Load_Avg,
	task_count: uint,
}

get_stats :: proc() -> (s: Stats) {
	s.mem_stats = get_mem_info()
	s.disk_stats = get_disk_info()
	s.cpu_stats = get_cpu_stats()
	s.load_stats = get_load_avg()
	return s
}

get_mem_info :: proc() -> (info: Mem_Info) {
	stat, err := read_mem_info("/proc/meminfo")
	if err != nil {
		log.errorf("Error reading from /proc/meminfo: %v", err)
		return info
	}
	return stat
}

get_disk_info :: proc() -> (info: Disk) {
	stat, err := read_disk("/")
	if err != nil {
		log.errorf("Error reading from /: %v", err)
		return info
	}
	return stat
}

get_cpu_stats :: proc() -> (info: Cpu_Stat) {
	stat, err := read_stat("/proc/stat")
	if err != nil {
		log.errorf("Error reading from /proc/stat: %v", err)
		return info
	}
	return stat
}

get_load_avg :: proc() -> (info: Load_Avg) {
	stat, err := read_load_avg("/proc/loadavg")
	if err != nil {
		log.errorf("Error reading from /proc/loadavg: %v", err)
		return info
	}
	return stat
}

mem_total_kb :: proc(s: ^Stats) -> u64 {
	return s.mem_stats.mem_total
}

mem_available_kb :: proc(s: ^Stats) -> u64 {
	return s.mem_stats.mem_available
}

mem_used_kb :: proc(s: ^Stats) -> u64 {
	return s.mem_stats.mem_total - s.mem_stats.mem_available
}

mem_used_percent :: proc(s: ^Stats) -> u64 {
	return s.mem_stats.mem_available / s.mem_stats.mem_total
}

disk_total :: proc(s: ^Stats) -> u64 {
	return s.disk_stats.all
}

disk_free :: proc(s: ^Stats) -> u64 {
	return s.disk_stats.free
}

disk_used :: proc(s: ^Stats) -> u64 {
	return s.disk_stats.used
}

cpu_usage :: proc(s: ^Stats) -> f64 {
	idle := s.cpu_stats.idle + s.cpu_stats.io_wait
	nonidle :=
		s.cpu_stats.user +
		s.cpu_stats.nice +
		s.cpu_stats.system +
		s.cpu_stats.irq +
		s.cpu_stats.soft_irq +
		s.cpu_stats.steal
	total := idle + nonidle

	if total == 0 {
		return 0.0
	}

	return f64(nonidle) / f64(total)
}

