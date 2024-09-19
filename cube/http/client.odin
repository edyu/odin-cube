package http

import "../libcurl"
import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

Http_Client_Error :: union {
	Curl_Error,
}

Curl_Error :: struct {
	code: libcurl.Code,
}

Response :: struct {
	status: int,
	body:   string,
}

// must be called before all other calls
client_init :: proc() -> Http_Client_Error {
	code := libcurl.curl_global_init(.GLOBAL_ALL)
	if code != .E_OK {
		fmt.eprintf("curl_global_init() failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}
	return nil
}

client_deinit :: proc() {
	libcurl.curl_global_cleanup()
}

Callback_Data :: struct {
	session:  ^libcurl.Session,
	response: ^Response,
}

response_callback :: proc "c" (
	buffer: rawptr,
	size: c.int,
	nmemb: c.int,
	data: ^Callback_Data,
) -> c.int {
	context = runtime.default_context()
	code := libcurl.curl_easy_getinfo(data.session, .INFO_RESPONSE_CODE, &data.response.status)
	if code != .E_OK {
		fmt.eprintf(
			"curl_easy_getinfo(RESPONSE_CODE) failed: %s\n",
			libcurl.curl_easy_strerror(code),
		)
	} else {
		reply := strings.clone_from_ptr(transmute([^]u8)buffer, int(size * nmemb))
		data.response.body = reply
	}

	return size * nmemb
}

session_init :: proc() -> (session: ^libcurl.Session, err: Http_Client_Error) {
	session = libcurl.curl_easy_init()
	if session == nil {
		return nil, Curl_Error{.E_FAILED_INIT}
	}
	return session, nil
}

session_done :: proc(session: ^libcurl.Session) {
	libcurl.curl_easy_cleanup(session)
}

session_set_unix_socket :: proc(session: ^libcurl.Session, socket: string) -> Http_Client_Error {
	code := libcurl.curl_easy_setopt(session, .OPT_UNIX_SOCKET_PATH, socket)
	if code != .E_OK {
		return Curl_Error{code}
	}
	return nil
}

session_set_content_type :: proc(
	session: ^libcurl.Session,
	content_type: string,
) -> Http_Client_Error {
	header: strings.Builder
	defer strings.builder_destroy(&header)
	fmt.sbprintf(&header, "Content-Type: %s", content_type)
	hs: ^libcurl.Slist
	hs = libcurl.curl_slist_append(hs, strings.to_cstring(&header))
	// defer libcurl.curl_slist_free_all(hs)
	code := libcurl.curl_easy_setopt(session, .OPT_HTTPHEADER, hs)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(HTTPHEADER) failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}
	return nil
}

session_post_only :: proc(
	session: ^libcurl.Session,
	url: string,
	content_type: string,
	content: string,
) -> (
	err: Http_Client_Error,
) {
	code := libcurl.curl_easy_setopt(session, .OPT_URL, url)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}

	session_set_content_type(session, content_type) or_return

	request := strings.clone_to_cstring(content, context.temp_allocator)
	code = libcurl.curl_easy_setopt(session, .OPT_POSTFIELDS, request)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(POSTFIELDS) failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}

	code = libcurl.curl_easy_perform(session)
	if code != .E_OK {
		fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}

	return nil
}

session_post :: proc(
	session: ^libcurl.Session,
	url: string,
	content_type: string,
	content: string,
) -> (
	resp: Response,
	err: Http_Client_Error,
) {
	code := libcurl.curl_easy_setopt(session, .OPT_URL, url)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
		return resp, Curl_Error{code}
	}

	session_set_content_type(session, content_type) or_return

	request := strings.clone_to_cstring(content, context.temp_allocator)
	code = libcurl.curl_easy_setopt(session, .OPT_POSTFIELDS, request)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(POSTFIELDS) failed: %s\n", libcurl.curl_easy_strerror(code))
		return resp, Curl_Error{code}
	}

	data := Callback_Data{session, &resp}
	code = libcurl.curl_easy_setopt(session, .OPT_WRITEDATA, &data)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(WRITEDATA) failed: %s\n", libcurl.curl_easy_strerror(code))
		return resp, Curl_Error{code}
	}

	code = libcurl.curl_easy_setopt(session, .OPT_WRITEFUNCTION, response_callback)
	if code != .E_OK {
		fmt.eprintf(
			"curl_easy_setopt(WRITEFUNCTION) failed: %s\n",
			libcurl.curl_easy_strerror(code),
		)
		return resp, Curl_Error{code}
	}

	code = libcurl.curl_easy_perform(session)
	if code != .E_OK {
		fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
		return resp, Curl_Error{code}
	}

	return resp, nil
}

session_delete :: proc(session: ^libcurl.Session, url: string) -> (err: Http_Client_Error) {
	code := libcurl.curl_easy_setopt(session, .OPT_URL, url)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}

	code = libcurl.curl_easy_setopt(session, .OPT_CUSTOMREQUEST, "DELETE")
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(DELETE) failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}

	code = libcurl.curl_easy_perform(session)
	if code != .E_OK {
		fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
		return Curl_Error{code}
	}

	return nil
}

session_get :: proc(
	session: ^libcurl.Session,
	url: string,
) -> (
	resp: Response,
	err: Http_Client_Error,
) {
	code := libcurl.curl_easy_setopt(session, .OPT_URL, url)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
		return resp, Curl_Error{code}
	}

	data := Callback_Data{session, &resp}
	code = libcurl.curl_easy_setopt(session, .OPT_WRITEDATA, &data)
	if code != .E_OK {
		fmt.eprintf("curl_easy_setopt(WRITEDATA) failed: %s\n", libcurl.curl_easy_strerror(code))
		return resp, Curl_Error{code}
	}

	code = libcurl.curl_easy_setopt(session, .OPT_WRITEFUNCTION, response_callback)
	if code != .E_OK {
		fmt.eprintf(
			"curl_easy_setopt(WRITEFUNCTION) failed: %s\n",
			libcurl.curl_easy_strerror(code),
		)
		return resp, Curl_Error{code}
	}

	code = libcurl.curl_easy_perform(session)
	if code != .E_OK {
		fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
		return resp, Curl_Error{code}
	}

	return resp, nil
}

get :: proc(url: string) -> (resp: Response, err: Http_Client_Error) {
	session := session_init() or_return
	defer session_done(session)
	return session_get(session, url)
}

delete :: proc(url: string) -> (err: Http_Client_Error) {
	session := session_init() or_return
	defer session_done(session)
	return session_delete(session, url)
}

post :: proc(
	url: string,
	content_type: string,
	content: string,
) -> (
	resp: Response,
	err: Http_Client_Error,
) {
	session := session_init() or_return
	defer session_done(session)
	return session_post(session, url, content_type, content)
}

