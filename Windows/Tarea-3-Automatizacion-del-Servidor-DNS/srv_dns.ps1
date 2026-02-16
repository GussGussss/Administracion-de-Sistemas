write-host ""
write-host ""
write-host "***** Automatizacion del Servidor DNS ******"
write-host ""

$hostname=hostname
$ipActual=(get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*loopback*" } | select-object -first 1).ipaddress
write-host "Host: $hostname"
write-host "IP: $ipActual"
write-host ""

function instalar-dns{
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

do{
	write-host ""
	write-host ""
	write-host "***** MENU ****"
	write-host "1) Instalar Servicio DNS"
	$opcion=read-host "Seleciona una opcion "
	
	switch($opcion){
		"1" {instalar-dns}
		"2" {estado-dns}
		"0" {exit}
	}
}while($true)