write-host "****** AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP *****"
$hostname = hostname
$ipActual = (get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*Loopback*" } | select-object -first 1).ipaddress
write-host "Host: $hostname"
write-host "IP: $ipActual"

function validar-ip {
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
        $IP -eq "127.0.0.1" -or
        $IP -eq "127.0.0.0"){
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

function priorizar-red-interna {
    $interno = Get-NetAdapter -Name "Ethernet 2" -ErrorAction SilentlyContinue
    if ($interno) { Set-NetIPInterface -InterfaceIndex $interno.ifIndex -InterfaceMetric 10 }
}

function configurar-dhcp {
    write-host "`n***** CONFIGURACION DEL DHCP ******"
    $ambito = read-host "Nombre del ambito: "
    
    $rangoInicial = pedir-ip "Ingrese el rango inicial (ej: 10.10.10.0)"
    $rangoFinal   = pedir-ip "Ingrese el rango final (ej: 10.10.10.10)"
    
    $prefijo = calcular-prefijo-desde-rango $rangoInicial $rangoFinal
    if ($prefijo -ge 24 -and $rangoInicial.EndsWith(".0")) {
        $prefijoParaWindows = 23 # TRUCO: Forzamos /23 para que acepte la IP .0 como válida
        Write-Host "Ajustando prefijo a /23 para compatibilidad de Windows con IP .0"
    } else {
        $prefijoParaWindows = $prefijo
    }

    $segmento = calcular-red $rangoInicial $prefijoParaWindows
    $maskNumero = [uint32]([math]::Pow(2,32) - [math]::Pow(2,(32 - [int]$prefijoParaWindows)))
    $mask = entero-a-ip $maskNumero

    $lease = read-host "Ingresa el tiempo de concesion (minutos)"
    $gateway = pedir-ip "Ingrese el gateway (opcional)" $true
    $dns = pedir-ip "Ingrese el DNS (opcional, ENTER para usar servidor)" $true
    if ([string]::IsNullOrWhiteSpace($dns)) { $dns = $rangoInicial }

    # Creación del Scope
    Restart-Service dhcpserver -Force
    Start-Sleep -Seconds 2
    
    Write-Host "Creando Ambito $ambito ($rangoInicial - $rangoFinal)..."
    Add-DhcpServerv4Scope -Name $ambito -StartRange $rangoInicial -EndRange $rangoFinal -SubNetmask $mask -LeaseDuration (New-TimeSpan -Minutes $lease) -State Active

    # Configuración de Opciones
    $scopeIP = [System.Net.IPAddress]::Parse($segmento)
    if (-not [string]::IsNullOrWhiteSpace($gateway)) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeIP -Router $gateway -Force
    }
    Set-DhcpServerv4OptionValue -ScopeId $scopeIP -DnsServer $dns -Force

    # Cambio de IP de la interfaz
    cambiar-ip-servidor -NuevaIP $rangoInicial -Prefijo $prefijoParaWindows
    priorizar-red-interna
    
    write-host "`nConfiguracion completada con exito."
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
