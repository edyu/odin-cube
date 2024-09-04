package libmhd

import "core:c"
import "core:os"

foreign import libmhd "system:microhttpd"

Result :: enum c.uint {
	/**
   * MHD result code for "NO".
   */
	NO  = 0,

	/**
   * MHD result code for "YES".
   */
	YES = 1,
}

Flag :: enum c.uint {
	/**
   * No options selected.
   */
	NO_FLAG                         = 0,

	/**
   * Print errors messages to custom error logger or to `stderr` if
   * custom error logger is not set.
   * @sa ::OPTION_EXTERNAL_LOGGER
   */
	USE_ERROR_LOG                   = 1,

	/**
   * Run in debug mode.  If this flag is used, the library should
   * print error messages and warnings to `stderr`.
   */
	USE_DEBUG                       = 1,

	/**
   * Run in HTTPS mode.  The modern protocol is called TLS.
   */
	USE_TLS                         = 2,

	/**
   * Run using one thread per connection.
   * Must be used only with #USE_INTERNAL_POLLING_THREAD.
   *
   * If #USE_ITC is also not used, closed and expired connections may only
   * be cleaned up internally when a new connection is received.
   * Consider adding of #USE_ITC flag to have faster internal cleanups
   * at very minor increase in system resources usage.
   */
	USE_THREAD_PER_CONNECTION       = 4,

	/**
   * Run using an internal thread (or thread pool) for sockets sending
   * and receiving and data processing. Without this flag MHD will not
   * run automatically in background thread(s).
   * If this flag is set, #run() and #run_from_select() couldn't
   * be used.
   * This flag is set explicitly by #USE_POLL_INTERNAL_THREAD and
   * by #USE_EPOLL_INTERNAL_THREAD.
   * When this flag is not set, MHD run in "external" polling mode.
   */
	USE_INTERNAL_POLLING_THREAD     = 8,

	/**
   * Run using the IPv6 protocol (otherwise, MHD will just support
   * IPv4).  If you want MHD to support IPv4 and IPv6 using a single
   * socket, pass #USE_DUAL_STACK, otherwise, if you only pass
   * this option, MHD will try to bind to IPv6-only (resulting in
   * no IPv4 support).
   */
	USE_IPv6                        = 16,

	/**
   * Be pedantic about the protocol (as opposed to as tolerant as
   * possible).
   * This flag is equivalent to setting 1 as #OPTION_CLIENT_DISCIPLINE_LVL
   * value.
   * @sa #OPTION_CLIENT_DISCIPLINE_LVL
   */
	USE_PEDANTIC_CHECKS             = 32,

	/**
   * Use `poll()` instead of `select()` for polling sockets.
   * This allows sockets with `fd >= FD_SETSIZE`.
   * This option is not compatible with an "external" polling mode
   * (as there is no API to get the file descriptors for the external
   * poll() from MHD) and must also not be used in combination
   * with #USE_EPOLL.
   * @sa ::FEATURE_POLL, #USE_POLL_INTERNAL_THREAD
   */
	USE_POLL                        = 64,

	/**
   * Run using an internal thread (or thread pool) doing `poll()`.
   * @sa ::FEATURE_POLL, #USE_POLL, #USE_INTERNAL_POLLING_THREAD
   */
	USE_POLL_INTERNAL_THREAD        = USE_POLL | USE_INTERNAL_POLLING_THREAD,

	/**
   * Suppress (automatically) adding the 'Date:' header to HTTP responses.
   * This option should ONLY be used on systems that do not have a clock
   * and that DO provide other mechanisms for cache control.  See also
   * RFC 2616, section 14.18 (exception 3).
   */
	USE_SUPPRESS_DATE_NO_CLOCK      = 128,

	/**
   * Run without a listen socket.  This option only makes sense if
   * #add_connection is to be used exclusively to connect HTTP
   * clients to the HTTP server.  This option is incompatible with
   * using a thread pool; if it is used, #OPTION_THREAD_POOL_SIZE
   * is ignored.
   */
	USE_NO_LISTEN_SOCKET            = 256,

	/**
   * Use `epoll()` instead of `select()` or `poll()` for the event loop.
   * This option is only available on some systems; using the option on
   * systems without epoll will cause #start_daemon to fail.  Using
   * this option is not supported with #USE_THREAD_PER_CONNECTION.
   * @sa ::FEATURE_EPOLL
   */
	USE_EPOLL                       = 512,

	/**
   * Run using an internal thread (or thread pool) doing `epoll` polling.
   * This option is only available on certain platforms; using the option on
   * platform without `epoll` support will cause #start_daemon to fail.
   * @sa ::FEATURE_EPOLL, #USE_EPOLL, #USE_INTERNAL_POLLING_THREAD
   */
	USE_EPOLL_INTERNAL_THREAD       = USE_EPOLL | USE_INTERNAL_POLLING_THREAD,

	/** @deprecated */
	USE_EPOLL_INTERNALLY            = USE_EPOLL | USE_INTERNAL_POLLING_THREAD,
	/** @deprecated */
	USE_EPOLL_INTERNALLY_LINUX_ONLY = USE_EPOLL | USE_INTERNAL_POLLING_THREAD,

	/**
   * Use inter-thread communication channel.
   * #USE_ITC can be used with #USE_INTERNAL_POLLING_THREAD
   * and is ignored with any "external" sockets polling.
   * It's required for use of #quiesce_daemon
   * or #add_connection.
   * This option is enforced by #ALLOW_SUSPEND_RESUME or
   * #USE_NO_LISTEN_SOCKET.
   * #USE_ITC is always used automatically on platforms
   * where select()/poll()/other ignore shutdown of listen
   * socket.
   */
	USE_ITC                         = 1024,

	/** @deprecated */
	USE_PIPE_FOR_SHUTDOWN           = 1024,

	/**
   * Use a single socket for IPv4 and IPv6.
   */
	USE_DUAL_STACK                  = USE_IPv6 | 2048,

	/**
   * Enable `turbo`.  Disables certain calls to `shutdown()`,
   * enables aggressive non-blocking optimistic reads and
   * other potentially unsafe optimizations.
   * Most effects only happen with #USE_EPOLL.
   */
	USE_TURBO                       = 4096,

	/**
   * Enable suspend/resume functions, which also implies setting up
   * ITC to signal resume.
   */
	ALLOW_SUSPEND_RESUME            = 8192 | USE_ITC,

	/**
   * Enable TCP_FASTOPEN option.  This option is only available on Linux with a
   * kernel >= 3.6.  On other systems, using this option cases #start_daemon
   * to fail.
   */
	USE_TCP_FASTOPEN                = 16384,

	/**
   * You need to set this option if you want to use HTTP "Upgrade".
   * "Upgrade" may require usage of additional internal resources,
   * which we do not want to use unless necessary.
   */
	ALLOW_UPGRADE                   = 32768,

	/**
   * Automatically use best available polling function.
   * Choice of polling function is also depend on other daemon options.
   * If #USE_INTERNAL_POLLING_THREAD is specified then epoll, poll() or
   * select() will be used (listed in decreasing preference order, first
   * function available on system will be used).
   * If #USE_THREAD_PER_CONNECTION is specified then poll() or select()
   * will be used.
   * If those flags are not specified then epoll or select() will be
   * used (as the only suitable for get_fdset())
   */
	USE_AUTO                        = 65536,

	/**
   * Run using an internal thread (or thread pool) with best available on
   * system polling function.
   * This is combination of #USE_AUTO and #USE_INTERNAL_POLLING_THREAD
   * flags.
   */
	USE_AUTO_INTERNAL_THREAD        = USE_AUTO | USE_INTERNAL_POLLING_THREAD,

	/**
   * Flag set to enable post-handshake client authentication
   * (only useful in combination with #USE_TLS).
   */
	USE_POST_HANDSHAKE_AUTH_SUPPORT = 1 << 17,

	/**
   * Flag set to enable TLS 1.3 early data.  This has
   * security implications, be VERY careful when using this.
   */
	USE_INSECURE_TLS_EARLY_DATA     = 1 << 18,

	/**
   * Indicates that MHD daemon will be used by application in single-threaded
   * mode only.  When this flag is set then application must call any MHD
   * function only within a single thread.
   * This flag turns off some internal thread-safety and allows MHD making
   * some of the internal optimisations suitable only for single-threaded
   * environment.
   * Not compatible with #USE_INTERNAL_POLLING_THREAD.
   * @note Available since #VERSION 0x00097707
   */
	USE_NO_THREAD_SAFETY            = 1 << 19,
}

