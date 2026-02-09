write-host "******* AUTOMATIZACION Y GESTION DEL SERVIDOR DHCP *******" 
$nombre=hostname 
$ipActual=get-netipaddress -addressFamily IPv4 | where-object { $_.interfacealias -notlike "*Loopback*" } | select-object -firs 1 -expandproperty ipaddress
write-host "Nombre del equipo: $nombre"
write-host "IP Actual: $ipActual"

write-host "Verificando si se encuentra el servicio DHCP"
$servicioDHCP=get-windowsfeature -name DHCP

if(-not $servicioDHCP.installed){
        write-host "El servicio DHPC no se encuentra. Se instalara automaticamente"
        install-windowsfeature -name DHCP -includemanagementtools
        write-host "La instalacion se ha completado"
}else{
        write-host "El servicio DHCP ya esta instalado en el sistema

$expresionRegular = "^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$"

function validarIP{
        param([string]$prompt)
        $IPvalida=$false
        while (-not $IPvalida){
                $IP=read-host $prompt
                if($IP -match $expresionRegular){
                        $IPvalida=$true
                        return $IP
                }else{
                        write-host "La '$IP' no es valida... intente de nuevo"

write-host "****** SOLICITUD DE DATOS ******"
$nombreAmbito=read-host "Ingrese nombre descriptivo del ambito (ej: red_interna_asfasd): "
$rangoInicial=get-validarIP "Ingrese el rango inicial de la IP (ej: 192.168.0.10): "
$rangoFinal=get-validarIP "Ingrese el rango final de la IP (ej: 192.168.0.160): "
$tiempo=read-host "Tiempo de concesion (dd.hh.mm - ej: 01:12:50): "
$gateway=get-validarIP "IP de puerta de enlace (gateway): "
$dnsServidor=get-validarIP "IP del servidor DNS: "

write-host "Creacion del ambito DHCP..."
try{
        add-dhcpserverv4scope -name $nombreAmbito -startrage $rangoInicial -endrage $rangofinal -subnetmask 255.255.255.0 -state active
        write-host "Ambito '$nombreAmbito' creado correctamente"

        set-dhcpserverv40optionvalue -optionid 3 -value $gateway -scopeid $rangoInicial
        write-host "Gateway configurado '$gateway'"

        set-dhcpserverv40optionvalue -optionid 6 -value $dnsServidor $scopeid -rangoInicial
        write-host "servidor DNS configurado '$dnsServidor'"
}catch{
        write-host "SI EL AMBITO NO SE CREO PUEDE QUE YA EXISTA"
        write-error $_
}

write-host "******** Monitoreo *******"
$servicioDHPC=get-service -name DHCPServer
write-host="Estado del servicio: " -nonewline
if($servicioDHCP.status -eq "Runnig"){
        write-host "ACTIVO"
}else{
        write-host "DETENIDO"

write-host "Lista de equipos conectados: "
$conectados=get.dhcpserver4lease -scopeid $rangoInicial
if($null -eq $conectados){
        write-host "No hay equipos conectados"
}else{
        $conectados | format-table IP-Del-Cliente, HostName, AddessState -autosize


write-host "FIN"

