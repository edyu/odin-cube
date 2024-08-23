package container

import "core:fmt"
import "core:io"

Container :: struct {}

Restart_Policy :: struct {
	name: string,
}

Resources :: struct {
	memory: i64,
}

Config :: struct {
	image: string,
	env:   []string,
}

Host_Config :: struct {
	restart_policy:    Restart_Policy,
	resources:         Resources,
	publish_all_ports: bool,
}

Container_Error :: struct {}

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

