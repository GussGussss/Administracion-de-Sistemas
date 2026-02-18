write-host ""
write-host ""
#write-host "***** Automatizacion del Servidor DNS ******"
write-host ""

#$hostname=hostname
$ipActual=(get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*loopback*" } | select-object -first 1).ipaddress
#write-host "Host: $hostname"
#write-host "IP: $ipActual"
#write-host ""

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

function instalar-dns{
	write-host ""
	write-host ""
	write-host "**** Instalacion del Servicio DNS *****"
	$dns=get-windowsfeature DNS

	if(-not $dns.Installed){
		write-host "Instalando servicio DNS...."
		install-windowsfeature DNS -includemanagementtools
		write-host "La instalacion ha finalizado :D"
	}else{
		write-host "El servicio DNS ya esta instalado"
		do{
			$opcion=read-host "Quieres reinstalar? (s/n)"
			switch ($opcion.tolower()){
				"s" {
					write-host "Reinstalando servicio DNS...."
					uninstall-windowsfeature DNS
					install-windowsfeature DNS -includemanagementtools
					write-host "La reinstalacion ha finalizado :D"
				}
				"n" {
					write-host "No se hara nada :D"
					$valido=$true
				}
				default {
					write-host "Opcion invalida"
					$valido=$false
				}
			}

		} while (-not $valido)
	}

	verificar-puerto-dns
	Set-DnsServerSetting -ListenAddresses @("0.0.0.0")
	Restart-Service DNS
	
	write-host ""
	Write-Host ""
	Write-Host "Configurando firewall para permitir DNS..."
	
	if (-not (Get-NetFirewallRule -DisplayName "DNS Server (TCP-In)" -ErrorAction SilentlyContinue)) {
	    New-NetFirewallRule -DisplayName "DNS Server TCP 53" -Direction Inbound -Protocol TCP -LocalPort 53 -Action Allow
	}
	
	if (-not (Get-NetFirewallRule -DisplayName "DNS Server (UDP-In)" -ErrorAction SilentlyContinue)) {
	    New-NetFirewallRule -DisplayName "DNS Server UDP 53" -Direction Inbound -Protocol UDP -LocalPort 53 -Action Allow
	}
	
	Write-Host "Firewall configurado correctamente."
	
	read-host "presiona ENTER para continuar"
}

function verificar-puerto-dns {
    Write-Host ""
    Write-Host "Verificando puerto 53..."

    $puerto = Get-NetTCPConnection -LocalPort 53 -ErrorAction SilentlyContinue

    if ($puerto) {
        Write-Host "DNS esta escuchando en puerto 53."
    }
    else {
        Write-Host "ADVERTENCIA: DNS no esta escuchando en puerto 53."
    }
}

function estado-dns{
	resolve-dnsname reprobados.com -erroraction silentlycontinue
	write-host ""
	write-host ""
	write-host "***** Estado del servicio DNS *****"
	$servicio=get-service DNS

	
	if($servicio.status -eq "Running"){
		write-host "Servicio DNS activo :D"
	}else{
		write-host "Servicio DNS no activo"
	}
	read-host "presione ENTER para continuar"
}

function crear-dominio-principal{
	write-host ""
	write-host ""
	write-host "***** Creacion del dominio por default (reprobados.com)"

	$dominio="reprobados.com"
	$existe=get-dnsserverzone -name $dominio -erroraction silentlycontinue

	if($existe){
		write-host "La zona $dominio ya existe"
		read-host "presione ENTER para continuar"
		return	
	}

	$ipDominio=read-host "Ingrese la IP que tendra el Dominio (ej: 192.168.0.71) "
	if([string]::isnullorwhitespace($ipDominio)){
		$ipDominio = $ipActual
	}
	
	if(-not(validar-ip $ipDominio)){
		write-host "IP invalida"
		read-host "Presiona ENTER"
		return
	}
	write-host ""
	write-host "Creando zona..."
	add-dnsserverprimaryzone -name $dominio -zonefile "$dominio.dns"
	write-host ""
	write-host "Creando registro A..."
	add-dnsserverresourcerecorda -name "@" -zonename $dominio -ipv4address $ipDominio
	write-host ""
	write-host "Creando registro CNAME..."
	add-dnsserverresourcerecordcname -name "www" -zonename $dominio -hostnamealias $dominio
	write-host ""
	write-host "Dominio configurado correctamente"
	read-host "Presiona ENTER para continuar"
	Clear-DnsServerCache -Force
	Restart-Service DNS
}

function crear-dominio{
	write-host ""
	write-host ""
	write-host "***** Agregar nuevo dominio *****"

	$dominio=read-host "Ingresa el nombre del dominio (ej: pikachu.com) "

	if([string]::isnullorwhitespace($dominio)){
		write-host "El nombre del dominio no puede estar vacio"
		read-host "Presion ENTER para continuar"
		return
	}
	
	$existe=get-dnsserverzone -name $dominio -erroraction silentlycontinue
	if($existe){
		write-host "La zona '$dominio' ya existe :c"
		read-host "Presion ENTER para continuar"
		return
	}

	$ipDominio=read-host "Ingresa la IP del dominio "
	if(-not(validar-ip $ipDominio)){
		write-host "IP invalida"
		read-host "presiona ENTER para continuar"
		return
	}
	write-host ""
	write-host "Creando zona...."
	add-dnsserverprimaryzone -name $dominio -zonefile "$dominio.dns"
	write-host ""
	write-host "Creando registro A..."
	add-dnsserverresourcerecorda -name "@" -zonename $dominio -ipv4address $ipDominio
	write-host ""
	write-host "Creando registro www...."
	add-dnsserverresourcerecordcname -name "www" -zonename $dominio -hostnamealias $dominio
	write-host ""
	write-host "Dominio agregado correctamente :D"
	read-host "Presione ENTERE para continuar"
	Clear-DnsServerCache -Force
	Restart-Service DNS
}

function todos-los-dominios{
	write-host ""
	write-host "***** Lista de Dominios *****"

	$dominios=get-dnsserverzone

	if(-not $dominios){
		write-host "No hay dominios configurados"
	}else{
		$dominios | format-table zonename, zonetype -autosize	
	}
	read-host "Presione ENTER para continuar"
}

function eliminar-dominio{
	write-host ""
	write-host "***** Eliminar dominio *****"
	
	$dominio=read-host "Ingrese el nombre del domino que quiere eliminar "
	$existe=get-dnsserverzone -name $dominio -erroraction silentlycontinue
	if(-not $existe){
		write-host "El dominio no existe"
		read-host "Presiona ENTER para continuar"
		return
	}
	remove-dnsserverzone -name $dominio -force

	write-host "El dominio se ha eliminado :D"
	read-host "Presiona ENTER para continuar"
}

#write-host "****** AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP *****"
#$hostname = hostname
#$ipActual = (get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*Loopback*" } | select-object -first 1).ipaddress
#write-host "Host: $hostname"
#write-host "IP: $ipActual"

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

        Write-Host "Instalando servicio DHCP..."
        Install-WindowsFeature DHCP -IncludeManagementTools
        Write-Host "Instalacion completada."

    }
    else{

        Write-Host "El servicio DHCP ya esta instalado."

        do{
            $opcion = Read-Host "¿Desea reinstalarlo? (s/n)"

            switch ($opcion.ToLower()){

                "s"{
                    Write-Host "Reinstalando servicio DHCP..."

                    Uninstall-WindowsFeature DHCP
                    Install-WindowsFeature DHCP -IncludeManagementTools

                    Write-Host "Reinstalacion completada."
                    $valido = $true
                }

                "n"{
                    Write-Host "No se realizo ninguna accion."
                    $valido = $true
                }
                default{
                    Write-Host "Opcion invalida. Escriba s o n."
                    $valido = $false
                }
            }
        }while(-not $valido)
    }
	Write-Host ""
	Write-Host "Configurando firewall para DHCP..."
	
	New-NetFirewallRule -DisplayName "DHCP Server UDP 67" -Direction Inbound -Protocol UDP -LocalPort 67 -Action Allow -ErrorAction SilentlyContinue
	
	Write-Host "Firewall DHCP configurado."

    Read-Host "Presiona ENTER para continuar"
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

