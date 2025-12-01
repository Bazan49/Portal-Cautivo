#!/bin/bash

echo "🔒 Iniciando Portal Cautivo"
echo "============================"

# Verificar permisos root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ejecutar con: sudo ./start_captive_portal.sh"
    exit 1
fi

CONFIG_FILE="portal_config.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/$CONFIG_FILE"

# CARGAR CONFIGURACIÓN

echo "📁 Cargando configuración..."

if [ ! -f "$CONFIG_PATH" ]; then
    echo "❌ ERROR: No se encuentra el archivo de configuración: $CONFIG_PATH"
    echo "💡 Crea el archivo $CONFIG_FILE con la configuración necesaria"
    exit 1
fi

# Cargar configuración
source "$CONFIG_PATH"

# Validar configuración mínima requerida
if [ -z "$WIFI_INTERFACE" ] || [ -z "$AP_IP" ] || [ -z "$AP_SSID" ]; then
    echo "❌ ERROR: Configuración incompleta en $CONFIG_FILE"
    echo "💡 Verifica que WIFI_INTERFACE, AP_IP y AP_SSID estén definidos"
    exit 1
fi

# DERIVAR VARIABLES

AP_INTERFACE="${WIFI_INTERFACE}_ap"
INTERNET_IFACE="$WIFI_INTERFACE"     # Tu interfaz WiFi con internet
LOCAL_IFACE="$AP_INTERFACE"          # Tu interfaz de WiFi hotspot
CONFIG_CACHE_FILE="/tmp/captive_portal_${AP_INTERFACE}.conf"
DNSMASQ_CONF="/tmp/dnsmasq_${AP_INTERFACE}.conf"
HOSTAPD_CONF="/etc/hostapd/hostapd_${AP_INTERFACE}.conf"

# Valores por defecto para configuraciones opcionales
AP_DHCP_START="${AP_DHCP_START:-192.168.100.50}"
AP_DHCP_END="${AP_DHCP_END:-192.168.100.150}"
AP_CHANNEL="${AP_CHANNEL:-7}"
AP_PASSWORD="${AP_PASSWORD:-12345678}"
PORTAL_PORT="${PORTAL_PORT:-8080}"

# Verificar que la interfaz WiFi existe
if ! ip link show "$WIFI_INTERFACE" > /dev/null 2>&1; then
    echo "❌ ERROR: La interfaz WiFi '$WIFI_INTERFACE' no existe"
    echo "📡 Interfaces disponibles:"
    ip link show | grep -E "^[0-9]+:" | awk -F: '{print $2}' | tr -d ' '
    exit 1
fi

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

# CONFIGURACIÓN DE RED

# Crear interfaz virtual AP
echo "[2/7] Creando interfaz virtual AP..."
if ! iw dev "$WIFI_INTERFACE" interface add "$AP_INTERFACE" type __ap; then
    echo "❌ Error creando interfaz virtual $AP_INTERFACE"
    echo "💡 Verifica que la interfaz $WIFI_INTERFACE soporte modo AP"
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
echo "✅ Interfaz configurada"

echo "[4/7] Configurando enrutamiento..."
echo 1 > /proc/sys/net/ipv4/ip_forward

echo "[5/7] Iniciando servicios de red..."

# Configurar dnsmasq
echo "   - Configurando servidor DHCP..."
cat > "$DNSMASQ_CONF" << EOF
interface=$AP_INTERFACE
bind-interfaces
dhcp-range=$AP_DHCP_START,$AP_DHCP_END,12h
dhcp-option=3,$AP_IP
dhcp-option=6,8.8.8.8
server=8.8.8.8
log-dhcp
EOF

dnsmasq -C "$DNSMASQ_CONF"
sleep 2

if ! pgrep dnsmasq > /dev/null; then
    echo "❌ Error iniciando dnsmasq"
    exit 1
fi
sleep 1

# Configurar hostapd
# Verificar/crear configuración hostapd
echo "[6/7] Configurando Access Point..."
if [ ! -f "$HOSTAPD_CONF" ]; then
    mkdir -p /etc/hostapd
    cat > "$HOSTAPD_CONF"<< EOF
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
else
    # Actualizar configuración existente
    sed -i 's/interface=.*/interface=wlo1_ap/' /etc/hostapd/hostapd.conf
    sed -i 's/channel=.*/channel=5/' /etc/hostapd/hostapd.conf
fi

echo "Iniciando hostapd..."
hostapd "$HOSTAPD_CONF" > "/tmp/hostapd_${AP_INTERFACE}.log" 2>&1 &
sleep 3

if pgrep hostapd > /dev/null; then
    echo "✅ Access Point iniciado: $AP_SSID"
else
    echo "❌ Error iniciando hostapd"
    echo "📄 Revisa el log: /tmp/hostapd_${AP_INTERFACE}.log"
    exit 1
fi


# INICIAR SERVIDOR WEB

echo "[7/7] Iniciando servidor web en puerto $PORTAL_PORT..."

# Guardar configuración para el script de cierre
cat > "$CONFIG_CACHE_FILE" << EOF
WIFI_INTERFACE=$WIFI_INTERFACE
AP_INTERFACE=$AP_INTERFACE
INTERNET_IFACE=$INTERNET_IFACE
LOCAL_IFACE=$LOCAL_IFACE
AP_IP=$AP_IP
DNSMASQ_CONF=$DNSMASQ_CONF
HOSTAPD_CONF=$HOSTAPD_CONF
PORTAL_PORT=$PORTAL_PORT
EOF

echo "🔧 Configuración guardada en: $CONFIG_CACHE_FILE"

# Mostrar resumen del firewall
echo ""
echo "🛡️  CONFIGURACIÓN DE FIREWALL ACTIVA:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ NAT configurado: $INTERNET_IFACE → MASQUERADE"
echo "✅ Servidor web accesible: $LOCAL_IFACE:$PORTAL_PORT"
echo "✅ Redirección activa: HTTP/HTTPS → Puerto $PORTAL_PORT"
echo "🚫 Forwarding bloqueado: Los dispositivos NO tienen internet"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Mostrar resumen general
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ PORTAL CAUTIVO INICIADO CORRECTAMENTE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📶 SSID:          $AP_SSID"
echo "🔑 Password:      $AP_PASSWORD"
echo "🌐 Gateway:       $AP_IP"
echo "🖥️  Portal Web:    http://$AP_IP:$PORTAL_PORT"
echo "📡 Interfaz AP:   $AP_INTERFACE"
echo "📡 Interfaz WiFi: $WIFI_INTERFACE"
echo "🔧 DHCP Range:    $AP_DHCP_START - $AP_DHCP_END"
echo "📶 Canal WiFi:    $AP_CHANNEL"
echo "🔧 Config File:   $CONFIG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 Los dispositivos se redirigirán automáticamente al portal"
echo "💡 Para dar internet a un dispositivo, agrega reglas de FORWARD"
echo ""

cd "$SCRIPT_DIR"

# CONFIGURAR LIMPIEZA AUTOMÁTICA AL SALIR
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

if [ -f "main.py" ]; then
    echo "🚀 Iniciando servidor Python..."
    python3 main.py "$PORTAL_PORT" "$INTERNET_IFACE" "$LOCAL_IFACE" &
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
    echo "cd $SCRIPT_DIR && python3 main.py"
    echo ""
    echo "💡 Presiona Ctrl+C para detener el portal cautivo"
    
    # Mantener el script corriendo
    while true; do
        sleep 10
        echo "⏳ Portal cautivo activo - SSID: $AP_SSID"
    done
fi

