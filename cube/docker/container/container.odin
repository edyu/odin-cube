package container

import "core:fmt"
import "core:io"

import "../../lib"
import "../connection"

Container :: struct {}

Container_Error :: struct {}

Restart_Policy :: struct {
	name:                string `json:"Name"`,
	maximum_retry_count: int `json:"MaximumRetryCount"`,
}

Resources :: struct {
	memory: i64 `json:"Memory"`,
}

Host_Config :: struct {
	publish_all_ports: bool `json:"PublishAllPorts"`,
	restart_policy:    Restart_Policy `json:"RestartPolicy"`,
	port_bindings:     connection.Port_Map `json:"PortBindings"`,
	// using resources:   Resources,
	memory:            i64 `json:"Memory"`,
}

Config :: struct {
	hostname:      string `json:"Hostname"`,
	domainname:    string `json:"Domainname"`,
	user:          string `json:"User"`,
	attach_stdin:  bool `json:"AttachStdin"`,
	attach_stdout: bool `json:"AttachStdout"`,
	attach_stderr: bool `json:"AttachStderr"`,
	tty:           bool `json:"Tty"`,
	open_stdin:    bool `json:"OpenStdin"`,
	stdin_once:    bool `json:"StdinOnce"`,
	env:           []string `json:"Env"`,
	cmd:           []string `json:"Cmd"`,
	image:         string `json:"Image"`,
	exposed_ports: connection.Port_Set `json:"ExposedPorts"`,
}

Create_Options :: struct {
	// using config:     Config,
	hostname:      string `json:"Hostname"`,
	domainname:    string `json:"Domainname"`,
	user:          string `json:"User"`,
	attach_stdin:  bool `json:"AttachStdin"`,
	attach_stdout: bool `json:"AttachStdout"`,
	attach_stderr: bool `json:"AttachStderr"`,
	exposed_ports: connection.Port_Set `json:"ExposedPorts"`,
	env:           []string `json:"Env"`,
	cmd:           []string `json:"Cmd"`,
	image:         string `json:"Image"`,
	host_config:   Host_Config `json:"HostConfig"`,
}

Container_Response :: union {
	Create_Response,
	Inspect_Response,
}

Create_Response :: struct {
	id:       string `json:"Id"`,
	warnings: []string `json:"Warnings"`,
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

State :: struct {
	status:      string `json:Status`,
	running:     bool `json:"Running"`,
	paused:      bool `json:"Paused"`,
	restarting:  bool `json:"Restarting"`,
	oom_killed:  bool `json:"OOMKilled"`,
	dead:        bool `json:"Dead"`,
	pid:         int `json:"Pid"`,
	exit_code:   int `json:"ExitCode"`,
	error:       string `json:"Error"`,
	started_at:  lib.Timestamp `json:"StartedAt"`,
	finished_at: lib.Timestamp `json:FinishedAt`,
}

Inspect_Response :: struct {
	id:               string `json:"Id"`,
	state:            State `json:"State"`,
	image:            string `json:"Image"`,
	host_config:      Host_Config `json:"HostConfig"`,
	config:           Config `json:"Config"`,
	network_settings: Network_Settings `json:"NetworkSettings"`,
}

Network_Settings :: struct {
	ports:       connection.Port_Map `json:"Ports"`,
	gateway:     connection.Ip_Address `json:"Gateway"`,
	ip_address:  connection.Ip_Address `json:"IPAddress"`,
	mac_address: connection.Mac_Address `json:"MacAddress"`,
}

