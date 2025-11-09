import http.server
from urllib.parse import urlparse, parse_qs, unquote
import socketserver
import os


class ServerCaptivePortal(http.server.BaseHTTPRequestHandler):
    authService = None

    def do_GET(self):
        # Mapeo rutas a archivos HTML
        routes = {
            '/': 'captive_login.html',
            '/index': 'captive_login.html',
            '/login': 'captive_login.html',
            '/registro': 'captive_registro.html',
            '/exito': 'captive_exito.html'
        }
        
        parsed_path = urlparse(self.path)
        path_only = parsed_path.path

        if path_only in routes and os.path.exists(routes[path_only]):
            self.serve_html_file(routes[path_only])
        else:
            self.send_error(404, "Archivo no encontrado")

    def do_POST(self):
        # Parsear datos del formulario 
        parsed_path = urlparse(self.path)
        result = {'status': 'failure', 'message': 'Ruta no encontrada'}
        if( parsed_path.path == '/login'):
            result = self.login()

        elif (parsed_path.path == '/registro'):
            result = self.register()

        if result['status'] == 'success':
            # Desblquear ip con firewallManager

            # Redirigir a página de éxito
            username = result.get('username')
            client_ip = self.client_address[0]
            
            self.send_response(302)
            self.send_header('Location', f'/exito?username={username}&ip={client_ip}')
            self.end_headers()
        else:
            error_type = result.get('error_type', 'invalid')
            if parsed_path.path == '/login':
                self.send_response(302)
                self.send_header('Location', f'/login?error={error_type}')
                self.end_headers()
            else:
                self.send_response(302)
                self.send_header('Location', f'/registro?error={error_type}')
                self.end_headers()

    def login(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode()
        data = {}
        for item in post_data.split('&'):
            if '=' in item:
                key, value = item.split('=', 1)
                data[key] = unquote(value.replace('+', ' '))

        username = data.get('username')
        password = data.get('password')
        
        # Validar credenciales con authService
        return self.authService.validate_user(username, password)
    
    def register(self):
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode()
        data = {}
        for item in post_data.split('&'):
            if '=' in item:
                key, value = item.split('=', 1)
                data[key] = unquote(value.replace('+', ' '))

        username = data.get('username')
        email = data.get('email')
        password = data.get('password')

        # Registrar usuario con authService
        return self.authService.register_user(username, email, password)
    
    def serve_html_file(self, filepath):
        try:
            with open(filepath, 'r') as file:
                html_content = file.read()
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(html_content.encode('utf-8'))
        except Exception as e:
            self.send_error(500, f"Error al leer el archivo: {str(e)}")

    def show_info(self):
        self.send_response(200)
        self.end_headers()

        #formato de client_address: {ip}:{puerto}
        respuesta = f"""
        Método: {self.command}
        Ruta: {self.path}
        Cliente: {self.client_address[0]}:{self.client_address[1]}
        """
        self.wfile.write(respuesta.encode('utf-8'))

def start(authService, port=8080):
    ServerCaptivePortal.authService = authService
    with socketserver.ThreadingTCPServer(("", port), ServerCaptivePortal) as httpd:
        print(f"Servidor HTTP corriendo en puerto {port}")
        httpd.serve_forever()