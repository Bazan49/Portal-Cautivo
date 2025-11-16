from authService import AuthService
import serverManager

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
