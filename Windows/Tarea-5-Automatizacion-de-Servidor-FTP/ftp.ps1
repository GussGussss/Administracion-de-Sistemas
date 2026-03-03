$usuarioActual = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($usuarioActual)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "El script debe ejecutarse como Administrador :D"
    exit 1
}

function Configurar-Firewall {

    Write-Host "Configurando Firewall para FTP..."
    
    if (-not (Get-NetFirewallRule -DisplayName "FTP Puerto 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -DisplayName "FTP Puerto 21" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 21 `
            -Action Allow
    }

    if (-not (Get-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -DisplayName "FTP Pasivo 40000-40100" `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 40000-40100 `
            -Action Allow
    }

    Write-Host "Firewall configurado correctamente para FTP."
}

Write-Host "****** Tarea 5: Automatizacion de Servidor FTP ********"

function Instalar-FTP {

    Write-Host ""
    Write-Host "Verificando si el servicio FTP (IIS) esta instalado..."
    Write-Host ""

    $ftpFeature = Get-WindowsFeature -Name Web-Ftp-Server

    if ($ftpFeature.Installed) {

        Write-Host "El servicio FTP ya esta instalado :D"

        while ($true) {
            $opcion = Read-Host "Desea reinstalarlo (s/n)?"
            Write-Host ""

            switch ($opcion.ToLower()) {
                "s" {
                    Write-Host "Reinstalando el servicio FTP..."

                    Remove-WindowsFeature -Name Web-Ftp-Server -ErrorAction SilentlyContinue
                    Install-WindowsFeature -Name Web-Server,Web-Ftp-Server -IncludeManagementTools

                    Write-Host ""
                    Write-Host "Reinstalacion completada :D"
                    break
                }
                "n" {
                    Write-Host "No se realizara ninguna accion"
                    break
                }
                default {
                    Write-Host "Opcion invalida... ingrese s o n"
                }
            }
        }

    } else {

        Write-Host "El servicio FTP no esta instalado"
        Write-Host ""
        Write-Host "Instalando..."

        $resultado = Install-WindowsFeature -Name Web-Server,Web-Ftp-Server -IncludeManagementTools

        if ($resultado.Success) {
            Write-Host "Instalacion completada :D"
        } else {
            Write-Host "Hubo un error en la instalacion."
        }
    }

    if ((Get-Service FTPSVC).StartType -ne "Automatic") {
        Write-Host "Habilitando servicio..."
        Set-Service -Name FTPSVC -StartupType Automatic
    }

    if ((Get-Service FTPSVC).Status -ne "Running") {
        Write-Host "Iniciando servicio..."
        Start-Service FTPSVC
    }

    Configurar-Firewall

    Read-Host "Presione ENTER para continuar..."
}

function Configurar-FTP {

    Import-Module WebAdministration

    $ftpRoot = "C:\FTP"
    $siteName = "FTPSite"

    if (-not (Test-Path $ftpRoot)) {
        New-Item -Path $ftpRoot -ItemType Directory
    }

    if (-not (Get-WebSite | Where-Object { $_.Name -eq $siteName })) {
        New-WebFtpSite `
            -Name $siteName `
            -Port 21 `
            -PhysicalPath $ftpRoot `
            -Force
    }

    Set-WebConfigurationProperty `
        -Filter "/system.ftpServer/security/authentication/anonymousAuthentication" `
        -PSPath "IIS:\Sites\$siteName" `
        -Name enabled -Value $true

    Set-WebConfigurationProperty `
        -Filter "/system.ftpServer/security/authentication/basicAuthentication" `
        -PSPath "IIS:\Sites\$siteName" `
        -Name enabled -Value $true

    Clear-WebConfiguration `
        -Filter "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$siteName"

    Add-WebConfiguration `
        -Filter "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$siteName" `
        -Value @{
            accessType="Allow";
            users="anonymous";
            permissions="Read"
        }

    Add-WebConfiguration `
        -Filter "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\Sites\$siteName" `
        -Value @{
            accessType="Allow";
            roles="reprobados,recursadores";
            permissions="Read,Write"
        }

    Set-ItemProperty `
        "IIS:\Sites\$siteName" `
        -Name ftpServer.firewallSupport.passivePortRange `
        -Value "40000-40100"

    Set-WebConfigurationProperty `
        -Filter "/system.ftpServer/userIsolation" `
        -PSPath "IIS:\Sites\$siteName" `
        -Name mode `
        -Value "IsolateUsers"

    Restart-Service FTPSVC

    Write-Host "Configuracion FTP aplicada correctamente :D"
}

function Crear-Grupos {

    if (Get-LocalGroup -Name "reprobados" -ErrorAction SilentlyContinue) {
        Write-Host "El grupo reprobados ya existe"
    } else {
        Write-Host "Creando grupo reprobados..."
        New-LocalGroup -Name "reprobados" -Description "Grupo FTP Reprobados"
    }

    if (Get-LocalGroup -Name "recursadores" -ErrorAction SilentlyContinue) {
        Write-Host "El grupo recursadores ya existe"
    } else {
        Write-Host "Creando grupo recursadores..."
        New-LocalGroup -Name "recursadores" -Description "Grupo FTP Recursadores"
    }

    if (-not (Get-LocalGroup -Name "ftpusuarios" -ErrorAction SilentlyContinue)) {
        Write-Host "Creando grupo ftpusuarios..."
        New-LocalGroup -Name "ftpusuarios" -Description "Grupo general de usuarios FTP"
    } else {
        Write-Host "El grupo ftpusuarios ya existe"
    }

    Write-Host "Verificacion de grupos finalizada :D"
}

function Crear-Estructura {

    $raiz = "C:\FTP"

    $directorios = @(
        "$raiz",
        "$raiz\general",
        "$raiz\reprobados",
        "$raiz\recursadores"
    )

    foreach ($dir in $directorios) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    Write-Host "Estructura base creada correctamente :D"
}
