package client

import "../../libcurl"
import "../container"
import "../image"
import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:io"
import "core:strings"

Client :: struct {
	scheme:              string,
	host:                string,
	proto:               string,
	addr:                string,
	base_path:           string,
	version:             string,
	custom_http_Headers: map[string]string,
}

Client_Error :: union {
	Curl_Error,
	Curl_Init_Error,
	container.Container_Error,
	json.Marshal_Error,
	Response_Error,
}

Curl_Init_Error :: struct {}

Curl_Error :: struct {
	code: libcurl.CURLcode,
}

Response_Error :: struct {
	code:    int,
	message: string,
}

init :: proc() -> (client: Client, err: Client_Error) {
	code := libcurl.curl_global_init(libcurl.CURL_GLOBAL_ALL)
	if code != libcurl.CURLcode.CURLE_OK {
		fmt.eprintf("curl_global_init() failed: %s\n", libcurl.curl_easy_strerror(code))
		err = Curl_Error{code}
	}
	return
}

deinit :: proc(client: ^Client) {
	libcurl.curl_global_cleanup()
}

DOCKER_SOCKET :: "/var/run/docker.sock"

API_PREFIX :: "http://localhost/v1.46"
// API_PREFIX :: "http://docker"

JSON_HEADER :: "Content-Type: application/json"

EMPTY_BODY :: "{}"

Container_Response :: struct {
	id: string,
}

image_pull :: proc(
	name: string,
	options: image.Pull_Options,
) -> (
	reader: io.Reader,
	err: Client_Error,
) {
	fmt.printf("docker image pull\n")
	curl := libcurl.curl_easy_init()
	defer libcurl.curl_easy_cleanup(curl)
	if curl != nil {
		code := libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_UNIX_SOCKET_PATH,
			DOCKER_SOCKET,
		)
		hs: ^libcurl.curl_slist
		hs = libcurl.curl_slist_append(hs, JSON_HEADER)
		defer libcurl.curl_slist_free_all(hs)
		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_HTTPHEADER, hs)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(HTTPHEADER) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		url: strings.Builder
		defer strings.builder_destroy(&url)
		strings.write_string(&url, API_PREFIX)
		strings.write_string(&url, "/images/create?fromImage=")
		strings.write_string(&url, name)
		code = libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_URL,
			strings.to_cstring(&url),
		)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_POSTFIELDS, EMPTY_BODY)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(POSTFIELDS) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_perform(curl)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}
	} else {
		err = Curl_Init_Error{}
	}

	return
}

Callback_Data :: struct {
	session:  ^libcurl.CURL,
	response: ^Container_Response,
	error:    ^Client_Error,
}

Error_Message :: struct {
	message: string,
}

Created_Message :: struct {
	id:       string `json:"Id"`,
	warnings: []string `json:"Warnings"`,
}

container_create_callback :: proc "c" (
	buffer: rawptr,
	size: c.int,
	nmemb: c.int,
	data: ^Callback_Data,
) -> c.int {
	context = runtime.default_context()
	status: c.int
	code := libcurl.curl_easy_getinfo(
		data.session,
		libcurl.CURLINFO.CURLINFO_RESPONSE_CODE,
		&status,
	)
	if code != libcurl.CURLcode.CURLE_OK {
		fmt.eprintf(
			"curl_easy_getinfo(RESPONSE_CODE) failed: %s\n",
			libcurl.curl_easy_strerror(code),
		)
	} else {
		// fmt.println("status code:", status)
		reply := strings.string_from_ptr(transmute([^]u8)buffer, int(size * nmemb))
		// fmt.printf("DATA: %s", reply)
		if status >= 400 {
			m: Error_Message
			err := json.unmarshal_string(reply, &m)
			if err != nil {
				fmt.eprintf("error marshalling: %v\n", err)
			}
			data.error^ = Response_Error{int(status), m.message}
		} else {
			m: Created_Message
			err := json.unmarshal_string(reply, &m)
			if err != nil {
				fmt.eprintf("error marshalling: %v\n", err)
			}
			data.response.id = m.id
			fmt.println("id:", m.id)
		}
	}

	return size * nmemb
}

container_create :: proc(
	name: string,
	options: container.Create_Options,
) -> (
	resp: Container_Response,
	err: Client_Error,
) {
	fmt.printf("docker container create\n")
	curl := libcurl.curl_easy_init()
	defer libcurl.curl_easy_cleanup(curl)
	if curl != nil {
		code := libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_UNIX_SOCKET_PATH,
			DOCKER_SOCKET,
		)
		hs: ^libcurl.curl_slist
		hs = libcurl.curl_slist_append(hs, JSON_HEADER)
		defer libcurl.curl_slist_free_all(hs)
		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_HTTPHEADER, hs)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(HTTPHEADER) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		url: strings.Builder
		defer strings.builder_destroy(&url)
		strings.write_string(&url, API_PREFIX)
		strings.write_string(&url, "/containers/create?name=")
		strings.write_string(&url, name)
		fmt.printf("container create: url=%s\n", strings.to_string(url))
		code = libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_URL,
			strings.to_cstring(&url),
		)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}

		fields: strings.Builder
		defer strings.builder_destroy(&fields)
		json.marshal_to_builder(&fields, options, &json.Marshal_Options{}) or_return
		fmt.printf("container create: fields=%s\n", strings.to_string(fields))
		code = libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_POSTFIELDS,
			strings.to_cstring(&fields),
		)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(POSTFIELDS) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		data := Callback_Data{curl, &resp, &err}

		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_WRITEDATA, &data)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(WRITEDATA) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_WRITEFUNCTION,
			container_create_callback,
		)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(WRITEFUNCTION) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_perform(curl)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}
	} else {
		err = Curl_Init_Error{}
	}
	return
}

