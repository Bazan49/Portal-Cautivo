#!/bin/bash

echo "🔒 Iniciando Portal Cautivo"
echo "============================"

# Verificar permisos root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ejecutar con: sudo ./start_captive_portal.sh"
    exit 1
fi

CONFIG_FILE=".env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/$CONFIG_FILE"

# ═══════════════════════════════════════════════════════════════
# CARGAR CONFIGURACIÓN
# ═══════════════════════════════════════════════════════════════

echo "📁 Cargando configuración..."

if [ ! -f "$CONFIG_PATH" ]; then
    echo "❌ ERROR: No se encuentra el archivo de configuración: $CONFIG_PATH"
    echo ""
    echo "💡 CONFIGURACIÓN INICIAL REQUERIDA"
    echo "   Ejecuta primero el asistente de configuración:"
    echo ""
    echo "   sudo ./setup_portal.sh"
    echo ""
    echo "   Esto te permitirá:"
    echo "   • Seleccionar la interfaz para Internet (WiFi/Ethernet/USB/etc)"
    echo "   • Seleccionar la interfaz WiFi para el Access Point"
    echo "   • Configurar SSID, contraseña y red"
    echo ""
    exit 1
fi

# Cargar configuración
source "$CONFIG_PATH"

# Validar configuración mínima requerida
if [ -z "$INTERNET_INTERFACE" ] || [ -z "$WIFI_INTERFACE" ] || [ -z "$AP_IP" ] || [ -z "$AP_SSID" ]; then
    echo "❌ ERROR: Configuración incompleta en $CONFIG_FILE"
    echo "💡 Ejecuta el asistente de configuración: sudo ./setup_portal.sh"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# DERIVAR VARIABLES
# ═══════════════════════════════════════════════════════════════

AP_INTERFACE="${WIFI_INTERFACE}_ap"
LOCAL_IFACE="$AP_INTERFACE"          # Interfaz del AP (virtual)
CONFIG_CACHE_FILE="/tmp/captive_portal_${AP_INTERFACE}.conf"
DNSMASQ_CONF="/tmp/dnsmasq_${AP_INTERFACE}.conf"
HOSTAPD_CONF="/etc/hostapd/hostapd_${AP_INTERFACE}.conf"

# Valores por defecto para configuraciones opcionales
AP_DHCP_START="${AP_DHCP_START:-192.168.100.50}"
AP_DHCP_END="${AP_DHCP_END:-192.168.100.150}"
AP_CHANNEL="${AP_CHANNEL:-6}"
AP_PASSWORD="${AP_PASSWORD:-12345678}"
PORTAL_PORT="${PORTAL_PORT:-8080}"
AP_NETWORK="${AP_NETWORK:-192.168.100.0/24}"

# ═══════════════════════════════════════════════════════════════
# MOSTRAR CONFIGURACIÓN CARGADA
# ═══════════════════════════════════════════════════════════════

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 CONFIGURACIÓN CARGADA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📡 Interfaz Internet:  $INTERNET_INTERFACE"
echo "📶 Interfaz WiFi AP:   $WIFI_INTERFACE"
echo "🌐 SSID:              $AP_SSID"
echo "🔐 Canal:             $AP_CHANNEL"
echo "🖥️  Gateway:           $AP_IP"
echo "🌍 Puerto Web:        $PORTAL_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ═══════════════════════════════════════════════════════════════
# VERIFICACIÓN DE INTERFACES
# ═══════════════════════════════════════════════════════════════

echo "[0/7] Verificando interfaces..."

# Verificar que la interfaz de Internet existe
if ! ip link show "$INTERNET_INTERFACE" > /dev/null 2>&1; then
    echo "❌ ERROR: La interfaz de Internet '$INTERNET_INTERFACE' no existe"
    echo "📡 Interfaces disponibles:"
    ip link show | grep -E "^[0-9]+:" | awk -F: '{print "   - " $2}' | tr -d ' '
    echo ""
    echo "💡 Solución: Ejecuta sudo ./setup_portal.sh para reconfigurar"
    exit 1
fi

# Verificar que la interfaz WiFi existe
if ! ip link show "$WIFI_INTERFACE" > /dev/null 2>&1; then
    echo "❌ ERROR: La interfaz WiFi '$WIFI_INTERFACE' no existe"
    echo "📡 Interfaces disponibles:"
    ip link show | grep -E "^[0-9]+:" | awk -F: '{print "   - " $2}' | tr -d ' '
    echo ""
    echo "💡 Solución: Ejecuta sudo ./setup_portal.sh para reconfigurar"
    exit 1
fi

