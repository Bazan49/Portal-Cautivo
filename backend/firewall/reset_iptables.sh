#!/bin/bash
#Restaura iptables a valores normales

# Restaurar políticas por defecto (ACCEPT)
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Limpiar todas las reglas
iptables -F
iptables -t nat -F

echo "IPTables restablecido a configuración normal"