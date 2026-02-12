#!/bin/bash
echo "***** AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP ******"
ipActual=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo "Hostname: $(hostname)"
echo "IP: $ipActual"

validar_ip(){
	local ip=$1
	local expresionRegular="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
	if ! [[ $ip =~ $expresionRegular ]]; then
		return 1
	fi

	IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
	for octeto in $o1 $o2 $o3 $o4; do
		if ((octeto < 0 || octeto > 255)); then
			return 1
		fi
	done

	if [[ "$ip" == "0.0.0.0" || "$ip" == "255.255.255.255" || "$ip" == "127.0.0.1" || "$ip" == "127.0.0.0" ]]; then
		return 1
	fi

	return 0
}

validar_ip_rango(){
	local ip=$1
	IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
	for octeto in $o1 $o2 $o3 $o4; do
		if ((octeto < 0 || octeto > 255)); then
			return 1
		fi
	done
	return 0

}

pedir_ip(){
	local mensaje=$1
	local vacio=$2
	local ip

	while true; do
		read -p "$mensaje: " ip
		if [[ -z "$ip" && "$vacio" == "si" ]]; then
			echo ""
			return
		fi

		if validar_ip "$ip"; then
			echo "$ip"
			return
		else
			echo "Esta mal: IP invalida"
		fi
	done
}

ip_entero(){
	local ip=$1
	IFS='.' read -r a b c d <<< "$ip"
	echo $((a<<24 | b<<16 | c<< 8 | d))
}

entero_ip(){
	local entero=$1
	echo "$(( (entero>>24)&255 )).$(( (entero>>16)&255 )).$(( (entero>>8)&255 )).$(( entero&255 ))"
}

instalar_kea(){
	echo ""
	echo "Viendo si el servicio DHCP ya esta instalado......"
	if rpm -q kea &>/dev/null; then
		echo "El servicio DHCP ya esta instalado :D"
	else
		echo "El servicio DHCP no esta instalado, lo instalaremos enseguida...."
		sudo dnf install -y kea > /dev/null 2>&1

		if rpm -q kea &>/dev/null; then
			echo "Instalacion completada"
		else
			echo "Hubo un error en la instalacion"
		fi
	fi

	read -p "Presiona ENTER para volver al continuar"
}

misma_red(){
	local ip=$1
	local red=$2
	[[ "${ip%.*}.0" == "$red" ]]
}

configurar_parametros(){
	instalar_kea
	echo "**** CONFIGURACION DEL DHCP ******"
	read -p "Nombre del ambito: " ambito

while true; do
	segmento=$(pedir_ip "Ingrese el segmento de Red (ej: 192.168.0.0) ")

	break
done
	read -p "Prefijo (ej: 24) " prefijo

while true; do
	rangoInicial=$(pedir_ip "Ingrese el rango inicial de la IP (ej: 192.168.0.100) ")
	rangoFinal=$(pedir_ip "Ingrese el rango final de la IP (ej: 192.168.0.150) ")

	if ! misma_red "$rangoInicial" "$segmento"; then
		echo "Esta mal: El rango de inicial no pertenece al segmento."
		continue
	fi

	if ! misma_red "$rangoFinal" "$segmento"; then
		echo "Esta mal: El rango final no pertenence al segmento"
		continue
	fi

	if (( $(ip_entero "$rangoInicial") >= $(ip_entero "$rangoFinal") )); then
		echo "Esta mal: El rango inicial debe ser menor al rango final"
		continue
	fi

	break
done
	while true; do
	    read -p "Ingrese el tiempo (ej: 600) " leaseTime
	    
	    if [[ "$leaseTime" =~ ^[0-9]+$ ]] && (( leaseTime > 0 )); then
	        break
	    else
	        echo "No debe de ser 0 o menor"
	    fi
	done
	gateway=$(pedir_ip "Ingrese la puerta de enlace (opcional) (ej: 192.168.0.1) " si)
	dns=$(pedir_ip "Ingrese el DNS (opcional) (ej: 192.168.0.70) " si)

	if [[ -n "$gateway" ]] && ! misma_red "$gateway" "$segmento"; then
		echo "Esta mal: La puerta de enlace no pertenece al segmento"
		return
	fi

	if [[ -n "$dns" ]] && ! misma_red "$dns" "$segmento"; then
		echo "El dns no pertenece al segmenteo"
		return
	fi

	if [[ -z "$dns" ]]; then
		dns="$rangoInicial"
	fi

	if [[ -z "$gateway" ]]; then
		final_entero=$(ip_entero "$rangoFinal")
		gateway_entero=$((final_entero + 1))
		gateway=$(entero_ip $gateway_entero)
	fi

	echo ""
	echo "**** datos ingresado ****"
	echo "segmento de red: $segmento"
	echo "Rango de IPs: $rangoInicial - $rangoFinal"
	echo "Gateway: $gateway"
	echo "DNS: $dns"
	echo ""


	if (( $(ip_entero "$rangoInicial") >= $(ip_entero "$rangoFinal") )); then
		echo "Esta mal: El rango inicial debe de ser menor al rango final"
		return
	fi

	ip_srv_entero=$(ip_entero "$ipActual")
	inicial_entero=$(ip_entero "$rangoInicial")
	final_entero=$(ip_entero "$rangoFinal")

	if (( ip_srv_entero >= inicial_entero && ip_srv_entero <= final_entero )); then
		echo "El rango incluye la IP del servidor ($ipActual)"
		return
	fi

	generar_config_kea
	validar_config_kea
	reiniciar_kea

	echo "Servidor DHCP configurado"
	read -p "presion ENTER para volver al menu"

}