container_start :: proc(id: string, options: container.Start_Options) -> (err: Client_Error) {
	fmt.printf("docker container start %s\n", id)
	curl := libcurl.curl_easy_init()
	defer libcurl.curl_easy_cleanup(curl)
	if curl != nil {
		code := libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_UNIX_SOCKET_PATH,
			DOCKER_SOCKET,
		)
		hs: ^libcurl.curl_slist
		hs = libcurl.curl_slist_append(hs, JSON_HEADER)
		defer libcurl.curl_slist_free_all(hs)
		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_HTTPHEADER, hs)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(HTTPHEADER) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		url: strings.Builder
		defer strings.builder_destroy(&url)
		strings.write_string(&url, API_PREFIX)
		strings.write_string(&url, "/containers/")
		strings.write_string(&url, id)
		strings.write_string(&url, "/start")
		code = libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_URL,
			strings.to_cstring(&url),
		)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_POSTFIELDS, EMPTY_BODY)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(POSTFIELDS) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_perform(curl)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}
	} else {
		err = Curl_Init_Error{}
	}

	return
}

container_logs :: proc(
	id: string,
	options: container.Logs_Options,
) -> (
	reader: io.Reader,
	err: Client_Error,
) {
	fmt.printf("docker constainer logs %s\n", id)
	return
}

std_copy :: proc(dstout, dsterr: io.Writer, src: io.Reader) -> (writtent: i64, err: Client_Error) {
	fmt.printf("docker std copy\n")
	return
}

container_stop :: proc(id: string, options: container.Stop_Options) -> (err: Client_Error) {
	fmt.printf("docker container stop %s\n", id)
	curl := libcurl.curl_easy_init()
	defer libcurl.curl_easy_cleanup(curl)
	if curl != nil {
		code := libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_UNIX_SOCKET_PATH,
			DOCKER_SOCKET,
		)
		hs: ^libcurl.curl_slist
		hs = libcurl.curl_slist_append(hs, JSON_HEADER)
		defer libcurl.curl_slist_free_all(hs)
		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_HTTPHEADER, hs)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(HTTPHEADER) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		url: strings.Builder
		defer strings.builder_destroy(&url)
		strings.write_string(&url, API_PREFIX)
		strings.write_string(&url, "/containers/")
		strings.write_string(&url, id)
		strings.write_string(&url, "/stop")
		code = libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_URL,
			strings.to_cstring(&url),
		)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_POSTFIELDS, EMPTY_BODY)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(POSTFIELDS) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_perform(curl)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}
	} else {
		err = Curl_Init_Error{}
	}

	return
}

container_remove :: proc(id: string, options: container.Remove_Options) -> (err: Client_Error) {
	fmt.printf("docker container remove %s\n", id)
	curl := libcurl.curl_easy_init()
	defer libcurl.curl_easy_cleanup(curl)
	if curl != nil {
		code := libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_UNIX_SOCKET_PATH,
			DOCKER_SOCKET,
		)
		hs: ^libcurl.curl_slist
		hs = libcurl.curl_slist_append(hs, JSON_HEADER)
		defer libcurl.curl_slist_free_all(hs)
		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_HTTPHEADER, hs)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf(
				"curl_easy_setopt(HTTPHEADER) failed: %s\n",
				libcurl.curl_easy_strerror(code),
			)
			err = Curl_Error{code}
			return
		}

		url: strings.Builder
		defer strings.builder_destroy(&url)
		strings.write_string(&url, API_PREFIX)
		strings.write_string(&url, "/containers/")
		strings.write_string(&url, id)
		code = libcurl.curl_easy_setopt(
			curl,
			libcurl.CURLoption.CURLOPT_URL,
			strings.to_cstring(&url),
		)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_setopt(URL) failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_setopt(curl, libcurl.CURLoption.CURLOPT_CUSTOMREQUEST, "DELETE")
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_setopt(DELETE) failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}

		code = libcurl.curl_easy_perform(curl)
		if code != libcurl.CURLcode.CURLE_OK {
			fmt.eprintf("curl_easy_perform() failed: %s\n", libcurl.curl_easy_strerror(code))
			err = Curl_Error{code}
			return
		}
	} else {
		err = Curl_Init_Error{}
	}

	return
}