# Verificar que la interfaz de Internet está UP
if ! ip link show "$INTERNET_INTERFACE" | grep -q "state UP"; then
    echo "⚠️  ADVERTENCIA: La interfaz $INTERNET_INTERFACE no está activa"
    echo "   Intentando activarla..."
    ip link set dev "$INTERNET_INTERFACE" up
    sleep 2
    
    if ! ip link show "$INTERNET_INTERFACE" | grep -q "state UP"; then
        echo "❌ No se pudo activar $INTERNET_INTERFACE"
        echo "💡 Verifica la conexión física (cable/WiFi)"
        exit 1
    fi
fi

# Verificar conectividad de Internet
echo "🌐 Verificando conectividad a Internet..."
if ip route show dev "$INTERNET_INTERFACE" 2>/dev/null | grep -q "default"; then
    echo "   ✅ Interfaz $INTERNET_INTERFACE tiene ruta por defecto"
else
    echo "   ⚠️  ADVERTENCIA: $INTERNET_INTERFACE no tiene ruta por defecto"
    echo "   El portal funcionará pero los clientes no tendrán Internet"
fi

# ═══════════════════════════════════════════════════════════════
# VERIFICACIÓN DEL ESTADO DEL SISTEMA
# ═══════════════════════════════════════════════════════════════

echo ""
echo "[1/7] Verificando estado del sistema..."

check_service() {
    local service_name=$1
    local friendly_name=$2
    
    if pgrep "$service_name" > /dev/null; then
        echo "❌ ERROR: $friendly_name ya está ejecutándose"
        echo "💡 Ejecuta primero: sudo ./stop_captive_portal.sh"
        return 1
    fi
    return 0
}

# Verificar servicios
if ! check_service "hostapd" "hostapd (Access Point)"; then exit 1; fi
if ! check_service "dnsmasq" "dnsmasq (DHCP/DNS)"; then exit 1; fi

# Verificar interfaz AP
if ip link show "$AP_INTERFACE" > /dev/null 2>&1; then
    echo "❌ ERROR: La interfaz $AP_INTERFACE ya existe"
    echo "💡 Ejecuta primero: sudo ./stop_captive_portal.sh"
    exit 1
fi

echo "✅ Sistema listo para iniciar"

# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN DE RED
# ═══════════════════════════════════════════════════════════════

# Crear interfaz virtual AP
echo ""
echo "[2/7] Creando interfaz virtual AP..."
if ! iw dev "$WIFI_INTERFACE" interface add "$AP_INTERFACE" type __ap; then
    echo "❌ Error creando interfaz virtual $AP_INTERFACE"
    echo "💡 Verifica que la interfaz $WIFI_INTERFACE soporte modo AP"
    echo "   Ejecuta: iw list | grep -A 10 'Supported interface modes'"
    exit 1
fi
sleep 1

echo "[3/7] Configurando interfaz de red..."
ip link set dev "$AP_INTERFACE" up
sleep 1

ip addr add "$AP_IP/24" brd + dev "$AP_INTERFACE"
sleep 1

# Verificar configuración IP
if ! ip addr show "$AP_INTERFACE" | grep -q "$AP_IP"; then
    echo "❌ Error: No se asignó la IP $AP_IP a $AP_INTERFACE"
    exit 1
fi
echo "✅ Interfaz $AP_INTERFACE configurada con IP $AP_IP"

echo "[4/7] Configurando enrutamiento..."
echo 1 > /proc/sys/net/ipv4/ip_forward
echo "✅ IP forwarding habilitado"

# ═══════════════════════════════════════════════════════════════
# SERVICIOS DE RED
# ═══════════════════════════════════════════════════════════════

echo ""
echo "[5/7] Iniciando servicios de red..."

# Configurar dnsmasq
echo "   - Configurando servidor DHCP/DNS..."
cat > "$DNSMASQ_CONF" << EOF
# Configuración DHCP/DNS para Portal Cautivo
interface=$AP_INTERFACE
bind-interfaces
dhcp-range=$AP_DHCP_START,$AP_DHCP_END,12h
dhcp-option=3,$AP_IP
dhcp-option=6,8.8.8.8,8.8.4.4
server=8.8.8.8
server=8.8.4.4
log-dhcp
log-queries
EOF

dnsmasq -C "$DNSMASQ_CONF"
sleep 2

if ! pgrep dnsmasq > /dev/null; then
    echo "❌ Error iniciando dnsmasq"
    echo "📄 Verifica: dnsmasq --test -C $DNSMASQ_CONF"
    exit 1
fi
echo "   ✅ Servidor DHCP/DNS iniciado"

# ═══════════════════════════════════════════════════════════════
# ACCESS POINT
# ═══════════════════════════════════════════════════════════════

echo ""
echo "[6/7] Configurando Access Point..."

# Crear/actualizar configuración hostapd
mkdir -p /etc/hostapd