estado_dhcp_kea(){
	echo ""
	echo "****** Estado del servicio DHCP (KEA aqui en oracle XD) **** "
	if systemctl is-active --quiet kea-dhcp4; then
		echo "Servicio DHCP (KEA) activo"
	else
		echo "Servicio DHCP (KEA) no activo"
	fi
}

mostrar_leases(){
	echo "Leases activos: "

	if [ -f /var/lib/kea/kea-leases4.csv ]; then
		lineas=$(wc -l < /var/lib/kea/kea-leases4.csv)

		if [ "$lineas" -gt 1 ]; then
			echo "Leases activos: "
			cat /var/lib/kea/kea-leases4.csv
		else
			echo "El archivo leases, si existe, pero no hay concesiones activas"
		fi
	else
		echo "El archivo leases todavia noha sido generado por KEA"
	fi
}

generar_config_kea(){
	CONFIG_FILE="/etc/kea/kea-dhcp4.conf"

	echo "Generando configuracion del KEA DHCP"

	sudo tee $CONFIG_FILE > /dev/null <<EOF
{
	"Dhcp4":{
		"interfaces-config":{
			"interfaces": [ "enp0s8" ]
	},
	"lease-database": {
		"type": "memfile",
		"persist": true,
		"name": "/var/lib/kea/kea-leases4.csv"
	},
	"valid-lifetime": 600,
	"max-valid-lifetime": 7200,

	"subnet4": [
		{
			"subnet": "$segmento/$prefijo",
			"id": 1,
			"pools": [
				{
					"pool": "$rangoInicial - $rangoFinal"
				}
			],
			"option-data": [
				{
					"name": "routers",
					"data": "$gateway"
				},
				{
					"name": "domain-name-servers",
					"data": "$dns"
				}
			]
		}
	]
}


}
EOF
}

validar_config_kea(){
	sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
}

reiniciar_kea(){
	sudo systemctl enable kea-dhcp4
	sudo systemctl restart kea-dhcp4
}

mexicanada(){
	echo "****** Leases activos ******"
	sudo cat /var/lib/kea/kea-leases4.csv
}

menu(){
	echo ""
	echo "1) Instalar servicio DHCP"
	echo "2) Configurar DCHP (KEA)"
	echo "3) Ver el estado del servicio DHCP"
	echo "4) Ver concesiones"
	echo "5) Salir"
	read -p "Selecciones una opcion: " opcion
	
	case $opcion in
		1)instalar_kea ;;
		2)configurar_parametros ;;
		3)estado_dhcp_kea ;;
		4)mexicanada ;;
		5)exit 0 ;;
		*)echo "opcion invalida" ;;
	esac

}

while true; do
	menu
done

