package worker

import "../http"
import "../http/router"
import "core:fmt"

Api :: struct {
	address: string,
	port:    int,
	worker:  ^Worker,
	router:  ^router.Router,
}

Error_Response :: struct {
	status_code: http.Status_Code,
	message:     string,
}

PAGE: string : "<html><head><title>blahblahblah</title></head><body>blah blah blah</body></html>"

serve_static :: proc(w: ^http.Response_Writer, r: ^http.Request) {
	fmt.println("IN STATIC: ")
	w.header["Content-Type"] = "text/html"
	http.set_response_status(w, .HTTP_OK)
	http.write_response_string(w, PAGE)
}

setup_routes :: proc(mux: ^router.Router) {
	fmt.println("SETUP ROUTES called")
	sub := router.route(mux, "/tasks")
	router.post(sub, "/", serve_static)
	router.get(sub, "/", serve_static)
	ssub := router.route(sub, "/{task_id}")
	router.delete(ssub, "/", serve_static)
}

start :: proc(api: ^Api) {
	fmt.println("starting server on port 8080")
	server, serr := router.start_server(8080, setup_routes)
	if serr != nil {
		panic("error starting http daemon")
	}
	defer router.stop_server(server)
}

