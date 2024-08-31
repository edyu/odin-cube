package libcurl

import "core:c"

foreign import libcurl "system:curl"

Code :: enum c.uint {
	E_OK = 0,
	E_UNSUPPORTED_PROTOCOL, /* 1 */
	E_FAILED_INIT, /* 2 */
	E_URL_MALFORMAT, /* 3 */
	E_NOT_BUILT_IN, /* 4 - [was obsoleted in August 2007 for
                                    7.17.0, reused in April 2011 for 7.21.5] */
	E_COULDNT_RESOLVE_PROXY, /* 5 */
	E_COULDNT_RESOLVE_HOST, /* 6 */
	E_COULDNT_CONNECT, /* 7 */
	E_WEIRD_SERVER_REPLY, /* 8 */
	E_REMOTE_ACCESS_DENIED, /* 9 a service was denied by the server
                                    due to lack of access - when login fails
                                    this is not returned. */
	E_FTP_ACCEPT_FAILED, /* 10 - [was obsoleted in April 2006 for
                                    7.15.4, reused in Dec 2011 for 7.24.0]*/
	E_FTP_WEIRD_PASS_REPLY, /* 11 */
	E_FTP_ACCEPT_TIMEOUT, /* 12 - timeout occurred accepting server
                                    [was obsoleted in August 2007 for 7.17.0,
                                    reused in Dec 2011 for 7.24.0]*/
	E_FTP_WEIRD_PASV_REPLY, /* 13 */
	E_FTP_WEIRD_227_FORMAT, /* 14 */
	E_FTP_CANT_GET_HOST, /* 15 */
	E_HTTP2, /* 16 - A problem in the http2 framing layer.
                                    [was obsoleted in August 2007 for 7.17.0,
                                    reused in July 2014 for 7.38.0] */
	E_FTP_COULDNT_SET_TYPE, /* 17 */
	E_PARTIAL_FILE, /* 18 */
	E_FTP_COULDNT_RETR_FILE, /* 19 */
	E_OBSOLETE20, /* 20 - NOT USED */
	E_QUOTE_ERROR, /* 21 - quote command failure */
	E_HTTP_RETURNED_ERROR, /* 22 */
	E_WRITE_ERROR, /* 23 */
	E_OBSOLETE24, /* 24 - NOT USED */
	E_UPLOAD_FAILED, /* 25 - failed upload "command" */
	E_READ_ERROR, /* 26 - could not open/read from file */
	E_OUT_OF_MEMORY, /* 27 */
	E_OPERATION_TIMEDOUT, /* 28 - the timeout time was reached */
	E_OBSOLETE29, /* 29 - NOT USED */
	E_FTP_PORT_FAILED, /* 30 - FTP PORT operation failed */
	E_FTP_COULDNT_USE_REST, /* 31 - the REST command failed */
	E_OBSOLETE32, /* 32 - NOT USED */
	E_RANGE_ERROR, /* 33 - RANGE "command" did not work */
	E_HTTP_POST_ERROR, /* 34 */
	E_SSL_CONNECT_ERROR, /* 35 - wrong when connecting with SSL */
	E_BAD_DOWNLOAD_RESUME, /* 36 - could not resume download */
	E_FILE_COULDNT_READ_FILE, /* 37 */
	E_LDAP_CANNOT_BIND, /* 38 */
	E_LDAP_SEARCH_FAILED, /* 39 */
	E_OBSOLETE40, /* 40 - NOT USED */
	E_FUNCTION_NOT_FOUND, /* 41 - NOT USED starting with 7.53.0 */
	E_ABORTED_BY_CALLBACK, /* 42 */
	E_BAD_FUNCTION_ARGUMENT, /* 43 */
	E_OBSOLETE44, /* 44 - NOT USED */
	E_INTERFACE_FAILED, /* 45 - OPT_INTERFACE failed */
	E_OBSOLETE46, /* 46 - NOT USED */
	E_TOO_MANY_REDIRECTS, /* 47 - catch endless re-direct loops */
	E_UNKNOWN_OPTION, /* 48 - User specified an unknown option */
	E_SETOPT_OPTION_SYNTAX, /* 49 - Malformed setopt option */
	E_OBSOLETE50, /* 50 - NOT USED */
	E_OBSOLETE51, /* 51 - NOT USED */
	E_GOT_NOTHING, /* 52 - when this is a specific error */
	E_SSL_ENGINE_NOTFOUND, /* 53 - SSL crypto engine not found */
	E_SSL_ENGINE_SETFAILED, /* 54 - can not set SSL crypto engine as
                                    default */
	E_SEND_ERROR, /* 55 - failed sending network data */
	E_RECV_ERROR, /* 56 - failure in receiving network data */
	E_OBSOLETE57, /* 57 - NOT IN USE */
	E_SSL_CERTPROBLEM, /* 58 - problem with the local certificate */
	E_SSL_CIPHER, /* 59 - could not use specified cipher */
	E_PEER_FAILED_VERIFICATION, /* 60 - peer's certificate or fingerprint
                                     was not verified fine */
	E_BAD_CONTENT_ENCODING, /* 61 - Unrecognized/bad encoding */
	E_OBSOLETE62, /* 62 - NOT IN USE since 7.82.0 */
	E_FILESIZE_EXCEEDED, /* 63 - Maximum file size exceeded */
	E_USE_SSL_FAILED, /* 64 - Requested FTP SSL level failed */
	E_SEND_FAIL_REWIND, /* 65 - Sending the data requires a rewind
                                    that failed */
	E_SSL_ENGINE_INITFAILED, /* 66 - failed to initialise ENGINE */
	E_LOGIN_DENIED, /* 67 - user, password or similar was not
                                    accepted and we failed to login */
	E_TFTP_NOTFOUND, /* 68 - file not found on server */
	E_TFTP_PERM, /* 69 - permission problem on server */
	E_REMOTE_DISK_FULL, /* 70 - out of disk space on server */
	E_TFTP_ILLEGAL, /* 71 - Illegal TFTP operation */
	E_TFTP_UNKNOWNID, /* 72 - Unknown transfer ID */
	E_REMOTE_FILE_EXISTS, /* 73 - File already exists */
	E_TFTP_NOSUCHUSER, /* 74 - No such user */
	E_OBSOLETE75, /* 75 - NOT IN USE since 7.82.0 */
	E_OBSOLETE76, /* 76 - NOT IN USE since 7.82.0 */
	E_SSL_CACERT_BADFILE, /* 77 - could not load CACERT file, missing
                                    or wrong format */
	E_REMOTE_FILE_NOT_FOUND, /* 78 - remote file not found */
	E_SSH, /* 79 - error from the SSH layer, somewhat
                                    generic so the error message will be of
                                    interest when this has happened */
	E_SSL_SHUTDOWN_FAILED, /* 80 - Failed to shut down the SSL
                                    connection */
	E_AGAIN, /* 81 - socket is not ready for send/recv,
                                    wait till it is ready and try again (Added
                                    in 7.18.2) */
	E_SSL_CRL_BADFILE, /* 82 - could not load CRL file, missing or
                                    wrong format (Added in 7.19.0) */
	E_SSL_ISSUER_ERROR, /* 83 - Issuer check failed.  (Added in
                                    7.19.0) */
	E_FTP_PRET_FAILED, /* 84 - a PRET command failed */
	E_RTSP_CSEQ_ERROR, /* 85 - mismatch of RTSP CSeq numbers */
	E_RTSP_SESSION_ERROR, /* 86 - mismatch of RTSP Session Ids */
	E_FTP_BAD_FILE_LIST, /* 87 - unable to parse FTP file list */
	E_CHUNK_FAILED, /* 88 - chunk callback reported error */
	E_NO_CONNECTION_AVAILABLE, /* 89 - No connection available, the
                                    session will be queued */
	E_SSL_PINNEDPUBKEYNOTMATCH, /* 90 - specified pinned public key did not
                                     match */
	E_SSL_INVALIDCERTSTATUS, /* 91 - invalid certificate status */
	E_HTTP2_STREAM, /* 92 - stream error in HTTP/2 framing layer
                                    */
	E_RECURSIVE_API_CALL, /* 93 - an api function was called from
                                    inside a callback */
	E_AUTH_ERROR, /* 94 - an authentication function returned an
                                    error */
	E_HTTP3, /* 95 - An HTTP/3 layer problem */
	E_QUIC_CONNECT_ERROR, /* 96 - QUIC connection error */
	E_PROXY, /* 97 - proxy handshake error */
	E_SSL_CLIENTCERT, /* 98 - client-side certificate required */
	E_UNRECOVERABLE_POLL, /* 99 - poll/select returned fatal error */
	E_TOO_LARGE, /* 100 - a value/data met its maximum */
	E_ECH_REQUIRED, /* 101 - ECH tried but failed */
	LAST, /* never use! */
}

