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

make_router :: proc() -> (router: Router) {
	router.sub = make(map[string]^Router)
	router.tree = make([dynamic]Node)
	router.method_map = make(map[string]http.Method)
	router.method_map[string(libmhd.MHD_HTTP_METHOD_GET)] = .GET
	router.method_map[string(libmhd.MHD_HTTP_METHOD_POST)] = .POST
	router.method_map[string(libmhd.MHD_HTTP_METHOD_PUT)] = .PUT
	router.method_map[string(libmhd.MHD_HTTP_METHOD_DELETE)] = .DELETE
	router.method_map[string(libmhd.MHD_HTTP_METHOD_PATCH)] = .PATCH

	return router
}

new_router :: proc() -> (router: ^Router) {
	router = new(Router)
	router.sub = make(map[string]^Router)
	router.tree = make([dynamic]Node)
	router.method_map = make(map[string]http.Method)
	router.method_map[string(libmhd.MHD_HTTP_METHOD_GET)] = .GET
	router.method_map[string(libmhd.MHD_HTTP_METHOD_POST)] = .POST
	router.method_map[string(libmhd.MHD_HTTP_METHOD_PUT)] = .PUT
	router.method_map[string(libmhd.MHD_HTTP_METHOD_DELETE)] = .DELETE
	router.method_map[string(libmhd.MHD_HTTP_METHOD_PATCH)] = .PATCH

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

handle :: proc(r: ^Router, method: http.Method, pattern: string) -> (handler: http.Handler) {
	for s in r.sub {}
	for n in r.tree {
		if n.method == method && n.pattern == pattern {
			return n.handler
		}
	}

	return nil
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

serve :: proc(router: ^Router, w: ^http.Response_Writer, r: ^http.Request) -> bool {
	fmt.println("IN SERVE")
	m := router.method_map[string(r.method)]

	for p, &s in router.sub {
		if strings.starts_with(r.url, p) {
			return serve(s, w, r)
		}
	}

	for n in router.tree {
		if n.pattern == r.url {
			n.handler(w, r)
			return true
		}
	}

	http.set_response_status(w, .HTTP_NOT_FOUND)

	return false
}

listen_and_serve :: proc "c" (
	cls: rawptr,
	connection: ^libmhd.Connection,
	url: cstring,
	method: cstring,
	version: cstring,
	upload_data: cstring,
	upload_data_size: ^c.size_t,
	ptr: ^rawptr,
) -> libmhd.Result {
	context = runtime.default_context()
	@(static) dummy: int
	mux := transmute(^Router)cls
	request: http.Request
	request.url = string(url)
	request.method = string(method)
	request.version = string(version)
	request.header = make(http.Header)
	request.connection = connection
	num_headers := libmhd.MHD_get_connection_values(
		connection,
		.MHD_HEADER_KIND,
		http.header_iterator,
		rawptr(&request.header),
	)
	fmt.printf("headers: %v\n", request.header)

	if &dummy != ptr^ {
		ptr^ = &dummy
		return .YES
	}
	if upload_data_size^ != 0 {
		return .NO
	}
	ptr^ = nil

	fmt.println("routing request...")
	ok := serve_http(&request, mux)

	if ok {
		return .YES
	} else {
		return .NO
	}
}

serve_http :: proc(r: ^http.Request, router: ^Router) -> (ok: bool) {
	w := http.make_response_writer()
	defer http.destroy_response_writer(&w)
	serve(router, &w, r)
	response := libmhd.MHD_create_response_from_buffer(
		len(w.buffer),
		raw_data(w.buffer),
		// .RESPMEM_PERSISTENT,
		.RESPMEM_MUST_COPY,
	)
	fmt.println("RESPONSE:", w)

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
		.USE_THREAD_PER_CONNECTION,
		port,
		nil,
		nil,
		listen_and_serve,
		rawptr(server.router),
		.OPTION_END,
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

