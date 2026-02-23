write-host ""
write-host ""
write-host "******* Tarea 4: SSH *******"
$ipActual=(get-netipaddress -addressfamily ipv4 | where-object {$_.interfacealias -eq "Ethernet 2" -and $_.ipaddress -notlike "169.*"} | select-object -first 1).ipaddress
write-host "Hostname: $env:COMPUTERNAME"
write-host "IP: $ipActual"
write-host ""

function instalar-ssh{
  write-host ""
  write-host "Checando que el servicio SSH ya este instalado...."
  $ssh=get-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
  if($ssh.state -eq "Installed"){
    write-host "El servicio SSH si esta instalado"
    $opcion=read-host "¿Quiere reinstalar el servicio? (s/n)"
      switch($opcion){
        "s"{
          write-host "Reintalado SSH...."
          remove-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
          add-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
          write-host "Reinstalacion completa :D"
        }
        "S"{
          write-host "Reintalado SSH...."
          remove-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
          add-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
          write-host "Reinstalacion completa :D"
        }
        "n" {break}
        "N" {break}
        default {write-host "Opcion incorrecta.... Ingrese s o n"}
      }
  }else{
    write-host "El servicio SSH no esta instalado"
    write-host "Instalando servicio SSH...."
    add-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
    $ssh=get-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
    if ($ssh.state -eq "Installed"){
      write-host "Instalacion completada :D"
    }else{
      write-host "Ocurrio un error al instalar el servicio SSH :c"
    }
  }
  start-service sshd
  set-service -name sshd -startuptype automatic
  if (-not(get-netfirewallrule -name sshd -erroraction silentlycontinue)){
    new-netfirewallrule -name sshd -displayname "OpenSSH Server (sshd)" -enabled true -direction inbound -protocol TCP -action allow -localport 22
  }
  read-host "Presione ENTER para continuar"
}

function menu_ssh{
  while ($true) {
    write-host ""
    write-host ""
    write-host "**** Menu SSH ****"
    write-host "1) Instalar servicio SSH"
    $opcion=read-host "Selecciona una opcion"

    switch($opcion){
      "1" {instalar-ssh}
      default {write-host "Opcion invalida" }
    }
  }
}
menu_ssh
