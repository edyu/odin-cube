package store

import "core:c"
import "core:c/libc"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"

import "../lib"
import "../librocksdb"

Db :: struct($E: typeid) {
	using _:   Store(E),
	db:        ^librocksdb.Rocksdb,
	options:   ^librocksdb.Options,
	w_options: ^librocksdb.Write_Options,
	r_options: ^librocksdb.Read_Options,
}

db_init :: proc(s: ^Db($E), db_path: string) -> Store_Error {
	s.options = librocksdb.rocksdb_options_create()
	librocksdb.rocksdb_options_set_error_if_exists(s.options, true)
	librocksdb.rocksdb_options_set_create_if_missing(s.options, true)
	s.w_options = librocksdb.rocksdb_writeoptions_create()
	s.r_options = librocksdb.rocksdb_readoptions_create()
	err: librocksdb.Error
	s.db = librocksdb.rocksdb_open(
		s.options,
		strings.clone_to_cstring(db_path, context.temp_allocator),
		&err,
	)
	if err != nil {
		msg := fmt.aprintf("Cannot open database: %v", err)
		log.error(msg)
		return Db_Error{msg}
	}
	return nil
}

db_deinit :: proc(s: ^Db($E)) {
	librocksdb.rocksdb_readoptions_destroy(s.r_options)
	librocksdb.rocksdb_writeoptions_destroy(s.w_options)
	librocksdb.rocksdb_options_destroy(s.options)
	librocksdb.rocksdb_close(s.db)
}

db_put :: proc(s: ^Db($E), id: lib.UUID, t: ^E) -> Store_Error {
	value, err := json.marshal(t^)
	if err != nil {
		return err
	}
	key := raw_data(id)
	err_str: cstring
	librocksdb.rocksdb_put(
		s.db,
		s.w_options,
		key,
		c.int(len(id)),
		raw_data(value),
		c.int(len(value)),
		&err_str,
	)
	if err_str != nil {
		return Db_Error{strings.clone_from_cstring(err_str)}
	}
	return nil
}

db_get :: proc(s: ^Db($E), id: lib.UUID) -> (t: ^E, e: Store_Error) {
	key := raw_data(id)
	v_len: c.int
	err_str: cstring
	value := librocksdb.rocksdb_get(s.db, s.r_options, key, c.int(len(id)), &v_len, &err_str)
	defer libc.free(value)
	if err_str != nil {
		return nil, Db_Error{strings.clone_from_cstring(err_str)}
	}
	if value == nil {
		msg := fmt.aprintf("%v %s not found", typeid_of(E), id)
		return nil, Db_Error{msg}
	}
	t = new(E)
	err := json.unmarshal(value[:v_len], t)
	if err != nil {
		free(t)
		return nil, err
	}
	return t, nil
}

db_list :: proc(s: ^Db($E)) -> (ts: []^E, e: Store_Error) {
	iter := librocksdb.rocksdb_create_iterator(s.db, s.r_options)
	defer librocksdb.rocksdb_iter_destroy(iter)
	librocksdb.rocksdb_iter_seek_to_first(iter)
	tasks := make([dynamic]^E)
	i := 0
	for librocksdb.rocksdb_iter_valid(iter) {
		v_len: c.int
		value := librocksdb.rocksdb_iter_value(iter, &v_len)
		t := new(E)
		err := json.unmarshal(value[:v_len], t)
		if err != nil {
			free(t)
			for t in tasks {
				free(t)
			}
			delete(tasks)
			return nil, err
		}
		append(&tasks, t)
		i += 1
		librocksdb.rocksdb_iter_next(iter)
	}

	return tasks[:], nil
}

db_count :: proc(s: ^Db($E)) -> (n: u64, e: Store_Error) {
	// ts := db_list(s) or_return
	// defer {
	// 	for t in ts {
	// 		free(t)
	// 	}
	// 	delete(ts)
	// }
	// return u64(len(ts)), nil
	ret := librocksdb.rocksdb_property_int(s.db, librocksdb.PROP_NUM_KEYS, &n)
	if ret == 0 {
		return n, nil
	} else {
		return n, Db_Error{"Error getting the number of objects in the db"}
	}
}

