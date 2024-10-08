package lib

import "core:encoding/uuid"
import "core:strings"

UUID :: distinct string

new_uuid :: proc() -> UUID {
	return UUID(uuid.to_string(uuid.generate_v4()))
}

clone_uuid :: proc(id: UUID) -> UUID {
	return UUID(strings.clone_from(string(id)))
}

parse_uuid :: proc(maybe_id: string) -> (id: UUID, ok: bool) {
	try_id, err := uuid.read(maybe_id)
	if err != nil {
		return id, false
	} else {
		return UUID(uuid.to_string(try_id)), true
	}
}

