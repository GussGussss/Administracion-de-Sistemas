#!/bin/bash
echo "********* AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP ***********"
nombre=$(hostname)
ipActual=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo "Nombre del equipo: $nombre"
echo "IP actua; $ipActual"

echo "Verificando si se encuentra el servicio dhcp...."

if ! rpm -q kea &> /dev/null; then
	echo "El servicio DHCP(KEA) no se encuentra... Se intalara automaticamente..."
	sudo dnf install -y kea /dev/null 2>&1
	echo "La instalacion se ha completado"
else
	echo "El servicio DHCP(KEA) ya esta instalado en el sistema"
fi
