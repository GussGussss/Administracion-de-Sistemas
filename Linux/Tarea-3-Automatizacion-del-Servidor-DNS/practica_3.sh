echo ""
echo ""
echo "***** AUTOMATIZACION DEL SERVIDOR DNS ******"
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

	local pref=$((32 - bits))
	
	if (( pref < 1 )); then
	    pref=1
	fi
	
	if (( pref > 29 )); then
	    pref=29
	fi
	
	echo $pref
}

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

	ipServidor="$rangoInicial"
	gateway=$(pedir_ip "Ingrese la puerta de enlace (opcional) (ej: 192.168.0.1) " si)
	dns=$(pedir_ip "Ingrese el DNS del dominio (ej: 192.168.0.70, si quiere usar el DNS del servidor deje vacio) " si)

	if [[ -z "$dns" ]]; then
		dns="$ipServidor"
	else
		IFS=',' read -ra lista_dns <<< "$dns"
		for d in "${lista_dns[@]}"; do
			if ! validar_ip "$d"; then
				echo "DNS invalido: $d"
				return
			fi
		done
	fi

	if [[ -n "$gateway" ]] && ! misma_red "$gateway" "$segmento" "$prefijo"; then
		echo "Esta mal: La puerta de enlace no pertenece al segmento"
		return
	fi

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

estado_servicios(){

    echo ""
    echo "**** Estados de los servicios DNS y DHCP ****"
    echo ""

    echo "DNS (BIND - named):"
    if systemctl is-active --quiet named; then
        echo "Estado: ACTIVO"
    else
        echo "Estado: INACTIVO"
    fi

    echo ""
    echo "DHCP (KEA - kea-dhcp4):"
    if systemctl is-active --quiet kea-dhcp4; then
        echo "Estado: ACTIVO"
    else
        echo "Estado: INACTIVO"
    fi

    echo ""
    read -p "Presiona ENTER para continuar"
}


instalar_dns(){
	echo ""
	echo "Verificando si DNS (BIND) esta instalado...."

	if rpm -q bind &>/dev/null; then
		echo "El servicio DNS (BIND) ya esta instalado"
	else
		echo "instalando DNS (BIND)...."
		sudo dnf install -y bind bind-utils
		echo "instalacion completada"
	fi

	sudo systemctl enable named
	sudo systemctl start named
	configurar_named_base

	echo ""
	echo "Configurando firewall para permitir DNS"
	sudo firewall-cmd --permanent --add-service=dns
	sudo firewall-cmd --reload
	read -p "presiona ENTER para continuar"
}

estado_dns(){
	echo ""
	echo "***** Estado del servicio DNS (BIND) *****"
	if systemctl is-active --quiet named; then
		echo "Servicio DNS (BIND) activo"
	else
		echo "Servicio DNS (BIND) no activo"
	fi
	read -p "Pesiona ENTER para continuar"
}

crear_dominio_principal(){
	dominio="reprobados.com"
	zona_file="/var/named/$dominio.db"

	if sudo grep -q "$dominio" /etc/named.rfc1912.zones; then
		echo "El dominio ya existe"
		read -p "Presione ENTERN para continuar"
		return
	fi

	read -p "Ingresa la IP del dominio (ej: 192.168.0.70 o presione ENTER para usar la IP del servidor) " ipDominio

	if [[ -z "$ipDominio" ]]; then
		ipDominio=$ipActual
	fi

	if ! validar_ip "$ipDominio"; then
		echo "IP invalida"
		read -p "Presione ENTER para continuar"
		return
	fi

	echo "Creando dominio...."
	sudo tee -a /etc/named.rfc1912.zones > /dev/null <<EOF

zone "$dominio" IN {
	type master;
	file "$dominio.db";
};
EOF
	echo "Creando archivo de zona...."
	sudo tee $zona_file > /dev/null <<EOF
\$TTL 86400
@	IN	SOA	ns1.$dominio. admin.$dominio. (
		2024021601
		3600
		1800
		604800
		86400 )

@	IN 	NS	ns1.$dominio.
ns1	IN	A	$ipActual
@	IN	A	$ipDominio
www	IN	CNAME	$dominio.
EOF

	sudo chown named:named $zona_file
	sudo chmod 640 $zona_file

	sudo named-checkconf
	sudo named-checkzone $dominio $zona_file
	sudo systemctl restart named
	echo "Dominio configurado correctamente"
	read -p "Presion ENTER para continuar"

}

