package node

import "base:builtin"

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

new :: proc(name: string, api: string, role: string) -> (node: ^Node) {
	node = builtin.new(Node)
	node.name = name
	node.api = api
	node.role = role

	return node
}

