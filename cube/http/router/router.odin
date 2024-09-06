package router

import ".."
import "../../libmhd"
import "base:builtin"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

Router_Server :: struct {
	daemon: ^libmhd.Daemon,
	router: ^Router,
}

Node :: struct {
	method:  http.Method,
	pattern: string,
	handler: http.Handler,
}

Router :: struct {
	method_map: map[string]http.Method,
	sub:        map[string]^Router,
	tree:       [dynamic]Node,
}

init_router :: proc(router: ^Router) {
	router.sub = make(map[string]^Router)
	router.tree = make([dynamic]Node)
	router.method_map = make(map[string]http.Method)
	router.method_map[libmhd.METHOD_GET] = .GET
	router.method_map[libmhd.METHOD_POST] = .POST
	router.method_map[libmhd.METHOD_PUT] = .PUT
	router.method_map[libmhd.METHOD_DELETE] = .DELETE
	router.method_map[libmhd.METHOD_PATCH] = .PATCH
}

make_router :: proc() -> (router: Router) {
	init_router(&router)
	return router
}

new_router :: proc() -> (router: ^Router) {
	router = new(Router)
	init_router(router)
	return router
}

destroy_router :: proc(router: ^Router) {
	builtin.delete(router.method_map)
	builtin.delete(router.tree)
	for _, s in router.sub {
		destroy_router(s)
		free(s)
	}
	builtin.delete(router.sub)
}

route :: proc(r: ^Router, pattern: string) -> ^Router {
	sub := new_router()
	r.sub[pattern] = sub
	return sub
}

get :: proc(r: ^Router, pattern: string, handler: http.Handler) {
	append(&r.tree, Node{.GET, pattern, handler})
}

post :: proc(r: ^Router, pattern: string, handler: http.Handler) {
	append(&r.tree, Node{.POST, pattern, handler})
}

put :: proc(r: ^Router, pattern: string, handler: http.Handler) {
	append(&r.tree, Node{.PUT, pattern, handler})
}

delete :: proc(r: ^Router, pattern: string, handler: http.Handler) {
	append(&r.tree, Node{.DELETE, pattern, handler})
}

route_request :: proc(router: ^Router, w: ^http.Response_Writer, r: ^http.Request) -> bool {
	fmt.println("IN ROUTE")
	m := router.method_map[r.method]

	fmt.println("ROUTE: BODY IS", string(r.body[:]))
	for p, &s in router.sub {
		if strings.starts_with(r.url, p) {
			return route_request(s, w, r)
		}
	}

	for n in router.tree {
		if n.method == m && n.pattern == r.url {
			n.handler(w, r)
			return true
		}
	}

	http.set_response_status(w, .HTTP_NOT_FOUND)

	return true
}

listen_and_serve :: proc "c" (
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
		fmt.println("FIRST TIME LISTEN")
		// con_info := new(http.Connection_Info)
		// if con_info == nil {
		// 	return .NO
		// }
		request := new(http.Request)
		request.url = string(url)
		request.method = string(method)
		request.version = string(version)
		request.header = make(http.Header)
		request.body = make([dynamic]byte)
		request.connection = connection
		num_headers := libmhd.MHD_get_connection_values(
			connection,
			.MHD_HEADER_KIND,
			http.header_iterator,
			rawptr(&request.header),
		)
		fmt.printf("headers[%d]: %v\n", num_headers, request.header)

		// if string(method) == libmhd.METHOD_POST {
		// 	fmt.println("creating post processor")
		// 	con_info.post_processor = libmhd.MHD_create_post_processor(
		// 		connection,
		// 		libmhd.POST_BUFFER_SIZE,
		// 		http.post_iterator,
		// 		rawptr(con_info),
		// 	)
		// 	if con_info.post_processor == nil {
		// 		fmt.println("Error creating post processor")
		// 		builtin.delete(con_info.request.header)
		// 		builtin.delete(con_info.request.body)
		// 		free(con_info.request)
		// 		free(con_info)
		// 		return .NO
		// 	}
		// } // else GET

		con_cls^ = rawptr(request)
		return .YES
	}

	fmt.println("NOT FIRST TIME")

	request := transmute(^http.Request)con_cls^

	if request == nil {
		fmt.println("listen: request is NULL")
	}
	if request.connection == nil {
		fmt.println("listen: connection is NULL")
	}

	if string(method) == libmhd.METHOD_POST {
		fmt.println("LISTEN POST:", upload_data_size^)
		if upload_data_size^ != 0 {
			append(&request.body, ..upload_data[:upload_data_size^])
			// libmhd.MHD_post_process(con_info.post_processor, upload_data, upload_data_size^)
			upload_data_size^ = 0

			// need to return here
			return .YES
		}
	}

	fmt.println("routing request...")
	mux := transmute(^Router)cls
	ok := serve_http(mux, request)
	fmt.println("after routing request:", ok)

	if ok {
		return .YES
	} else {
		return .NO
	}
}

serve_http :: proc(router: ^Router, r: ^http.Request) -> (ok: bool) {
	w := http.make_response_writer()
	defer http.destroy_response_writer(&w)
	route_request(router, &w, r)
	append(&w.buffer, "hello there")
	fmt.println("RESPONSE.buffer.len:", len(w.buffer))
	response := libmhd.MHD_create_response_from_buffer(
		len(w.buffer),
		raw_data(w.buffer),
		// .PERSISTENT,
		.MUST_COPY,
	)
	fmt.println("WRITER:", w)
	fmt.println("RESP:", response)

	if response == nil {
		fmt.eprintln("Error: cannot create response")
		return false
	}

	for h, v in w.header {
		hs := strings.clone_to_cstring(h, context.temp_allocator)
		vs := strings.clone_to_cstring(v, context.temp_allocator)
		ret := libmhd.MHD_add_response_header(response, hs, vs)
		fmt.println("add_header:", ret, hs, vs)
	}
	ret := libmhd.MHD_queue_response(r.connection, libmhd.Status_Code(w.status_code), response)
	fmt.println("QUEUE RESP ret:", ret)
	libmhd.MHD_destroy_response(response)

	return ret == .YES
}

start_server :: proc(
	port: u16,
	init: proc(mux: ^Router),
) -> (
	server: Router_Server,
	error: http.Http_Error,
) {
	r := new_router()
	init(r)
	server.router = r
	server.daemon = libmhd.MHD_start_daemon(
		.USE_AUTO_INTERNAL_THREAD | .USE_TCP_FASTOPEN | .USE_DEBUG,
		// .USE_THREAD_PER_CONNECTION | .USE_AUTO | .USE_TCP_FASTOPEN | .USE_DEBUG,
		port,
		nil,
		nil,
		listen_and_serve,
		rawptr(server.router),
		libmhd.Option.NOTIFY_COMPLETED,
		http.request_completed,
		nil,
		libmhd.Option.THREAD_POOL_SIZE,
		4,
		libmhd.Option.END,
	)

	if server.daemon == nil {
		return server, http.Server_Start_Error{}
	}
	return server, nil
}

stop_server :: proc(server: Router_Server) {
	libmhd.MHD_stop_daemon(server.daemon)
	destroy_router(server.router)
	free(server.router)
}

