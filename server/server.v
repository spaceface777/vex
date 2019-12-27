// from: https://github.com/vlang/v/pull/1142
// See also: https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html

module server

import (
	net
	http
	net.urllib
	strings
)

const (
	separator = '\r\n'
	HTTP_REQUEST_TYPICAL_SIZE = 1024
)

pub struct Context {
pub:
    current_route string
mut:
    req Request
    res Response
}

pub struct Server {
pub mut:
	port int = 80
	routes []Route
}

type Handler fn(ctx mut Context)

// create server
pub fn new() Server {
	return Server{ routes: [] }
}

pub fn (srv mut Server) create(handler Handler, port int) {
	println('Serving at port: $port')
	srv.port = port
	listener := net.listen(port) or {panic("Failed to listen to port $port")}
	for {
		conn := listener.accept() or {panic("conn accept() failed.")}
		srv.handle_http_connection(conn, handler)
	}
}

fn write_body(res &Response, conn &net.Socket) {
	mut response := strings.new_builder(1024)
	statuscode_msg := status_code_msg(res.status_code)
	response.write('HTTP/1.1 ${res.status_code} ${statuscode_msg}$separator')
	for header_name, header_value in res.headers {
		response.write('$header_name: ${header_value}$separator')
	}
	response.write('Content-Length: ${res.body.len}$separator')
	response.write('Connection: close$separator')
	conn.write(response.str()) or {}
	response.free()
	conn.send(res.body.str, res.body.len) or {}
	conn.close() or {}
}

fn con500(conn &net.Socket){
	mut eres := Response{}
	eres.send('<h1>500 Internal Server Error</h1>', 500)
	write_body(eres, conn)
}

fn (srv Server) handle_http_connection(conn &net.Socket, handler Handler) {	
	request_lines := read_http_request_lines( conn )
	if request_lines.len < 1 {
		con500(conn)
		return
	}
	first_line := request_lines[0]
	data := first_line.split(' ')
	if data.len < 2 {
		con500(conn)
		return
	}
	
	req_path := urllib.parse(data[1]) or {
		con500(conn)
		return
	}
	
	params, raw_path, matched_rte := srv.find(data[0], req_path.path)
	rte := if matched_rte.name.len != 0 { matched_rte } else { Route{name: req_path.path, method: data[0]} }
	mut ctx := Context{ req: Request{}, res: Response{}, current_route: if matched_rte.name.len != 0 { raw_path } else { req_path.path } }
	ctx.res.status_code = 200
	ctx.req.headers = http.parse_headers(request_lines)
	ctx.req.method = data[0]
	ctx.req.path = req_path.path
	ctx.res.path = req_path.path
	ctx.req.params = params
	
	if 'Cookie' in ctx.req.headers {
		cookies_arr := ctx.req.headers['Cookie'].split('; ')
		
		for cookie_data in cookies_arr {
			ck := cookie_data.split('=')
			ck_val := urllib.query_unescape(ck[1]) or {
				con500(conn)
				return
			}
			ctx.req.cookies[ck[0]] = ck_val
		}
	}
	
	if req_path.raw_query.len != 0 {
		query_map := req_path.query().data
		for q in query_map.keys() {
			ctx.req.query[q] = query_map[q].data[0]
		}
	}

	if rte.method == 'POST' {
		body_arr := first_line.split(separator)
		ctx.req.body = body_arr[body_arr.len-1]
	}

	if !('Content-Type' in ctx.req.headers) {
		ctx.res.set_header('Content-Type', 'text/plain')
	}

	handler(mut ctx)
	write_body(ctx.res, conn)
}

fn read_http_request_lines(sock &net.Socket) []string {
	mut lines := []string
	mut buf := [HTTP_REQUEST_TYPICAL_SIZE]byte // where C.recv will store the network data

	for {
		mut res := '' // The buffered line, including the ending \n.
		mut line := '' // The current line segment. Can be a partial without \n in it.
		for {
			n := C.recv(sock.sockfd, buf, HTTP_REQUEST_TYPICAL_SIZE-1, net.MSG_PEEK)
			if n == -1 { return lines }
			if n == 0 {	return lines }
			buf[n] = `\0`
			mut eol_idx := -1
			for i := 0; i < n; i++ {
				if int(buf[i]) == 10 {
					eol_idx = i
					// Ensure that tos_clone(buf) later,
					// will return *only* the first line (including \n),
					// and ignore the rest
					buf[i+1] = `\0`
					break
				}
			}
			line = tos_clone(buf)
			if eol_idx > 0 {
				// At this point, we are sure that recv returned valid data,
				// that contains *at least* one line.
				// Ensure that the block till the first \n (including it)
				// is removed from the socket's receive queue, so that it does
				// not get read again.
				C.recv(sock.sockfd, buf, eol_idx+1, 0)
				res += line
				break
			}
			// recv returned a buffer without \n in it .
			C.recv(sock.sockfd, buf, n, 0)
			res += line
			break
		}
		trimmed_line := res.trim_right(separator)
		if trimmed_line.len == 0 { break }
		lines << trimmed_line
	}

	return lines
}