OPTTYPE_OBJECTPOINT: c.uint : 10000
OPTTYPE_STRINGPOINT :: OPTTYPE_OBJECTPOINT
OPTTYPE_SLISTPOINT :: OPTTYPE_OBJECTPOINT
OPTTYPE_CBPOINT :: OPTTYPE_OBJECTPOINT
OPTTYPE_FUNCTIONPOINT: c.uint : 20000

Option :: enum c.uint {
	OPT_WRITEDATA        = OPTTYPE_CBPOINT + 1,
	OPT_URL              = OPTTYPE_STRINGPOINT + 2,
	OPT_WRITEFUNCTION    = OPTTYPE_FUNCTIONPOINT + 11,
	OPT_POSTFIELDS       = OPTTYPE_OBJECTPOINT + 15,
	OPT_HTTPHEADER       = OPTTYPE_SLISTPOINT + 23,
	OPT_CUSTOMREQUEST    = OPTTYPE_STRINGPOINT + 36,
	OPT_UNIX_SOCKET_PATH = OPTTYPE_STRINGPOINT + 231,
}

INFO_LONG :: 0x200000

Info :: enum c.uint {
	INFO_RESPONSE_CODE = INFO_LONG + 2,
}

Flag :: enum c.uint {
	GLOBAL_SSL   = 1 << 0,
	GLOBAL_WIN32 = 1 << 1,
	GLOBAL_ALL   = GLOBAL_SSL | GLOBAL_WIN32,
}

Session :: struct {}

Slist :: struct {
	data: cstring,
	next: ^Slist,
}

foreign libcurl {
	curl_global_init :: proc(flags: Flag) -> Code ---
	curl_easy_init :: proc() -> ^Session ---
	curl_easy_setopt :: proc(curl: ^Session, opt: Option, #c_vararg data: ..any) -> Code ---
	curl_easy_perform :: proc(curl: ^Session) -> Code ---
	curl_easy_cleanup :: proc(curl: ^Session) ---
	curl_easy_strerror :: proc(code: Code) -> cstring ---
	curl_global_cleanup :: proc() ---
	curl_slist_append :: proc(list: ^Slist, header: cstring) -> ^Slist ---
	curl_slist_free_all :: proc(list: ^Slist) ---
	curl_easy_getinfo :: proc(curl: ^Session, info: Info, #c_vararg data: ..any) -> Code ---
}