function calcular-prefijo-desde-rango {
    param(
        [string]$ipInicio,
        [string]$ipFin
    )

    $ini = ip-a-entero $ipInicio
    $fin = ip-a-entero $ipFin

    $xor = $ini -bxor $fin

    $bits = 0
    while ($xor -gt 0) {
        $xor = $xor -shr 1
        $bits++
    }

    return 32 - $bits
}

function configurar-dhcp{
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

			$prefijo = calcular-prefijo-desde-rango $rangoInicial $rangoFinal
			Write-Host "Prefijo calculado: /$prefijo"

			
			$broadcastTemp = calcular-broadcast (calcular-red $rangoInicial $prefijo) $prefijo
			
			if ($rangoFinal -eq $broadcastTemp) {
			    Write-Host "No puedes usar la direccion broadcast"
			    $valido = $false
			    continue
			}

			$segmentoCalculado = calcular-red $rangoInicial $prefijo

			$redInicio = calcular-red $rangoInicial $prefijo
			$redFinal  = calcular-red $rangoFinal   $prefijo
			
			if ($redInicio -ne $redFinal){
			    Write-Host "El rango inicial y final no pertenecen al mismo segmento."
			    $valido = $false
			    continue
			}
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
	
	$dnsInput = Read-Host "Ingrese el DNS (opcional.. Deja vacio para tomar como DNS la IP del servidor)"
	
	if ([string]::IsNullOrWhiteSpace($dnsInput)) {
	    $dns = $ipServidor
	}
	else {
	    $listaDns = $dnsInput.Split(",")
	
	    foreach ($d in $listaDns) {
	        $d = $d.Trim()
	        if (-not (validar-ip $d)) {
	            Write-Host "DNS invalido: $d"
	            return
	        }
	    }
	
	    $dns = ($listaDns | ForEach-Object { $_.Trim() })
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

	cambiar-ip-servidor -NuevaIP $ipServidor -Prefijo $prefijo
	set-dhcpserverv4optionvalue -scopeid $scopeIP -Router $gateway -Force
	set-dhcpserverv4optionvalue -scopeid $scopeIP -DnsServer $dns -Force

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

function menu-dhcp{
do {
	write-host ""
	write-host "***** MENU DHCP *****"
	write-host "1) Instalar servicio DHPC"
	write-host "2) Configurar DHCP"
	write-host "3) Ver el estado del DHPC"
	write-host "4) Monitor (Ver concesiones)"
	write-host "5) Eliminar scopes"
	write-host "6) Volver al menu principal"
	write-host "0) salir"
	$opcion = read-host "Elije una opcion: "

	switch ($opcion){
		"1" {instalar-dhcp}
		"2" {configurar-dhcp}
		"3" {estado-dhcp}
		"4" {mostrar-leases}
		"5" {eliminar-scope}
		"6" {menu-principal}
		"0" {break}
		default {write-host "Opcion no valida :p"; read-host "Presione ENTER para continuar"}
		}
	}while($true)

}
function menu-dns{
do{
	write-host ""
	write-host ""
	write-host "***** MENU DNS ****"
	write-host "1) Instalar Servicio DNS"
	write-host "2) Ver estaod del Servicio DNS"
	write-host "3) Crear dominio principal (reprobados.com)"
	write-host "4) Crear dominio"
	write-host "5) Consultar todos los dominios"
	write-host "6) Eliminar dominio"
	write-host "7) Volver al menu principal "
	write-host "0) salir"
	$opcion=read-host "Seleciona una opcion "
	
	switch($opcion){
		"1" {instalar-dns}
		"2" {estado-dns}
		"3" {crear-dominio-principal}
		"4" {crear-dominio}
		"5" {todos-los-dominios}
		"6" {eliminar-dominio}
		"7" {menu-principal}
		"0" {break}
		default {write-host "opcion no valida"; read-host "Presione ENTER para continuar"}
		}
	}while($true)
}

function menu-principal{
	do{
		write-host ""
		write-host "***** MENU PRINCIPAL *****"
		write-host "1) Ir a DHCP"
		write-host "2) Ir a DNS"
		write-host "3) Estados de los servicios DNS y DHCP"
		write-host "0) Salir"
		$opcion=read-host "Selecciona una opcion "
		
		switch($opcion){
			"1" {menu-dhcp}
			"2" {menu-dns}
			"3" {
				write-host ""
				write-host "**** Estados de los servicios DNS y DHCP *****"
				get-service DNS
				get-service DHCPServer
				read-host "Presione ENTER para continuar"
			}
			"0" {break}
			default {write-host "Opcion no valida"; read-host "Presione ENTER para continuar"}
		}
		
	}while($true)
}

	menu-principal
