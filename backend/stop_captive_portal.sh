#!/bin/bash

echo "🛑 CERRANDO Portal Cautivo"
echo "==========================="

# ==============================
# CONFIGURACIÓN
# ==============================

# Verificar permisos root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ejecutar con: sudo ./stop_captive_portal.sh"
    exit 1
fi

# Buscar archivo de configuración cache
CONFIG_CACHE_FILE=$(ls /tmp/captive_portal_*_ap.conf 2>/dev/null | head -n1)

if [ -f "$CONFIG_CACHE_FILE" ]; then
    echo "📁 Cargando configuración desde: $CONFIG_CACHE_FILE"
    source "$CONFIG_CACHE_FILE"
    echo "✅ Configuración cargada:"
    echo "   - Interfaz WiFi: $WIFI_INTERFACE"
    echo "   - Interfaz AP: $AP_INTERFACE"
    echo "   - IP Gateway: $AP_IP"
    echo "   - Puerto Web: $PORTAL_PORT"
else
    echo "⚠️  No se encontró configuración cache, intentando detectar automáticamente..."
    
    # Intentar cargar desde archivo de configuración principal
    CONFIG_FILE="portal_config.conf"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    CONFIG_PATH="$SCRIPT_DIR/$CONFIG_FILE"
    
    if [ -f "$CONFIG_PATH" ]; then
        echo "📁 Cargando desde configuración principal: $CONFIG_FILE"
        source "$CONFIG_PATH"
        AP_INTERFACE="${WIFI_INTERFACE}_ap"
        INTERNET_IFACE="$WIFI_INTERFACE"
        LOCAL_IFACE="$AP_INTERFACE"
    else
        # Detección automática de última instancia
        AP_INTERFACE=$(iw dev | awk '$1=="Interface" && $2 ~ /_ap$/ {print $2}' | head -n1)
        if [ -n "$AP_INTERFACE" ]; then
            WIFI_INTERFACE="${AP_INTERFACE%_ap}"
            INTERNET_IFACE="$WIFI_INTERFACE"
            LOCAL_IFACE="$AP_INTERFACE"
            AP_IP="192.168.100.1"  # Valor por defecto
            PORTAL_PORT="8080"     # Valor por defecto
        else
            echo "❌ No se pudo detectar la interfaz AP"
            echo "💡 El portal cautivo podría no estar ejecutándose"
            exit 1
        fi
    fi
fi

# ==============================
# DETENER SERVICIOS
# ==============================

echo ""
echo "[1/6] Deteniendo servicios..."

stop_service() {
    local service_name=$1
    local friendly_name=$2
    
    if pgrep "$service_name" > /dev/null; then
        echo "   - Deteniendo $friendly_name..."
        pkill "$service_name"
        sleep 2
        
        # Forzar si no se detuvo
        if pgrep "$service_name" > /dev/null; then
            echo "   - Forzando cierre de $friendly_name..."
            pkill -9 "$service_name"
            sleep 1
        fi
        echo "   ✅ $friendly_name detenido"
    else
        echo "   ✅ $friendly_name no estaba ejecutándose"
    fi
}

stop_service "hostapd" "Access Point (hostapd)"
stop_service "dnsmasq" "Servidor DHCP/DNS (dnsmasq)"
stop_service "python3" "Servidor Web Python"

# Detener procesos específicos por archivo de configuración
if [ -n "$DNSMASQ_CONF" ] && [ -f "$DNSMASQ_CONF" ]; then
    echo "   - Deteniendo dnsmasq específico del portal..."
    pkill -f "dnsmasq -C $DNSMASQ_CONF"
fi

if [ -n "$HOSTAPD_CONF" ] && [ -f "$HOSTAPD_CONF" ]; then
    echo "   - Deteniendo hostapd específico del portal..."
    pkill -f "hostapd $HOSTAPD_CONF"
fi

# ==============================
# LIMPIAR REGLAS DE FIREWALL ESPECÍFICAS
# ==============================

echo "[2/6] Limpiando reglas específicas de firewall del portal..."

if [ -n "$INTERNET_IFACE" ] && [ -n "$LOCAL_IFACE" ]; then
    echo "   - Eliminando reglas NAT..."
    iptables -t nat -D POSTROUTING -o "$INTERNET_IFACE" -j MASQUERADE 2>/dev/null || true
    
    echo "   - Eliminando redirecciones HTTP/HTTPS..."
    iptables -t nat -D PREROUTING -i "$LOCAL_IFACE" -p tcp --dport 80 -j REDIRECT --to-port "$PORTAL_PORT" 2>/dev/null || true
    iptables -t nat -D PREROUTING -i "$LOCAL_IFACE" -p tcp --dport 443 -j REDIRECT --to-port "$PORTAL_PORT" 2>/dev/null || true
    
    echo "   - Eliminando reglas de forwarding..."
    iptables -D FORWARD -i "$LOCAL_IFACE" -o "$INTERNET_IFACE" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$INTERNET_IFACE" -o "$LOCAL_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    
    echo "   - Eliminando reglas de INPUT específicas..."
    iptables -D INPUT -i "$LOCAL_IFACE" -p tcp --dport "$PORTAL_PORT" -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$LOCAL_IFACE" -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$LOCAL_IFACE" -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i "$LOCAL_IFACE" -p udp --dport 67:68 -j ACCEPT 2>/dev/null || true
fi

