write-host "****** AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP *****"
$hostname = hostname
$ipActual = (get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*Loopback*" } | select-object -first 1).ipaddress
write-host "Host: $hostname"
write-host "IP: $ipActual"

function validar-ip{
	param ([string]$IP)

    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$'){
        return $false
    }

    $octetos = $IP.Split('.')
    foreach ($o in $octetos){
        if ([int]$o -lt 0 -or [int]$o -gt 255){
            return $false
        }
    }

    if ($IP -eq "0.0.0.0" -or
        $IP -eq "255.255.255.255" -or
        $IP -eq "127.0.0.1"){
        return $false
    }

    return $true
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

function instalar-dhcp{
	$dhcp = get-windowsfeature DHCP
	if (-not $dhcp.installed){
		write-host "Instalando servicio DHCP"
		install-windowsfeature DHCP -includemanagementtools
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

	$segmentoServidor = (($ipActual -split '\.')[0..2] -join '.') + ".0"
	
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

	$scopeExiste=get-dhcpserverv4scope -erroraction SilentlyContinue | where-object {$_.subnetaddres -eq $segmento}	
	
	if($scopeExiste) {
		write-host "El scope (ambito) ya existe, no se volver a crear"
	}else{
		add-dhcpserverv4scope -Name $ambito -StartRange $rangoInicial -EndRange $rangoFinal -SubNetmask $mask -State Active
	}

	set-dhcpserverv4optionvalue -Router $gateway
	try{
		set-dhcpserverv4optionvalue -DnsServer $dns
	}catch{
		write-host "Esta mal: El DNS no es el correcto :c"
	}
}

function estado-dhcp{
	$servicio = get-service dhcpserver
	if ($servicio.status -eq "Running"){
		write-host "Servicio DHCP activo"
	}else{
		write-host "Servicio DHCP no activo"
	}	
} 

function mostrar-leases{
	$scope=get-dhcpserverv4scope | select-object -first 1
	if (-not $scope){
		write-host "no hay scopes configurados"
		return
	}
	
	$leases = get-dhcpserverv4lease -scopeid $scope.scopeid
	if ($leases) {
		$leases | format-table ipaddress, clientid, hostname -autosize
	}else{
		write-host "No hay concesiones registradas"
	}
}

do {
	write-host ""
	write-host "1) Configurar DHCP"
	write-host "2) Ver el estado del DHPC"
	write-host "3) Ver concesiones"
	write-host "4) Salir"
	$opcion = read-host "Elije una opcion: "

	switch ($opcion){
		"1" {configurar-dhcp}
		"2" {estado-dhcp}
		"3" {mostrar-leases}
		"4" {break}
		default {write-host "Opcion no valida :p"}
	}
}while($true)
