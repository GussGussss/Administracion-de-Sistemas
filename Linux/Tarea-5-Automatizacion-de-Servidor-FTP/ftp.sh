configurar_firewall(){
  if systemctl is-active --quiet firewalld; then
     firewall-cmd --permanent --add-service=ftp
     firewall-cmd --permanent --add-port=40000-40100/tcp
     firewall-cmd --reload
     echo "Firewall configurado para FTP"
  fi
}

function Instalar-ServicioFTP {
    Write-Host "`nVerificando si IIS y FTP están instalados..." -ForegroundColor Cyan

    # 1. Verificar si FTP para IIS está instalado
    $ftpFeature = Get-WindowsFeature -Name Web-Ftp-Server
    
    if ($ftpFeature.Installed) {
        Write-Host "El servicio FTP ya está instalado." -ForegroundColor Green
        $opcion = Read-Host "Desea reinstalarlo? (s/n)"
        if ($opcion -eq 's') {
            Write-Host "Reinstalando..."
            Uninstall-WindowsFeature -Name Web-Ftp-Server -Remove
            Install-WindowsFeature -Name Web-Ftp-Server -IncludeManagementTools
            Write-Host "Reinstalación completada." -ForegroundColor Green
        }
    } else {
        Write-Host "Instalando IIS con soporte FTP..."
        # Instala IIS y el módulo de FTP
        Install-WindowsFeature -Name Web-Server, Web-Ftp-Server -IncludeManagementTools
        
        if (Get-WindowsFeature -Name Web-Ftp-Server | Where-Object { $_.Installed }) {
            Write-Host "Instalación completada exitosamente." -ForegroundColor Green
        } else {
            Write-Host "Hubo un error en la instalación." -ForegroundColor Red
            return
        }
    }

    # 2. Asegurar que el servicio de gestión de IIS esté corriendo
    # En Windows, el servicio W3SVC gestiona el sitio y el FTP
    if ((Get-Service W3SVC).Status -ne 'Running') {
        Write-Host "Iniciando servicio IIS/FTP..."
        Start-Service W3SVC
        Set-Service W3SVC -StartupType Automatic
    }

    # Llamamos a las funciones siguientes (Firewall y SELinux/ACLs)
    Configurar-FirewallFTP
    # Configurar-SELinux (En Windows, esto se manejará con políticas NTFS/ACLs)
    
    Read-Host "Presione ENTER para continuar..."
}

function Configurar-FTP {
    Write-Host "Configurando el servicio FTP en IIS..." -ForegroundColor Cyan

    # 1. Crear la estructura base (root)
    $ftpRoot = "C:\ftp"
    if (!(Test-Path $ftpRoot)) { New-Item -Path $ftpRoot -ItemType Directory }

    # 2. Configurar Aislamiento de Usuario (User Name Directory)
    # Esto equivale a chroot_local_user=YES
    Set-WebConfigurationProperty -Filter /system.ftpServer/serverRuntime -Name "userIsolationMode" -Value "UserName" -PSPath "IIS:\"

    # 3. Configurar el rango de puertos pasivos
    # Necesario para el firewall (equivalente a pasv_min/max_port)
    Set-WebConfigurationProperty -Filter /system.ftpServer/firewallSupport -Name "lowTcpPort" -Value 40000 -PSPath "IIS:\"
    Set-WebConfigurationProperty -Filter /system.ftpServer/firewallSupport -Name "highTcpPort" -Value 40100 -PSPath "IIS:\"

    # 4. Habilitar autenticación anónima y básica
    Set-WebConfigurationProperty -Filter /system.ftpServer/security/authentication/anonymousAuthentication -Name "enabled" -Value $true -PSPath "IIS:\Sites\Default FTP Site"
    Set-WebConfigurationProperty -Filter /system.ftpServer/security/authentication/basicAuthentication -Name "enabled" -Value $true -PSPath "IIS:\Sites\Default FTP Site"

    # 5. Configurar permisos globales
    # Permitir escritura (write_enable=YES)
    Set-WebConfigurationProperty -Filter /system.ftpServer/security/authorization -Name "." -Value @{accessType="Allow"; users="*"; permissions="Read, Write"} -PSPath "IIS:\Sites\Default FTP Site"

    # 6. Reiniciar el servicio FTP
    Restart-Service W3SVC
    Write-Host "Servidor FTP configurado correctamente." -ForegroundColor Green
}
