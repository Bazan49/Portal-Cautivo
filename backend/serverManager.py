from threadingTCPServer import ThreadingTCPServer
from httpServer import BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, unquote
import os
import mimetypes

class ServerCaptivePortal(BaseHTTPRequestHandler):
    authService = None
    frontend_path = os.path.join(os.path.dirname(__file__), '..', 'frontend')

    def do_GET(self):
        '''
            Cliente → Servidor:
            ┌────────────────────────────────────┐
            │ GET /login HTTP/1.1\r\n            │
            │ Host: 192.168.1.1\r\n              │
            │ User-Agent: curl/7.68.0\r\n        │
            │ Accept: */*\r\n                    │
            │ \r\n                               │
            └────────────────────────────────────┘

            Servidor → Cliente:
            ┌────────────────────────────────────┐
            │ HTTP/1.1 200 OK\r\n                │
            │ Content-Type: text/html\r\n        │
            │ Content-Length: 150\r\n            │
            │ \r\n                               │
            │ <html>                             │
            │   <body>                           │
            │     <h1>Login</h1>                 │
            │     <form method="POST">...</form> │
            │   </body>                          │
            │ </html>                            │
            └────────────────────────────────────┘
        '''
        # Mapeo rutas a archivos HTML
        routes = {
            '/': os.path.join(self.frontend_path, 'login.html'),
            '/index': os.path.join(self.frontend_path, 'login.html'),
            '/login': os.path.join(self.frontend_path, 'login.html'),
            '/registro': os.path.join(self.frontend_path, 'register.html'),
            '/exito': os.path.join(self.frontend_path, 'captive_exito.html')
        }
        
        parsed_path = urlparse(self.path)
        path_only = parsed_path.path

        if self.is_static_file(path_only):
            self.serve_static_file(path_only)
            return
        if path_only in routes and os.path.exists(routes[path_only]):
            self.serve_html_file(routes[path_only])
            return
        else:
            self.send_error(404, "Archivo no encontrado")

    def do_POST(self):
        '''
            Cliente → Servidor:
            ┌────────────────────────────────────────┐
            │ POST /login HTTP/1.1\r\n               │
            │ Host: 192.168.1.1\r\n                  │
            │ Content-Type: application/x-www-form-  │
            │               urlencoded\r\n           │
            │ Content-Length: 35\r\n                 │
            │ \r\n                                   │
            │ username=admin&password=admin123       │
            └────────────────────────────────────────┘

            Servidor → Cliente:
            ┌────────────────────────────────────┐
            │ HTTP/1.1 302 Found\r\n             │
            │ Location: /exito\r\n               │
            │ \r\n                               │
            └────────────────────────────────────┘
        '''
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
            client_ip = self.clientAddress[0]
            
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
    
    def is_static_file(self, path):
        """Verifica si la ruta es un archivo estático"""
        static_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.css', '.js', '.ico']
        return any(path.lower().endswith(ext) for ext in static_extensions)

    def serve_static_file(self, path):
        """Sirve archivos estáticos (imágenes, CSS, etc.)"""
        try:
            # Quita la barra inicial del path
            clean_path = path[1:] if path.startswith('/') else path
            file_path = os.path.join(self.frontend_path, clean_path)
            
            # Verifica que el archivo existe
            if not os.path.exists(file_path):
                self.send_error(404, f"Archivo no encontrado: {clean_path}")
                return
            
            # Determina el tipo MIME
            mime_type, _ = mimetypes.guess_type(file_path)
            if mime_type is None:
                mime_type = 'application/octet-stream'
            
            # Lee y sirve el archivo en modo binario
            with open(file_path, 'rb') as file:
                content = file.read()
            
            self.send_response(200)
            self.send_header('Content-type', mime_type)
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            
        except Exception as e:
            self.send_error(500, f"Error al leer el archivo estático: {str(e)}")

    
    def serve_html_file(self, filepath):
        try:
            with open(filepath, 'r', encoding='utf-8') as file:
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

        #formato de clientAddress: {ip}:{puerto}
        respuesta = f"""
        Método: {self.command}
        Ruta: {self.path}
        Cliente: {self.clientAddress[0]}:{self.clientAddress[1]}
        """
        self.wfile.write(respuesta.encode('utf-8'))

def start(authService, port=8080):
    ServerCaptivePortal.authService = authService
    with ThreadingTCPServer(("", port), ServerCaptivePortal) as httpd:
        print(f"Servidor HTTP corriendo en puerto {port}")
        httpd.serve_forever()