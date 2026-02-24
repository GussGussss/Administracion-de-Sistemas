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
          remove-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0 | out-null
          add-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0 | out-null
          write-host "Reinstalacion completa :D"
        }
        "S"{
          write-host "Reintalado SSH...."
          remove-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0 | out-null
          add-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0  | out-null
          write-host "Reinstalacion completa :D"
        }
        "n" {break}
        "N" {break}
        default {write-host "Opcion incorrecta.... Ingrese s o n"}
      }
  }else{
    write-host "El servicio SSH no esta instalado"
    write-host "Instalando servicio SSH...."
    add-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0 | out-null
    $ssh=get-windowscapability -online -name OpenSSH.Server~~~~0.0.1.0
    if ($ssh.state -eq "Installed"){
      write-host "Instalacion completada :D"
    }else{
      write-host "Ocurrio un error al instalar el servicio SSH :c"
    }
  }

  $sshPath = "C:\ProgramData\ssh"
  $rsaKey = Join-Path $sshPath "ssh_host_rsa_key"
  
  if (-not (Test-Path $rsaKey)) {
      Write-Host "Generando claves del servidor SSH..."
      & "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -A | Out-Null
  }
  set-service -name sshd -startuptype automatic
  start-service sshd
  if (-not(get-netfirewallrule -name sshd -erroraction silentlycontinue)){
    new-netfirewallrule -name sshd -displayname "OpenSSH Server (sshd)" -enabled true -direction inbound -protocol TCP -action allow -localport 22 | out-null
  }
  read-host "Presione ENTER para continuar"
}

function estado-ssh{
  write-host ""
  write-host "***** Estado del servicio SSH *****"
  write-host ""

  $servicio=get-service sshd -erroraction silentlycontinue
  if($servicio.status -eq "Running"){
    write-host "Estado: Servicio SSH activo"
    write-host ""
    $opcion=read-host "¿Quiere ver el estado detallado del servicio? (s/n) "
    switch ($opcion) {
      "s" {
        get-service sshd | format-list *
        return
      }
      "S" {
        get-service sshd | format-list *
        return
      }
      "n" { return }
      "N"  {return }
      default { write-host "Opcion invalida... ingresa s o n" }
      }
    }else{
      write-host "Estado: Servicio SSH inactivo"
    }
  }

function menu_ssh{
  while ($true) {
    write-host ""
    write-host ""
    write-host "**** Menu SSH ****"
    write-host "1) Instalar servicio SSH"
    write-host "2) Ver estado del servicio SSH"
    $opcion=read-host "Selecciona una opcion"

    switch($opcion){
      "1" {instalar-ssh}
      "2" {estado-ssh}
      default {write-host "Opcion invalida" }
    }
  }
}
menu_ssh
