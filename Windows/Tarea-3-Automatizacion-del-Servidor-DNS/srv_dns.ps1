write-host ""
write-host ""
write-host "***** Automatizacion del Servidor DNS ******"
write-host ""

$hostname=hostname
$ipActual=(get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*loopback*" } | select-object -first 1).ipaddress
write-host "Host: $hostname"
write-host "IP: $ipActual"
write-host ""

import-module dnsserver -erroraction silentlycontinue
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
					install-windows-feature DNS -includemanagementtools
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
	read-host "presiona ENTER para continuar"
}

function estado-dns{
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
		$ipDominio = "192.168.0.72"
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
}

function crear-dominio{
	write-host ""
	write-host ""
	write-host "***** Agregar nuevo dominio *****"

	$dominio=read-host "Ingresa el nombre del dominio (ej: pikachu.com) "

	if([string]::isnullorwhitespace($zon)){
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


do{
	write-host ""
	write-host ""
	write-host "***** MENU ****"
	write-host "1) Instalar Servicio DNS"
	write-host "2) Ver estaod del Servicio DNS"
	write-host "3) Crear dominio principal (reprobados.com)"
	write-host "4) Crear dominio"
	write-host "5) Ver todos los dominios"
	$opcion=read-host "Seleciona una opcion "ver
	
	switch($opcion){
		"1" {instalar-dns}
		"2" {estado-dns}
		"3" {crear-dominio-principal}
		"4" {crear-dominio}
		"5" {todos-los-dominios}
		"0" {exit}
	}
}while($true)