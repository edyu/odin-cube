package stats

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/linux"

Stats_Error :: union {
	mem.Allocator_Error,
	os.Error,
	Stats_Parse_Error,
}

Stats_Parse_Error :: struct {
	path:    string,
	content: string,
}

Mem_Info :: struct {
	mem_total:     u64,
	mem_free:      u64,
	mem_available: u64,
}

Disk :: struct {
	all:         u64,
	free:        u64,
	used:        u64,
	free_inodes: u64,
}

Cpu_Stat :: struct {
	id:         string,
	user:       u64,
	nice:       u64,
	system:     u64,
	idle:       u64,
	io_wait:    u64,
	irq:        u64,
	soft_irq:   u64,
	steal:      u64,
	guest:      u64,
	guest_nice: u64,
}

Load_Avg :: struct {
	last_1_min:      f64,
	last_5_min:      f64,
	last_15_min:     f64,
	process_running: u64,
	process_total:   u64,
	last_pid:        u64,
}

read_mem_info :: proc(path: string) -> (info: Mem_Info, error: Stats_Error) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	fd, errno := linux.open(cpath, {})
	if errno != .NONE {
		return info, Stats_Parse_Error{path, "open"}
	}
	defer linux.close(fd)

	data: [512]u8
	read, errno2 := linux.read(fd, data[:])
	if errno2 != .NONE {
		return info, Stats_Parse_Error{path, "read"}
	}
	// data := os.read_entire_file_or_err(path) or_return
	// defer delete(data)

	lines := strings.split(string(data[:]), "\n") or_return

	for line in lines {
		fields := strings.split_n(line, ":", 2) or_return
		if len(fields) < 2 {
			continue
		}
		val := strings.fields(fields[1])
		ok: bool
		if fields[0] == "MemTotal" {
			info.mem_total, ok = strconv.parse_u64(val[0])
			if !ok {
				return info, Stats_Parse_Error{path, val[0]}
			}
		} else if fields[0] == "MemFree" {
			info.mem_free, ok = strconv.parse_u64(val[0])
			if !ok {
				return info, Stats_Parse_Error{path, val[0]}
			}
		} else if fields[0] == "MemAvailable" {
			info.mem_available, ok = strconv.parse_u64(val[0])
			if !ok {
				return info, Stats_Parse_Error{path, val[0]}
			}
		} else {
			break
		}
	}

	return info, nil
}

read_disk :: proc(path: string) -> (disk: Disk, error: Stats_Error) {
	fs: linux.Stat_FS
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	result := linux.statfs(cpath, &fs)
	if result == .NONE {
		disk.all = u64(fs.blocks * fs.bsize)
		disk.free = u64(fs.bfree * fs.bsize)
		disk.used = disk.all - disk.free
		disk.free_inodes = u64(fs.ffree)
		return disk, nil
	} else {
		sb: strings.Builder
		fmt.sbprintf(&sb, "Error calling statfs: %d", result)
		return disk, Stats_Parse_Error{"disk", strings.to_string(sb)}
	}

	return
}

read_stat :: proc(path: string) -> (cpustat: Cpu_Stat, error: Stats_Error) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	fd, errno := linux.open(cpath, {})
	if errno != .NONE {
		return cpustat, Stats_Parse_Error{path, "open"}
	}
	defer linux.close(fd)

	data: [512]u8
	read, errno2 := linux.read(fd, data[:])
	if errno2 != .NONE {
		return cpustat, Stats_Parse_Error{path, "read"}
	}
	// data := os.read_entire_file_or_err(path) or_return
	// defer delete(data)

	lines := strings.split(string(data[:]), "\n") or_return

	for line in lines {
		fields := strings.fields(line) or_return
		if len(fields) == 0 {
			continue
		}
		if fields[0][:3] == "cpu" {
			cpustat.id = "cpu"
			ok: bool

			cpustat.user, ok = strconv.parse_u64(fields[1])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[1]}
			}

			cpustat.nice, ok = strconv.parse_u64(fields[2])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[2]}
			}

			cpustat.system, ok = strconv.parse_u64(fields[3])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[3]}
			}

			cpustat.idle, ok = strconv.parse_u64(fields[4])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[4]}
			}

			cpustat.io_wait, ok = strconv.parse_u64(fields[5])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[5]}
			}

			cpustat.irq, ok = strconv.parse_u64(fields[6])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[6]}
			}

			cpustat.soft_irq, ok = strconv.parse_u64(fields[7])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[7]}
			}

			cpustat.steal, ok = strconv.parse_u64(fields[8])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[8]}
			}

			cpustat.guest, ok = strconv.parse_u64(fields[9])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[9]}
			}

			cpustat.guest_nice, ok = strconv.parse_u64(fields[10])
			if !ok {
				return cpustat, Stats_Parse_Error{path, fields[10]}
			}

			break
		}
	}

	return cpustat, nil

}

read_load_avg :: proc(path: string) -> (loadavg: Load_Avg, error: Stats_Error) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	fd, errno := linux.open(cpath, {})
	if errno != .NONE {
		return loadavg, Stats_Parse_Error{path, "open"}
	}
	defer linux.close(fd)

	data: [512]u8
	read, errno2 := linux.read(fd, data[:])
	if errno2 != .NONE {
		return loadavg, Stats_Parse_Error{path, "read"}
	}
	// data := os.read_entire_file_or_err(path) or_return
	// defer delete(data)

	content := strings.trim_space(string(data[:]))
	fields := strings.fields(content) or_return
	if len(fields) < 5 {
		return loadavg, Stats_Parse_Error{path, content}
	}
	process := strings.split(fields[3], "/")
	if len(process) != 2 {
		return loadavg, Stats_Parse_Error{path, content}
	}

	ok: bool

	loadavg.last_1_min, ok = strconv.parse_f64(fields[0])
	if !ok {
		return loadavg, Stats_Parse_Error{path, fields[0]}
	}

	loadavg.last_5_min, ok = strconv.parse_f64(fields[1])
	if !ok {
		return loadavg, Stats_Parse_Error{path, fields[1]}
	}

	loadavg.last_15_min, ok = strconv.parse_f64(fields[2])
	if !ok {
		return loadavg, Stats_Parse_Error{path, fields[2]}
	}

	loadavg.process_running, ok = strconv.parse_u64(process[0])
	if !ok {
		return loadavg, Stats_Parse_Error{path, process[1]}
	}

	loadavg.process_total, ok = strconv.parse_u64(process[1])
	if !ok {
		return loadavg, Stats_Parse_Error{path, process[1]}
	}

	loadavg.last_pid, ok = strconv.parse_u64(fields[4])
	if !ok {
		return loadavg, Stats_Parse_Error{path, fields[4]}
	}

	return loadavg, nil
}

