$usuarioActual = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($usuarioActual)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "El script debe ejecutarse como Administrador :D"
    exit 1
}

function Configurar-Firewall {

    Write-Host "Configurando Firewall para FTP..."
    
    if (-not (Get-NetFirewallRule -DisplayName "FTP Puerto 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Puerto 21" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow
    }

    if (-not (Get-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" -Direction Inbound -Protocol TCP -LocalPort 40000-40100 -Action Allow
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
                    Install-WindowsFeature -Name Web-Server,Web-Ftp-Server,Web-Ftp-Service,Web-Ftp-Ext -IncludeManagementTools
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

        $resultado = Install-WindowsFeature -Name Web-Server,Web-Ftp-Server,Web-Ftp-Service,Web-Ftp-Ext -IncludeManagementTools
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

    $siteName = "FTPSite"
    $ftpRoot = "C:\FTP"

    Write-Host "Configurando sitio FTP en IIS..."

    # Crear carpeta raíz si no existe
    if (-not (Test-Path $ftpRoot)) {
        New-Item -Path $ftpRoot -ItemType Directory | Out-Null
    }

    # Crear sitio FTP si no existe
    if (-not (Get-Website | Where-Object { $_.Name -eq $siteName })) {
        New-WebFtpSite -Name $siteName -Port 21 -PhysicalPath $ftpRoot -Force
        Write-Host "Sitio FTP creado."
    }

    # -------------------------
    # AUTENTICACIÓN
    # -------------------------

    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authentication/basicAuthentication" `
        -Name enabled -Value True `
        -PSPath "IIS:\Sites\$siteName"

    Set-WebConfigurationProperty `
        -Filter "system.ftpServer/security/authentication/anonymousAuthentication" `
        -Name enabled -Value True `
        -PSPath "IIS:\Sites\$siteName"

    Write-Host "Autenticacion basica y anonima habilitadas."

    # -------------------------
    # AISLAMIENTO CORRECTO PARA SERVER CORE
    # -------------------------

    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/userIsolation" `
        -Name mode -Value "StartInUsersDirectory"

    Write-Host "Aislamiento configurado en modo StartInUsersDirectory."

    # Dominio local por defecto
    Set-ItemProperty `
        -Path "IIS:\Sites\$siteName" `
        -Name ftpServer.defaultLogonDomain `
        -Value $env:COMPUTERNAME

    # -------------------------
    # AUTORIZACIÓN
    # -------------------------

    Clear-WebConfiguration `
        -Filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/security/authorization"

    # Anónimo solo lectura
    Add-WebConfiguration `
        -Filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/security/authorization" `
        -PSPath IIS:\ `
        -Value @{accessType="Allow"; users="IUSR"; permissions="Read"}

    # Usuarios autenticados
    Add-WebConfiguration `
        -Filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/security/authorization" `
        -PSPath IIS:\ `
        -Value @{accessType="Allow"; users="*"; permissions="Read,Write"}

    Write-Host "Reglas de autorizacion configuradas."

    # -------------------------
    # PUERTOS PASIVOS
    # -------------------------

    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/ftpServer/firewallSupport" `
        -Name passivePortRange -Value "40000-40100"

    # SSL opcional
    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/security/ssl" `
        -Name controlChannelPolicy -Value "SslAllow"

    Set-WebConfigurationProperty `
        -Filter "system.applicationHost/sites/site[@name='$siteName']/ftpServer/security/ssl" `
        -Name dataChannelPolicy -Value "SslAllow"

    Restart-Service FTPSVC

    Write-Host ""
    Write-Host "Configuracion FTP aplicada correctamente :D"
}

function Permitir-AccesoRedFTP {

    Write-Host "Asignando derecho 'Acceder a este equipo desde la red'..."

    secedit /export /cfg C:\temp.cfg | Out-Null

    (Get-Content C:\temp.cfg) -replace "SeNetworkLogonRight = (.*)", "SeNetworkLogonRight = `$1,ftpusuarios" | Set-Content C:\temp.cfg

    secedit /configure /db C:\Windows\Security\Database\secedit.sdb /cfg C:\temp.cfg /areas USER_RIGHTS | Out-Null

    Remove-Item C:\temp.cfg

    Write-Host "Derecho asignado correctamente."
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
    
    Permitir-AccesoRedFTP
    Write-Host "Verificacion de grupos finalizada :D"
}

function Crear-Estructura {

    $raiz = "C:\FTP"

    $directorios = @(
        "$raiz",
        "$raiz\general",
        "$raiz\reprobados",
        "$raiz\recursadores",
        "$raiz\LocalUser"
    )

    foreach ($dir in $directorios) {
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    Write-Host "Estructura base creada correctamente :D"
}

function Asignar-Permisos {

    $raiz = "C:\FTP"

    Write-Host "Configurando permisos NTFS..."

    icacls $raiz /grant "Administrators:(OI)(CI)F" /T | Out-Null
    icacls $raiz /grant "SYSTEM:(OI)(CI)F" /T | Out-Null

    $general = "$raiz\general"

    icacls $general /grant "ftpusuarios:(OI)(CI)M" | Out-Null

    icacls $general /grant "IUSR:(OI)(CI)R" | Out-Null

    $reprobados = "$raiz\reprobados"

    icacls $reprobados /inheritance:r | Out-Null
    icacls $reprobados /grant "Administrators:F" | Out-Null
    icacls $reprobados /grant "SYSTEM:F" | Out-Null
    icacls $reprobados /grant "reprobados:(OI)(CI)M" | Out-Null

    $recursadores = "$raiz\recursadores"

    icacls $recursadores /inheritance:r | Out-Null
    icacls $recursadores /grant "Administrators:F" | Out-Null
    icacls $recursadores /grant "SYSTEM:F" | Out-Null
    icacls $recursadores /grant "recursadores:(OI)(CI)M" | Out-Null

    icacls $raiz /grant "Users:(OI)(CI)RX" | Out-Null
    
    Write-Host "Permisos configurados correctamente :D"
}

function Crear-Usuarios {

    $cantidad = Read-Host "Ingrese el numero de usuarios a capturar"

    for ($i = 1; $i -le [int]$cantidad; $i++) {

        Write-Host ""
        Write-Host "Usuario $i"

        $nombre = Read-Host "Nombre de usuario"

        # Verificar si ya existe
        if (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue) {
            Write-Host "El usuario ya existe"
            continue
        }

        $passwordPlano = Read-Host "Contraseña" -AsSecureString
        $grupo = Read-Host "Grupo (reprobados / recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo invalido"
            continue
        }

        # Crear usuario
        New-LocalUser -Name $nombre -Password $passwordPlano -FullName $nombre -Description "Usuario FTP"

        Add-LocalGroupMember -Group $grupo -Member $nombre
        Add-LocalGroupMember -Group "ftpusuarios" -Member $nombre
        
        $rutaUsuario = "C:\FTP\LocalUser\$nombre"

        if (-not (Test-Path $rutaUsuario)) {
            New-Item -Path $rutaUsuario -ItemType Directory | Out-Null
        }

        icacls $rutaUsuario /inheritance:r | Out-Null
        
        icacls $rutaUsuario /grant "${nombre}:(OI)(CI)F" | Out-Null
        icacls $rutaUsuario /grant "Administrators:(OI)(CI)F" | Out-Null
        icacls $rutaUsuario /grant "SYSTEM:(OI)(CI)F" | Out-Null
        icacls $rutaUsuario /grant "IUSR:(OI)(CI)RX" | Out-Null
        icacls $rutaUsuario /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null
        Write-Host "Usuario $nombre creado correctamente :D"
    }
}

function Cambiar-GrupoUsuario {

    Write-Host ""
    Write-Host "***** Cambiar de grupo a usuario *****"

    $nombre = Read-Host "Ingrese el nombre del usuario"

    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario no existe"
        return
    }

    $nuevoGrupo = Read-Host "Ingrese el nuevo grupo (reprobados / recursadores)"

    if ($nuevoGrupo -ne "reprobados" -and $nuevoGrupo -ne "recursadores") {
        Write-Host "Grupo invalido"
        return
    }

    $miembrosReprobados = Get-LocalGroupMember -Group "reprobados" -ErrorAction SilentlyContinue
    $miembrosRecursadores = Get-LocalGroupMember -Group "recursadores" -ErrorAction SilentlyContinue

    if ($miembrosReprobados.Name -contains $nombre) {
        Remove-LocalGroupMember -Group "reprobados" -Member $nombre
    }

    if ($miembrosRecursadores.Name -contains $nombre) {
        Remove-LocalGroupMember -Group "recursadores" -Member $nombre
    }

    Add-LocalGroupMember -Group $nuevoGrupo -Member $nombre

    Write-Host "Grupo del usuario $nombre actualizado correctamente :D"
}

function Configurar-SeguridadFTP {

    Write-Host "Verificando configuracion de seguridad FTP..."

    $servicio = Get-Service -Name FTPSVC -ErrorAction SilentlyContinue

    if ($servicio -and $servicio.Status -eq "Running") {
        Write-Host "Servicio FTP activo y listo."
    } else {
        Write-Host "Advertencia: El servicio FTP no esta en ejecucion."
    }

    Write-Host "En Windows la seguridad se controla mediante permisos NTFS e IIS."
}

function Mostrar-Menu {

    while ($true) {
        Write-Host ""
        Write-Host "***** Menu FTP *****"
        Write-Host "1) Instalar servicio FTP"
        Write-Host "2) Configurar FTP (IIS)"
        Write-Host "3) Crear grupos"
        Write-Host "4) Crear estructura base"
        Write-Host "5) Asignar permisos base"
        Write-Host "6) Crear usuarios"
        Write-Host "7) Cambiar grupo usuario"
        Write-Host "0) Salir"
        Write-Host ""

        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {

            "1" { Instalar-FTP }
            "2" { Configurar-FTP }
            "3" { Crear-Grupos }
            "4" { Crear-Estructura }
            "5" { Asignar-Permisos }
            "6" { Crear-Usuarios }
            "7" { Cambiar-GrupoUsuario }
            "0" { 
                Write-Host "Saliendo..."
                break 
            }
            default {
                Write-Host "Opcion invalida"
                Start-Sleep -Seconds 1
            }
        }

        if ($opcion -ne "0") {
            Write-Host ""
            Read-Host "Presione ENTER para continuar..."
        }
    }
}

Mostrar-Menu
