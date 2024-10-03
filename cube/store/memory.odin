package store

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"

import "../lib"
import "../task"

Memory :: struct($E: typeid) {
	using _: Store(E),
	db:      map[lib.UUID]^E,
}

mem_init :: proc(s: ^Memory($E)) {
	s.db = make(map[lib.UUID]^E)
}

mem_deinit :: proc(s: ^Memory($E)) {
	delete(s.db)
}

mem_put :: proc(s: ^Memory($E), id: lib.UUID, t: ^E) -> Store_Error {
	s.db[id] = t
	return nil
}

mem_get :: proc(s: ^Memory($E), id: lib.UUID) -> (t: ^E, e: Store_Error) {
	ok: bool
	t, ok = s.db[id]
	if !ok {
		msg := fmt.aprintf("Item with id %s does not exist", id)
		return nil, Nonexistent_Error{msg}
	}
	return t, nil
}

mem_list :: proc(s: ^Memory($E)) -> (ts: []^E, e: Store_Error) {
	ts = make([]^E, len(s.db))
	i := 0
	for _, t in s.db {
		ts[i] = t
		i += 1
	}
	return ts, nil
}

mem_count :: proc(s: ^Memory($E)) -> (n: int, e: Store_Error) {
	return len(s.db), nil
}

