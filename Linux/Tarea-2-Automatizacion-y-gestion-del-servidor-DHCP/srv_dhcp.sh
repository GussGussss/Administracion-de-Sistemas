#!/bin/bash
echo "***** AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP ******"
ipActual=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo "Hostname: $(hostname)"
echo "IP: $ipActual"

validar_ip(){
	local ip=$1
	local expresionRegular="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
	[[ $ip =~ $expresionRegular ]]
}

pedir_ip(){
	local mensaje=$1
	local ip
	
	while true;do
		read -p "$mensaje: " ip
		if validar_ip "$ip"; then
			echo "$ip"
			return
		else
			echo "Esta mal: La ip es invalida"
		fi
	done
}

configurar_parametros(){
	echo "**** CONFIGURACION DEL DHCP ******"
	read -p "Nombre del ambito: " ambito
	
	segmento=$(pedir_ip "Ingrese el segmento de Red (ej: 192.168.100.0): "
	rangoInicial=$(pedir_ip "Ingrese el rango inicial de la IP (ej: 192.168.100.50): "
	rangoFinal=$(pedir_ip "Ingrese el rango final de la IP (ej: 192.168.100.150): "
	gateway=$(pedir_ip "Ingrese la puerta de enlace 'gateway' (ej: 192.168.100.1): "
	dns=$(pedir_ip "Ingrese el DNS (ej: 192.168.0.70): "
	echo ""

	echo "**** datos ingresado ****"
	echo "segmento de red: $segmento"
	echo "Rango de IPs: $rangoInicial - $rangoFinal"
	echo "Gateway: $gateway"
	echo "DNS: $dns"
}
