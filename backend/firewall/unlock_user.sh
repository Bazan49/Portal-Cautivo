#!/bin/bash
# Desbloquea una IP específica 

IP_USUARIO=$1

if [ -z "$IP_USUARIO" ]; then
    echo "Error: Se necesita la IP del usuario"
    exit 1
fi

# Permitir tráfico completo para esta IP
iptables -I FORWARD -s $IP_USUARIO -j ACCEPT 
iptables -I FORWARD -d $IP_USUARIO -j ACCEPT 

echo "✅ Usuario $IP_USUARIO desbloqueado - Tiene internet completo"
