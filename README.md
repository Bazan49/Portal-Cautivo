# Portal Cautivo

**2do Proyecto de la Asignatura Redes de Computadoras, Curso 2025**

## Descripción

Un **portal cautivo** es una solución informática que permite el control de acceso a una red corporativa. Al incorporarse un dispositivo nuevo a la red, el ordenador que funge como portal bloquea cualquier tipo de comunicación fuera de la red local hasta que el usuario haya iniciado sesión o cumplido alguna prerrogativa de acceso. Tras cumplir los requisitos de acceso, el usuario obtiene acceso fuera de su red local.

El ordenador que implementa la funcionalidad de portal es también el **gateway de la red** sobre la cual opera.

## Arquitectura del Sistema

El proyecto está implementado completamente en **Python puro** (sin frameworks externos) y utiliza `iptables` para el control de firewall. La arquitectura se compone de los siguientes módulos:

```
backend/
├── main.py                    # Punto de entrada y orquestación
├── httpServer.py              # Servidor HTTP base (multithreading)
├── threadingTCPServer.py      # Servidor TCP con hilos por conexión
├── serverManager.py           # Manejador de rutas y lógica HTTP
├── authService.py             # Autenticación y gestión de usuarios
├── sessionsManager.py         # Gestión de sesiones activas
├── firewallManager.py         # Interfaz con iptables
├── dataUsers.json             # Base de datos de usuarios
└── firewall/
    ├── block_all.sh           # Configuración inicial del firewall
    ├── unlock_user.sh         # Desbloqueo de acceso por IP
    └── lock_user.sh           # Bloqueo por IP/MAC

frontend/
├── login.html                 # Página de inicio de sesión
├── register.html              # Página de registro
├── success.html               # Dashboard post-autenticación
├── error.html                 # Página de errores
└── static/
    ├── css/                   # Estilos personalizados
    └── images/                # Recursos gráficos
```

### Flujo de Funcionamiento

1. **Inicialización del Portal:**
   - El script `setup_portal.sh` configura el sistema como gateway y habilita IP forwarding
   - `block_all.sh` establece políticas de firewall: DROP por defecto en FORWARD, permitiendo solo DNS y acceso al puerto del portal

2. **Conexión de Cliente:**
   - Al intentar navegar, la regla `PREROUTING` redirige HTTP (puerto 80) → portal (puerto 8080)
   - El cliente no autenticado es forzado a ver `/login`

3. **Autenticación:**
   - Usuario envía credenciales vía POST a `/login` o `/registro`
   - `authService` valida contra `dataUsers.json`
   - Si es exitoso, `sessionsManager` crea una sesión guardando IP y MAC del cliente

4. **Concesión de Acceso:**
   - `firewallManager` ejecuta `unlock_user.sh` que inserta reglas ACCEPT en FORWARD para la IP del usuario
   - El usuario obtiene acceso a Internet a través del NAT MASQUERADE

5. **Gestión de Sesiones:**
   - Un hilo de limpieza (`_cleanup_loop`) revisa cada 5 minutos las sesiones expiradas (timeout: 30 min por defecto)
   - Al expirar o hacer logout, se ejecuta `lock_user.sh` y se elimina la sesión

## Requisitos Mínimos Implementados

✅ **1. Endpoint HTTP de inicio de sesión**
   - Rutas públicas: `/`, `/login`, `/registro`
   - Rutas privadas: `/exito`, `/logout`
   - Servidor HTTP implementado desde cero con sockets

✅ **2. Bloqueo de enrutamiento sin autenticación**
   - Política `FORWARD DROP` por defecto
   - Solo DNS y acceso al portal permitidos inicialmente
   - Desbloqueo granular por IP tras login exitoso

✅ **3. Mecanismo de cuentas de usuario**
   - Sistema de registro (`/registro`) que almacena usuarios en `dataUsers.json`
   - Validación de credenciales en login
   - Gestión de contraseñas (almacenadas en texto plano para simplificidad del proyecto académico)

✅ **4. Concurrencia mediante hilos**
   - `ThreadingTCPServer` crea un thread por cada conexión entrante
   - `NetworkSessionManager` usa locks (`threading.RLock`) para acceso seguro a sesiones
   - Hilo dedicado para limpieza automática de sesiones expiradas

## Extras Implementados

✅ **3. Control de suplantación de IPs (0.5 pts)**

Implementa detección y mitigación de **IP spoofing** mediante verificación de direcciones MAC:

**Funcionamiento:**
- Al autenticarse, se guarda la IP y MAC del cliente (obtenida vía `ip neigh show`)
- En cada request, `is_authenticated()` obtiene la MAC actual y la compara con la registrada
- Si detecta MAC diferente:
  1. Bloquea tráfico de la MAC atacante con regla específica: `iptables -I FORWARD -m mac --mac-source <MAC_ATACANTE> -j DROP`
  2. Termina la sesión del usuario legítimo (debe relogear)
  3. La IP queda bloqueada temporalmente hasta que el usuario original vuelva a autenticarse

