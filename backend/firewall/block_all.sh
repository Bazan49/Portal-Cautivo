#!/bin/bash
#Configura el portal cautivo para dispositivos conectados a la WiFi   

# Limpiar reglas existentes
iptables -F
iptables -t nat -F

# Políticas por defecto: bloquear todo forwarding
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP  # Bloquea el tráfico que pasa por la PC
iptables -P OUTPUT ACCEPT

# Permitir tráfico local
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Configurar NAT para que los dispositivos usen tu conexión
INTERNET_IFACE="wlp2s0"     # Tu interfaz WiFi con internet
LOCAL_IFACE="wlp2s0_ap"     # Tu interfaz de WiFi hotspot

# NAT - permite que dispositivos compartan tu internet (después de autenticar)
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE

# PERMITIR acceso al servidor web del portal (puerto 8080)
iptables -A INPUT -i $LOCAL_IFACE -p tcp --dport 8080 -j ACCEPT

# REDIRIGIR tráfico web de dispositivos al portal cautivo
iptables -t nat -A PREROUTING -i $LOCAL_IFACE -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A PREROUTING -i $LOCAL_IFACE -p tcp --dport 443 -j REDIRECT --to-port 8080

echo "Portal cautivo configurado"
echo "- Dispositivos en $LOCAL_IFACE redirigidos al portal"
echo "- Puerto 8080 accesible para el portal web"