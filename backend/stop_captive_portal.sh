#!/bin/bash

echo "🛑 Deteniendo Portal Cautivo..."

# Verificar permisos root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ejecutar con: sudo ./stop_captive_portal.sh"
    exit 1
fi

# Detener hostapd
echo "[1/5] Deteniendo Access Point..."
pkill hostapd

# Detener servidor Python (si está corriendo)
echo "[2/5] Deteniendo servidor web..."
pkill -f "python3 main.py"

# Eliminar interfaz virtual
echo "[3/5] Eliminando interfaz virtual..."
ip link set wlp2s0_ap down 2>/dev/null
iw dev wlp2s0_ap del 2>/dev/null

# Limpiar reglas iptables
echo "[4/5] Limpiando reglas de firewall..."
iptables -t nat -D POSTROUTING -o wlp2s0 -j MASQUERADE 2>/dev/null
iptables -D FORWARD -i wlp2s0_ap -o wlp2s0 -j ACCEPT 2>/dev/null
iptables -D FORWARD -i wlp2s0 -o wlp2s0_ap -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null

echo "[5/5] Reiniciando NetworkManager..."
systemctl restart NetworkManager

echo ""
echo "✅ Portal Cautivo detenido"
echo "🌐 Tu conexión WiFi normal ha sido restaurada"