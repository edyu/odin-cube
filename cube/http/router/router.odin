package router

import ".."
import "../../libmhd"
import "core:strings"

Handler :: proc(w: http.Response_Writer, r: ^http.Request)

Node :: struct {
	method:  http.Method,
	pattern: string,
	handler: Handler,
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

// destroy_router :: proc(router: ^Router) {
// 	delete(router.method_map)
// 	delete(router.tree)
// 	for _, s in router.sub {
// 		destroy_router(s)
// 	}
// 	delete(router.sub)
// }

handle :: proc(r: ^Router, method: http.Method, pattern: string) -> (handler: Handler) {
	for s in r.sub {}
	for n in r.tree {
		if n.method == method && n.pattern == pattern {
			return n.handler
		}
	}

	return nil
}

route :: proc(r: ^Router, pattern: string) -> Router {
	sub := make_router()
	r.sub[pattern] = &sub

	return sub
}

get :: proc(r: ^Router, pattern: string, handler: Handler) {
	append(&r.tree, Node{.GET, pattern, handler})
}

post :: proc(r: ^Router, pattern: string, handler: Handler) {
	append(&r.tree, Node{.POST, pattern, handler})
}

put :: proc(r: ^Router, pattern: string, handler: Handler) {
	append(&r.tree, Node{.PUT, pattern, handler})
}

delete :: proc(r: ^Router, pattern: string, handler: Handler) {
	append(&r.tree, Node{.DELETE, pattern, handler})
}

serve :: proc(router: ^Router, w: http.Response_Writer, r: ^http.Request) -> bool {
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

	return false
}

