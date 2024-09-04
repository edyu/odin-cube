package http

import "../libmhd"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

Server :: struct {
	daemon: ^libmhd.Daemon,
}

Http_Error :: union {
	Server_Start_Error,
	Response_Create_Error,
}

Server_Start_Error :: struct {}

Response_Create_Error :: struct {}

Header :: map[string]string

Response_Writer :: struct {
	header:      Header,
	status_code: Status_Code,
	connection:  ^libmhd.Connection,
	response:    ^libmhd.Response,
	buffer:      [dynamic]byte,
}

make_response_writer :: proc() -> (response: Response_Writer) {
	response.header = make(map[string]string)
	response.buffer = make([dynamic]byte)

	return response
}

destroy_response_writer :: proc(response: ^Response_Writer) {
	delete(response.header)
	delete(response.buffer)
}

Request :: struct {
	url:        string,
	method:     string,
	version:    string,
	header:     Header,
	body:       string,
	connection: ^libmhd.Connection,
}

Status_Code :: enum uint {
	/* 100 "Continue".            RFC9110, Section 15.2.1. */
	HTTP_CONTINUE                             = 100,
	/* 101 "Switching Protocols". RFC9110, Section 15.2.2. */
	HTTP_SWITCHING_PROTOCOLS                  = 101,
	/* 102 "Processing".          RFC2518. */
	HTTP_PROCESSING                           = 102,
	/* 103 "Early Hints".         RFC8297. */
	HTTP_EARLY_HINTS                          = 103,

	/* 200 "OK".                  RFC9110, Section 15.3.1. */
	HTTP_OK                                   = 200,
	/* 201 "Created".             RFC9110, Section 15.3.2. */
	HTTP_CREATED                              = 201,
	/* 202 "Accepted".            RFC9110, Section 15.3.3. */
	HTTP_ACCEPTED                             = 202,
	/* 203 "Non-Authoritative Information". RFC9110, Section 15.3.4. */
	HTTP_NON_AUTHORITATIVE_INFORMATION        = 203,
	/* 204 "No Content".          RFC9110, Section 15.3.5. */
	HTTP_NO_CONTENT                           = 204,
	/* 205 "Reset Content".       RFC9110, Section 15.3.6. */
	HTTP_RESET_CONTENT                        = 205,
	/* 206 "Partial Content".     RFC9110, Section 15.3.7. */
	HTTP_PARTIAL_CONTENT                      = 206,
	/* 207 "Multi-Status".        RFC4918. */
	HTTP_MULTI_STATUS                         = 207,
	/* 208 "Already Reported".    RFC5842. */
	HTTP_ALREADY_REPORTED                     = 208,

	/* 226 "IM Used".             RFC3229. */
	HTTP_IM_USED                              = 226,

	/* 300 "Multiple Choices".    RFC9110, Section 15.4.1. */
	HTTP_MULTIPLE_CHOICES                     = 300,
	/* 301 "Moved Permanently".   RFC9110, Section 15.4.2. */
	HTTP_MOVED_PERMANENTLY                    = 301,
	/* 302 "Found".               RFC9110, Section 15.4.3. */
	HTTP_FOUND                                = 302,
	/* 303 "See Other".           RFC9110, Section 15.4.4. */
	HTTP_SEE_OTHER                            = 303,
	/* 304 "Not Modified".        RFC9110, Section 15.4.5. */
	HTTP_NOT_MODIFIED                         = 304,
	/* 305 "Use Proxy".           RFC9110, Section 15.4.6. */
	HTTP_USE_PROXY                            = 305,
	/* 306 "Switch Proxy".        Not used! RFC9110, Section 15.4.7. */
	HTTP_SWITCH_PROXY                         = 306,
	/* 307 "Temporary Redirect".  RFC9110, Section 15.4.8. */
	HTTP_TEMPORARY_REDIRECT                   = 307,
	/* 308 "Permanent Redirect".  RFC9110, Section 15.4.9. */
	HTTP_PERMANENT_REDIRECT                   = 308,

	/* 400 "Bad Request".         RFC9110, Section 15.5.1. */
	HTTP_BAD_REQUEST                          = 400,
	/* 401 "Unauthorized".        RFC9110, Section 15.5.2. */
	HTTP_UNAUTHORIZED                         = 401,
	/* 402 "Payment Required".    RFC9110, Section 15.5.3. */
	HTTP_PAYMENT_REQUIRED                     = 402,
	/* 403 "Forbidden".           RFC9110, Section 15.5.4. */
	HTTP_FORBIDDEN                            = 403,
	/* 404 "Not Found".           RFC9110, Section 15.5.5. */
	HTTP_NOT_FOUND                            = 404,
	/* 405 "Method Not Allowed".  RFC9110, Section 15.5.6. */
	HTTP_METHOD_NOT_ALLOWED                   = 405,
	/* 406 "Not Acceptable".      RFC9110, Section 15.5.7. */
	HTTP_NOT_ACCEPTABLE                       = 406,
	/* 407 "Proxy Authentication Required". RFC9110, Section 15.5.8. */
	HTTP_PROXY_AUTHENTICATION_REQUIRED        = 407,
	/* 408 "Request Timeout".     RFC9110, Section 15.5.9. */
	HTTP_REQUEST_TIMEOUT                      = 408,
	/* 409 "Conflict".            RFC9110, Section 15.5.10. */
	HTTP_CONFLICT                             = 409,
	/* 410 "Gone".                RFC9110, Section 15.5.11. */
	HTTP_GONE                                 = 410,
	/* 411 "Length Required".     RFC9110, Section 15.5.12. */
	HTTP_LENGTH_REQUIRED                      = 411,
	/* 412 "Precondition Failed". RFC9110, Section 15.5.13. */
	HTTP_PRECONDITION_FAILED                  = 412,
	/* 413 "Content Too Large".   RFC9110, Section 15.5.14. */
	HTTP_CONTENT_TOO_LARGE                    = 413,
	/* 414 "URI Too Long".        RFC9110, Section 15.5.15. */
	HTTP_URI_TOO_LONG                         = 414,
	/* 415 "Unsupported Media Type". RFC9110, Section 15.5.16. */
	HTTP_UNSUPPORTED_MEDIA_TYPE               = 415,
	/* 416 "Range Not Satisfiable". RFC9110, Section 15.5.17. */
	HTTP_RANGE_NOT_SATISFIABLE                = 416,
	/* 417 "Expectation Failed".  RFC9110, Section 15.5.18. */
	HTTP_EXPECTATION_FAILED                   = 417,


	/* 421 "Misdirected Request". RFC9110, Section 15.5.20. */
	HTTP_MISDIRECTED_REQUEST                  = 421,
	/* 422 "Unprocessable Content". RFC9110, Section 15.5.21. */
	HTTP_UNPROCESSABLE_CONTENT                = 422,
	/* 423 "Locked".              RFC4918. */
	HTTP_LOCKED                               = 423,
	/* 424 "Failed Dependency".   RFC4918. */
	HTTP_FAILED_DEPENDENCY                    = 424,
	/* 425 "Too Early".           RFC8470. */
	HTTP_TOO_EARLY                            = 425,
	/* 426 "Upgrade Required".    RFC9110, Section 15.5.22. */
	HTTP_UPGRADE_REQUIRED                     = 426,

	/* 428 "Precondition Required". RFC6585. */
	HTTP_PRECONDITION_REQUIRED                = 428,
	/* 429 "Too Many Requests".   RFC6585. */
	HTTP_TOO_MANY_REQUESTS                    = 429,

	/* 431 "Request Header Fields Too Large". RFC6585. */
	HTTP_REQUEST_HEADER_FIELDS_TOO_LARGE      = 431,

	/* 451 "Unavailable For Legal Reasons". RFC7725. */
	HTTP_UNAVAILABLE_FOR_LEGAL_REASONS        = 451,

	/* 500 "Internal Server Error". RFC9110, Section 15.6.1. */
	HTTP_INTERNAL_SERVER_ERROR                = 500,
	/* 501 "Not Implemented".     RFC9110, Section 15.6.2. */
	HTTP_NOT_IMPLEMENTED                      = 501,
	/* 502 "Bad Gateway".         RFC9110, Section 15.6.3. */
	HTTP_BAD_GATEWAY                          = 502,
	/* 503 "Service Unavailable". RFC9110, Section 15.6.4. */
	HTTP_SERVICE_UNAVAILABLE                  = 503,
	/* 504 "Gateway Timeout".     RFC9110, Section 15.6.5. */
	HTTP_GATEWAY_TIMEOUT                      = 504,
	/* 505 "HTTP Version Not Supported". RFC9110, Section 15.6.6. */
	HTTP_HTTP_VERSION_NOT_SUPPORTED           = 505,
	/* 506 "Variant Also Negotiates". RFC2295. */
	HTTP_VARIANT_ALSO_NEGOTIATES              = 506,
	/* 507 "Insufficient Storage". RFC4918. */
	HTTP_INSUFFICIENT_STORAGE                 = 507,
	/* 508 "Loop Detected".       RFC5842. */
	HTTP_LOOP_DETECTED                        = 508,

	/* 510 "Not Extended".        (OBSOLETED) RFC2774; status-change-http-experiments-to-historic. */
	HTTP_NOT_EXTENDED                         = 510,
	/* 511 "Network Authentication Required". RFC6585. */
	HTTP_NETWORK_AUTHENTICATION_REQUIRED      = 511,


	/* Not registered non-standard codes */
	/* 449 "Reply With".          MS IIS extension. */
	HTTP_RETRY_WITH                           = 449,

	/* 450 "Blocked by Windows Parental Controls". MS extension. */
	HTTP_BLOCKED_BY_WINDOWS_PARENTAL_CONTROLS = 450,

	/* 509 "Bandwidth Limit Exceeded". Apache extension. */
	HTTP_BANDWIDTH_LIMIT_EXCEEDED             = 509,
}

