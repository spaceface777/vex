module picoserver

import picoev
import picohttpparser
import server
import router
import ctx

pub struct Server {
pub mut:
	port int
	router router.Router
	middlewares []Middleware
}

pub fn new() Server {
    return Server{ 
		router: router.new()
		middlewares: []
	}
}

fn callback(req picohttpparser.Request, res mut picohttpparser.Response) {
    // println(req.method + ' ' + req.path)
    println(req.num_headers)
    res.http_ok().header_server().header_date().plain().body('Hello')
}

pub fn (srv mut Server) serve(port int) {
    srv.port = port
    println('Serving at port: $port')
    picoev.new(srv.port, &callback).serve()
}
