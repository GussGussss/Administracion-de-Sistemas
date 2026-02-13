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

	$ip = ($ip.Split('.') | ForEach-Object { [int]$_ }) -join '.'

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

function calcular-red {
    param($ip, $prefijo)

    $ipInt = ip-a-entero $ip
    $mascara = [uint32]([math]::Pow(2,32) - [math]::Pow(2,(32 - [int]$prefijo)))
    $redInt = $ipInt -band $mascara

    return entero-a-ip $redInt
}

function calcular-broadcast {
    param($red, $prefijo)

    $redInt = ip-a-entero $red
    $mascara = [uint32]([math]::Pow(2,32) - [math]::Pow(2,(32 - [int]$prefijo)))
    $broadcastInt = $redInt -bor (-bnot $mascara)

    return entero-a-ip $broadcastInt
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

function cambiar-ip-servidor{
    param(
        [string]$NuevaIP,
        [string]$Prefijo
    )

    write-host ""
    write-host "Cambiando IP del servidor a $NuevaIP..."

    $adaptador = Get-NetAdapter -Name "Ethernet 2"

    Get-NetIPAddress -InterfaceIndex $adaptador.ifIndex -AddressFamily IPv4 |
        Remove-NetIPAddress -Confirm:$false

    New-NetIPAddress -InterfaceIndex $adaptador.ifIndex -IPAddress $NuevaIP -PrefixLength $Prefijo

    write-host "Nueva IP asignada correctamente."
}

function configurar-dhcp{
	instalar-dhcp
	write-host "***** CONFIGURACION DEL DHCP ******"
	$ambito = read-host "Nombre del ambito: "

	$segmento = pedir-ip "Ingrese el segmento de red (ej: 192.168.0.0)" $true

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

			$cantidad = ($fin - $ini) + 1
			$bits = [math]::Ceiling([math]::Log($cantidad,2))
			if ($bits -lt 1){ $bits = 1 }
			$prefijo = 32 - $bits
			Write-Host "Prefijo: /$prefijo"
			
			$broadcastTemp = calcular-broadcast (calcular-red $rangoInicial $prefijo) $prefijo
			
			if ($rangoFinal -eq $broadcastTemp) {
			    Write-Host "No puedes usar la direccion broadcast"
			    $valido = $false
			    continue
			}

			$segmentoCalculado = calcular-red $rangoInicial $prefijo
			
			if (-not [string]::IsNullOrWhiteSpace($segmento)) {
			    if ($segmento -ne $segmentoCalculado) {
			        Write-Host "El rango no pertenece al segmento"
			        $valido = $false
			        continue
			    }
			}
			else {
			    $segmento = $segmentoCalculado
			}

	    $valido = $true
	
	}while(-not $valido)

	$segmento = calcular-red $rangoInicial $prefijo
	$broadcast = calcular-broadcast $segmento $prefijo

	$broadcastNumero = ip-a-entero $broadcast

	if ($fin -gt $broadcastNumero){
	    Write-Host "El rango excede el tamaño de la red calculada"
	    return
	}


	Write-Host "Segmento calculado: $segmento"
	Write-Host "Broadcast calculado: $broadcast"

	$ipServidor = $rangoInicial
	
	$iniNumero = ip-a-entero $rangoInicial
	$nuevoInicioNumero = $iniNumero + 1
	$nuevoInicioPool = entero-a-ip $nuevoInicioNumero

    	$gateway = pedir-ip "Ingrese el gateway (opcional)" $true
    	$dns     = pedir-ip "Ingrese el DNS (opcional)" $true

    	if ([string]::IsNullOrWhiteSpace($dns)){
        	$dns = $rangoInicial
    	}
		
		Restart-Service dhcpserver -Force
		Start-Sleep -Seconds 3

		if ([string]::IsNullOrWhiteSpace($gateway)){
		    $broadcastNumero = ip-a-entero $broadcast
		    $gatewayNumero = $broadcastNumero - 1
		
		    if ($gatewayNumero -le $iniNumero -or $gatewayNumero -gt $fin){
		        $gatewayNumero = $iniNumero + 1
		    }
		
		    $gateway = entero-a-ip $gatewayNumero
		}
	
	do{
		$lease = read-host "Ingresa el tiempo (en minutos) "
		if( -not ($lease -match '^[0-9]+$') -or [int] $lease -le 0 ){
			write-host "No debe de de ser 0 :D"
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
	
	$maskNumero = [uint32]([math]::Pow(2,32) - [math]::Pow(2,(32 - [int]$prefijo)))
	$mask = entero-a-ip $maskNumero

	$scopeExiste=get-dhcpserverv4scope -erroraction SilentlyContinue | where-object {$_.subnetaddress -eq $segmento}	
	
	if($scopeExiste) {
		write-host "El scope (ambito) ya existe, no se volver a crear"
	}else{
		add-dhcpserverv4scope -Name $ambito -StartRange $nuevoInicioPool -EndRange $rangoFinal -SubNetmask $mask -leaseduration (new-timespan -minutes $lease) -State Active
	}

	$scopeIP = [System.Net.IPAddress]::Parse($segmento)

	set-dhcpserverv4optionvalue -scopeid $scopeIP -Router $gateway -Force
	
	set-dhcpserverv4optionvalue -scopeid $scopeIP -DnsServer $dns -Force

	cambiar-ip-servidor -NuevaIP $ipServidor -Prefijo $prefijo
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

    $scopes = Get-DhcpServerv4Scope

    write-host "******* Concesiones ******"

    if (-not $scopes){
        Write-Host "No hay scopes configurados"
        return
    }

    foreach ($scope in $scopes){
        write-host ""
        write-host "Scope: $($scope.ScopeId)"
        Get-DhcpServerv4Lease -ScopeId $scope.ScopeId
    }

    read-host "presione ENTER para continuar"
}

function eliminar-scope{
	$scopes = get-dhcpserverv4scope

	if (-not $scopes){
		write-host "no hay scopes configurados"
		return
	}

	write-host ""
	write-host "Scopes que hay: "
	$scopes | Format-Table ScopeId, Name, StartRange, EndRange -AutoSize
	write-host ""
			
	$scopeid = read-host "ingrese el scopeid que desea eliminar (ej: 192.168.0.0)"
	
	if  ($scopes.scopeid -contains $scopeid){
		remove-dhcpserverv4scope -scopeid $scopeid -force
		write-host "scope eliminado"
	}
	else{
		write-host "scope no encontrado"
	}

	read-host "presione ENTER para continuar"
}
do {
	write-host ""
	write-host "1) Instalar servicio DHPC"
	write-host "2) Configurar DHCP"
	write-host "3) Ver el estado del DHPC"
	write-host "4) Monitor (Ver concesiones)"
	write-host "5) Eliminar scopes"
	write-host "6) Salir"
	$opcion = read-host "Elije una opcion: "

	switch ($opcion){
		"1" {instalar-dhcp}
		"2" {configurar-dhcp}
		"3" {estado-dhcp}
		"4" {mostrar-leases}
		"5" {eliminar-scope}
		"6" {break}
		default {write-host "Opcion no valida :p"}
	}
}while($true)
