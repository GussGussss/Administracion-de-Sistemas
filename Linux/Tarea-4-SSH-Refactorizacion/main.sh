#!/bin/bash
ipActual=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
export ipActual
source ./lib/network.sh
source ./modulos/dhcp.sh
source ./modulos/dns.sh
source ./modulos/ssh.sh

mostrar_info() {
	echo ""
    echo "Hostname: $(hostname)"
    echo "IP: $ipActual"
    echo ""
}

menu_dhcp() {
    while true; do
	echo ""
	echo "****** Menu DHCP ******"
	echo "1) Instalar servicio DHCP"
	echo "2) Configurar DCHP (KEA)"
	echo "3) Ver el estado del servicio DHCP"
	echo "4) Monitoreo (Ver concesiones)"
	echo "5) Eliminar Scope"	
	echo "6) Volver al menu principal"
	echo "0) Salir"
	read -p "Selecciones una opcion: " opcion
	
	case $opcion in
		1)instalar_kea ;;
		2)configurar_parametros ;;
		3)estado_dhcp_kea ;;
		4)mexicanada ;;
		5)eliminar_scope ;;
		6)break ;;
		0)exit 0 ;;
		*)echo "opcion invalida" ;;
	esac
    done
}

menu_dns() {
    while true; do
	    echo ""
	    echo ""
	    echo "***** MENU DNS *****"
	    echo "1) Instalar servicio DNS"
	    echo "2) Ver estado del servicio DNS"
	    echo "3) Crear dominio principal (reprobados.com)"
	    echo "4) Crear dominio"
	    echo "5) Listar dominios"
	    echo "6) Eliminar dominio"
	    echo "7) Volver al menu principal"
	    echo "0) Salir"
	
	    read -p "Selecciona una opcion: " opcion
	
	    case $opcion in
	        1) instalar_dns ;;
	        2) estado_dns ;;
	        3) crear_dominio_principal ;;
	        4) crear_dominio ;;
	        5) listar_dominio ;;
	        6) eliminar_dominio ;;
	        7) break ;;
	        0) exit 0 ;;
	        *) echo "Opcion invalida"; sleep 1 ;;
	    esac
	done
}

menu_ssh() {
    while true; do
        echo ""
		echo ""
		echo "***** Menu SSH ****"
		echo "1) Instalar servicio SSH"
		echo "2) Estado del servicio DNS"
		echo "3) Volver al menu principal"
		echo "0) Salir"
		read -p "Selecciona un opcion: " opcion
		case $opcion in
			1)instalar_ssh ;;
		 	2)estado_ssh ;;
			3)break ;;
			0)exit 0 ;;
		 	*) echo "opcion invalida"; sleep 1;;
		esac
    done
}

menu_principal() {
    while true; do
        mostrar_info
        echo "***** Menu principal *****"
        echo "1) DHCP"
        echo "2) DNS"
        echo "3) SSH"
        echo "0) Salir"
        read -p "Seleccione opcion: " opcion

        case $opcion in
            1) menu_dhcp ;;
            2) menu_dns ;;
            3) menu_ssh ;;
            0) exit 0 ;;
            *) echo "Opcion invalida" ;;
        esac
    done
}

menu_principal
