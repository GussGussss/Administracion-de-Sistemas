instalar_kea(){
	echo ""
	echo "Verificando si el servicio DHCP (KEA) está instalado..."

	if rpm -q kea &>/dev/null; then
		echo "El servicio DHCP ya está instalado."

		while true; do
			read -p "¿Desea reinstalarlo? (s/n): " opcion

			case $opcion in
				s|S)
					echo "Reinstalando KEA..."
					sudo dnf reinstall -y kea > /dev/null 2>&1
					echo "Reinstalación completada."
					break
					;;
				n|N)
					echo "No se realizará ninguna acción."
					break
					;;
				*)
					echo "Opción inválida. Escriba s o n."
					;;
			esac
		done

	else
		echo "El servicio DHCP no está instalado."
		echo "Instalando KEA..."
		sudo dnf install -y kea > /dev/null 2>&1

		if rpm -q kea &>/dev/null; then
			echo "Instalación completada correctamente."
		else
			echo "Hubo un error en la instalación."
		fi
	fi

	read -p "Presiona ENTER para continuar..."
}

configurar_parametros(){
	echo "**** CONFIGURACION DEL DHCP ******"
	read -p "Nombre del ambito: " ambito

	while true; do
		segmento=$(pedir_ip "Ingrese el segmento de Red (ej: 192.168.0.0) " si)
		break
	done

while true; do
	rangoInicial=$(pedir_ip "Ingrese el rango inicial de la IP (ej: 192.168.0.100) ")
	rangoFinal=$(pedir_ip "Ingrese el rango final de la IP (ej: 192.168.0.150) ")

	if (( $(ip_entero "$rangoInicial") >= $(ip_entero "$rangoFinal" ) )); then
		echo "Esta mal: El rango inicial debe ser menor al rango final o no deben de ser iguales"
		continue
	fi

	read -p "Ingrese el prefijo manual (opcional, ej: 24): " prefijo_manual

	if [[ -n "$prefijo_manual" ]]; then
	    prefijo=$prefijo_manual
	    echo "Prefijo manual usado: /$prefijo"
	else
	    prefijo=$(calcular_prefijo_desde_rango "$rangoInicial" "$rangoFinal")
	    echo "Prefijo calculado automaticamente: /$prefijo"
	fi


	segmento_temp=$(calcular_red "$rangoInicial" "$prefijo")
	broadcast_temp=$(calcular_broadcast "$segmento_temp" "$prefijo")
	
	if [[ -n "$segmento" && "$segmento" != "$segmento_temp" ]]; then
	    echo "El segmento ingresado no coincide con el segmento calculado ($segmento_temp)"
	    echo "Se usará el segmento calculado."
	fi

	if [[ "$rangoInicial" == "$segmento_temp" ]]; then
	    echo "Esta mal: El rango inicial no puede ser la direccion de red ($segmento_temp)"
	    continue
	fi
	if [[ "$rangoFinal" == "$broadcast_temp" ]]; then
	    echo "Esta mal: El rango final no puede ser la direccion broadcast ($broadcast_temp)"
	    continue
	fi
	
	break
done
	segmento="$segmento_temp"
	broadcast="$broadcast_temp"
	
	ini_entero=$(ip_entero "$rangoInicial")
	seg_entero=$(ip_entero "$segmento")
	
	if (( ini_entero < seg_entero )); then
	    echo "El rango no está alineado correctamente a la red calculada"
	    return
	fi
	fin_entero=$(ip_entero "$rangoFinal")
	broadcast_entero=$(ip_entero "$broadcast")
	
	if (( fin_entero > broadcast_entero )); then
	    echo "El rango excede el tamaño de la red calculada"
	    return
	fi

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

	if [[ -n "$gateway" ]] && ! misma_red "$gateway" "$segmento" "$prefijo"; then
		echo "Esta mal: La puerta de enlace no pertenece al segmento"
		return
	fi

	ipServidor="$rangoInicial"

	if [[ "$ipServidor" == "$segmento" ]]; then
	    echo "Error: No puedes usar la direccion de red ($segmento) como IP del servidor"
	    return
	fi
	
	ini_entero=$(ip_entero "$rangoInicial")
	nuevo_inicio_entero=$((ini_entero + 1))
	nuevoInicioPool=$(entero_ip $nuevo_inicio_entero)
	
	if [[ "$ipServidor" == "$broadcast" ]]; then
	    echo "Error: No puedes asignar la direccion broadcast al servidor"
	    return
	fi
	
	echo "Cambiando IPs..."
	sudo ip -4 addr flush dev enp0s8

	sudo ip addr add $ipServidor/$prefijo dev enp0s8
	sudo ip link set enp0s8 up
	sleep 2

	if [[ -z "$gateway" ]]; then
	    red_entero=$(ip_entero "$segmento")
	    broadcast_entero=$(ip_entero "$broadcast")
	    gateway_entero=$((broadcast_entero - 1))
	    gateway=$(entero_ip $gateway_entero)
	fi

	if [[ "$gateway" == "$broadcast" ]]; then
	    echo "Error: El gateway calculado es la direccion broadcast ($broadcast)"
	    return
	fi

	echo ""
	echo "**** datos ingresado ****"
	echo "segmento de red: $segmento"
	echo "Rango de IPs: $rangoInicial - $rangoFinal"
	echo "Gateway: $gateway"
	echo "DNS: $dns"
	echo ""
	
	generar_config_kea
	validar_config_kea
	reiniciar_kea

	echo "Servidor DHCP configurado"
	read -p "presion ENTER para volver al menu"

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
	"valid-lifetime": $leaseTime,

	"subnet4": [
		{
			"subnet": "$segmento/$prefijo",
			"id": 1,
			"pools": [
				{
					"pool": "$nuevoInicioPool - $rangoFinal"
				}
			],
			"option-data": [
				    {
				        "name": "routers",
				        "data": "$gateway"
				    }$( [[ -n "$dns" ]] && echo ',
				    {
				        "name": "domain-name-servers",
				        "data": "'"$dns"'"
				    }' )
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