Response_Memory_Mode :: enum c.uint {
	/**
   * Buffer is a persistent (static/global) buffer that won't change
   * for at least the lifetime of the response, MHD should just use
   * it, not free it, not copy it, just keep an alias to it.
   * @ingroup response
   */
	RESPMEM_PERSISTENT,

	/**
   * Buffer is heap-allocated with `malloc()` (or equivalent) and
   * should be freed by MHD after processing the response has
   * concluded (response reference counter reaches zero).
   * The more portable way to automatically free the buffer is function
   * create_response_from_buffer_with_free_callback() with '&free' as
   * crfc parameter as it does not require to use the same runtime library.
   * @warning It is critical to make sure that the same C-runtime library
   *          is used by both application and MHD (especially
   *          important for W32).
   * @ingroup response
   */
	RESPMEM_MUST_FREE,

	/**
   * Buffer is in transient memory, but not on the heap (for example,
   * on the stack or non-`malloc()` allocated) and only valid during the
   * call to #create_response_from_buffer.  MHD must make its
   * own private copy of the data for processing.
   * @ingroup response
   */
	RESPMEM_MUST_COPY,
}

/**
 * @brief MHD options.
 *
 * Passed in the varargs portion of #start_daemon.
 */
Option :: enum c.uint {
	/**
   * No more options / last option.  This is used
   * to terminate the VARARGs list.
   */
	OPTION_END                               = 0,

	/**
   * Maximum memory size per connection (followed by a `size_t`).
   * Default is 32 kb (#POOL_SIZE_DEFAULT).
   * Values above 128k are unlikely to result in much benefit, as half
   * of the memory will be typically used for IO, and TCP buffers are
   * unlikely to support window sizes above 64k on most systems.
   * Values below 64 bytes are completely unusable.
   * Since #VERSION 0x00097710 silently ignored if followed by zero value.
   */
	OPTION_CONNECTION_MEMORY_LIMIT           = 1,

	/**
   * Maximum number of concurrent connections to
   * accept (followed by an `unsigned int`).
   */
	OPTION_CONNECTION_LIMIT                  = 2,

	/**
   * After how many seconds of inactivity should a
   * connection automatically be timed out? (followed
   * by an `unsigned int`; use zero for no timeout).
   * Values larger than (UINT64_MAX / 2000 - 1) will
   * be clipped to this number.
   */
	OPTION_CONNECTION_TIMEOUT                = 3,

	/**
   * Register a function that should be called whenever a request has
   * been completed (this can be used for application-specific clean
   * up).  Requests that have never been presented to the application
   * (via #AccessHandlerCallback) will not result in
   * notifications.
   *
   * This option should be followed by TWO pointers.  First a pointer
   * to a function of type #RequestCompletedCallback and second a
   * pointer to a closure to pass to the request completed callback.
   * The second pointer may be NULL.
   */
	OPTION_NOTIFY_COMPLETED                  = 4,

	/**
   * Limit on the number of (concurrent) connections made to the
   * server from the same IP address.  Can be used to prevent one
   * IP from taking over all of the allowed connections.  If the
   * same IP tries to establish more than the specified number of
   * connections, they will be immediately rejected.  The option
   * should be followed by an `unsigned int`.  The default is
   * zero, which means no limit on the number of connections
   * from the same IP address.
   */
	OPTION_PER_IP_CONNECTION_LIMIT           = 5,

	/**
   * Bind daemon to the supplied `struct sockaddr`. This option should
   * be followed by a `struct sockaddr *`.  If #USE_IPv6 is
   * specified, the `struct sockaddr*` should point to a `struct
   * sockaddr_in6`, otherwise to a `struct sockaddr_in`.
   * Silently ignored if followed by NULL pointer.
   * @deprecated Use #OPTION_SOCK_ADDR_LEN
   */
	OPTION_SOCK_ADDR                         = 6,

	/**
   * Specify a function that should be called before parsing the URI from
   * the client.  The specified callback function can be used for processing
   * the URI (including the options) before it is parsed.  The URI after
   * parsing will no longer contain the options, which maybe inconvenient for
   * logging.  This option should be followed by two arguments, the first
   * one must be of the form
   *
   *     void * my_logger(void *cls, const char *uri, struct Connection *con)
   *
   * where the return value will be passed as
   * (`* req_cls`) in calls to the #AccessHandlerCallback
   * when this request is processed later; returning a
   * value of NULL has no special significance (however,
   * note that if you return non-NULL, you can no longer
   * rely on the first call to the access handler having
   * `NULL == *req_cls` on entry;)
   * "cls" will be set to the second argument following
   * #OPTION_URI_LOG_CALLBACK.  Finally, uri will
   * be the 0-terminated URI of the request.
   *
   * Note that during the time of this call, most of the connection's
   * state is not initialized (as we have not yet parsed the headers).
   * However, information about the connecting client (IP, socket)
   * is available.
   *
   * The specified function is called only once per request, therefore some
   * programmers may use it to instantiate their own request objects, freeing
   * them in the notifier #OPTION_NOTIFY_COMPLETED.
   */
	OPTION_URI_LOG_CALLBACK                  = 7,

	/**
   * Memory pointer for the private key (key.pem) to be used by the
   * HTTPS daemon.  This option should be followed by a
   * `const char *` argument.
   * This should be used in conjunction with #OPTION_HTTPS_MEM_CERT.
   */
	OPTION_HTTPS_MEM_KEY                     = 8,

	/**
   * Memory pointer for the certificate (cert.pem) to be used by the
   * HTTPS daemon.  This option should be followed by a
   * `const char *` argument.
   * This should be used in conjunction with #OPTION_HTTPS_MEM_KEY.
   */
	OPTION_HTTPS_MEM_CERT                    = 9,

	/**
   * Daemon credentials type.
   * Followed by an argument of type
   * `gnutls_credentials_type_t`.
   */
	OPTION_HTTPS_CRED_TYPE                   = 10,

	/**
   * Memory pointer to a `const char *` specifying the GnuTLS priorities string.
   * If this options is not specified, then MHD will try the following strings:
   * * "@LIBMICROHTTPD" (application-specific system-wide configuration)
   * * "@SYSTEM"        (system-wide configuration)
   * * default GnuTLS priorities string
   * * "NORMAL"
   * The first configuration accepted by GnuTLS will be used.
   * For more details see GnuTLS documentation for "Application-specific
   * priority strings".
   */
	OPTION_HTTPS_PRIORITIES                  = 11,

	/**
   * Pass a listen socket for MHD to use (systemd-style).  If this
   * option is used, MHD will not open its own listen socket(s). The
   * argument passed must be of type `socket` and refer to an
   * existing socket that has been bound to a port and is listening.
   * If followed by INVALID_SOCKET value, MHD ignores this option
   * and creates socket by itself.
   */
	OPTION_LISTEN_SOCKET                     = 12,

	/**
   * Use the given function for logging error messages.  This option
   * must be followed by two arguments; the first must be a pointer to
   * a function of type #LogCallback and the second a pointer
   * `void *` which will be passed as the first argument to the log
   * callback.
   * Should be specified as the first option, otherwise some messages
   * may be printed by standard MHD logger during daemon startup.
   *
   * Note that MHD will not generate any log messages
   * if it was compiled without the "--enable-messages"
   * flag being set.
   */
	OPTION_EXTERNAL_LOGGER                   = 13,

	/**
   * Number (`unsigned int`) of threads in thread pool. Enable
   * thread pooling by setting this value to to something
   * greater than 1.
   * Can be used only for daemons started with #USE_INTERNAL_POLLING_THREAD.
   * Ignored if followed by zero value.
   */
	OPTION_THREAD_POOL_SIZE                  = 14,

	/**
   * Additional options given in an array of `struct OptionItem`.
   * The array must be terminated with an entry `{OPTION_END, 0, NULL}`.
   * An example for code using #OPTION_ARRAY is:
   *
   *     struct OptionItem ops[] = {
   *       { OPTION_CONNECTION_LIMIT, 100, NULL },
   *       { OPTION_CONNECTION_TIMEOUT, 10, NULL },
   *       { OPTION_END, 0, NULL }
   *     };
   *     d = start_daemon (0, 8080, NULL, NULL, dh, NULL,
   *                           OPTION_ARRAY, ops,
   *                           OPTION_END);
   *
   * For options that expect a single pointer argument, the
   * 'value' member of the `struct OptionItem` is ignored.
   * For options that expect two pointer arguments, the first
   * argument must be cast to `intptr_t`.
   */
	OPTION_ARRAY                             = 15,

	/**
   * Specify a function that should be called for unescaping escape
   * sequences in URIs and URI arguments.  Note that this function
   * will NOT be used by the `struct PostProcessor`.  If this
   * option is not specified, the default method will be used which
   * decodes escape sequences of the form "%HH".  This option should
   * be followed by two arguments, the first one must be of the form
   *
   *     size_t my_unescaper(void *cls,
   *                         struct Connection *c,
   *                         char *s)
   *
   * where the return value must be the length of the value left in
   * "s" (without the 0-terminator) and "s" should be updated.  Note
   * that the unescape function must not lengthen "s" (the result must
   * be shorter than the input and must still be 0-terminated).
   * However, it may also include binary zeros before the
   * 0-termination.  "cls" will be set to the second argument
   * following #OPTION_UNESCAPE_CALLBACK.
   */
	OPTION_UNESCAPE_CALLBACK                 = 16,

	/**
   * Memory pointer for the random values to be used by the Digest
   * Auth module. This option should be followed by two arguments.
   * First an integer of type `size_t` which specifies the size
   * of the buffer pointed to by the second argument in bytes.
   * The recommended size is between 8 and 32. If size is four or less
   * then security could be lowered. Sizes more then 32 (or, probably
   * more than 16 - debatable) will not increase security.
   * Note that the application must ensure that the buffer of the
   * second argument remains allocated and unmodified while the
   * daemon is running.
   * @sa #OPTION_DIGEST_AUTH_RANDOM_COPY
   */
	OPTION_DIGEST_AUTH_RANDOM                = 17,

	/**
   * Size of the internal array holding the map of the nonce and
   * the nonce counter. This option should be followed by an `unsigend int`
   * argument.
   * The map size is 4 by default, which is enough to communicate with
   * a single client at any given moment of time, but not enough to
   * handle several clients simultaneously.
   * If Digest Auth is not used, this option can be set to zero to minimise
   * memory allocation.
   */
	OPTION_NONCE_NC_SIZE                     = 18,

	/**
   * Desired size of the stack for threads created by MHD. Followed
   * by an argument of type `size_t`.  Use 0 for system default.
   */
	OPTION_THREAD_STACK_SIZE                 = 19,

	/**
   * Memory pointer for the certificate (ca.pem) to be used by the
   * HTTPS daemon for client authentication.
   * This option should be followed by a `const char *` argument.
   */
	OPTION_HTTPS_MEM_TRUST                   = 20,

	/**
   * Increment to use for growing the read buffer (followed by a
   * `size_t`).
   * Must not be higher than 1/4 of #OPTION_CONNECTION_MEMORY_LIMIT.
   * Since #VERSION 0x00097710 silently ignored if followed by zero value.
   */
	OPTION_CONNECTION_MEMORY_INCREMENT       = 21,

	/**
   * Use a callback to determine which X.509 certificate should be
   * used for a given HTTPS connection.  This option should be
   * followed by a argument of type `gnutls_certificate_retrieve_function2 *`.
   * This option provides an
   * alternative to #OPTION_HTTPS_MEM_KEY,
   * #OPTION_HTTPS_MEM_CERT.  You must use this version if
   * multiple domains are to be hosted at the same IP address using
   * TLS's Server Name Indication (SNI) extension.  In this case,
   * the callback is expected to select the correct certificate
   * based on the SNI information provided.  The callback is expected
   * to access the SNI data using `gnutls_server_name_get()`.
   * Using this option requires GnuTLS 3.0 or higher.
   */
	OPTION_HTTPS_CERT_CALLBACK               = 22,

	/**
   * When using #USE_TCP_FASTOPEN, this option changes the default TCP
   * fastopen queue length of 50.  Note that having a larger queue size can
   * cause resource exhaustion attack as the TCP stack has to now allocate
   * resources for the SYN packet along with its DATA.  This option should be
   * followed by an `unsigned int` argument.
   */
	OPTION_TCP_FASTOPEN_QUEUE_SIZE           = 23,

	/**
   * Memory pointer for the Diffie-Hellman parameters (dh.pem) to be used by the
   * HTTPS daemon for key exchange.
   * This option must be followed by a `const char *` argument.
   */
	OPTION_HTTPS_MEM_DHPARAMS                = 24,

	/**
   * If present and set to true, allow reusing address:port socket
   * (by using SO_REUSEPORT on most platform, or platform-specific ways).
   * If present and set to false, disallow reusing address:port socket
   * (does nothing on most platform, but uses SO_EXCLUSIVEADDRUSE on Windows).
   * This option must be followed by a `unsigned int` argument.
   */
	OPTION_LISTENING_ADDRESS_REUSE           = 25,

	/**
   * Memory pointer for a password that decrypts the private key (key.pem)
   * to be used by the HTTPS daemon. This option should be followed by a
   * `const char *` argument.
   * This should be used in conjunction with #OPTION_HTTPS_MEM_KEY.
   * @sa ::FEATURE_HTTPS_KEY_PASSWORD
   */
	OPTION_HTTPS_KEY_PASSWORD                = 26,

	/**
   * Register a function that should be called whenever a connection is
   * started or closed.
   *
   * This option should be followed by TWO pointers.  First a pointer
   * to a function of type #NotifyConnectionCallback and second a
   * pointer to a closure to pass to the request completed callback.
   * The second pointer may be NULL.
   */
	OPTION_NOTIFY_CONNECTION                 = 27,

	/**
   * Allow to change maximum length of the queue of pending connections on
   * listen socket. If not present than default platform-specific SOMAXCONN
   * value is used. This option should be followed by an `unsigned int`
   * argument.
   */
	OPTION_LISTEN_BACKLOG_SIZE               = 28,

	/**
   * If set to 1 - be strict about the protocol.  Use -1 to be
   * as tolerant as possible.
   *
   * The more flexible option #OPTION_CLIENT_DISCIPLINE_LVL is recommended
   * instead of this option.
   *
   * The values mapping table:
   * #OPTION_STRICT_FOR_CLIENT | #OPTION_CLIENT_DISCIPLINE_LVL
   * -----------------------------:|:---------------------------------
   * 1                             | 1
   * 0                             | 0
   * -1                            | -3
   *
   * This option should be followed by an `int` argument.
   * @sa #OPTION_CLIENT_DISCIPLINE_LVL
   */
	OPTION_STRICT_FOR_CLIENT                 = 29,

	/**
   * This should be a pointer to callback of type
   * gnutls_psk_server_credentials_function that will be given to
   * gnutls_psk_set_server_credentials_function. It is used to
   * retrieve the shared key for a given username.
   */
	OPTION_GNUTLS_PSK_CRED_HANDLER           = 30,

	/**
   * Use a callback to determine which X.509 certificate should be
   * used for a given HTTPS connection.  This option should be
   * followed by a argument of type `gnutls_certificate_retrieve_function3 *`.
   * This option provides an
   * alternative/extension to #OPTION_HTTPS_CERT_CALLBACK.
   * You must use this version if you want to use OCSP stapling.
   * Using this option requires GnuTLS 3.6.3 or higher.
   */
	OPTION_HTTPS_CERT_CALLBACK2              = 31,

	/**
   * Allows the application to disable certain sanity precautions
   * in MHD. With these, the client can break the HTTP protocol,
   * so this should never be used in production. The options are,
   * however, useful for testing HTTP clients against "broken"
   * server implementations.
   * This argument must be followed by an "unsigned int", corresponding
   * to an `enum DisableSanityCheck`.
   */
	OPTION_SERVER_INSANITY                   = 32,

	/**
   * If followed by value '1' informs MHD that SIGPIPE is suppressed or
   * handled by application. Allows MHD to use network functions that could
   * generate SIGPIPE, like `sendfile()`.
   * Valid only for daemons without #USE_INTERNAL_POLLING_THREAD as
   * MHD automatically suppresses SIGPIPE for threads started by MHD.
   * This option should be followed by an `int` argument.
   * @note Available since #VERSION 0x00097205
   */
	OPTION_SIGPIPE_HANDLED_BY_APP            = 33,

	/**
   * If followed by 'int' with value '1' disables usage of ALPN for TLS
   * connections even if supported by TLS library.
   * Valid only for daemons with #USE_TLS.
   * This option should be followed by an `int` argument.
   * @note Available since #VERSION 0x00097207
   */
	OPTION_TLS_NO_ALPN                       = 34,

	/**
   * Memory pointer for the random values to be used by the Digest
   * Auth module. This option should be followed by two arguments.
   * First an integer of type `size_t` which specifies the size
   * of the buffer pointed to by the second argument in bytes.
   * The recommended size is between 8 and 32. If size is four or less
   * then security could be lowered. Sizes more then 32 (or, probably
   * more than 16 - debatable) will not increase security.
   * An internal copy of the buffer will be made, the data do not
   * need to be static.
   * @sa #OPTION_DIGEST_AUTH_RANDOM
   * @note Available since #VERSION 0x00097701
   */
	OPTION_DIGEST_AUTH_RANDOM_COPY           = 35,

	/**
   * Allow to controls the scope of validity of MHD-generated nonces.
   * This regulates how "nonces" are generated and how "nonces" are checked by
   * #digest_auth_check3() and similar functions.
   * This option should be followed by an 'unsigned int` argument with value
   * formed as bitwise OR combination of #DAuthBindNonce values.
   * When not specified, default value #DAUTH_BIND_NONCE_NONE is used.
   * @note Available since #VERSION 0x00097701
   */
	OPTION_DIGEST_AUTH_NONCE_BIND_TYPE       = 36,

	/**
   * Memory pointer to a `const char *` specifying the GnuTLS priorities to be
   * appended to default priorities.
   * This allow some specific options to be enabled/disabled, while leaving
   * the rest of the settings to their defaults.
   * The string does not have to start with a colon ':' character.
   * See #OPTION_HTTPS_PRIORITIES description for details of automatic
   * default priorities.
   * @note Available since #VERSION 0x00097701
   */
	OPTION_HTTPS_PRIORITIES_APPEND           = 37,

	/**
   * Sets specified client discipline level (i.e. HTTP protocol parsing
   * strictness level).
   *
   * The following basic values are supported:
   *  0 - default MHD level, a balance between extra security and broader
   *      compatibility, as allowed by RFCs for HTTP servers;
   *  1 - more strict protocol interpretation, within the limits set by
   *      RFCs for HTTP servers;
   * -1 - more lenient protocol interpretation, within the limits set by
   *      RFCs for HTTP servers.
   * The following extended values could be used as well:
   *  2 - stricter protocol interpretation, even stricter then allowed
   *      by RFCs for HTTP servers, however it should be absolutely compatible
   *      with clients following at least RFCs' "MUST" type of requirements
   *      for HTTP clients;
   *  3 - strictest protocol interpretation, even stricter then allowed
   *      by RFCs for HTTP servers, however it should be absolutely compatible
   *      with clients following RFCs' "SHOULD" and "MUST" types of requirements
   *      for HTTP clients;
   * -2 - more relaxed protocol interpretation, violating RFCs' "SHOULD" type
   *      of requirements for HTTP servers;
   * -3 - the most flexible protocol interpretation, beyond RFCs' "MUST" type of
   *      requirements for HTTP server.
   * Values higher than "3" or lower than "-3" are interpreted as "3" or "-3"
   * respectively.
   *
   * Higher values are more secure, lower values are more compatible with
   * various HTTP clients.
   *
   * The default value ("0") could be used in most cases.
   * Value "1" is suitable for highly loaded public servers.
   * Values "2" and "3" are generally recommended only for testing of HTTP
   * clients against MHD.
   * Value "2" may be used for security-centric application, however it is
   * slight violation of RFCs' requirements.
   * Negative values are not recommended for public servers.
   * Values "-1" and "-2" could be used for servers in isolated environment.
   * Value "-3" is not recommended unless it is absolutely necessary to
   * communicate with some client(s) with badly broken HTTP implementation.
   *
   * This option should be followed by an `int` argument.
   * @note Available since #VERSION 0x00097701
   */
	OPTION_CLIENT_DISCIPLINE_LVL             = 38,

	/**
   * Specifies value of FD_SETSIZE used by application.  Only For external
   * polling modes (without MHD internal threads).
   * Some platforms (FreeBSD, Solaris, W32 etc.) allow overriding of FD_SETSIZE
   * value.  When polling by select() is used, MHD rejects sockets with numbers
   * equal or higher than FD_SETSIZE.  If this option is used, MHD treats this
   * value as a limitation for socket number instead of FD_SETSIZE value which
   * was used for building MHD.
   * When external polling is used with #get_fdset2() (or #get_fdset()
   * macro) and #run_from_select() interfaces, it is recommended to always
   * use this option.
   * It is safe to use this option on platforms with fixed FD_SETSIZE (like
   * GNU/Linux) if system value of FD_SETSIZE is used as the argument.
   * Can be used only for daemons without #USE_INTERNAL_POLLING_THREAD, i.e.
   * only when external sockets polling is used.
   * On W32 it is silently ignored, as W32 does not limit the socket number in
   * fd_sets.
   * This option should be followed by a positive 'int' argument.
   * @note Available since #VERSION 0x00097705
   */
	OPTION_APP_FD_SETSIZE                    = 39,

	/**
   * Bind daemon to the supplied 'struct sockaddr'.  This option should
   * be followed by two parameters: 'socklen_t' the size of memory at the next
   * pointer and the pointer 'const struct sockaddr *'.
   * Note: the order of the arguments is not the same as for system bind() and
   * other network functions.
   * If #USE_IPv6 is specified, the 'struct sockaddr*' should
   * point to a 'struct sockaddr_in6'.
   * The socket domain (protocol family) is detected from provided
   * 'struct sockaddr'. IP, IPv6 and UNIX sockets are supported (if supported
   * by the platform). Other types may work occasionally.
   * Silently ignored if followed by zero size and NULL pointer.
   * @note Available since #VERSION 0x00097706
   */
	OPTION_SOCK_ADDR_LEN                     = 40,
	/**
   * Default nonce timeout value used for Digest Auth.
   * This option should be followed by an 'unsigned int' argument.
   * Silently ignored if followed by zero value.
   * @see #digest_auth_check3(), digest_auth_check_digest3()
   * @note Available since #VERSION 0x00097709
   */
	OPTION_DIGEST_AUTH_DEFAULT_NONCE_TIMEOUT = 41,
	/**
   * Default maximum nc (nonce count) value used for Digest Auth.
   * This option should be followed by an 'uint32_t' argument.
   * Silently ignored if followed by zero value.
   * @see #digest_auth_check3(), digest_auth_check_digest3()
   * @note Available since #VERSION 0x00097709
   */
	OPTION_DIGEST_AUTH_DEFAULT_MAX_NC        = 42,
}