**Archivos clave:**
- `sessionsManager.py`: Método `is_authenticated()` con lógica de detección
- `firewall/lock_user.sh`: Acepta MAC opcional para bloqueo selectivo
- `serverManager.py`: Obtiene MAC en cada request (GET/POST) y la pasa a validación

**Cuidados de implementación:**
- Las reglas de bloqueo por MAC se insertan con `-I` (al inicio) para no afectar tráfico legítimo
- El usuario víctima pierde acceso pero **no queda bloqueado permanentemente**: puede reconectarse
- No interfiere con el tráfico general del punto de acceso (solo actúa sobre MAC/IP específicas)

✅ **4. Servicio de enmascaramiento IP (0.25 pts)**

NAT MASQUERADE implementado en `block_all.sh`:
```bash
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE
```
Permite que todos los dispositivos autenticados compartan la conexión del gateway con una sola IP pública.

✅ **5. Experiencia de usuario (0.25 pts)**

- Diseño frontend con CSS personalizado (`static/css/`)
- Páginas responsive con mensajes claros de error/éxito
- Dashboard (`success.html`) muestra: usuario, IP asignada, duración de sesión
- Redirecciones automáticas según estado de autenticación

## Requisitos del Sistema

- **Sistema Operativo:** Linux (Ubuntu/Debian recomendado)
- **Python:** 3.8+
- **Dependencias del sistema:**
  - `iptables`
  - `iproute2` (comando `ip`)
  - Privilegios de superusuario (sudo)

## Configuración e Instalación

### 1. Configurar el gateway

Edita las variables en `start_captive_portal.sh`:

```bash
INTERNET_IFACE="enp3s0"     # Interfaz con salida a Internet
LOCAL_IFACE="wlp2s0"        # Interfaz de la red local (WiFi AP)
PORTAL_PORT=8080            # Puerto del servidor HTTP
```

### 2. Ejecutar setup inicial

```bash
cd backend
sudo ./setup_portal.sh
```

Esto configura:
- IP forwarding (`net.ipv4.ip_forward=1`)
- Firewall base con `block_all.sh`

### 3. Iniciar el portal

```bash
sudo ./start_captive_portal.sh
```

El servidor iniciará en `http://192.168.100.1:8080` (o la IP de tu interfaz local).

### 4. Detener el portal

```bash
sudo ./stop_captive_portal.sh
```

## Estructura de Datos

### Sesiones (`sessionsManager.py`)

```python
active_sessions = {
    '192.168.100.50': {
        'mac': '3C:A0:67:BA:C2:99',
        'username': 'usuario1',
        'login_time': 1733445123.45
    }
}
```

### Usuarios (`dataUsers.json`)

```json
{
  "usuario1": {
    "password": "pass123",
    "email": "user@example.com"
  }
}
```

## Decisiones de Diseño

### Servidor HTTP desde Cero

No se usó ningún framework (Flask, Django, etc.) siguiendo las restricciones del proyecto. Implementamos:

- **Parser HTTP manual:** Lee request line, headers y body desde sockets raw
- **Enrutamiento propio:** Diccionario de rutas públicas/privadas con control de acceso
- **Multithreading:** Un thread por conexión usando `threading.Thread`

### Gestión de Firewall

- **Scripts bash modulares:** Cada acción (bloquear, desbloquear, setup) es un script separado
- **Reglas insertadas con `-I`:** Para que tengan prioridad sobre la política DROP
- **Limpieza automática:** `lock_user.sh` elimina reglas viejas antes de insertar nuevas

### Seguridad

⚠️ **Advertencias para producción:**
- Contraseñas en texto plano (solo para fines académicos)
- Sin HTTPS (se puede implementar con certificados autofirmados)
- Validación básica de inputs (vulnerable a inyección)

✅ **Protecciones implementadas:**
- Bloqueo por defecto + whitelist explícita
- Detección de IP spoofing por MAC
- Timeout de sesiones automático
- Aislamiento de sesiones por IP


## Limitaciones Conocidas

- **HTTP plano:** Sin encriptación de credenciales en tránsito
- **Persistencia volátil:** Sesiones en memoria (se pierden al reiniciar)
- **Tabla ARP:** La detección de MAC depende de entradas ARP activas



## Créditos

**Proyecto académico - Redes de Computadoras 2025**

Implementado siguiendo las restricciones de solo biblioteca estándar de Python y comandos CLI del sistema operativo.

## Licencia

Este proyecto es de uso académico y educativo.