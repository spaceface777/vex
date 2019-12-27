module server

struct Route {
pub mut:
	method string
	name string
	children []Route
	is_param bool
}

fn empty_cb (req Request, res mut Response) {
	res.set_header('Content-Type', 'text/html')
	res.send('<h1>404 Not Found</h1>', 404)
}

fn (srv Server) find(method string, path string) (map[string]string, string, Route) {
	mut params_map := map[string]string
	path_arr := path.split('/')[1..]
	params_keys, raw_path, route := match_route(method, path, srv.routes)

	for i, params_key in params_keys {
		if params_key.starts_with('/:') {
			params_map[params_key.all_after('/:')] = path_arr[i]
		}
	}

	return params_map, raw_path, route
}

fn match_route(method string, path string, routes []Route) ([]string, string, Route) {	
	mut params_arr := []string
	mut raw_path := ''
	mut path_arr := path.split('/')[1..]

	if path_arr.len == 0 { path_arr << '' }

	route_name := '/' + path_arr[0]
	child_routes := if path_arr.len > 1 { path_arr[1..path_arr.len] } else { []string } 

	for route in routes {
		if route.method == method && (route.name == route_name || route.is_param) {
			if child_routes.len >= 1 {
				child_params, raw_child, child_route := match_route(method, '/' + child_routes.join('/'), route.children)

				raw_path += route.name
				raw_path += raw_child

				params_arr << route.name
				params_arr << child_params

				return params_arr, raw_path, child_route
			} else {
				raw_path += route.name
				params_arr << route.name
				return params_arr, raw_path, route
			}
		}
	}

	return params_arr, raw_path, Route{}
}

fn (routes []Route) has_param() bool {
	for route in routes {
		if route.is_param {
			return true
		}
	}
	
	return false
}

fn (routes []Route) index(method string, path string) int {
	for i, route in routes {
		if route.method == method && route.name == path {
			return i
		}
	}

	return -1
}

fn (srv mut Server) register_route(method string, r_path string) {
	if !r_path.starts_with('/') {
		panic('route paths must start with a forward slash (/)')
	}

	mut path_arr := r_path.split('/')[1..]
	if path_arr.len == 0 { path_arr << '' }
	if path_arr.len > 1 && path_arr[1].len == 0 { path_arr = [''] }

	child_route_name := '/' + path_arr[0]
	route_children := if path_arr.len > 1 { path_arr[1..path_arr.len]} else { []string }
	mut child_route_idx := srv.routes.index(method, child_route_name)

	if child_route_idx == -1 {
		if srv.routes.has_param() {
			panic('Only one param is allowed.')
		} else {
			srv.routes << Route{ 
				method: method, 
				name: child_route_name, 
				children: [], 
				is_param: if child_route_name.starts_with('/:') { true } else { false }
			}
		}

		child_route_idx = srv.routes.index(method, child_route_name)
	}

	if route_children.len >= 1 {
		combined := '/' + route_children.join('/')
		srv.routes[child_route_idx].add_child_route(method, combined)
	}
}

fn (rte mut Route) add_child_route(method string, path string) {
	mut path_arr := path.split('/')[1..]
	if path_arr.len == 0 { path_arr << '' }
	if path_arr.len > 1 && path_arr[1].len == 0 { path_arr = [''] }

	child_route_name := '/' + path_arr[0]
	route_children := if path_arr.len > 1 { path_arr[1..path_arr.len]} else { []string }
	mut child_route_idx := rte.children.index(method, child_route_name)

	if child_route_idx == -1 {
		if rte.children.has_param() {
			panic('Only one wildcard or param is allowed.')
		} else {
			rte.children << Route{ 
				method: method, 
				name: child_route_name, 
				children: [], 
				is_param: if child_route_name.starts_with('/:') { true } else { false }
			}
		}

		child_route_idx = rte.children.index(method, child_route_name)
	}

	if route_children.len >= 1 {
		combined := '/' + route_children.join('/')
		rte.children[child_route_idx].add_child_route(method, combined)
	}
}

pub fn (srv mut Server) register(method string, r_path string) {
	srv.register_route(method.to_upper(), r_path)	
}

pub fn (srv mut Server) get(r_path string) {
	srv.register_route('GET', r_path)
}

pub fn (srv mut Server) post(r_path string) {
	srv.register_route('POST', r_path)
}

pub fn (srv mut Server) patch(r_path string) {
	srv.register_route('PATCH', r_path)
}

pub fn (srv mut Server) delete(r_path string) {
	srv.register_route('DELETE', r_path)
}

pub fn (srv mut Server) put(r_path string) {
	srv.register_route('PUT', r_path)
}

pub fn (srv mut Server) options(r_path string) {
	srv.register_route('OPTIONS', r_path)
}
