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
			
			if ($prefijo -ne 31 -and $rangoFinal -eq $broadcastTemp) {
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

	if ($prefijo -ne 31 -and $fin -gt $broadcastNumero){
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

	Restart-Service DNS
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
