package store

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"

import "../lib"

Db_Type :: enum {
	MEMORY = 1,
}

Store_Error :: union {
	Nonexistent_Error,
}

Nonexistent_Error :: struct {
	message: string,
}

Store :: struct($E: typeid) {
	variant: union {
		^Memory(E),
	},
}

new_store :: proc($T: typeid, $E: typeid) -> ^T {
	s := new(T)
	s.variant = s
	switch v in s.variant {
	case ^Memory(E):
		mem_init(v)
	case:
		panic("no such store")
	}
	return s
}

destroy_store :: proc(s: ^Store($E)) {
	switch v in s.variant {
	case ^Memory(E):
		mem_deinit(v)
	case:
		panic("no such store")
	}
}

put :: proc(s: ^Store($E), id: lib.UUID, t: ^E) -> Store_Error {
	switch v in s.variant {
	case ^Memory(E):
		return mem_put(v, id, t)
	case:
		panic("no such store")
	}
}

get :: proc(s: ^Store($E), id: lib.UUID) -> (t: ^E, e: Store_Error) {
	switch v in s.variant {
	case ^Memory(E):
		return mem_get(v, id)
	case:
		panic("no such store")
	}
}

list :: proc(s: ^Store($E)) -> (ts: []^E, e: Store_Error) {
	switch v in s.variant {
	case ^Memory(E):
		return mem_list(v)
	case:
		panic("no such store")
	}
}

count :: proc(s: ^Store($E)) -> (n: int, e: Store_Error) {
	switch v in s.variant {
	case ^Memory(E):
		return mem_count(v)
	case:
		panic("no such store")
	}
}

