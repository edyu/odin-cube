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

setup_routes :: proc(mux: ^router.Router, ctx: rawptr) {
	sub := router.route(mux, "/tasks", ctx)
	router.post(sub, "/", start_task_handler)
	router.get(sub, "/", get_task_handler)
	ssub := router.route(sub, "/{task_id}", ctx)
	router.delete(ssub, "/", stop_task_handler)
	sub2 := router.route(mux, "/stats", ctx)
	router.get(sub2, "/", get_stats_handler)
}

start :: proc(address: string, port: u16, worker: ^Worker) -> (api: Api) {
	api.address = address
	api.port = port
	fmt.printfln("starting server %s:%d", address, port)
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

