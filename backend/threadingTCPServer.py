import socket
import threading
import sys
'''
Define el tipo de protocolo (TCP) de un servidor que maneja 
flujos continuos de datos servidor-cliente

Cliente                    Servidor
   │                          │
   │──────── SYN ────────────→│  1. Cliente solicita conexión
   │                          │
   │←─────── SYN-ACK ─────────│  2. Servidor acepta
   │                          │
   │──────── ACK ────────────→│  3. Cliente confirma
   │                          │
   │    CONEXIÓN ESTABLECIDA  │
   │                          │

Servidor
socket.socket()      # 1. Crear socket
socket.bind()        # 2. Enlazar a IP:puerto
socket.listen()      # 3. Escuchar conexiones entrantes
socket.accept()      # 4. Aceptar cliente (bloquea hasta que llegue uno)
socket.recv()        # 5. Recibir datos
socket.send()        # 6. Enviar datos
socket.close()       # 7. Cerrar conexión

Cliente
socket.socket()      # 1. Crear socket
socket.connect()     # 2. Conectar al servidor
socket.send()        # 3. Enviar datos
socket.recv()        # 4. Recibir datos
socket.close()       # 5. Cerrar conexión
```
'''

class ThreadingTCPServer:
    def __init__(self, serverAddress, RequestHandlerClass):
        """
            serverAddress: direccion del servidor con formato (host, port)
            RequestHandlerClass: Clase del handler (debe heredar de BaseHTTPRequestHandler)
        """
        self.serverAddress = serverAddress
        self.RequestHandlerClass = RequestHandlerClass
        self.socket = None
        self.running = False
    
    def __enter__(self):
        return self
    
    def __exit__(self, *args):
        self.server_close()
    
    def server_start(self):
        '''
            Crea socket y enlaza a puerto
        '''
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(self.serverAddress)
    
    def server_activate(self):
        '''
            Escucha conexiones entrantes
        '''
        self.socket.listen(5) # maximo de conexiones en cola esperando a ser aceptadas

    def serve_forever(self):
        '''
            loop principal que pone en marcha el ciclo de vida de una conexion TCP
        '''

        self.server_start()
        self.server_activate()

        print(f"[ThreadingTCPServer] Servidor escuchando en {self.serverAddress[0]}:{self.serverAddress[1]}")

        self.running=True
        try:
            while self.running:
                try:
                    # aceptar una nueva conexion
                    clientSocket, clientAddress = self.socket.accept()

                    # manejar la peticion con un hilo
                    client_thread = threading.Thread(
                            target=self.process_request_thread,
                            args=(clientSocket, clientAddress)
                        ) 
                    client_thread.daemon = True
                    client_thread.start()  # procesar datos (recibir/enviar)

                except KeyboardInterrupt:
                    print("\n[ThreadingTCPServer] Deteniendo servidor...")
                    break
                except Exception as e:
                    if self.running:
                        print(f"[ThreadingTCPServer] Error: {e}", file=sys.stderr)

        finally: 
            self.server_close()
    
    def process_request_thread(self, clientSocket, clientAddress):
        
        try:
            self.RequestHandlerClass(clientSocket, clientAddress, self) # recibe los datos y envia datos 
        except Exception as e:
            print(f"[ThreadingTCPServer] Error procesando petición: {e}", file=sys.stderr)
        finally:
            try:
                clientSocket.close()
            except:
                pass
    
    def server_close(self):
        self.running = False
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
        
