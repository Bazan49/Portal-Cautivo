#!/bin/bash

IP_USUARIO=$1
# MAC_USUARIO=$2 

if [ -z "$IP_USUARIO" ]; then
    echo "Error: Se necesita la IP del usuario"
    exit 1
fi

# if [ -n "$MAC_USUARIO" ]; then
#     iptables -I FORWARD -s $IP_USUARIO -m mac --mac-source $MAC_USUARIO -j DROP
#     iptables -I FORWARD -d $IP_USUARIO -m mac --mac-source $MAC_USUARIO -j DROP
#     echo "✅ Usuario $IP_USUARIO ($MAC_USUARIO) desbloqueado con protección MAC"
# else
    # Modo básico: solo por IP 
    iptables -I FORWARD -s $IP_USUARIO -j DROP
    iptables -I FORWARD -d $IP_USUARIO -j DROP
    echo "✅ Usuario $IP_USUARIO desbloqueado (sin protección MAC)"
# fi