# ==============================
# LIMPIAR REGLAS GENERALES DE FIREWALL
# ==============================

echo "[3/6] Limpiando reglas generales de firewall..."

# Solo limpiar si estamos seguros de que no afectará otras configuraciones
echo "   - Limpiando reglas de NAT..."
iptables -t nat -F 2>/dev/null || true

echo "   - Limpiando reglas de FILTER..."
iptables -F 2>/dev/null || true

echo "   - Restaurando políticas por defecto..."
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

# Limpiar reglas de loopback (las re-agregamos para seguridad)
iptables -D INPUT -i lo -j ACCEPT 2>/dev/null || true
iptables -D OUTPUT -o lo -j ACCEPT 2>/dev/null || true
iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
iptables -A OUTPUT -o lo -j ACCEPT 2>/dev/null || true

# ==============================
# LIMPIAR INTERFACES DE RED
# ==============================

echo "[4/6] Limpiando interfaces de red..."

if ip link show "$AP_INTERFACE" > /dev/null 2>&1; then
    echo "   - Eliminando interfaz $AP_INTERFACE..."
    ip link set "$AP_INTERFACE" down 2>/dev/null || true
    iw dev "$AP_INTERFACE" del 2>/dev/null || true
    echo "   ✅ Interfaz $AP_INTERFACE eliminada"
else
    echo "   ✅ Interfaz $AP_INTERFACE no existe"
fi

# Limpiar posibles direcciones IP residuales
if [ -n "$AP_IP" ]; then
    ip addr del "$AP_IP/24" dev "$AP_INTERFACE" 2>/dev/null || true
fi

# ==============================
# RESTAURAR CONFIGURACIÓN DEL SISTEMA
# ==============================

echo "[5/6] Restaurando configuración del sistema..."

echo "   - Deshabilitando IP forwarding..."
echo 0 > /proc/sys/net/ipv4/ip_forward

echo "   - Reiniciando NetworkManager..."
systemctl restart NetworkManager 2>/dev/null || true

echo "   - Reiniciando servicio de red..."
systemctl restart networking 2>/dev/null || true

# Esperar a que los servicios se estabilicen
sleep 3

# ==============================
# LIMPIEZA FINAL
# ==============================

echo "[6/6] Limpiando archivos temporales..."

# Limpiar archivos de configuración temporales
cleanup_file() {
    local file="$1"
    local description="$2"
    
    if [ -f "$file" ]; then
        rm -f "$file" 2>/dev/null && echo "   ✅ $description eliminado" || echo "   ⚠️  No se pudo eliminar $description"
    else
        echo "   ✅ $description no existe"
    fi
}

cleanup_file "$CONFIG_CACHE_FILE" "Archivo de cache de configuración"
cleanup_file "$DNSMASQ_CONF" "Configuración de dnsmasq"
cleanup_file "/tmp/hostapd_${AP_INTERFACE}.log" "Log de hostapd"
cleanup_file "$HOSTAPD_CONF" "Configuración de hostapd"

# Limpiar cualquier otro archivo temporal relacionado
rm -f "/tmp/dnsmasq_${AP_INTERFACE}.conf" 2>/dev/null || true
rm -f "/etc/hostapd/hostapd_${AP_INTERFACE}.conf" 2>/dev/null || true

# Verificar que no quedan procesos relacionados
echo ""
echo "🔍 Verificando que no quedan procesos del portal..."
if pgrep -f "hostapd.*$AP_INTERFACE" > /dev/null; then
    echo "   ⚠️  Aún hay procesos de hostapd activos, forzando cierre..."
    pkill -9 -f "hostapd.*$AP_INTERFACE" 2>/dev/null || true
fi

if pgrep -f "dnsmasq.*$AP_INTERFACE" > /dev/null; then
    echo "   ⚠️  Aún hay procesos de dnsmasq activos, forzando cierre..."
    pkill -9 -f "dnsmasq.*$AP_INTERFACE" 2>/dev/null || true
fi

# ==============================
# RESUMEN FINAL
# ==============================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ PORTAL CAUTIVO CERRADO CORRECTAMENTE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$AP_INTERFACE" ]; then
    echo "📡 Interfaces limpiadas: $AP_INTERFACE"
fi

if [ -n "$WIFI_INTERFACE" ]; then
    echo "📶 Interfaz WiFi restaurada: $WIFI_INTERFACE"
fi

echo "🛡️  Reglas de firewall eliminadas"
echo "🔧 Configuración de red restaurada"
echo "🧹 Archivos temporales limpiados"
echo "🌐 Tu conexión WiFi normal ha sido restaurada"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verificación final
echo ""
echo "🔍 Estado final del sistema:"
if ip link show "$AP_INTERFACE" > /dev/null 2>&1; then
    echo "   ❌ ADVERTENCIA: La interfaz $AP_INTERFACE sigue existiendo"
else
    echo "   ✅ Interfaz AP eliminada correctamente"
fi

if pgrep hostapd > /dev/null; then
    echo "   ❌ ADVERTENCIA: Hay procesos hostapd activos"
else
    echo "   ✅ Hostapd detenido correctamente"
fi

if pgrep dnsmasq > /dev/null; then
    echo "   ❌ ADVERTENCIA: Hay procesos dnsmasq activos"
else
    echo "   ✅ Dnsmasq detenido correctamente"
fi

echo ""
echo "🎯 Para iniciar el portal nuevamente: sudo ./start_captive_portal.sh"