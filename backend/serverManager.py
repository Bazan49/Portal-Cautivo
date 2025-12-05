from threadingTCPServer import ThreadingTCPServer
from httpServer import BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, unquote
import os
import mimetypes
import sys

class ServerCaptivePortal(BaseHTTPRequestHandler):
    authService = None
    sessionsManager = None
    frontend_path = os.path.join(os.path.dirname(__file__), '..', 'frontend')

    route_files = {
        '/': 'login.html',
        '/index': 'login.html', 
        '/login': 'login.html',
        '/registro': 'register.html',
        '/exito': 'success.html',
        '/logout': None,  
    }
    
    public_routes = {'/', '/index', '/login', '/registro'}
    private_routes = {'/exito', '/logout'}

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
        
        parsed_path = urlparse(self.path)
        path_only = parsed_path.path or '/'
        client_ip = self.clientAddress[0]

        print(f"[{client_ip}] {self.command} {path_only}", file=sys.stderr)

        if path_only == '/logout':
            self.handle_logout(client_ip)
            return

        if self.is_static_file(path_only):
            self.serve_static_file(path_only)
            return

        is_authenticated = self.sessionsManager and self.sessionsManager.is_authenticated(client_ip)

        return self.route_request(path_only, is_authenticated, client_ip)
    
    def route_request(self, path, is_authenticated, client_ip):
        # Rutas públicas (siempre permitidas)
        if path in self.public_routes:
            return self.serve_route(path)
        
        # Rutas privadas (requieren autenticación)
        elif path in self.private_routes:
            if is_authenticated:
                return self.serve_route(path)
            else:
                print(f"🔒 Acceso denegado a {path} para {client_ip}")
                self.send_redirect('/login')
                return
            
        else:
            self.send_redirect('/login')

    def serve_route(self, path):    

        # Obtener el archivo correspondiente
        filename = self.route_files.get(path)
        
        if not filename:
            self.send_error(404, "Ruta no válida")
            return
        
        # Construir ruta completa
        filepath = os.path.join(self.frontend_path, filename)
        
        # Verificar que el archivo existe
        if not os.path.exists(filepath):
            self.send_error(404, f"Archivo {filename} no encontrado")
            return
        
        # Servir el archivo
        self.serve_html_file(filepath)
        return

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

        else:
            self.send_error(405, "Método POST no permitido para esta ruta")
            return

        if result['status'] == 'success':

            username = result.get('username')
            client_ip = self.clientAddress[0]

            if parsed_path.path in ['/login', '/registro']:
                # Obtener MAC del cliente
                # client_mac = self.sessionsManager.get_client_mac(client_ip)
                
                # Crear sesión en el NetworkSessionManager
                if self.sessionsManager:
                    success = self.sessionsManager.create_session(client_ip, username)
                    if success:
                        print(f"✅ Sesión creada: {username} - IP: {client_ip}")
                    else:
                        print(f"❌ Error creando sesión para {username}")
                        self.send_redirect('/login?error=session_failed')
                        return
            
            # Redirigir a página de éxito
            timeout = self.sessionsManager._format_time(self.sessionsManager.session_timeout)
            self.send_redirect(f'/exito?username={username}&ip={client_ip}&session_duration={timeout}')

        else:
            error_type = result.get('error_type', 'invalid')
            if parsed_path.path == '/login':
                self.send_redirect(f'/login?error={error_type}')
            elif parsed_path.path == '/registro':
                self.send_redirect(f'/registro?error={error_type}')
            else:
                self.send_error(400, "Acción no válida")

    def handle_logout(self, client_ip):
        '''Maneja el cierre de sesión'''
        if self.sessionsManager:
            self.sessionsManager.terminate_session(client_ip)
        
        self.send_redirect('/login')
        return

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
    
    def send_redirect(self, location):
        """Envía una redirección HTTP 302"""
        self.send_response(302)
        self.send_header('Location', location)
        self.end_headers()
    
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
            if getattr(self, '_send_body', True):
                self.wfile.write(content)
            
        except Exception as e:
            self.send_error(500, f"Error al leer el archivo estático: {str(e)}")

    def serve_html_file(self, filepath):
        try:
            with open(filepath, 'r', encoding='utf-8') as file:
                html_content = file.read()
            content_bytes = html_content.encode('utf-8')
            self.send_response(200)
            self.send_header('Content-type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(content_bytes)))
            self.end_headers()
            if getattr(self, '_send_body', True):
                self.wfile.write(content_bytes)
        except Exception as e:
            print("entro a una excepcion")
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

def start(authService, sessionsManager, port=8080):

    ServerCaptivePortal.authService = authService
    ServerCaptivePortal.sessionsManager = sessionsManager

    with ThreadingTCPServer(("", port), ServerCaptivePortal) as httpd:
        print(f"Servidor HTTP corriendo en puerto {port}")
        httpd.serve_forever()
