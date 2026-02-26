#!/bin/bash
source ./lib/network.sh

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
        rangoInicial=$(pedir_ip "Ingrese el rango inicial de la IP (ej: 10.10.10.0) ")
        rangoFinal=$(pedir_ip "Ingrese el rango final de la IP (ej: 10.10.10.10) ")

        if (( $(ip_entero "$rangoInicial") >= $(ip_entero "$rangoFinal" ) )); then
            echo "Esta mal: El rango inicial debe ser menor al rango final"
            continue
        fi

        read -p "Ingrese el prefijo manual (opcional, ej: 24): " prefijo_manual
        if [[ -n "$prefijo_manual" ]]; then
            prefijo=$prefijo_manual
        else
            prefijo=$(calcular_prefijo_desde_rango "$rangoInicial" "$rangoFinal")
            echo "Prefijo calculado automaticamente: /$prefijo"
        fi

        segmento_temp=$(calcular_red "$rangoInicial" "$prefijo")
        broadcast_temp=$(calcular_broadcast "$segmento_temp" "$prefijo")
        
        if [[ -z "$segmento" ]]; then segmento="$segmento_temp"; fi
        broadcast="$broadcast_temp"
        break
    done

    while true; do
        read -p "Ingrese el tiempo (ej: 600) " leaseTime
        if [[ "$leaseTime" =~ ^[0-9]+$ ]] && (( leaseTime > 0 )); then break; else echo "Invalido"; fi
    done

    gateway=$(pedir_ip "Ingrese la puerta de enlace (opcional) " si)
    dns=$(pedir_ip "Ingrese el DNS (opcional) " si)

    ipServidor="$rangoInicial"
    nuevoInicioPool="$rangoInicial" 


    echo "Cambiando IPs con nmcli..."
    CONN="enp0s8"
    
    sudo nmcli connection modify $CONN ipv4.method manual
    sudo nmcli connection modify $CONN ipv4.addresses "$ipServidor/$prefijo"
    sudo nmcli connection modify $CONN ipv4.gateway ""
    sudo nmcli connection modify $CONN ipv4.dns "$ipServidor"
    sudo nmcli connection modify $CONN ipv4.ignore-auto-dns yes
    sudo nmcli connection up $CONN
    sleep 2
    
    ipActual=$ipServidor
    export ipActual

    if [[ -z "$gateway" ]]; then
        gateway_entero=$(( $(ip_entero "$broadcast") - 1 ))
        gateway=$(entero_ip $gateway_entero)
    fi

    generar_config_kea
    validar_config_kea
    reiniciar_kea

    echo "Servidor DHCP configurado exitosamente con IP $ipServidor"
    read -p "Presiona ENTER para volver al menu"
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

configurar_dns_local(){
    echo "Configurando servidor para usar su propio DNS..."

    sudo nmcli connection modify enp0s8 ipv4.dns "$ipServidor"
    sudo nmcli connection modify enp0s8 ipv4.ignore-auto-dns yes

    sudo nmcli connection up enp0s8 > /dev/null 2>&1

    echo "DNS local configurado en $ipServidor"
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

mexicanada(){
	echo "****** Leases activos ******"
	sudo cat /var/lib/kea/kea-leases4.csv
}
