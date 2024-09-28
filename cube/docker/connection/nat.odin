package connection

Ip_Address :: string

Mac_Address :: string

// Port is a string containing port number and protocol in the format "80/tcp"
Port :: string

Port_Binding :: struct {
	host_ip:   string,
	host_port: string,
}

// Port_Map :: map[Port][]Port_Binding
Port_Map :: map[Port]string

Port_Set :: map[Port]struct {}

