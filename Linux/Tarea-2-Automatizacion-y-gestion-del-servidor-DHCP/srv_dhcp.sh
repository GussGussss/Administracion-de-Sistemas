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
	
	while true; do
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
	instalar_kea
	echo "**** CONFIGURACION DEL DHCP ******"
	read -p "Nombre del ambito: " ambito
	
	segmento=$(pedir_ip "Ingrese el segmento de Red (ej: 192.168.0.0): ")
	read -p "Prefijo (ej: 24): " prefijo
	rangoInicial=$(pedir_ip "Ingrese el rango inicial de la IP (ej: 192.168.0.100): ")
	rangoFinal=$(pedir_ip "Ingrese el rango final de la IP (ej: 192.168.0.150): ")
	gateway=$(pedir_ip "Ingrese la puerta de enlace 'gateway' (ej: 192.168.0.1): ")
	dns=$(pedir_ip "Ingrese el DNS (ej: 192.168.0.70): ")
	echo ""

	echo "**** datos ingresado ****"
	echo "segmento de red: $segmento"
	echo "Rango de IPs: $rangoInicial - $rangoFinal"
	echo "Gateway: $gateway"
	echo "DNS: $dns"
	

	ip_servidor=$(ip -4 addr show enp0s8 | awk '/inet/ {print $2}' | cut -d/ -f1)

	if [[ $segmento != ${ip_servidor%.*}.0 ]]; then
		echo "Esta mal: el segmento que ingreso debe coincidir con la del servidor"
		echo "IP del servido: $ip_servidor"
		echo "Segmento ingresado: $segmento"
		exit 1
	fi

	generar_config_kea
	validar_config_kea
	reiniciar_kea

	echo "Servidor DHCP (KEA) configurado chilo (creo XD)"
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
		echo "Leases activos: "
		cat /var/lib/kea/kea-leases4.csv
	else
		echo "No hay concesiones registradas todavia."
	fi
}

instalar_kea(){
	echo "Verificando si se encuentra el servicio DHPC (KEA aqui xd)"
	
	if rpm -q kea &>/dev/null; then
		echo "El servicio DHCP (KEA) ya esta instalado :D"
	else
		echo "El servicio DHCP (KEA) no esta instalado, asi que lo vamos a instalar :D"
		sudo dnf install -y kea
		
		if rpm -q kea &>/dev/null; then
			echo "El servicio DHCP (KEA) se instalo correctamente :D"
		else
			echo "Esta mal: el servicio DHCP (KEA) no se pudo instalar :c"
		fi
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

menu(){
	echo ""
	echo "1) Configurar DHCP"
	echo "2) Ver estado del servicio DCHP (KEA)"
	echo "3) ver concesiones"
	echo "4) salir "
	read -p "Selecciones una opcion: " opcion
	
	case $opcion in
		1)configurar_parametros ;;
		2)estado_dhcp_kea ;;
		3)mostrar_leases ;;
		4)exit 0 ;;
		5)echo "opcion invalida" ;;
	esac

}

while true; do
	menu
done

