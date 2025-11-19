#!/bin/bash
#Desbloquea una IP específica

IP_USUARIO=$1

if [ -z "$IP_USUARIO" ]; then
    echo "Error: Se necesita la IP del usuario"
    exit 1
fi

# Permitir tráfico completo para esta IP
iptables -I FORWARD -s $IP_USUARIO -j ACCEPT #Permite tráfico SALIENTE del dispositivo
iptables -I FORWARD -d $IP_USUARIO -j ACCEPT #Permite tráfico ENTRANTE al dispositivo

echo "✅ Usuario $IP_USUARIO desbloqueado - Tiene internet completo"
