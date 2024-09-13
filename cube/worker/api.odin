package worker

import "../http"
import "../http/router"
import "core:fmt"

Api :: struct {
	address: string,
	port:    u16,
	server:  router.Router_Server,
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

setup_routes :: proc(mux: ^router.Router, ctx: rawptr) {
	fmt.println("SETUP ROUTES called")
	sub := router.route(mux, "/tasks", ctx)
	router.post(sub, "/", start_task_handler)
	router.get(sub, "/", get_task_handler)
	ssub := router.route(sub, "/{task_id}", ctx)
	router.delete(ssub, "/", stop_task_handler)
}

start :: proc(address: string, port: u16, worker: ^Worker) -> (api: Api) {
	api.address = address
	api.port = port
	fmt.printf("starting server %s:%d\n", address, port)
	server, err := router.start_server(port, setup_routes, worker)
	if err != nil {
		panic("error starting http daemon")
	}
	api.server = server
	return api
}

stop :: proc(api: ^Api) {
	router.stop_server(api.server)
}