set_response_status :: proc(w: ^Response_Writer, code: Status_Code) {
	w.status_code = code
}

set_response_header :: proc(w: ^Response_Writer, header: string, value: string) {
	w.header[header] = value
}

write_response :: proc(w: ^Response_Writer, bytes: []byte) -> (written: int, error: Http_Error) {
	val := append(&w.buffer, ..bytes[:])
	return val, nil
}

write_response_string :: proc(
	w: ^Response_Writer,
	msg: string,
) -> (
	written: int,
	error: Http_Error,
) {
	// val := append(&w.buffer, ..(transmute([]u8)msg)[:])
	fmt.println("WRITING: ", msg)
	val := append(&w.buffer, msg[:])
	fmt.println("WROTE: ", w.buffer)
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

answer_to_connection :: proc "c" (
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
	// page := cstring(cls)
	request: Request
	request.url = string(url)
	request.method = string(method)
	request.version = string(version)
	request.header = make(Header)
	request.connection = connection
	fmt.println("calling header iterator")
	num_headers := libmhd.MHD_get_connection_values(
		connection,
		.MHD_HEADER_KIND,
		header_iterator,
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
	ok := route(&request)

	if ok {
		return .YES
	} else {
		return .NO
	}
}

PAGE: string : "<html><head><title>blahblahblah</title></head><body>blah blah blah</body></html>"

handle :: proc(r: ^Request) -> (writer: Response_Writer, error: Http_Error) {
	fmt.println("in HANDLE")
	fmt.println("REQUEST: ", r)
	writer = make_response_writer()
	writer.connection = r.connection
	set_response_status(&writer, .HTTP_OK)
	write_response_string(&writer, PAGE)
	writer.response = libmhd.MHD_create_response_from_buffer(
		len(writer.buffer),
		// transmute([^]u8)(strings.clone_to_cstring(string(writer.buffer[:]))),
		raw_data(writer.buffer),
		// .RESPMEM_PERSISTENT,
		.RESPMEM_MUST_COPY,
	)
	fmt.println("RESPONSE:", writer)

	if writer.response == nil {
		fmt.eprintln("Error: cannot create response")
		return writer, Response_Create_Error{}
	}

	return writer, nil
}

route :: proc(r: ^Request) -> (ok: bool) {
	if r.method != "GET" {
		return false
	}

	writer, err := handle(r)
	if err != nil {
		fmt.eprintf("%v\n", err)
		return false
	}
	defer destroy_response_writer(&writer)

	for h, v in writer.header {
		hs := strings.clone_to_cstring(h, context.temp_allocator)
		vs := strings.clone_to_cstring(v, context.temp_allocator)
		ret := libmhd.MHD_add_response_header(writer.response, hs, vs)
	}
	ret := libmhd.MHD_queue_response(
		r.connection,
		libmhd.Status_Code(writer.status_code),
		writer.response,
	)
	libmhd.MHD_destroy_response(writer.response)

	return ret == .YES
}

start_server :: proc(port: u16) -> (server: Server, error: Http_Error) {
	server.daemon = libmhd.MHD_start_daemon(
		.USE_THREAD_PER_CONNECTION,
		port,
		nil,
		nil,
		answer_to_connection,
		nil,
		.OPTION_END,
	)

	if server.daemon == nil {
		return server, Server_Start_Error{}
	}
	return server, nil
}

stop_server :: proc(server: Server) {
	libmhd.MHD_stop_daemon(server.daemon)
}

