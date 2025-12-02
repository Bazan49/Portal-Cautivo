import time
import subprocess
import threading
from datetime import datetime
from enum import Enum

class SessionTerminationReason(Enum):
    """Razones de terminación de sesión de red (completamente en español)"""
    
    USER_LOGOUT = "usuario cerró sesión"  # Usuario cerró sesión voluntariamente
    SESSION_TIMEOUT = "tiempo sesion agotado, sesión expirada"  # Tiempo máximo de sesión alcanzado
    IP_SPOOFING_DETECTED = "suplantacion_ip"  # Posible suplantación de IP
    MAC_MISMATCH = "cambio_mac"  # Cambio de dirección MAC
    UNKNOWN = "desconocida"  # Razón desconocida
    SYSTEM_ERROR = "error_sistema" # Error genérico del sistema
   
class NetworkSessionManager:

    def __init__(self, firewall_manager, timeout=30*60, cleanup_interval=5*60):
        """
        Inicializa el gestor de sesiones en memoria

        """
        self.session_timeout = timeout
        self.active_sessions = {}  
        self.firewall = firewall_manager

        self.cleanup_interval = cleanup_interval 
        self._stop_cleanup = threading.Event()
        self._session_lock = threading.RLock()
        
        # Iniciar el hilo de limpieza
        self.cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
        self.cleanup_thread.start()
        
        print(f"✅ SessionManager iniciado - Timeout: {timeout}s - Cleanup cada {self.cleanup_interval}s")

    # Funcionamiento para manejar las sesiones expiradas

    def _cleanup_loop(self):
        """Bucle de limpieza automática cada 5 minutos"""
        while not self._stop_cleanup.is_set():
            time.sleep(self.cleanup_interval)
            self._check_and_cleanup_expired()

    def _check_and_cleanup_expired(self):
        """Verifica y limpia sesiones expiradas"""
        try:
            current_time = time.time()
            expired_count = 0
            
            with self._session_lock:
                # Crear lista de IPs expiradas para evitar modificar el dict durante la iteración
                expired_ips = []
                
                for ip, session in self.active_sessions.items():
                    elapsed = current_time - session.get('login_time', 0)
                    if elapsed > self.session_timeout:
                        expired_ips.append(ip)
            
            # Terminar sesiones expiradas
            for ip in expired_ips:
                if self.terminate_session(ip, SessionTerminationReason.SESSION_TIMEOUT):
                    expired_count += 1
            
            if expired_count > 0:
                print(f"⏰ [{datetime.now().strftime('%H:%M:%S')}] Limpieza automática: {expired_count} sesiones expiradas")

            self._display_active_sessions_summary()
                
        except Exception as e:
            print(f"❌ Error en limpieza automática: {e}")

    def _format_time(self, seconds: float) -> str:
        """Formatear tiempo en segundos a string legible"""
        if seconds <= 0:
            return "0 segundos"
        
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = int(seconds % 60)
        
        parts = []
        if hours > 0:
            parts.append(f"{hours}h")
        if minutes > 0:
            parts.append(f"{minutes}m")
        if secs > 0 and hours == 0:
            parts.append(f"{secs}s")
        
        return " ".join(parts)

    def _display_active_sessions_summary(self):
        """Muestra un resumen de las sesiones activas"""
        with self._session_lock:
            active_count = len(self.active_sessions)
            
            if active_count == 0:
                print(f"📊 Sesiones activas: 0")
                return
            
            print(f"\n📊 RESUMEN DE SESIONES ACTIVAS")
            print(f"   Total: {active_count} sesión(es)")
            print(f"   {'─' * 40}")
            
            for ip, session in self.active_sessions.items():
                username = session.get('username', 'Desconocido')
                login_time = session.get('login_time', 0)
                elapsed = time.time() - login_time
                remaining = max(0, self.session_timeout - elapsed)
                
                elapsed_str = self._format_time(elapsed)
                remaining_str = self._format_time(remaining)
                
                print(f"   • {username:20} {ip:15}")
                print(f"     Tiempo conectado: {elapsed_str}")
                print(f"     Tiempo restante:  {remaining_str}")
                print(f"     Login: {datetime.fromtimestamp(login_time).strftime('%H:%M:%S')}")

    def terminate_session(self, ip, reason: SessionTerminationReason = SessionTerminationReason.UNKNOWN):
        """
        Terminar sesión y bloquear usuario
        
        Returns:
            bool: True si la sesión se terminó exitosamente
        """
        try:
            with self._session_lock:
                # Verificar si existe en el diccionario
                if ip not in self.active_sessions:
                    print(f"⚠️  No se encontró sesión para IP {ip}")
                    return False
                
                session = self.active_sessions[ip]
                username = session.get('username', 'Desconocido')
                # mac = session['mac']
                
                print(f"🔒 Terminando sesión: {username} ({ip}) - Razón: {reason}")
                
                # Bloquear en firewall
                self.firewall.lock_user(ip)
                
                # Eliminar del diccionario 
                del self.active_sessions[ip]
                
                print(f"✅ Sesión terminada: {username} ({ip})")
                return True
            
        except Exception as e:
            print(f"❌ Error terminando sesión: {e}")
            return False
    
    def stop_cleanup(self): #Configurar mejor esto
        """Detener el hilo de limpieza"""
        self._stop_cleanup.set()
        if self.cleanup_thread.is_alive():
            self.cleanup_thread.join(timeout=2)        
    
    # Manejo de creación y actualización de sesiones

    def create_session(self, ip, username, mac = None):
        """
        Crear nueva sesión para usuario autenticado
        
        Returns:
            bool: True si la sesión se creó exitosamente
        """
        try:
            # Validar IP
            if not ip or ip == "0.0.0.0":
                print(f"❌ IP inválida: {ip}")
                return False
          
            # Normalizar MAC
            # normalized_mac = mac.upper().replace('-', ':') if mac else "00:00:00:00:00:00"
            
            with self._session_lock:
                # Verificar si ya existe sesión para esta IP 
                if ip in self.active_sessions:
                    existing = self.active_sessions[ip]
                    
                    # Si es el mismo usuario con misma MAC, renovar sesión
                    # if existing['mac'] == normalized_mac and existing['username'] == username:
                    print(f"🔄 Renovando sesión existente para {username}")
                    self.active_sessions[ip]['login_time'] = time.time()
                    return True
                    
                    # # Si la MAC cambió, posible suplantación
                    # if existing['mac'] != normalized_mac:
                    #     print(f"🚨 Conflicto MAC: IP {ip} tenía {existing['mac']}, ahora {normalized_mac}")
                    #     self.terminate_session(ip)

                else:
                    # Desbloquear en firewall (IP + MAC)
                    print(f"🔓 Desbloqueando en firewall: {ip}")
                    self.firewall.unlock_user(ip)
                
                    # Guardar sesión 
                    self.active_sessions[ip] = {
                        # 'mac': normalized_mac,
                        'username': username,
                        'login_time': time.time(),
                    }

                    return True
                
        except Exception as e:
            print(f"❌ Error en create_session: {e}")
            return False
        
    # Manejo de usuarios conectados

    def is_authenticated(self, ip, mac=None):
        """
        Verifica si un cliente está autenticado
        
        Returns:
            bool: True si está autenticado y la sesión es válida
        """
        with self._session_lock:
            # Verificar si existe en el diccionario
            if ip not in self.active_sessions:
                return False
            
            # session = self.active_sessions[ip]
            
            # Verificación de MAC
            # if mac is not None:
            #     normalized_mac = mac.upper().replace('-', ':')
            #     session_mac = session['mac']
                
            #     if session_mac != normalized_mac and normalized_mac != "00:00:00:00:00:00":
            #         print(f"🚨 MAC no coincide para {ip}: sesión={session_mac}, actual={normalized_mac}")
            #         self.terminate_session(ip, SessionTerminationReason.MAC_MISMATCH)
            #         return False
            
            return True
    
    def get_client_mac(self, client_ip):
        """
            Obtiene la MAC address del cliente.
        """
        try:
            result = subprocess.run(['arp', '-a', client_ip], capture_output=True, text=True)
            if result.returncode == 0:
            # Parsear la salida para extraer MAC
                lines = result.stdout.split('\n')
                for line in lines:
                    if client_ip in line:
                        parts = line.split()
                        if len(parts) >= 2:
                            return parts[3] if len(parts) > 3 else parts[1]
        except:
            pass
                    
        return "00:00:00:00:00:00"  # MAC por defecto si no se puede obtener   
    