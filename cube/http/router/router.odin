package router

import ".."

Router :: struct {}
Handler :: proc(w: http.Response_Writer, r: ^http.Request)

post :: proc(r: ^Router, route: string, handler: Handler) {

}

get :: proc(route: string, handler: Handler) {

}

delete :: proc(route: string, handler: Handler) {}

route :: proc(route: string) {

}

