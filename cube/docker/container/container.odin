package container

import "core:fmt"
import "core:io"

Container :: struct {}

Container_Error :: struct {}

Restart_Policy :: struct {
	name:                string `json:"Name"`,
	maximum_retry_count: int `json:"MaximumRetryCount"`,
}

Host_Config :: struct {
	memory:            i64 `json:"Memory"`,
	publish_all_ports: bool `json:"PublishAllPorts"`,
	restart_policy:    Restart_Policy `json:"RestartPolicy"`,
}

Create_Options :: struct {
	env:         []string `json:"Env"`,
	image:       string `json:"Image"`,
	host_config: Host_Config `json:"HostConfig"`,
}

Start_Options :: struct {}

Logs_Options :: struct {
	show_stdout: bool,
	show_stderr: bool,
}

Stop_Options :: struct {}

Remove_Options :: struct {
	remove_volumes: bool,
	remove_links:   bool,
	force:          bool,
}

