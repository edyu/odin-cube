package utils

import "core:fmt"
import "core:time"

import "../http"

http_func :: proc(url: string) -> (http.Response, http.Http_Client_Error)

http_with_retry :: proc(
	f: http_func,
	url: string,
) -> (
	resp: http.Response,
	err: http.Http_Client_Error,
) {
	count := 10
	for i := 0; i < count; i += 1 {
		resp, err = f(url)
		if err != nil {
			fmt.printfln("Error calling url %s: %v", url, err)
			time.sleep(5 * time.Second)
		} else {
			break
		}
	}
	return
}