/**
 * @defgroup httpcode HTTP response codes.
 * These are the status codes defined for HTTP responses.
 * See: https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml
 * Registry export date: 2023-09-29
 * @{
 */

Status_Code :: enum c.uint {
	/* 100 "Continue".            RFC9110, Section 15.2.1. */
	HTTP_CONTINUE                             = 100,
	/* 101 "Switching Protocols". RFC9110, Section 15.2.2. */
	HTTP_SWITCHING_PROTOCOLS                  = 101,
	/* 102 "Processing".          RFC2518. */
	HTTP_PROCESSING                           = 102,
	/* 103 "Early Hints".         RFC8297. */
	HTTP_EARLY_HINTS                          = 103,

	/* 200 "OK".                  RFC9110, Section 15.3.1. */
	HTTP_OK                                   = 200,
	/* 201 "Created".             RFC9110, Section 15.3.2. */
	HTTP_CREATED                              = 201,
	/* 202 "Accepted".            RFC9110, Section 15.3.3. */
	HTTP_ACCEPTED                             = 202,
	/* 203 "Non-Authoritative Information". RFC9110, Section 15.3.4. */
	HTTP_NON_AUTHORITATIVE_INFORMATION        = 203,
	/* 204 "No Content".          RFC9110, Section 15.3.5. */
	HTTP_NO_CONTENT                           = 204,
	/* 205 "Reset Content".       RFC9110, Section 15.3.6. */
	HTTP_RESET_CONTENT                        = 205,
	/* 206 "Partial Content".     RFC9110, Section 15.3.7. */
	HTTP_PARTIAL_CONTENT                      = 206,
	/* 207 "Multi-Status".        RFC4918. */
	HTTP_MULTI_STATUS                         = 207,
	/* 208 "Already Reported".    RFC5842. */
	HTTP_ALREADY_REPORTED                     = 208,

	/* 226 "IM Used".             RFC3229. */
	HTTP_IM_USED                              = 226,

	/* 300 "Multiple Choices".    RFC9110, Section 15.4.1. */
	HTTP_MULTIPLE_CHOICES                     = 300,
	/* 301 "Moved Permanently".   RFC9110, Section 15.4.2. */
	HTTP_MOVED_PERMANENTLY                    = 301,
	/* 302 "Found".               RFC9110, Section 15.4.3. */
	HTTP_FOUND                                = 302,
	/* 303 "See Other".           RFC9110, Section 15.4.4. */
	HTTP_SEE_OTHER                            = 303,
	/* 304 "Not Modified".        RFC9110, Section 15.4.5. */
	HTTP_NOT_MODIFIED                         = 304,
	/* 305 "Use Proxy".           RFC9110, Section 15.4.6. */
	HTTP_USE_PROXY                            = 305,
	/* 306 "Switch Proxy".        Not used! RFC9110, Section 15.4.7. */
	HTTP_SWITCH_PROXY                         = 306,
	/* 307 "Temporary Redirect".  RFC9110, Section 15.4.8. */
	HTTP_TEMPORARY_REDIRECT                   = 307,
	/* 308 "Permanent Redirect".  RFC9110, Section 15.4.9. */
	HTTP_PERMANENT_REDIRECT                   = 308,

	/* 400 "Bad Request".         RFC9110, Section 15.5.1. */
	HTTP_BAD_REQUEST                          = 400,
	/* 401 "Unauthorized".        RFC9110, Section 15.5.2. */
	HTTP_UNAUTHORIZED                         = 401,
	/* 402 "Payment Required".    RFC9110, Section 15.5.3. */
	HTTP_PAYMENT_REQUIRED                     = 402,
	/* 403 "Forbidden".           RFC9110, Section 15.5.4. */
	HTTP_FORBIDDEN                            = 403,
	/* 404 "Not Found".           RFC9110, Section 15.5.5. */
	HTTP_NOT_FOUND                            = 404,
	/* 405 "Method Not Allowed".  RFC9110, Section 15.5.6. */
	HTTP_METHOD_NOT_ALLOWED                   = 405,
	/* 406 "Not Acceptable".      RFC9110, Section 15.5.7. */
	HTTP_NOT_ACCEPTABLE                       = 406,
	/* 407 "Proxy Authentication Required". RFC9110, Section 15.5.8. */
	HTTP_PROXY_AUTHENTICATION_REQUIRED        = 407,
	/* 408 "Request Timeout".     RFC9110, Section 15.5.9. */
	HTTP_REQUEST_TIMEOUT                      = 408,
	/* 409 "Conflict".            RFC9110, Section 15.5.10. */
	HTTP_CONFLICT                             = 409,
	/* 410 "Gone".                RFC9110, Section 15.5.11. */
	HTTP_GONE                                 = 410,
	/* 411 "Length Required".     RFC9110, Section 15.5.12. */
	HTTP_LENGTH_REQUIRED                      = 411,
	/* 412 "Precondition Failed". RFC9110, Section 15.5.13. */
	HTTP_PRECONDITION_FAILED                  = 412,
	/* 413 "Content Too Large".   RFC9110, Section 15.5.14. */
	HTTP_CONTENT_TOO_LARGE                    = 413,
	/* 414 "URI Too Long".        RFC9110, Section 15.5.15. */
	HTTP_URI_TOO_LONG                         = 414,
	/* 415 "Unsupported Media Type". RFC9110, Section 15.5.16. */
	HTTP_UNSUPPORTED_MEDIA_TYPE               = 415,
	/* 416 "Range Not Satisfiable". RFC9110, Section 15.5.17. */
	HTTP_RANGE_NOT_SATISFIABLE                = 416,
	/* 417 "Expectation Failed".  RFC9110, Section 15.5.18. */
	HTTP_EXPECTATION_FAILED                   = 417,


	/* 421 "Misdirected Request". RFC9110, Section 15.5.20. */
	HTTP_MISDIRECTED_REQUEST                  = 421,
	/* 422 "Unprocessable Content". RFC9110, Section 15.5.21. */
	HTTP_UNPROCESSABLE_CONTENT                = 422,
	/* 423 "Locked".              RFC4918. */
	HTTP_LOCKED                               = 423,
	/* 424 "Failed Dependency".   RFC4918. */
	HTTP_FAILED_DEPENDENCY                    = 424,
	/* 425 "Too Early".           RFC8470. */
	HTTP_TOO_EARLY                            = 425,
	/* 426 "Upgrade Required".    RFC9110, Section 15.5.22. */
	HTTP_UPGRADE_REQUIRED                     = 426,

	/* 428 "Precondition Required". RFC6585. */
	HTTP_PRECONDITION_REQUIRED                = 428,
	/* 429 "Too Many Requests".   RFC6585. */
	HTTP_TOO_MANY_REQUESTS                    = 429,

	/* 431 "Request Header Fields Too Large". RFC6585. */
	HTTP_REQUEST_HEADER_FIELDS_TOO_LARGE      = 431,

	/* 451 "Unavailable For Legal Reasons". RFC7725. */
	HTTP_UNAVAILABLE_FOR_LEGAL_REASONS        = 451,

	/* 500 "Internal Server Error". RFC9110, Section 15.6.1. */
	HTTP_INTERNAL_SERVER_ERROR                = 500,
	/* 501 "Not Implemented".     RFC9110, Section 15.6.2. */
	HTTP_NOT_IMPLEMENTED                      = 501,
	/* 502 "Bad Gateway".         RFC9110, Section 15.6.3. */
	HTTP_BAD_GATEWAY                          = 502,
	/* 503 "Service Unavailable". RFC9110, Section 15.6.4. */
	HTTP_SERVICE_UNAVAILABLE                  = 503,
	/* 504 "Gateway Timeout".     RFC9110, Section 15.6.5. */
	HTTP_GATEWAY_TIMEOUT                      = 504,
	/* 505 "HTTP Version Not Supported". RFC9110, Section 15.6.6. */
	HTTP_HTTP_VERSION_NOT_SUPPORTED           = 505,
	/* 506 "Variant Also Negotiates". RFC2295. */
	HTTP_VARIANT_ALSO_NEGOTIATES              = 506,
	/* 507 "Insufficient Storage". RFC4918. */
	HTTP_INSUFFICIENT_STORAGE                 = 507,
	/* 508 "Loop Detected".       RFC5842. */
	HTTP_LOOP_DETECTED                        = 508,

	/* 510 "Not Extended".        (OBSOLETED) RFC2774; status-change-http-experiments-to-historic. */
	HTTP_NOT_EXTENDED                         = 510,
	/* 511 "Network Authentication Required". RFC6585. */
	HTTP_NETWORK_AUTHENTICATION_REQUIRED      = 511,


	/* Not registered non-standard codes */
	/* 449 "Reply With".          MS IIS extension. */
	HTTP_RETRY_WITH                           = 449,

	/* 450 "Blocked by Windows Parental Controls". MS extension. */
	HTTP_BLOCKED_BY_WINDOWS_PARENTAL_CONTROLS = 450,

	/* 509 "Bandwidth Limit Exceeded". Apache extension. */
	HTTP_BANDWIDTH_LIMIT_EXCEEDED             = 509,
}

