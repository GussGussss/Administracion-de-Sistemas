write-host "****** AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP *****
$hostname = hostname
$ipActual = (get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*Loopback*" } | select-object -first 1).ipaddress
write-host "Host: $hostname"
write-host "IP: $ipActual"

function validar-ip{
	param ([string]$IP)
	return $IP -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

function pedir-ip{
	param([string]$mensaje)
	do {
		$ip = read-host $mensaje
		if (-not (validar-ip $ip)) {
			write-host "Esta mal: la IP es invalida"
		}
	}while (-not (validar-ip $ip))
	return $ip
}

function intalar-dhcp{
	$dhcp = get-windowsfeature DHCP
	if (-not $dhcp.installed){
		write-host "Instalando servicio DHCP"
		install-windowsfeature DHCP-include-managementools
	}else{
		write-host "El servicio DHCP ya esta instalado :p"
	}
}

function configurar-dhcp{
	instalar-dhcp
	write-host "***** CONFIGURACION DEL DHCP ******"
	$ambito = read-host "Nombre del ambito: "
	$segmento = pedir-ip "Ingrese el segmento de red (ej: 192.168.0.0): "
	$prefijo = read-host "Prefijo (ej: 24): "
	$rangoInicial = pedir-ip "Ingrese el rango inicial de la IP (ej: 192.168.0.100): "
	$rangoFinal = pedir-ip "Ingrese el rango final de la IP (ej: 192.168.0.150): "
	$gateway = pedir-ip "Ingrese el gateway (ej: 192.168.0.1): "
	$dns = pedir-ip "Ingrese el DNS (ej: 192.168.0.71): "

	write-host ""
	write-host "**** Datos ingresados ****"
	write-host "Segmento de red: $segmento"
	write-host "Rango: $rangoInicial - $rangoFinal"
	write-host "Gateway: $gateway"
	write-host "DNS: $dns"

	$segmentoServidor = (($ipActual -split '\.') [0..2] -join '.') + ".0"
	
	if ($segmento -ne $segmentoServidor) {
		write-host "Esta mal: el segmento debe coincidir con el segmentod el servidor"
		write-host "IP del servidor: $ipActual"
		write-host "Segmento ingresado: $segmento"
		exit 1
	}
	
	$mask = switch ($prefijo){
	24 {"255.255.255.0"}
	16 {"255.255.0.0"}
	default {"255.255.255.0"}
	}

	add-dhcpserverv4scope '
		-Name $ambito '
		-StartRange $rangoInicial '
		-EndRange $rangoFinal '
		-SubNetmask $mask '
		-State Active
	
	set-dhcpserverv4optionvalue '
		-Router $gateway
		-DnsServer $dns

	write-host "Servidor DHCP configurado aca chilo :p"
}

function estado-dhcp{
	$servicio = get-service dhcpserver
	if ($servicio.status -eq "Running"){
		write-host "Servicio DHCP activo"
	}else{
		write-host "Servicio DHCP no activo"
	}	
}

