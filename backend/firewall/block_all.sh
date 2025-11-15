#!/bin/bash
#Configura el portal cautivo para dispositivos conectados a la WiFi   

# Limpiar reglas existentes
iptables -F
iptables -t nat -F

# Políticas por defecto: bloquear todo
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP #bloque el trafico que pasa por la pc
iptables -P OUTPUT ACCEPT

# Permitir tráfico local
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

#Configurar NAT para que los dispositivos usen tu conexión
INTERNET_IFACE="eth0"       # Tu interfaz con internet (ej: eth0, wlan0)
LOCAL_IFACE="wlan1"         # Tu interfaz de WiFi hotspot (ej: wlan1)

# NAT - permite que dispositivos compartan tu internet
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE

# PERMITIR tráfico desde dispositivos locales (pero lo redirigiremos)
iptables -A FORWARD -i $LOCAL_IFACE -j ACCEPT
iptables -A FORWARD -o $LOCAL_IFACE -j ACCEPT

# PERMITIR tu servidor web para todos
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT

# REDIRIGIR tráfico web de dispositivos al portal cautivo
iptables -t nat -A PREROUTING -i $LOCAL_IFACE -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -t nat -A PREROUTING -i $LOCAL_IFACE -p tcp --dport 443 -j REDIRECT --to-port 8080

# PERMITIR DNS para dispositivos
iptables -A FORWARD -i $LOCAL_IFACE -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -o $LOCAL_IFACE -p udp --sport 53 -j ACCEPT

echo "Portal cautivo configurado"
echo "- Dispositivos en $LOCAL_IFACE redirigidos al portal"
