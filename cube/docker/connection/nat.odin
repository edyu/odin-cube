package connection

Port :: string

Port_Binding :: struct {
	host_ip:   string,
	host_port: string,
}

Port_Map :: map[Port][]Port_Binding

Port_Set :: map[Port]struct {}

