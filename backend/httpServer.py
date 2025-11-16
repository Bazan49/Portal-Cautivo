import socket
import threading
from urllib.parse import parse_qs, unquote
from io import BytesIO
import sys
import os

"""
Maneja las peticiones http que llegan al servidor.
Redirecciona solicitud al metodo requerido y construye response

Respuesta HTTP (Response)

┌──────────────────────────────────────────┐
│ STATUS LINE                              │
│ HTTP/1.1 200 OK\r\n                      │
├──────────────────────────────────────────┤
│ HEADERS                                  │
│ Content-Type: text/html\r\n              │
│ Content-Length: 150\r\n                  │
│ ...\r\n                                  │
├──────────────────────────────────────────┤
│ BLANK LINE                               │
│ \r\n                                     │
├──────────────────────────────────────────┤
│ BODY                                     │
│ <html>...</html>                         │
└──────────────────────────────────────────┘
"""

class BaseHTTPRequestHandler:

    def __init__(self, socketRequest, clientAddress, serverInstance):
        """
        socketRequest: socket de la conexion
        clientAddress: direccion del cliente con formato (host, port)
        serverInstance: instancia actual del servidor
        """
        self.socketRequest = socketRequest
        self.clientAddress = clientAddress
        self.serverInstance = serverInstance
        self.frontend_path = os.path.join(os.path.dirname(__file__), '..', 'frontend')
        
        # Parsear datos http
        self.raw_requestline = None # cadena de solicitud http cruda
        self.requestline = None # cadena de solicitud sin CRLS
        self.command = None  # GET, POST, etc.
        self.path = None # ruta de la solicitud
        self.request_version = None # cadena de versiones de la solicitud ex: 'Http/1.0'
        self.headers = {} # metadatos de la solicitud
        self.rfile = None  # Para leer el body
        self.wfile = None  # Para escribir respuesta
        

        self.handle() # procesa la peticion
    
    def handle(self):
        try:
            # recibir datos max 8192 bytes
            self.raw_requestline = self.socketRequest.recv(8192).decode('utf-8', errors='ignore')

            if not self.raw_requestline:
                return
            
            # parsear peticion http
            if not self.parse_request():
                return

            # separar los headers del body
            remaining_data = self.raw_requestline.split('\r\n\r\n', 1)
            if len(remaining_data) > 1: 
                body_data = remaining_data[1] # solicitud POST
            else:
                body_data = '' # solicitud GET tipica

            # simular un archivo de solo lectura en memoria para el body
            self.rfile = BytesIO(body_data.encode('utf-8'))

            # crear un archivo para escribir la respuesta
            self.wfile = self.socketRequest.makefile('wb')

            # llamar al metodo indicado
            method_name = f'do_{self.command}'
            if hasattr(self, method_name): 
                method = getattr(self, method_name)
                method()
            else:
                self.send_error(501, f"Metodo no encontrado ({self.command})")

        
        except Exception as e:
            print(f"[HTTP Handler] Error: {e}", file=sys.stderr)
            try:
                self.send_error(500, str(e))
            except:
                pass

    def parse_request(self):
        '''

            Estructura de un Mensaje HTTP

            HTTP usa **CRLF** (`\r\n`) como terminador de línea.

            Petición HTTP (Request)

            ┌──────────────────────────────────────────┐
            │ REQUEST LINE                             │
            │ GET /path HTTP/1.1\r\n                   │
            ├──────────────────────────────────────────┤
            │ HEADERS                                  │
            │ Header1: value1\r\n                      │
            │ Header2: value2\r\n                      │
            │ ...\r\n                                  │
            ├──────────────────────────────────────────┤
            │ BLANK LINE (separador)                   │
            │ \r\n                                     │
            ├──────────────────────────────────────────┤
            │ BODY (opcional)                          │
            │ username=admin&password=123              │
            └──────────────────────────────────────────┘
        '''

        try:
            lines = self.raw_requestline.split('\r\n')
            self.requestline = lines[0]
            args = self.requestline.split()
            if len(args) != 3:
                return False
            self.command = args[0]
            self.path = args[1]
            self.request_version = args[2]

            for line in lines[1:]:
                if line == '':
                    break
                if ':' in line:
                    key, value = line.split(':', 1)
                    self.headers[key.strip()] = value.strip()
            
            return True

        except Exception as e:
            print(f"[HTTP Parser] Error parseando petición: {e}", file=sys.stderr)
            return False
        
    def send_response(self, code, message=None):
        '''
            formato de respuesta http:
            1xx: Informational (100 Continue)
            2xx: Success (200 OK, 201 Created)
            3xx: Redirection (301 Moved, 302 Found)
            4xx: Client Error (400 Bad Request, 404 Not Found)
            5xx: Server Error (500 Internal Error, 503 Unavailable)
        '''
        if message is None:
            message = self.responses.get(code, ('Unknown',))[0]
        
        response_line = f"HTTP/1.1 {code} {message}\r\n"
        self.wfile.write(response_line.encode('utf-8'))

        # headers de control del servidor
        self.send_header('Server', 'CaptivePortalHTTP/1.0')
        self.send_header('Connection', 'close')

    def send_header(self, keyword, value):
        """    
        keyword: Nombre del header
        value: Valor del header
        """
        header_line = f"{keyword}: {value}\r\n"
        self.wfile.write(header_line.encode('utf-8'))
    
    def end_headers(self):
        self.wfile.write(b"\r\n")

    def send_error(self, code, message=None):

        try:
            short_msg, long_msg = self.responses.get(code, ('Error', 'Error'))
            if message:
                long_msg = message
            
            file_error_path = os.path.join(self.frontend_path, 'error.html')
            with open(file_error_path, 'rb') as file:
                content = file.read()
            
            self.send_response(code)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(content.encode('utf-8'))))
            self.end_headers()
            self.wfile.write(content.encode('utf-8'))
        except:
            pass

    responses = {
    200: ('OK', 'Solicitud cumplida, documento sigue'),
    302: ('Encontrado', 'Objeto movido temporalmente'), 
    400: ('Solicitud Incorrecta', 'Sintaxis de solicitud errónea o método no soportado'),
    404: ('No Encontrado', 'Nada coincide con el URI proporcionado'),
    500: ('Error Interno del Servidor', 'El servidor tuvo problemas internos'),
    501: ('No Implementado', 'El servidor no soporta esta operación')
}
    
    # Métodos a implementar en subclase ServerCaptivePortal
    def do_GET(self):
        """Maneja peticiones GET (debe implementarse en subclase)"""
        self.send_error(501, "GET method not implemented")
    
    def do_POST(self):
        """Maneja peticiones POST (debe implementarse en subclase)"""
        self.send_error(501, "POST method not implemented")


        