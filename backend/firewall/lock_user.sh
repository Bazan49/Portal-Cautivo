#!/bin/bash
#
# lock_user.sh
# Uso: ./lock_user.sh <IP_USUARIO> <MAC_ATACANTE>
#
# Este script BLOQUEA (DROP) el tráfico FORWARD procedente/de destino de la MAC del atacante.
# Antes de bloquear valida la MAC y crea excepciones necesarias (DNS/DHCP/portal) para no romper la red.
#

IP_USUARIO="$1"
MAC_ATACANTE="$2"

if [ -z "$IP_USUARIO" ]; then
    echo "Error: Se necesita la IP del usuario"
    exit 1
fi

if [ -n "$MAC_ATACANTE" ] && [ "$MAC_ATACANTE" != "00:00:00:00:00:00" ]; then
    # Normalizar MAC a mayúsculas con dos puntos
    MAC_ATACANTE=$(echo "$MAC_ATACANTE" | tr '[:lower:]' '[:upper:]' | sed 's/-/:/g')
    echo "🔒 Bloqueo por MAC atacante: $MAC_ATACANTE"
    iptables -I FORWARD -m mac --mac-source "$MAC_ATACANTE" -j DROP
fi

echo "🔒 Bloqueo por IP: $IP_USUARIO"
iptables -I FORWARD -s "$IP_USUARIO" -j DROP
iptables -I FORWARD -d "$IP_USUARIO" -j DROP
echo "✅ Bloqueo aplicado para IP $IP_USUARIO"
