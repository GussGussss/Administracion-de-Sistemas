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

calcular_prefijo_desde_rango(){
    local ipInicio=$1
    local ipFin=$2

    local ini=$(ip_entero "$ipInicio")
    local fin=$(ip_entero "$ipFin")

    local xor=$(( ini ^ fin ))
    local bits=0

    while (( xor > 0 )); do
        xor=$(( xor >> 1 ))
        ((bits++))
    done

    echo $((32 - bits))
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
    local prefijo=$3

    [[ "$(calcular_red "$ip" "$prefijo")" == "$red" ]]
}


calcular_red(){
    local ip=$1
    local prefijo=$2

    local ip_int=$(ip_entero "$ip")
    local mascara=$(( 0xFFFFFFFF << (32 - prefijo) & 0xFFFFFFFF ))
    local red_int=$(( ip_int & mascara ))

    entero_ip $red_int
}

calcular_broadcast(){
    local red=$1
    local prefijo=$2

    local red_int=$(ip_entero "$red")
    local mascara=$(( 0xFFFFFFFF << (32 - prefijo) & 0xFFFFFFFF ))
    local broadcast_int=$(( red_int | (~mascara & 0xFFFFFFFF) ))

    entero_ip $broadcast_int
}

configurar_parametros(){
	instalar_kea
	echo "**** CONFIGURACION DEL DHCP ******"
	read -p "Nombre del ambito: " ambito

while true; do
	segmento=$(pedir_ip "Ingrese el segmento de Red (ej: 192.168.0.0) " si)

	break
done

while true; do
	rangoInicial=$(pedir_ip "Ingrese el rango inicial de la IP (ej: 192.168.0.100) ")
	rangoFinal=$(pedir_ip "Ingrese el rango final de la IP (ej: 192.168.0.150) ")

	if [[ -n "$segmento" ]]; then
	    if ! misma_red "$rangoInicial" "$segmento" "$prefijo"; then
	        echo "Esta mal: El rango inicial no pertenece al segmento."
	        continue
	    fi
	
	    if ! misma_red "$rangoFinal" "$segmento" "$prefijo"; then
	        echo "Esta mal: El rango final no pertenece al segmento."
	        continue
	    fi
	fi

	if (( $(ip_entero "$rangoInicial") >= $(ip_entero "$rangoFinal" ) )); then
		echo "Esta mal: El rango inicial debe ser menor al rango final o no deben de ser iguales"
		continue
	fi

	prefijo=$(calcular_prefijo_desde_rango "$rangoInicial" "$rangoFinal")
	echo "Prefijo calculado: /$prefijo"

	segmento_temp=$(calcular_red "$rangoInicial" "$prefijo")
	broadcast_temp=$(calcular_broadcast "$segmento_temp" "$prefijo")
	
	if [[ "$rangoFinal" == "$broadcast_temp" ]]; then
	    echo "Esta mal: El rango final no puede ser broadcast"
	    continue
	fi

	if [[ "$rangoInicial" == "$segmento" ]]; then
	    echo "Esta mal: El rango inicial no puede ser la direccion de red ($segmento)"
	    continue
	fi
	if [[ "$rangoFinal" == "$broadcast" ]]; then
	    echo "Esta mal: El rango final no puede ser la direccion broadcast ($broadcast)"
	    continue
	fi
	
	break
done
	if [[ -z "$segmento" ]]; then
	    segmento=$(calcular_red "$rangoInicial" "$prefijo")
	fi
	
	broadcast=$(calcular_broadcast "$segmento" "$prefijo")
	
	if [[ "$rangoFinal" == "$broadcast" ]]; then
	    echo "Esta mal: El rango final no puede ser la direccion broadcast ($broadcast)"
	    return
	fi

	segmento=$(calcular_red "$rangoInicial" "$prefijo")
	broadcast=$(calcular_broadcast "$segmento" "$prefijo")
	
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
	
	echo "Cambiando IP del servidor a $ipServidor..."
	ipActual=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)

	if [[ -n "$ipActual" ]]; then
	    sudo ip addr del $ipActual/$prefijo dev enp0s8 2>/dev/null
	fi
	
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

mexicanada(){
	echo "****** Leases activos ******"
	sudo cat /var/lib/kea/kea-leases4.csv
}

eliminar_scope(){
    CONFIG_FILE="/etc/kea/kea-dhcp4.conf"

    echo ""
    echo "******** SCOPES CONFIGURADOS ********"

    subnets=$(sudo grep '"subnet":' $CONFIG_FILE | awk -F '"' '{print $4}')

    if [[ -z "$subnets" ]]; then
        echo "No hay scopes configurados."
        read -p "Presiona ENTER para continuar"
        return
    fi

    i=1
    declare -a lista_subnets
    for subnet in $subnets; do
        echo "$i) $subnet"
        lista_subnets[$i]=$subnet
        ((i++))
    done

    echo ""
    read -p "Selecciona el numero del scope a eliminar: " opcion

    if [[ -z "${lista_subnets[$opcion]}" ]]; then
        echo "Opcion invalida."
        read -p "Presiona ENTER para continuar"
        return
    fi

    subnetEliminar=${lista_subnets[$opcion]}
    echo "Eliminando scope $subnetEliminar..."

    sudo sed -i "/\"subnet\": \"$subnetEliminar\"/,/}/d" $CONFIG_FILE

    validar_config_kea
    reiniciar_kea

    echo "Scope eliminado correctamente."
    read -p "Presiona ENTER para continuar"
}

menu(){
	echo ""
	echo "1) Instalar servicio DHCP"
	echo "2) Configurar DCHP (KEA)"
	echo "3) Ver el estado del servicio DHCP"
	echo "4) Monitoreo (Ver concesiones)"
	echo "5) Eliminar Scope"	
	echo "6) Salir"
	read -p "Selecciones una opcion: " opcion
	
	case $opcion in
		1)instalar_kea ;;
		2)configurar_parametros ;;
		3)estado_dhcp_kea ;;
		4)mexicanada ;;
		5)eliminar_scope ;;
		6)exit 0 ;;
		*)echo "opcion invalida" ;;
	esac

}

while true; do
	menu
done

