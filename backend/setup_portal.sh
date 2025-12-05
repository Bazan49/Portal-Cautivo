#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       CONFIGURACIÓN INICIAL DEL PORTAL CAUTIVO               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Verificar permisos root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Este script requiere permisos de superusuario"
    echo "💡 Ejecuta: sudo ./setup_portal.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.env"

# ============================================================
# FUNCIONES AUXILIARES
# ============================================================

print_section() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

get_interface_type() {
    local iface=$1
    local type="Desconocido"
    
    # Verificar si es WiFi
    if [ -d "/sys/class/net/$iface/wireless" ] || iw dev "$iface" info &>/dev/null; then
        type="WiFi"
    # Verificar si es Ethernet
    elif [ -d "/sys/class/net/$iface/device" ]; then
        if ethtool "$iface" 2>/dev/null | grep -q "Link detected: yes"; then
            type="Ethernet (Conectado)"
        else
            type="Ethernet"
        fi
    # Verificar si es USB
    elif readlink "/sys/class/net/$iface" | grep -q "usb"; then
        type="USB"
    # Verificar loopback
    elif [ "$iface" == "lo" ]; then
        type="Loopback"
    # Verificar interfaz virtual
    elif [ -L "/sys/class/net/$iface" ]; then
        type="Virtual"
    fi
    
    echo "$type"
}

get_interface_status() {
    local iface=$1
    local status="DOWN"
    
    if ip link show "$iface" | grep -q "state UP"; then
        status="UP"
    elif ip link show "$iface" | grep -q "state DOWN"; then
        status="DOWN"
    elif ip link show "$iface" | grep -q "state UNKNOWN"; then
        status="UNKNOWN"
    fi
    
    echo "$status"
}

get_interface_ip() {
    local iface=$1
    local ip=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1 | head -n1)
    
    if [ -z "$ip" ]; then
        echo "Sin IP"
    else
        echo "$ip"
    fi
}

has_internet_connection() {
    local iface=$1
    
    # Verificar si tiene gateway
    if ip route show dev "$iface" 2>/dev/null | grep -q "default"; then
        echo "✓"
    else
        echo "✗"
    fi
}

# ============================================================
# ESCANEO DE INTERFACES
# ============================================================

print_section "1. ESCANEO DE INTERFACES DE RED"

echo "🔍 Detectando interfaces disponibles..."
echo ""

# Obtener todas las interfaces excepto loopback
mapfile -t INTERFACES < <(ip link show | awk -F': ' '/^[0-9]+:/ {print $2}' | grep -v "^lo$" | sort)

