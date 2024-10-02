package node

import "core:encoding/json"
import "core:fmt"
import "core:log"

import "../http"
import "../stats"
import "../utils"

Node :: struct {
	name:             string,
	ip:               string,
	api:              string,
	cpu:              f64,
	memory:           u64,
	memory_allocated: u64,
	disk:             u64,
	disk_allocated:   u64,
	stats:            stats.Stats,
	role:             string,
	task_count:       int,
}

Node_Error :: union {
	Stats_Error,
}

Stats_Error :: struct {
	message: string,
}

new_node :: proc(name: string, api: string, role: string) -> (node: ^Node) {
	node = new(Node)
	node.name = name
	node.api = api
	node.role = role

	return node
}

get_stats :: proc(n: ^Node) -> (s: stats.Stats, e: Node_Error) {
	url := fmt.tprintf("%s/stats", n.api)
	resp, err := utils.http_with_retry(http.get, url)
	if err != nil {
		msg := fmt.aprintf("Unable to connect to %v, permanent failure: %v", n.api, err)
		log.error(msg)
		return s, Stats_Error{msg}
	}

	if http.Status_Code(resp.status) != .HTTP_OK {
		msg := fmt.aprintf("Error retrieving stats from %s: %d", n.api, resp.status)
		log.error(msg)
		return s, Stats_Error{msg}
	}

	uerr := json.unmarshal_string(resp.body, &s)
	if uerr != nil {
		msg := fmt.aprintf(
			"Error decoding message while getting stats for node %s: %v",
			n.name,
			uerr,
		)
		log.error(msg)
		return s, Stats_Error{msg}
	}

	n.cpu = stats.cpu_usage(&s)
	n.memory = stats.mem_total_kb(&s)
	n.disk = stats.disk_total(&s)
	n.memory_allocated = stats.mem_used_kb(&s)
	n.disk_allocated = stats.disk_used(&s)

	n.stats = s

	return s, nil
}

