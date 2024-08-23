package node

Node :: struct {
	name:             string,
	ip:               string,
	api:              string `fmt:"-"`,
	memory:           i64,
	memory_allocated: i64 `fmt:"-"`,
	disk:             i64,
	disk_allocated:   i64 `fmt:"-"`,
	role:             string,
	task_count:       int `fmt:"-"`,
}

new :: proc(name: string, ip: string, memory: i64, disk: i64, role: string) -> (node: Node) {
	node.name = name
	node.ip = ip
	node.memory = memory
	node.disk = disk
	node.role = role

	return node
}

