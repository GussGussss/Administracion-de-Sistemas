. .\lib\network.ps1

function instalar-dns{
	write-host ""
	write-host ""
	write-host "**** Instalacion del Servicio DNS *****"
	$dns=get-windowsfeature DNS

		if (-not $dns.Installed) {
	
	    Write-Host "Instalando servicio DNS..."
	    $resultado = Install-WindowsFeature DNS -IncludeManagementTools
	
	    if ($resultado.RestartNeeded -eq "Yes") {
	
	        Write-Host ""
	        Write-Host "Se requiere reiniciar el servidor para completar la instalacion."
	
	        $resp = Read-Host "¿Desea reiniciar ahora? (s/n)"
	
	        if ($resp.ToLower() -eq "s") {
	            Restart-Computer -force
	        }
	
	        return
	    }
	
	    Write-Host "La instalacion ha finalizado correctamente :D"
	}
	else{
		write-host "El servicio DNS ya esta instalado"
		do{
			$opcion=read-host "Quieres reinstalar? (s/n)"
			switch ($opcion.tolower()){
				"s" {
					write-host "Reinstalando servicio DNS...."
					$resultadoRemove = Uninstall-WindowsFeature DNS

					if ($resultadoRemove.RestartNeeded -eq "Yes") {
					
					    Write-Host ""
					    Write-Host "Se requiere reiniciar para completar la desinstalación."
					
					    $resp = Read-Host "¿Desea reiniciar ahora? (s/n)"
					
					    if ($resp.ToLower() -eq "s") {
					        Restart-Computer -force
					    }
					
					    return
					}
					
					Write-Host "Instalando nuevamente DNS..."
					$resultadoInstall = Install-WindowsFeature DNS -IncludeManagementTools
					
					if ($resultadoInstall.RestartNeeded -eq "Yes") {
					
					    Write-Host ""
					    Write-Host "Se requiere reiniciar para completar la instalación."
					
					    $resp = Read-Host "¿Desea reiniciar ahora? (s/n)"
					
					    if ($resp.ToLower() -eq "s") {
					        Restart-Computer -force
					    }
					
					    return
					}
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
	$adaptador = Get-NetAdapter -Name "Ethernet 2"

	if ($adaptador) {
	    Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ResetServerAddresses
	    Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses 127.0.0.1
	    Clear-DnsClientCache
	    Write-Host "DNS local configurado en Ethernet 2."
	}
	read-host "presiona ENTER para continuar"
}

function estado-dns{
	#resolve-dnsname reprobados.com -erroraction silentlycontinue
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

	$ipDominio=read-host "Ingrese la IP que tendra el Dominio (opcional.... si queda vacio tomara la ip del servidor) "
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

	$ipDominio=read-host "Ingrese la IP que tendra el Dominio (opcional.... si queda vacio tomara la ip del servidor) "
	if([string]::isnullorwhitespace($ipDominio)){
		$ipDominio = $ipActual
	}
	
	if(-not(validar-ip $ipDominio)){
		write-host "IP invalida"
		read-host "Presiona ENTER"
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
	Clear-DnsClientCache
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

	Clear-DnsServerCache -Force
	Restart-Service DNS
	
	write-host "El dominio se ha eliminado :D"
	read-host "Presiona ENTER para continuar"
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