cat > "$HOSTAPD_CONF" << EOF
# Configuración Access Point para Portal Cautivo
interface=$AP_INTERFACE
driver=nl80211
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHANNEL
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$AP_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

echo "   - Iniciando hostapd..."
hostapd "$HOSTAPD_CONF" > "/tmp/hostapd_${AP_INTERFACE}.log" 2>&1 &
sleep 3

if pgrep hostapd > /dev/null; then
    echo "   ✅ Access Point '$AP_SSID' iniciado en canal $AP_CHANNEL"
else
    echo "❌ Error iniciando hostapd"
    echo "📄 Revisa el log: /tmp/hostapd_${AP_INTERFACE}.log"
    echo ""
    echo "Contenido del log:"
    tail -n 20 "/tmp/hostapd_${AP_INTERFACE}.log"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# GUARDAR CONFIGURACIÓN PARA CIERRE
# ═══════════════════════════════════════════════════════════════

cat > "$CONFIG_CACHE_FILE" << EOF
INTERNET_INTERFACE=$INTERNET_INTERFACE
WIFI_INTERFACE=$WIFI_INTERFACE
AP_INTERFACE=$AP_INTERFACE
LOCAL_IFACE=$LOCAL_IFACE
AP_IP=$AP_IP
DNSMASQ_CONF=$DNSMASQ_CONF
HOSTAPD_CONF=$HOSTAPD_CONF
PORTAL_PORT=$PORTAL_PORT
CONFIG_SOURCE="$CONFIG_FILE"
EOF

# ═══════════════════════════════════════════════════════════════
# INICIAR SERVIDOR WEB
# ═══════════════════════════════════════════════════════════════

echo ""
echo "[7/7] Iniciando servidor web en puerto $PORTAL_PORT..."

# Mostrar resumen general
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ PORTAL CAUTIVO INICIADO CORRECTAMENTE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📶 SSID:              $AP_SSID"
echo "🔑 Password:          $(echo "$AP_PASSWORD" | sed 's/./*/g')"
echo "🌐 Gateway:           $AP_IP"
echo "🖥️  Portal Web:        http://$AP_IP:$PORTAL_PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📡 Interfaz Internet: $INTERNET_INTERFACE"
echo "📶 Interfaz AP:       $AP_INTERFACE"
echo "🔧 DHCP Range:        $AP_DHCP_START - $AP_DHCP_END"
echo "📶 Canal WiFi:        $AP_CHANNEL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Los dispositivos se redirigirán automáticamente al portal"
echo "💡 Para detener: Presiona Ctrl+C o ejecuta sudo ./stop_captive_portal.sh"
echo ""

cd "$SCRIPT_DIR"

# ═══════════════════════════════════════════════════════════════
# CONFIGURAR LIMPIEZA AUTOMÁTICA AL SALIR
# ═══════════════════════════════════════════════════════════════

cleanup_portal() {
    echo ""
    echo "🛑 Señal de interrupción recibida"
    if [ -f "./stop_captive_portal.sh" ]; then
        ./stop_captive_portal.sh
    else
        echo "❌ No se encontró stop_captive_portal.sh, cerrando manualmente..."
        pkill -f "python3 main.py" 2>/dev/null || true
        pkill hostapd 2>/dev/null || true
        pkill dnsmasq 2>/dev/null || true
    fi
    exit 0
}

trap cleanup_portal INT TERM

# ═══════════════════════════════════════════════════════════════
# INICIAR SERVIDOR PYTHON
# ═══════════════════════════════════════════════════════════════

if [ -f "main.py" ]; then
    echo "🚀 Iniciando servidor Python..."
    python3 main.py "$PORTAL_PORT" "$INTERNET_INTERFACE" "$LOCAL_IFACE" &
    PYTHON_PID=$!
    
    echo "🔧 Servidor Python iniciado con PID: $PYTHON_PID"
    echo ""
    echo "💡 Presiona Ctrl+C para detener el portal cautivo"
    
    # Esperar a que el proceso de Python termine
    wait $PYTHON_PID
    
else
    echo "❌ No se encuentra main.py en $SCRIPT_DIR"
    echo ""
    echo "El Access Point está funcionando. Para iniciar el portal web manualmente:"
    echo "cd $SCRIPT_DIR && python3 main.py $PORTAL_PORT $INTERNET_INTERFACE $LOCAL_IFACE"
    echo ""
    echo "💡 Presiona Ctrl+C para detener el portal cautivo"
    
    # Mantener el script corriendo
    while true; do
        sleep 10
        if ! pgrep hostapd > /dev/null || ! pgrep dnsmasq > /dev/null; then
            echo "⚠️  Servicios detenidos inesperadamente"
            break
        fi
    done
fi