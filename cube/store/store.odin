package store

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"

import "../lib"

Db_Type :: enum {
	MEMORY     = 1,
	PERSISTENT = 2,
}

Store_Error :: union {
	Db_Error,
	json.Marshal_Error,
	json.Unmarshal_Error,
}

Db_Error :: struct {
	message: string,
}

Store :: struct($T: typeid) {
	variant: union {
		^Memory(T),
		^Db(T),
	},
}

new_store :: proc($T: typeid, $E: typeid, name: string = "") -> (s: ^T, err: Store_Error) {
	s = new(T)
	s.variant = s
	switch v in s.variant {
	case ^Memory(E):
		mem_init(v)
	case ^Db(E):
		err = db_init(v, name)
		if err != nil {
			log.fatalf("%s db cannot be initialized: %v", typeid_of(E), err)
			free(s)
			return nil, err
		}
	case:
		panic("no such store")
	}
	return s, nil
}

destroy_store :: proc(s: ^Store($E)) {
	switch v in s.variant {
	case ^Memory(E):
		mem_deinit(v)
	case ^Db(E):
		db_deinit(v)
	case:
		panic("no such store")
	}
}

put :: proc(s: ^Store($E), id: lib.UUID, t: ^E) -> Store_Error {
	switch v in s.variant {
	case ^Memory(E):
		return mem_put(v, id, t)
	case ^Db(E):
		return db_put(v, id, t)
	case:
		panic("no such store")
	}
}

get :: proc(s: ^Store($E), id: lib.UUID) -> (t: ^E, e: Store_Error) {
	switch v in s.variant {
	case ^Memory(E):
		return mem_get(v, id)
	case ^Db(E):
		return db_get(v, id)
	case:
		panic("no such store")
	}
}

list :: proc(s: ^Store($E)) -> (ts: []^E, e: Store_Error) {
	switch v in s.variant {
	case ^Memory(E):
		return mem_list(v)
	case ^Db(E):
		return db_list(v)
	case:
		panic("no such store")
	}
}

count :: proc(s: ^Store($E)) -> (n: int, e: Store_Error) {
	switch v in s.variant {
	case ^Memory(E):
		return mem_count(v)
	case ^Db(E):
		return db_count(v)
	case:
		panic("no such store")
	}
}