crear_dominio(){
	echo ""
	echo "***** Agregar nuevo dominio *****"
	read -p "Ingresa el nombre del dominio (ej: pikachu.com) " dominio
	if [[ -z "$dominio" ]]; then
		echo "El nombre no puede estar vacio"
		read -p "Presione ENTER para continuar"
		return
	fi

	if sudo grep -q "zone \"$dominio\"" /etc/named.rfc1912.zones; then
		echo "EL dominio ya existe"
		read -p "Presione ENTER para continuar"
	fi

	read -p "Ingresa la IP del dominio (ej: 192.168.0.70 o presione ENTER para usar la IP del servidor) " ipDominio
	if [[ -z "$ipDominio" ]]; then
		ipDominio=$ipActual
	fi

	zona_file="/var/named/$dominio.db"
	sudo tee -a /etc/named.rfc1912.zones > /dev/null << EOF

zone "$dominio" IN {
    type master;
    file "$dominio.db";
};
EOF

    sudo tee $zona_file > /dev/null <<EOF
\$TTL 86400
@   IN  SOA     ns1.$dominio. admin.$dominio. (
        2024021601
        3600
        1800
        604800
        86400 )

@       IN  NS      ns1.$dominio.
ns1     IN  A       $ipActual
@       IN  A       $ipDominio
www     IN  CNAME   $dominio.
EOF
	sudo chown named:named $zona_file
	sudo chmod 640 $zona_file
	sudo named-checkconf
	sudo named-checkzone $dominio $zona_file
	sudo systemctl restart named
	echo "Dominio creado correctamente"
	read -p "presione ENTER para continuar"
}

listar_dominio(){
	echo ""
	echo "***** Lista de Dominios *****"
	sudo grep 'zone "' /etc/named.rfc1912.zones | awk -F '"' '{print $2}'
	read -p "Presione ENTER para continuar"
}

eliminar_dominio(){
	echo ""
	echo "***** Eliminar dominio ******"
	read -p "Ingresa el nombre del dominio a eliminar: " dominio
	if ! sudo grep -q "zone \"$dominio\"" /etc/named.rfc1912.zones; then
		echo "El dominio no existe"
		read -p "Presione ENTER para continuar"
		return
	fi
	zona_file="/var/named/$dominio.db"
	sudo sed -i "/zone \"$dominio\"/,/};/d" /etc/named.rfc1912.zones
	sudo rm -f $zona_file
	sudo named-checkconf
	sudo systemctl restart named
	echo "Dominio eliminado correctamente"
	read -p "Presiona ENTER para continuar"
}

configurar_named_base(){

    echo ""
    echo "***** Configuracion base profesional de BIND *****"

    CONF="/etc/named.conf"

    if [[ ! -f ${CONF}.backup ]]; then
        echo "Creando backup de named.conf..."
        sudo cp $CONF ${CONF}.backup
    fi

    if ! sudo grep -q "listen-on port 53 { any; };" $CONF; then
        echo "Configurando listen-on para todas las interfaces..."

        sudo sed -i '/listen-on port 53/c\        listen-on port 53 { any; };' $CONF
    else
        echo "listen-on ya esta correctamente configurado."
    fi

    if ! sudo grep -q "allow-query     { any; };" $CONF; then
        echo "Configurando allow-query para permitir consultas externas..."

        sudo sed -i '/allow-query/c\        allow-query     { any; };' $CONF
    else
        echo "allow-query ya esta correctamente configurado."
    fi
    if sudo named-checkconf; then
        echo "Configuracion valida."
        sudo systemctl restart named
        echo "Servicio DNS reiniciado correctamente."
    else
        echo "ERROR en la configuracion. Restaurando backup..."
        sudo cp ${CONF}.backup $CONF
        sudo systemctl restart named
    fi

    echo "Configuracion base finalizada."
}


menu_dns(){

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

menu_dhcp(){
while true; do
	echo ""
	echo ""
	echo "****** Menu DHCP *****"
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
		6)menu_principal ;;
		0)exit 0 ;;
		*)echo "opcion invalida" ;;
	esac
done
}

menu_principal(){

while true; do
    echo ""
    echo ""
    echo "***** Menu Principal *****"
    echo "1) DHCP"
    echo "2) DNS"
    echo "3) Estado de servicios (DNS y DHCP)"
    echo "0) Salir"

    read -p "Selecciona una opcion: " opcion

    case $opcion in
        1) menu_dhcp ;;
        2) menu_dns ;;
        3) estado_servicios ;;
        0) exit 0 ;;
        *) echo "Opcion invalida" ;;
    esac
done
}


menu_principal
