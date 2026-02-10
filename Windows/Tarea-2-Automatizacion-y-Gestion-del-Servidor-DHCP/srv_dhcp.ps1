write-host "****** AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP *****
$hostname = hostname
$ipActual = (get-netipaddress -addressfamily IPv4 | where-object { $_.interfacealias -notlike "*Loopback*" } | select-object -first 1).ipaddress
write-host "Host: $hostname"
write-host "IP: $ipActual"
