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
    param(
        [string]$mensaje,
        [bool]$opcional = $false
    )

    do{
        $ip = Read-Host $mensaje

        if ($opcional -and [string]::IsNullOrWhiteSpace($ip)){
            return ""
        }

        if (-not (validar-ip $ip)){
            Write-Host "Esta mal: IP invalida"
        }

    }while (-not (validar-ip $ip))

    return $ip
}

function ip-a-entero($ip){
    $octetos = $ip.Split('.')
    return ([int]$octetos[0] -shl 24) -bor
           ([int]$octetos[1] -shl 16) -bor
           ([int]$octetos[2] -shl 8)  -bor
           ([int]$octetos[3])
}

function entero-a-ip($numero){
    return "$(($numero -shr 24) -band 255)." +
           "$(($numero -shr 16) -band 255)." +
           "$(($numero -shr 8) -band 255)." +
           "$($numero -band 255)"
}

function instalar-dhcp{
    $dhcp = Get-WindowsFeature DHCP

    if (-not $dhcp.Installed){
        write-host "Instalando servicio DHCP..."
        Install-WindowsFeature DHCP -IncludeManagementTools
        write-host "Instalacion completada."
    }else{
        write-host "El servicio DHCP ya esta instalado."
    }

    read-host "Presiona ENTER para continuar"
}

function configurar-dhcp{
	instalar-dhcp
	write-host "***** CONFIGURACION DEL DHCP ******"
	$ambito = read-host "Nombre del ambito: "
	do{
	    $segmento = pedir-ip "Ingrese el segmento de red (ej: 192.168.0.0)"
	    $segmentoServidor = (($ipActual -split '\.')[0..2] -join '.') + ".0"
	
	    if ($segmento -ne $segmentoServidor){
	        write-host "El segmento debe coincidir con el del servidor ($segmentoServidor)"
	    }
	}while($segmento -ne $segmentoServidor)
	
	$prefijo = read-host "Prefijo (ej: 24): "
	do{
	    $rangoInicial = pedir-ip "Ingrese el rango inicial"
	    $rangoFinal   = pedir-ip "Ingrese el rango final"
	
	    $ini = ip-a-entero $rangoInicial
	    $fin = ip-a-entero $rangoFinal
	
	    if ($ini -ge $fin){
	        write-host "El rango inicial debe ser menor al rango final"
	        $valido = $false
	        continue
	    }
	
	    $segmentoBase = ($segmento -split '\.')[0..2] -join '.'
	
	    if (($rangoInicial -split '\.')[0..2] -join '.' -ne $segmentoBase -or
	        ($rangoFinal -split '\.')[0..2] -join '.' -ne $segmentoBase){
	        write-host "El rango no pertenece al segmento"
	        $valido = $false
	        continue
	    }
	
	    $valido = $true
	
	}while(-not $valido)

	$ipServidorNumero = ip-a-entero $ipActual
	
	if ($ipServidorNumero -ge $ini -and $ipServidorNumero -le $fin){
	    write-host "El rango incluye la IP del servidor"
	    return
	}
    	$gateway = pedir-ip "Ingrese el gateway (opcional)" $true
    	$dns     = pedir-ip "Ingrese el DNS (opcional)" $true

    	if ([string]::IsNullOrWhiteSpace($dns)){
        	$dns = $rangoInicial
    	}

    	if ([string]::IsNullOrWhiteSpace($gateway)){
        	$gatewayNumero = (ip-a-entero $rangoFinal) + 1
        	$gateway = entero-a-ip $gatewayNumero
    	}
	
	do{
		$lease = read-host "Ingresa el tiempo (en minutos) "
		if( -not ($lease -match '^[0-9]+$') -or [int] $lease -le 0 or ){
			write-host "Error: no debe de ser 0"
			$valido = $false
		}else{
			$valido = $true
		}
	}while(-not $valido)
	
    	write-host ""
    	write-host "Segmento: $segmento"
    	write-host "Rango: $rangoInicial - $rangoFinal"
    	write-host "Gateway: $gateway"
    	write-host "DNS: $dns"

	$segmentoServidor = (($ipActual -split '\.')[0..2] -join '.') + ".0"
	
	$mask = switch ($prefijo){
	24 {"255.255.255.0"}
	16 {"255.255.0.0"}
	default {"255.255.255.0"}
	}

	$scopeExiste=get-dhcpserverv4scope -erroraction SilentlyContinue | where-object {$_.subnetaddress -eq $segmento}	
	
	if($scopeExiste) {
		write-host "El scope (ambito) ya existe, no se volver a crear"
	}else{
		add-dhcpserverv4scope -Name $ambito -StartRange $rangoInicial -EndRange $rangoFinal -SubNetmask $mask leaseduration (new-timespan -minutes $lease)-State Active
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

    $scope = Get-DhcpServerv4Scope | Select-Object -First 1

    if (-not $scope){
        Write-Host "No hay scopes configurados"
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
	write-host "1) Instalar servicio DHPC"
	write-host "2) Configurar DHCP"
	write-host "3) Ver el estado del DHPC"
	write-host "4) Ver concesiones"
	write-host "5) Salir"
	$opcion = read-host "Elije una opcion: "

	switch ($opcion){
		"1" {instalar-dhcp}
		"2" {configurar-dhcp}
		"3" {estado-dhcp}
		"4" {mostrar-leases}
		"5" {break}
		default {write-host "Opcion no valida :p"}
	}
}while($true)
