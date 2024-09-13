package worker

import "../http"
import "../http/router"
import "core:fmt"

Api :: struct {
	address: string,
	port:    u16,
	worker:  ^Worker,
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

setup_routes :: proc(mux: ^router.Router) {
	fmt.println("SETUP ROUTES called")
	sub := router.route(mux, "/tasks")
	router.post(sub, "/", serve_static)
	router.get(sub, "/", serve_static)
	ssub := router.route(sub, "/{task_id}")
	router.delete(ssub, "/", serve_static)
}

start :: proc(address: string, port: u16, worker: ^Worker) -> (api: Api) {
	api.address = address
	api.port = port
	api.worker = worker
	fmt.printf("starting server %s:%d\n", address, port)
	server, err := router.start_server(port, setup_routes)
	if err != nil {
		panic("error starting http daemon")
	}
	api.server = server
	return api
}

stop :: proc(api: ^Api) {
	router.stop_server(api.server)
}