Value_Kind :: enum c.uint {
	/**
   * HTTP header (request/response).
   */
	MHD_HEADER_KIND       = 1,

	/**
   * Cookies.  Note that the original HTTP header containing
   * the cookie(s) will still be available and intact.
   */
	MHD_COOKIE_KIND       = 2,

	/**
   * POST data.  This is available only if a content encoding
   * supported by MHD is used (currently only URL encoding),
   * and only if the posted content fits within the available
   * memory pool.  Note that in that case, the upload data
   * given to the #MHD_AccessHandlerCallback will be
   * empty (since it has already been processed).
   */
	MHD_POSTDATA_KIND     = 4,

	/**
   * GET (URI) arguments.
   */
	MHD_GET_ARGUMENT_KIND = 8,

	/**
   * HTTP footer (only for HTTP 1.1 chunked encodings).
   */
	MHD_FOOTER_KIND       = 16,
}

/* Main HTTP methods. */
/* Safe.     Idempotent.     RFC9110, Section 9.3.1. */
MHD_HTTP_METHOD_GET: cstring : "GET"
/* Safe.     Idempotent.     RFC9110, Section 9.3.2. */
MHD_HTTP_METHOD_HEAD: cstring : "HEAD"
/* Not safe. Not idempotent. RFC9110, Section 9.3.3. */
MHD_HTTP_METHOD_POST: cstring : "POST"
/* Not safe. Idempotent.     RFC9110, Section 9.3.4. */
MHD_HTTP_METHOD_PUT: cstring : "PUT"
/* Not safe. Idempotent.     RFC9110, Section 9.3.5. */
MHD_HTTP_METHOD_DELETE: cstring : "DELETE"
/* Not safe. Not idempotent. RFC9110, Section 9.3.6. */
MHD_HTTP_METHOD_CONNECT: cstring : "CONNECT"
/* Safe.     Idempotent.     RFC9110, Section 9.3.7. */
MHD_HTTP_METHOD_OPTIONS: cstring : "OPTIONS"
/* Safe.     Idempotent.     RFC9110, Section 9.3.8. */
MHD_HTTP_METHOD_TRACE: cstring : "TRACE"
/* Not safe. Not idempotent. RFC5789, Section 2. */
MHD_HTTP_METHOD_PATCH: cstring : "PATCH"

