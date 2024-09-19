package http

import "../libmhd"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

Server :: struct {
	daemon: ^libmhd.Daemon,
}

Http_Server_Error :: union {
	Server_Start_Error,
	Response_Create_Error,
}

Server_Start_Error :: struct {}

Response_Create_Error :: struct {}

Header :: map[string]string

Response_Writer :: struct {
	status_code: Status_Code,
	header:      Header,
	buffer:      [dynamic]byte `fmt:"s"`,
}

Request :: struct {
	url:        string,
	method:     string,
	version:    string,
	header:     Header,
	body:       [dynamic]u8,
	connection: ^libmhd.Connection,
}

Handler :: proc(w: ^Response_Writer, r: ^Request)

make_response_writer :: proc() -> (response: Response_Writer) {
	response.header = make(map[string]string)
	response.buffer = make([dynamic]u8)

	return response
}

destroy_response_writer :: proc(response: ^Response_Writer) {
	delete(response.header)
	delete(response.buffer)
}

set_response_status :: proc(w: ^Response_Writer, code: Status_Code) {
	w.status_code = code
}

set_response_header :: proc(w: ^Response_Writer, header: string, value: string) {
	w.header[header] = value
}

write_response :: proc(
	w: ^Response_Writer,
	bytes: []u8,
) -> (
	written: int,
	error: Http_Server_Error,
) {
	val := append(&w.buffer, ..bytes)
	return val, nil
}

write_response_string :: proc(
	w: ^Response_Writer,
	msg: string,
) -> (
	written: int,
	error: Http_Server_Error,
) {
	val := append(&w.buffer, msg[:])
	return val, nil
}

header_iterator :: proc "c" (
	cls: rawptr,
	kind: libmhd.Value_Kind,
	key: cstring,
	value: cstring,
) -> libmhd.Result {
	headers := transmute(^Header)cls
	headers[string(key)] = string(value)

	return .YES
}

Connection_Info :: struct {
	request:        ^Request,
	post_processor: ^libmhd.Post_Processor,
}

post_iterator :: proc "c" (
	coninfo_cls: rawptr,
	kind: libmhd.Value_Kind,
	key: cstring,
	filename: cstring,
	content_type: cstring,
	transfer_encoding: cstring,
	data: [^]byte,
	off: c.uint64_t,
	size: c.size_t,
) -> libmhd.Result {
	context = runtime.default_context()

	con_info := transmute(^Connection_Info)coninfo_cls
	if size > 0 {
		append_elems(&con_info.request.body, ..data[:size])
	}

	return .YES
}

request_completed :: proc "c" (
	cls: rawptr,
	connection: ^libmhd.Connection,
	con_cls: ^rawptr,
	toe: libmhd.Request_Termination_Code,
) {
	context = runtime.default_context()
	fmt.println("IN REQUEST COMPLETED:", toe)

	request := transmute(^Request)con_cls^
	if request == nil {
		fmt.println("COMPLETED: request is NULL")
		return
	}
	if request.method == libmhd.METHOD_POST {
		fmt.println("COMPLETED: method is POST")
		// libmhd.MHD_destroy_post_processor(con_info.post_processor)
	}

	delete(request.body)
	delete(request.header)
	free(request)
	// free(con_info)
	con_cls^ = nil
}

answer_to_connection :: proc "c" (
	cls: rawptr,
	connection: ^libmhd.Connection,
	url: cstring,
	method: cstring,
	version: cstring,
	upload_data: [^]u8,
	upload_data_size: ^c.size_t,
	con_cls: ^rawptr,
) -> libmhd.Result {
	context = runtime.default_context()

	if con_cls^ == nil {
		// con_info := new(Connection_Info)
		// if con_info == nil {
		// 	return .NO
		// }
		request := new(Request)
		request.url = string(url)
		request.method = string(method)
		request.version = string(version)
		request.header = make(Header)
		request.body = make([dynamic]byte)
		request.connection = connection
		libmhd.MHD_get_connection_values(
			connection,
			.MHD_HEADER_KIND,
			header_iterator,
			rawptr(&request.header),
		)

		if string(method) == libmhd.METHOD_POST {
			// con_info.post_processor = libmhd.MHD_create_post_processor(
			// 	connection,
			// 	libmhd.POST_BUFFER_SIZE,
			// 	post_iterator,
			// 	rawptr(con_info),
			// )
			// if con_info.post_processor == nil {
			// 	free(con_info)
			// 	return .NO
			// }
		} // else GET

		// con_cls^ = rawptr(con_info)
		con_cls^ = rawptr(request)
		return .YES
	}

	con_info := transmute(^Connection_Info)con_cls^
	handler := Handler(cls)

	if string(method) == libmhd.METHOD_POST {
		if upload_data_size^ != 0 {
			libmhd.MHD_post_process(con_info.post_processor, upload_data, upload_data_size^)
			upload_data_size^ = 0

			return .YES
		}
	}

	ok := handle_request(con_info.request, handler)

	if ok {
		return .YES
	} else {
		return .NO
	}
}

handle_request :: proc(r: ^Request, handler: Handler) -> (ok: bool) {
	w := make_response_writer()
	defer destroy_response_writer(&w)
	handler(&w, r)
	response := libmhd.MHD_create_response_from_buffer(
		len(w.buffer),
		raw_data(w.buffer),
		// .PERSISTENT,
		.MUST_COPY,
	)

	if response == nil {
		fmt.eprintln("Error: cannot create response")
		return false
	}

	for h, v in w.header {
		hs := strings.clone_to_cstring(h, context.temp_allocator)
		vs := strings.clone_to_cstring(v, context.temp_allocator)
		ret := libmhd.MHD_add_response_header(response, hs, vs)
	}
	ret := libmhd.MHD_queue_response(r.connection, libmhd.Status_Code(w.status_code), response)
	libmhd.MHD_destroy_response(response)

	return ret == .YES
}

start_server :: proc(port: u16, handler: Handler) -> (server: Server, error: Http_Server_Error) {
	server.daemon = libmhd.MHD_start_daemon(
		.USE_THREAD_PER_CONNECTION,
		port,
		nil,
		nil,
		answer_to_connection,
		rawptr(handler),
		libmhd.Option.NOTIFY_COMPLETED,
		request_completed,
		nil,
		libmhd.Option.END,
	)

	if server.daemon == nil {
		return server, Server_Start_Error{}
	}
	return server, nil
}

stop_server :: proc(server: Server) {
	libmhd.MHD_stop_daemon(server.daemon)
}

