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