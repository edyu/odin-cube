package librocksdb

import "core:c"

foreign import librocksdb "system:rocksdb"

Compression :: enum c.uint {
	NO     = 0,
	SNAPPY = 1,
	ZLIB   = 2,
	BZ2    = 3,
	LZ4    = 4,
	LZ4HC  = 5,
	XPRESS = 6,
	ZSTD   = 7,
}

PROP_NUM_KEYS: cstring : "rocksdb.estimate-num-keys"

Rocksdb :: struct {}

Iterator :: struct {}

Options :: struct {}

Backup_Engine :: struct {}

Write_Options :: struct {}

Read_Options :: struct {}

Ptr :: [^]u8

Error :: cstring

foreign librocksdb {
	rocksdb_open :: proc(options: ^Options, db_path: cstring, err: ^Error) -> ^Rocksdb ---
	rocksdb_options_create :: proc() -> ^Options ---
	rocksdb_options_destroy :: proc(options: ^Options) ---
	rocksdb_options_set_create_if_missing :: proc(options: ^Options, yes: c.bool) ---
	rocksdb_options_set_error_if_exists :: proc(options: ^Options, yes: c.bool) ---
	rocksdb_options_set_compression :: proc(options: ^Options, compression: Compression) ---
	rocksdb_close :: proc(db: ^Rocksdb) ---
	rocksdb_writeoptions_create :: proc() -> ^Write_Options ---
	rocksdb_writeoptions_destroy :: proc(options: ^Write_Options) ---
	rocksdb_put :: proc(db: ^Rocksdb, options: ^Write_Options, key: Ptr, k_len: c.int, value: Ptr, v_len: c.int, err: ^Error) ---
	rocksdb_readoptions_create :: proc() -> ^Read_Options ---
	rocksdb_readoptions_destroy :: proc(options: ^Read_Options) ---
	rocksdb_get :: proc(db: ^Rocksdb, options: ^Read_Options, key: Ptr, k_len: c.int, v_len: ^c.int, err: ^Error) -> Ptr ---
	rocksdb_property_int :: proc(db: ^Rocksdb, property: cstring, value: ^c.uint64_t) -> c.int ---
	rocksdb_create_iterator :: proc(db: ^Rocksdb, options: ^Read_Options) -> ^Iterator ---
	rocksdb_iter_destroy :: proc(iter: ^Iterator) ---
	rocksdb_iter_seek_to_first :: proc(iter: ^Iterator) ---
	rocksdb_iter_valid :: proc(iter: ^Iterator) -> c.bool ---
	rocksdb_iter_next :: proc(iter: ^Iterator) ---
	rocksdb_iter_key :: proc(iter: ^Iterator, k_len: ^c.int) -> Ptr ---
	rocksdb_iter_value :: proc(iter: ^Iterator, v_len: ^c.int) -> Ptr ---
}