Connection :: struct {}

Daemon :: struct {}

Response :: struct {}

Accept_Policy_Callback :: proc "c" (
	cls: rawptr,
	addr: ^os.SOCKADDR,
	addrlen: os.socklen_t,
) -> Result

Access_Handler_Callback :: proc "c" (
	cls: rawptr,
	connection: ^Connection,
	url: cstring,
	method: cstring,
	version: cstring,
	upload_data: cstring,
	upload_data_size: ^c.size_t,
	req_cls: ^rawptr,
) -> Result

Key_Value_Iterator :: proc "c" (
	cls: rawptr,
	kind: Value_Kind,
	key: cstring,
	value: cstring,
) -> Result

foreign libmhd {
	MHD_start_daemon :: proc(flags: Flag, port: c.uint16_t, apc: Accept_Policy_Callback, apc_cls: rawptr, dh: Access_Handler_Callback, dh_cls: rawptr, #c_vararg data: ..Option) -> ^Daemon ---
	MHD_stop_daemon :: proc(daemon: ^Daemon) ---
	MHD_create_response_from_buffer :: proc(size: c.size_t, buffer: rawptr, mode: Response_Memory_Mode) -> ^Response ---
	MHD_queue_response :: proc(connection: ^Connection, status_code: Status_Code, response: ^Response) -> Result ---
	MHD_destroy_response :: proc(response: ^Response) ---
	MHD_add_response_header :: proc(response: ^Response, header: cstring, value: cstring) -> Result ---
	MHD_get_connection_values :: proc(connection: ^Connection, kind: Value_Kind, iterator: Key_Value_Iterator, cls: rawptr) -> c.int ---
}

