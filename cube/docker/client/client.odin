package client

import "../container"
import "core:fmt"
import "core:io"

Client :: struct {
	scheme:              string,
	host:                string,
	proto:               string,
	addr:                string,
	base_path:           string,
	version:             string,
	custom_http_Headers: map[string]string,
}

Image_Pull_Options :: struct {}

Client_Error :: union {
	Docker_Error,
	container.Container_Error,
}

Docker_Error :: struct {}

new_env_client :: proc() -> (client: Client, err: Client_Error) {
	return
}

image_pull :: proc(image: string) -> (reader: io.Reader, err: Client_Error) {
	fmt.printf("docker image pull\n")
	return
}

Container_Response :: struct {
	id: string,
}

container_create :: proc(
	config: container.Config,
	host_config: container.Host_Config,
	name: string,
) -> (
	resp: Container_Response,
	err: Client_Error,
) {
	fmt.printf("docker container create\n")
	return
}

container_start :: proc(id: string, options: container.Start_Options) -> (err: Client_Error) {
	fmt.printf("docker container start %s\n", id)
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
	return
}

container_remove :: proc(id: string, options: container.Remove_Options) -> (err: Client_Error) {
	fmt.printf("docker container remove %s\n", id)
	return
}

