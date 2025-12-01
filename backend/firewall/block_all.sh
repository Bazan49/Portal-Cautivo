#!/bin/bash

#Configura el portal cautivo para dispositivos conectados a la WiFi   
INTERNET_IFACE=$1
LOCAL_IFACE=$2
HTTP_REDIRECT_PORT=$3

# Limpiar reglas existentes
iptables -t nat -F

# Políticas por defecto: bloquear todo forwarding
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

#Permitir resolver DNS
iptables -A FORWARD -i "$LOCAL_IFACE" -o "$INTERNET_IFACE" -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i "$LOCAL_IFACE" -o "$INTERNET_IFACE" -p tcp --dport 53 -j ACCEPT

# Permitir tráfico local
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# iptables -A FORWARD -i wlo1_ap -o wlo1 -j ACCEPT
# iptables -A FORWARD -i wlo1 -o wlo1_ap -m state --state RELATED,ESTABLISHED -j ACCEPT

# NAT - permite que dispositivos compartan tu internet (después de autenticar)
iptables -t nat -A POSTROUTING -o $INTERNET_IFACE -j MASQUERADE

# PERMITIR acceso al servidor web del portal (puerto 8080)
iptables -A FORWARD -i $LOCAL_IFACE -p tcp --dport 8080 -j ACCEPT

#Hacer redireccionamiento
# iptables -t nat -A PREROUTING -i "$LOCAL_IFACE" -p tcp --dport 80 -j REDIRECT --to-port "$HTTP_REDIRECT_PORT"
# iptables -t nat -A PREROUTING -i "$LOCAL_IFACE" -p tcp --dport 443 -j REDIRECT --to-port "$HTTP_REDIRECT_PORT"

echo "Portal cautivo configurado"
echo "- Puerto 8080 accesible para el portal web"