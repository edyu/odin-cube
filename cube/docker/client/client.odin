package client

import "../../http"
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
	http.Curl_Error,
	http.Http_Client_Error,
	container.Container_Error,
	json.Marshal_Error,
	Response_Error,
}

Response_Error :: struct {
	code:    int,
	message: string,
}

init :: proc() -> (client: Client, err: Client_Error) {
	http.client_init() or_return
	return client, nil
}

deinit :: proc(client: ^Client) {
	http.client_deinit()
}

DOCKER_SOCKET :: "/var/run/docker.sock"

API_PREFIX :: "http://localhost/v1.46"
// API_PREFIX :: "http://docker"

JSON_HEADER :: "application/json"

EMPTY_JSON: string : "{}"

image_pull :: proc(
	name: string,
	options: image.Pull_Options,
) -> (
	stream: io.Reader,
	err: Client_Error,
) {
	fmt.printf("docker image pull\n")
	session := http.session_init() or_return
	defer http.session_done(session)

	http.session_set_unix_socket(session, DOCKER_SOCKET) or_return

	url: strings.Builder
	defer strings.builder_destroy(&url)
	strings.write_string(&url, API_PREFIX)
	strings.write_string(&url, "/images/create?fromImage=")
	strings.write_string(&url, name)

	resp := http.session_post(session, strings.to_string(url), JSON_HEADER, EMPTY_JSON) or_return

	reader: strings.Reader
	strings.reader_init(&reader, resp.body)
	return strings.reader_to_stream(&reader), nil
	// return stream, nil
}

Error_Message :: struct {
	message: string,
}

container_create :: proc(
	name: string,
	options: container.Create_Options,
) -> (
	resp: container.Create_Response,
	err: Client_Error,
) {
	fmt.printf("docker container create\n")
	session := http.session_init() or_return
	defer http.session_done(session)

	http.session_set_unix_socket(session, DOCKER_SOCKET) or_return

	url: strings.Builder
	defer strings.builder_destroy(&url)
	strings.write_string(&url, API_PREFIX)
	strings.write_string(&url, "/containers/create?name=")
	strings.write_string(&url, name)

	fields: strings.Builder
	defer strings.builder_destroy(&fields)
	json.marshal_to_builder(&fields, options, &json.Marshal_Options{}) or_return

	fmt.println("DOCKER CREATE: ", strings.to_string(fields))

	reply := http.session_post(
		session,
		strings.to_string(url),
		JSON_HEADER,
		strings.to_string(fields),
	) or_return

	if reply.status >= 400 {
		m: Error_Message
		err := json.unmarshal_string(reply.body, &m)
		if err != nil {
			fmt.eprintf("error marshalling: %v\n", err)
		}
		return resp, Response_Error{reply.status, m.message}
	} else {
		err := json.unmarshal_string(reply.body, &resp)
		if err != nil {
			fmt.eprintf("error marshalling: %s -> %v\n", reply, err)
		}
		fmt.println("id:", resp.id)
		fmt.println("warnings:", resp.warnings)
	}

	return resp, nil
}

container_start :: proc(id: string, options: container.Start_Options) -> Client_Error {
	fmt.printf("docker container start %s\n", id)
	session := http.session_init() or_return
	defer http.session_done(session)

	http.session_set_unix_socket(session, DOCKER_SOCKET)

	url: strings.Builder
	defer strings.builder_destroy(&url)
	strings.write_string(&url, API_PREFIX)
	strings.write_string(&url, "/containers/")
	strings.write_string(&url, id)
	strings.write_string(&url, "/start")

	http.session_post_only(session, strings.to_string(url), JSON_HEADER, EMPTY_JSON) or_return

	return nil
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

container_stop :: proc(id: string, options: container.Stop_Options) -> Client_Error {
	fmt.printf("docker container stop %s\n", id)
	session := http.session_init() or_return
	defer http.session_done(session)

	http.session_set_unix_socket(session, DOCKER_SOCKET) or_return

	url: strings.Builder
	defer strings.builder_destroy(&url)
	strings.write_string(&url, API_PREFIX)
	strings.write_string(&url, "/containers/")
	strings.write_string(&url, id)
	strings.write_string(&url, "/stop")

	http.session_post_only(session, strings.to_string(url), JSON_HEADER, EMPTY_JSON)

	return nil
}

container_remove :: proc(id: string, options: container.Remove_Options) -> Client_Error {
	fmt.printf("docker container remove %s\n", id)
	session := http.session_init() or_return
	defer http.session_done(session)

	http.session_set_unix_socket(session, DOCKER_SOCKET) or_return

	url: strings.Builder
	defer strings.builder_destroy(&url)
	strings.write_string(&url, API_PREFIX)
	strings.write_string(&url, "/containers/")
	strings.write_string(&url, id)

	http.session_delete(session, strings.to_string(url)) or_return

	return nil
}

container_inspect :: proc(id: string) -> (resp: container.Inspect_Response, err: Client_Error) {
	fmt.printf("docker container inspect\n")
	session := http.session_init() or_return
	defer http.session_done(session)

	http.session_set_unix_socket(session, DOCKER_SOCKET) or_return

	url: strings.Builder
	defer strings.builder_destroy(&url)
	strings.write_string(&url, API_PREFIX)
	strings.write_string(&url, "/containers/")
	strings.write_string(&url, id)
	strings.write_string(&url, "/json")

	reply := http.session_get(session, strings.to_string(url)) or_return

	if reply.status >= 400 {
		m: Error_Message
		err := json.unmarshal_string(reply.body, &m)
		if err != nil {
			fmt.eprintf("error marshalling: %v\n", err)
		}
		return resp, Response_Error{reply.status, m.message}
	} else {
		err := json.unmarshal_string(reply.body, &resp)
		if err != nil {
			fmt.eprintf("error marshalling: %s -> %v\n", reply, err)
		}
		fmt.println("state:", resp.state)
		fmt.println("ports:", resp.network_settings.ports)
	}

	return resp, nil
}

