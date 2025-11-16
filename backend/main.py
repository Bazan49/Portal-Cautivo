from authService import AuthService
import serverManager
'''
┌─────────────────────────────────────────────────────────┐
│                    SERVIDOR HTTP                        │
└─────────────────────────────────────────────────────────┘
                          │
                          │ 1. Crear socket TCP
                          ▼
                  socket.socket(AF_INET, SOCK_STREAM)
                          │
                          │ 2. Enlazar a puerto 80
                          ▼
                  socket.bind(('0.0.0.0', 80))
                          │
                          │ 3. Escuchar conexiones
                          ▼
                  socket.listen(5)
                          │
                          │
    ┌─────────────────────┴─────────────────────┐
    │         Loop infinito: while True          │
    └─────────────────────┬─────────────────────┘
                          │
                          │ 4. Esperar cliente (bloqueante)
                          ▼
            client_sock, addr = socket.accept()
                          │
                          │ 5. Crear thread para este cliente
                          ▼
                threading.Thread(target=handle_client)
                          │
    ┌─────────────────────┴──────────────────────┐
    │         En thread separado:                 │
    └─────────────────────┬──────────────────────┘
                          │
                          │ 6. Recibir petición
                          ▼
                request = client_sock.recv(8192)
                          │
                          │ 7. Parsear HTTP
                          ▼
          ┌───────────────┴────────────────┐
          │  method, path, headers, body   │
          └───────────────┬────────────────┘
                          │
                          │ 8. Decidir acción
                          ▼
          ┌───────────────┴────────────────┐
          │   if method == 'GET':          │
          │     serve_html()               │
          │   elif method == 'POST':       │
          │     process_form()             │
          └───────────────┬────────────────┘
                          │
                          │ 9. Construir respuesta HTTP
                          ▼
          response = "HTTP/1.1 200 OK\r\n..."
                          │
                          │ 10. Enviar respuesta
                          ▼
          client_sock.sendall(response.encode())
                          │
                          │ 11. Cerrar socket cliente
                          ▼
                  client_sock.close()
                          │
          (Thread termina, servidor sigue aceptando)
'''
class CaptivePortal:
    def __init__(self):
        print("[Main] Inicializando Portal Cautivo...")

        self.auth_manager = AuthService(data='dataUsers.json')
        print("[Main] AuthManager inicializado")
        self.http_server = None

    def start(self):
        print("[Main] Iniciando servidor HTTP...")
        serverManager.start(self.auth_manager, port=8080)
        

if __name__ == '__main__':
    portal = CaptivePortal()
    portal.start()