if [ ${#INTERFACES[@]} -eq 0 ]; then
    echo "❌ No se encontraron interfaces de red"
    exit 1
fi

# Mostrar tabla de interfaces
echo "┌────┬─────────────────┬──────────────────┬──────────┬─────────────────┬──────────┐"
echo "│ N° │ INTERFAZ        │ TIPO             │ ESTADO   │ IP              │ INTERNET │"
echo "├────┼─────────────────┼──────────────────┼──────────┼─────────────────┼──────────┤"

declare -A INTERFACE_INFO
index=1

for iface in "${INTERFACES[@]}"; do
    type=$(get_interface_type "$iface")
    status=$(get_interface_status "$iface")
    ip=$(get_interface_ip "$iface")
    internet=$(has_internet_connection "$iface")
    
    # Guardar información para uso posterior
    INTERFACE_INFO["$index"]="$iface|$type|$status|$ip|$internet"
    
    printf "│ %-2s │ %-15s │ %-16s │ %-8s │ %-15s │ %-8s │\n" \
        "$index" "$iface" "$type" "$status" "$ip" "$internet"
    
    ((index++))
done

echo "└────┴─────────────────┴──────────────────┴──────────┴─────────────────┴──────────┘"
echo ""
echo "💡 Leyenda: ✓ = Tiene ruta por defecto, ✗ = Sin ruta por defecto"

# ============================================================
# SELECCIÓN DE INTERFAZ PARA INTERNET
# ============================================================

print_section "2. SELECCIÓN DE INTERFAZ DE INTERNET"

echo "Esta interfaz proporcionará conectividad a Internet al portal cautivo."
echo "Puede ser WiFi, Ethernet, USB o cualquier interfaz con acceso a Internet."
echo ""

# Sugerir interfaz con Internet
SUGGESTED=""
for key in "${!INTERFACE_INFO[@]}"; do
    IFS='|' read -r iface type status ip internet <<< "${INTERFACE_INFO[$key]}"
    if [ "$internet" == "✓" ] && [ "$status" == "UP" ]; then
        SUGGESTED="$key"
        echo "💡 Recomendación: [$key] $iface ($type, $ip) - Tiene Internet activo"
        break
    fi
done

echo ""
read -p "Selecciona el número de interfaz para Internet [${SUGGESTED:-1}]: " INTERNET_CHOICE

# Usar valor por defecto si no se ingresa nada
if [ -z "$INTERNET_CHOICE" ]; then
    INTERNET_CHOICE=${SUGGESTED:-1}
fi

# Validar selección
if [ -z "${INTERFACE_INFO[$INTERNET_CHOICE]}" ]; then
    echo "❌ Selección inválida"
    exit 1
fi

IFS='|' read -r INTERNET_IFACE INTERNET_TYPE INTERNET_STATUS INTERNET_IP INTERNET_NET <<< "${INTERFACE_INFO[$INTERNET_CHOICE]}"

echo ""
echo "✅ Interfaz seleccionada para Internet:"
echo "   - Nombre: $INTERNET_IFACE"
echo "   - Tipo: $INTERNET_TYPE"
echo "   - Estado: $INTERNET_STATUS"
echo "   - IP: $INTERNET_IP"

# ============================================================
# SELECCIÓN DE INTERFAZ PARA ACCESS POINT
# ============================================================

print_section "3. SELECCIÓN DE INTERFAZ PARA ACCESS POINT"

echo "Esta interfaz se usará para crear el punto de acceso WiFi del portal."
echo "DEBE ser una interfaz WiFi que soporte modo AP."
echo ""

# Filtrar solo interfaces WiFi disponibles para AP
echo "Interfaces WiFi disponibles:"
echo ""

WIFI_INTERFACES=()
wifi_index=1

for key in "${!INTERFACE_INFO[@]}"; do
    IFS='|' read -r iface type status ip internet <<< "${INTERFACE_INFO[$key]}"
    
    # Verificar si es WiFi y no es la misma que la de Internet
    if [[ "$type" == "WiFi" ]]; then
        # Verificar soporte para modo AP
        if iw list 2>/dev/null | grep -A 10 "Supported interface modes" | grep -q "AP"; then
            WIFI_INTERFACES+=("$iface")
            ap_support="✓ Soporta AP"
        else
            ap_support="✗ No soporta AP"
        fi
        
        same_warning=""
        if [ "$iface" == "$INTERNET_IFACE" ]; then
            same_warning="(⚠️  Misma que Internet)"
        fi
        
        printf "  [%d] %-15s %-20s %s\n" "$wifi_index" "$iface" "$ap_support" "$same_warning"
        ((wifi_index++))
    fi
done

if [ ${#WIFI_INTERFACES[@]} -eq 0 ]; then
    echo "❌ No se encontraron interfaces WiFi con soporte para modo AP"
    echo ""
    echo "💡 Opciones:"
    echo "   1. Conecta un adaptador WiFi USB con soporte AP"
    echo "   2. Verifica que tu tarjeta WiFi soporte modo AP: iw list"
    exit 1
fi

echo ""
read -p "Selecciona el número de interfaz WiFi para AP [1]: " AP_CHOICE

# Usar valor por defecto
if [ -z "$AP_CHOICE" ]; then
    AP_CHOICE=1
fi

# Validar selección
if [ "$AP_CHOICE" -lt 1 ] || [ "$AP_CHOICE" -gt ${#WIFI_INTERFACES[@]} ]; then
    echo "❌ Selección inválida"
    exit 1
fi

WIFI_INTERFACE="${WIFI_INTERFACES[$((AP_CHOICE-1))]}"

echo ""
echo "✅ Interfaz seleccionada para AP: $WIFI_INTERFACE"

# Informar sobre la creación de interfaz virtual
echo ""
echo "ℹ️  NOTA: Se creará una interfaz virtual '${WIFI_INTERFACE}_ap' para el Access Point"
echo "   Interfaz base: $WIFI_INTERFACE"
echo "   Interfaz AP:   ${WIFI_INTERFACE}_ap"

# Advertencia adicional si se usa la misma interfaz
if [ "$WIFI_INTERFACE" == "$INTERNET_IFACE" ]; then
    echo ""
    echo "⚠️  ADVERTENCIA: Estás usando la misma interfaz para Internet y AP"
    echo "   Si $WIFI_INTERFACE pierde conexión WiFi, el portal perderá Internet"
    echo "   Considera usar interfaces separadas para mayor estabilidad"
    echo ""
    read -p "¿Deseas continuar? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[sS]$ ]]; then
        echo "Configuración cancelada"
        exit 0
    fi
fi

# ============================================================
# CONFIGURACIÓN DEL ACCESS POINT
# ============================================================

print_section "4. CONFIGURACIÓN DEL ACCESS POINT"

echo "Configura los parámetros del punto de acceso WiFi."
echo ""

# SSID
read -p "Nombre de red WiFi (SSID) [PortalCautivo]: " AP_SSID
AP_SSID=${AP_SSID:-PortalCautivo}

# Contraseña
while true; do
    read -sp "Contraseña WiFi (mínimo 8 caracteres) [12345678]: " AP_PASSWORD
    echo ""
    
    if [ -z "$AP_PASSWORD" ]; then
        AP_PASSWORD="12345678"
        break
    fi
    
    if [ ${#AP_PASSWORD} -ge 8 ]; then
        break
    else
        echo "❌ La contraseña debe tener al menos 8 caracteres"
    fi
done

# Canal WiFi
read -p "Canal WiFi (1-11) [6]: " AP_CHANNEL
AP_CHANNEL=${AP_CHANNEL:-6}

# Validar canal
if [ "$AP_CHANNEL" -lt 1 ] || [ "$AP_CHANNEL" -gt 11 ]; then
    echo "⚠️  Canal inválido, usando canal 6"
    AP_CHANNEL=6
fi

# Configuración de red
read -p "IP del Gateway [192.168.100.1]: " AP_IP
AP_IP=${AP_IP:-192.168.100.1}

read -p "Red del portal [192.168.100.0/24]: " AP_NETWORK
AP_NETWORK=${AP_NETWORK:-192.168.100.0/24}

read -p "Inicio rango DHCP [192.168.100.50]: " AP_DHCP_START
AP_DHCP_START=${AP_DHCP_START:-192.168.100.50}

read -p "Fin rango DHCP [192.168.100.150]: " AP_DHCP_END
AP_DHCP_END=${AP_DHCP_END:-192.168.100.150}

# Puerto del portal
read -p "Puerto del servidor web [8080]: " PORTAL_PORT
PORTAL_PORT=${PORTAL_PORT:-8080}

# ============================================================
# RESUMEN Y CONFIRMACIÓN
# ============================================================

print_section "5. RESUMEN DE CONFIGURACIÓN"

cat << EOF

╔═══════════════════════════════════════════════════════════════╗
║                    CONFIGURACIÓN FINAL                        ║
╚═══════════════════════════════════════════════════════════════╝

📡 INTERFACES:
   Internet:        $INTERNET_IFACE ($INTERNET_TYPE)
   WiFi Base:       $WIFI_INTERFACE
   AP Virtual:      ${WIFI_INTERFACE}_ap (se creará automáticamente)

📶 ACCESS POINT:
   SSID:            $AP_SSID
   Contraseña:      $(echo "$AP_PASSWORD" | sed 's/./*/g')
   Canal:           $AP_CHANNEL

🌐 CONFIGURACIÓN DE RED:
   Gateway:         $AP_IP
   Red:             $AP_NETWORK
   DHCP Inicio:     $AP_DHCP_START
   DHCP Fin:        $AP_DHCP_END

🖥️  SERVIDOR WEB:
   Puerto:          $PORTAL_PORT
   URL Portal:      http://$AP_IP:$PORTAL_PORT

EOF

read -p "¿Guardar configuración? (S/n): " confirm

if [[ "$confirm" =~ ^[nN]$ ]]; then
    echo "❌ Configuración cancelada"
    exit 0
fi

# ============================================================
# GUARDAR CONFIGURACIÓN
# ============================================================

print_section "6. GUARDANDO CONFIGURACIÓN"

cat > "$CONFIG_FILE" << EOF
# ═══════════════════════════════════════════════════════════════
# CONFIGURACIÓN DEL PORTAL CAUTIVO
# Generado automáticamente por setup_portal.sh
# Fecha: $(date '+%Y-%m-%d %H:%M:%S')
# ═══════════════════════════════════════════════════════════════

# INTERFACES DE RED
# Interfaz que proporciona acceso a Internet (puede ser WiFi, Ethernet, USB, etc.)
INTERNET_INTERFACE="$INTERNET_IFACE"

# Interfaz WiFi para crear el Access Point
WIFI_INTERFACE="$WIFI_INTERFACE"

# CONFIGURACIÓN DEL ACCESS POINT
AP_SSID="$AP_SSID"
AP_PASSWORD="$AP_PASSWORD"
AP_CHANNEL="$AP_CHANNEL"

# CONFIGURACIÓN DE RED
AP_IP="$AP_IP"
AP_NETWORK="$AP_NETWORK"
AP_DHCP_START="$AP_DHCP_START"
AP_DHCP_END="$AP_DHCP_END"

# SERVIDOR WEB
PORTAL_PORT="$PORTAL_PORT"
EOF

chmod 600 "$CONFIG_FILE"

echo "✅ Configuración guardada en: $CONFIG_FILE"

# ============================================================
# VERIFICACIÓN DE DEPENDENCIAS
# ============================================================

print_section "7. VERIFICACIÓN DE DEPENDENCIAS"

check_command() {
    if command -v "$1" &> /dev/null; then
        echo "   ✅ $1 instalado"
        return 0
    else
        echo "   ❌ $1 NO ENCONTRADO"
        return 1
    fi
}

missing_deps=0

echo "Verificando herramientas necesarias..."
echo ""

check_command "hostapd" || ((missing_deps++))
check_command "dnsmasq" || ((missing_deps++))
check_command "iptables" || ((missing_deps++))
check_command "python3" || ((missing_deps++))
check_command "iw" || ((missing_deps++))
check_command "ip" || ((missing_deps++))

if [ $missing_deps -gt 0 ]; then
    echo ""
    echo "⚠️  Faltan $missing_deps dependencia(s)"
    echo ""
    echo "Para instalar en Debian/Ubuntu:"
    echo "   sudo apt-get update"
    echo "   sudo apt-get install hostapd dnsmasq iptables python3 iw iproute2"
    echo ""
    echo "Para instalar en Fedora/RHEL:"
    echo "   sudo dnf install hostapd dnsmasq iptables python3 iw iproute"
    echo ""
fi

# ============================================================
# FINALIZACIÓN
# ============================================================

print_section "✅ CONFIGURACIÓN COMPLETADA"

cat << EOF

El portal cautivo ha sido configurado exitosamente.

📋 PRÓXIMOS PASOS:

1. Inicia el portal cautivo:
   sudo ./start_captive_portal.sh

2. Conéctate a la red WiFi:
   SSID: $AP_SSID
   Contraseña: $(echo "$AP_PASSWORD" | sed 's/./*/g')

3. Accede al portal:
   http://$AP_IP:$PORTAL_PORT

4. Para detener el portal:
   sudo ./stop_captive_portal.sh

📁 ARCHIVOS:
   Configuración:   $CONFIG_FILE
   Directorio:      $SCRIPT_DIR

💡 NOTA: Puedes editar $CONFIG_FILE manualmente y volver a ejecutar
   el script de inicio sin necesidad de reconfigurar.

EOF

echo "═══════════════════════════════════════════════════════════════"