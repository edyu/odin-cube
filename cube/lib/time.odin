package lib

import "core:strings"
import "core:time"

Timestamp :: distinct string

new_time :: proc() -> Timestamp {
	ts, _ := time.time_to_rfc3339(time.now())
	return Timestamp(ts)
}

clone_time :: proc(ts: Timestamp) -> Timestamp {
	return Timestamp(strings.clone_from(string(ts)))
}

parse_time :: proc(maybe_ts: string) -> (ts: Timestamp, ok: bool) {
	try_ts, _ := time.rfc3339_to_time_utc(maybe_ts)
	ts_str: string
	ts_str, ok = time.time_to_rfc3339(try_ts)
	return Timestamp(ts_str), ok
}

