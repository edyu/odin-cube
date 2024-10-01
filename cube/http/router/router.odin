package router

import ".."
import "../../libmhd"
import "base:builtin"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

Route_Handler :: proc(ctx: rawptr, w: ^http.Response_Writer, r: ^http.Request)

Router_Server :: struct {
	daemon: ^libmhd.Daemon,
	router: ^Router,
}

Node :: struct {
	method:  http.Method,
	pattern: string,
	handler: Route_Handler,
}

Router :: struct {
	method_map: map[string]http.Method,
	sub:        map[string]^Router,
	tree:       [dynamic]Node,
	ctx:        rawptr,
}

init_router :: proc(router: ^Router, ctx: rawptr) {
	router.ctx = ctx
	router.sub = make(map[string]^Router)
	router.tree = make([dynamic]Node)
	router.method_map = make(map[string]http.Method)
	router.method_map[libmhd.METHOD_GET] = .GET
	router.method_map[libmhd.METHOD_POST] = .POST
	router.method_map[libmhd.METHOD_PUT] = .PUT
	router.method_map[libmhd.METHOD_DELETE] = .DELETE
	router.method_map[libmhd.METHOD_PATCH] = .PATCH
}

make_router :: proc(ctx: rawptr) -> (router: Router) {
	init_router(&router, ctx)
	return router
}

new_router :: proc(ctx: rawptr) -> (router: ^Router) {
	router = new(Router)
	init_router(router, ctx)
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

sanitize_pattern :: proc(pattern: string) -> string {
	if pattern == "" {
		return "/"
	} else if pattern != "/" && strings.ends_with(pattern, "/") {
		return strings.trim_right(pattern, "/")
	}
	return pattern
}

starts_with :: proc(url: string, pattern: string) -> int {
	if strings.starts_with(url, pattern) {
		return len(pattern)
	}
	i := 0
	j := 0
	for j < len(pattern) {
		if i >= len(url) {
			return -1
		}
		if url[i] == pattern[j] {
			i += 1
			j += 1
			continue
		}
		if pattern[j] == '{' {
			cb := strings.index_rune(pattern[j:], '}')
			if cb == -1 {
				return -1
			}
			j += cb
			if j + 1 == len(pattern) {
				ns := strings.index_rune(url[i:], '/')
				if ns == -1 {
					return len(url)
				} else {
					return i + ns
				}
			} else {
				if i + 1 >= len(url) {
					return -1
				}
				ns := strings.index_rune(url[i + 1:], rune(pattern[j + 1]))
				if ns == -1 {
					return -1
				}
				i += ns - 1
			}
		} else {
			return -1
		}
	}
	return i
}

matches :: proc(url: string, pattern: string) -> bool {
	if url == pattern {
		return true
	}
	i := 0
	j := 0
	for i < len(url) && j < len(pattern) {
		if url[i] == pattern[j] {
			i += 1
			j += 1
			continue
		}
		if pattern[j] == '{' {
			cb := strings.index_rune(pattern[j:], '}')
			if cb == -1 {
				return false
			}
			j += cb
			if j + 1 == len(pattern) {
				i = len(url) - 1
			} else {
				ns := strings.index_rune(url[i:], rune(pattern[j + 1]))
				if ns == -1 {
					return false
				}
				i += ns - 1
			}
		} else {
			return false
		}
	}
	return i == len(url) && j == len(pattern)
}

route :: proc(r: ^Router, pattern: string, ctx: rawptr) -> ^Router {
	sub := new_router(ctx)
	p := sanitize_pattern(pattern)
	r.sub[p] = sub
	return sub
}

get :: proc(r: ^Router, pattern: string, handler: Route_Handler) {
	p := sanitize_pattern(pattern)
	append(&r.tree, Node{.GET, p, handler})
}

post :: proc(r: ^Router, pattern: string, handler: Route_Handler) {
	p := sanitize_pattern(pattern)
	append(&r.tree, Node{.POST, p, handler})
}

put :: proc(r: ^Router, pattern: string, handler: Route_Handler) {
	p := sanitize_pattern(pattern)
	append(&r.tree, Node{.PUT, p, handler})
}

delete :: proc(r: ^Router, pattern: string, handler: Route_Handler) {
	p := sanitize_pattern(pattern)
	append(&r.tree, Node{.DELETE, p, handler})
}

route_request :: proc(
	router: ^Router,
	w: ^http.Response_Writer,
	r: ^http.Request,
	url: string,
) -> bool {
	m := router.method_map[r.method]

	u := sanitize_pattern(url)
	for p, &s in router.sub {
		off := starts_with(u, p)
		if off != -1 {
			if off == len(u) {
				return route_request(s, w, r, "/")
			} else {
				u = u[off:]
				return route_request(s, w, r, u)
			}
		}
	}

	for n in router.tree {
		if n.method == m && matches(u, n.pattern) {
			fmt.println("[router]: url match", m, u, r.url)
			n.handler(router.ctx, w, r)
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

	request := transmute(^http.Request)con_cls^

	if string(method) == libmhd.METHOD_POST {
		if upload_data_size^ != 0 {
			append(&request.body, ..upload_data[:upload_data_size^])
			// libmhd.MHD_post_process(con_info.post_processor, upload_data, upload_data_size^)
			upload_data_size^ = 0

			// need to return here
			return .YES
		}
	}

	mux := transmute(^Router)cls
	ok := serve_http(mux, request)

	if ok {
		return .YES
	} else {
		return .NO
	}
}

serve_http :: proc(router: ^Router, r: ^http.Request) -> (ok: bool) {
	w := http.make_response_writer()
	defer http.destroy_response_writer(&w)
	route_request(router, &w, r, r.url)
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

start_server :: proc(
	port: u16,
	init: proc(mux: ^Router, ctx: rawptr),
	ctx: rawptr,
) -> (
	server: Router_Server,
	error: http.Http_Server_Error,
) {
	r := new_router(ctx)
	init(r, ctx)
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

