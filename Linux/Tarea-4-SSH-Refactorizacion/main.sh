#!/bin/bash
source ./lib/network.sh
source ./modulos/dhcp.sh
source ./modulos/dns.sh
source ./modulos/ssh.sh
ipActual=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
export ipActual

echo "Pruebas"
if validar_ip "192.168.0.1"; then
	echo "IP valida"
else
	echo "IP invalida"
fi

red=$(calcular_red "192.168.0.10" 24)
echo "red calculada: $red"
