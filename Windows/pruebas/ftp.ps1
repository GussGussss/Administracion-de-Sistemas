# ==============================================================================
#  Tarea 5: Automatizacion de Servidor FTP - Windows Server 2019 (Sin GUI)
#  Basado en script de referencia funcional (WS2022 ES) adaptado a WS2019 EN
#  Requiere ejecutarse como Administrador
# ==============================================================================

#region ── Verificar privilegios de Administrador ─────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "El script debe ejecutarse como Administrador :D" -ForegroundColor Red
    exit 1
}
#endregion

# ── Variables globales ────────────────────────────────────────────────────────
$FTP_ROOT = "C:\ftp"
$FTP_SITE = "FTP_Tarea5"
$LOG_FILE = "C:\ftp\ftp_log.txt"

# ── Funcion de log ────────────────────────────────────────────────────────────
function Log($msg) {
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    if (-not (Test-Path (Split-Path $LOG_FILE))) {
        New-Item -ItemType Directory -Path (Split-Path $LOG_FILE) -Force | Out-Null
    }
    Add-Content $LOG_FILE "$fecha - $msg"
}

# ==============================================================================
#  1) INSTALAR FTP
# ==============================================================================
function Instalar-FTP {
    Write-Host ""
    Write-Host "Verificando si el rol IIS/FTP esta instalado....." -ForegroundColor Cyan
    Write-Host ""

    $features = @("Web-Server", "Web-Ftp-Server", "Web-Ftp-Service", "Web-Ftp-Ext")

    $yaInstalado = $true
    foreach ($f in $features) {
        if (-not (Get-WindowsFeature -Name $f).Installed) { $yaInstalado = $false; break }
    }

    if ($yaInstalado) {
        Write-Host "El servicio FTP (IIS) ya esta instalado :D" -ForegroundColor Green
        do {
            $opcion = Read-Host "Desea reinstalarlo (s/n)?"
            switch ($opcion.ToLower()) {
                "s" {
                    Write-Host "Reinstalando....." -ForegroundColor Yellow
                    foreach ($f in $features) { Uninstall-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null }
                    foreach ($f in $features) { Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null }
                    Write-Host "Reinstalacion completada :D" -ForegroundColor Green
                    $continuar = $true
                }
                "n" { Write-Host "No se realizara ninguna accion" -ForegroundColor Yellow; $continuar = $true }
                default { Write-Host "Opcion invalida... ingrese s o n" -ForegroundColor Red; $continuar = $false }
            }
        } while (-not $continuar)
    } else {
        Write-Host "El servicio FTP (IIS) no esta instalado" -ForegroundColor Yellow
        Write-Host "Instalando....." -ForegroundColor Cyan
        $ok = $true
        foreach ($f in $features) {
            $r = Install-WindowsFeature -Name $f -IncludeManagementTools
            if (-not $r.Success) { $ok = $false }
        }
        if ($ok) { Write-Host "Instalacion completada :D" -ForegroundColor Green }
        else     { Write-Host "Hubo un error en la instalacion." -ForegroundColor Red }
    }

    Start-Service -Name W3SVC  -ErrorAction SilentlyContinue
    Start-Service -Name ftpsvc -ErrorAction SilentlyContinue
    Set-Service   -Name ftpsvc -StartupType Automatic

    Write-Host "Servicio FTP iniciado y configurado para arranque automatico" -ForegroundColor Green
    Log "FTP instalado"
    Configurar-Firewall
    Read-Host "Presione ENTER para continuar..."
}

# ==============================================================================
#  2) FIREWALL
# ==============================================================================
function Configurar-Firewall {
    Write-Host ""
    Write-Host "Configurando Windows Firewall para FTP..." -ForegroundColor Cyan

    New-NetFirewallRule -DisplayName "FTP Control 21" `
        -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow `
        -ErrorAction SilentlyContinue | Out-Null

    New-NetFirewallRule -DisplayName "FTP Pasivo 40000-40100" `
        -Direction Inbound -Protocol TCP -LocalPort 40000-40100 -Action Allow `
        -ErrorAction SilentlyContinue | Out-Null

    Write-Host "Firewall configurado para FTP" -ForegroundColor Green
    Log "Firewall configurado"
}

# ==============================================================================
#  3) CREAR GRUPOS
# ==============================================================================
function Crear-Grupos {
    Write-Host ""
    Write-Host "Creando grupos..." -ForegroundColor Cyan

    foreach ($g in @("reprobados", "recursadores", "ftpusuarios")) {
        if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) {
            Write-Host "El grupo '$g' ya existe" -ForegroundColor Yellow
        } else {
            New-LocalGroup -Name $g -Description "Grupo FTP $g" | Out-Null
            Write-Host "Grupo '$g' creado" -ForegroundColor Green
        }
    }
    Log "Grupos creados"
}

# ==============================================================================
#  4) CREAR ESTRUCTURA DE DIRECTORIOS
# ==============================================================================
function Crear-Estructura {
    Write-Host ""
    Write-Host "Creando estructura de directorios..." -ForegroundColor Cyan

    New-Item -ItemType Directory -Path $FTP_ROOT                    -Force | Out-Null
    New-Item -ItemType Directory -Path "$FTP_ROOT\general"          -Force | Out-Null
    New-Item -ItemType Directory -Path "$FTP_ROOT\reprobados"       -Force | Out-Null
    New-Item -ItemType Directory -Path "$FTP_ROOT\recursadores"     -Force | Out-Null
    New-Item -ItemType Directory -Path "$FTP_ROOT\Data\Usuarios"    -Force | Out-Null
    New-Item -ItemType Directory -Path "$FTP_ROOT\LocalUser\Public" -Force | Out-Null

    # Junction publica: anonimos ven general dentro de LocalUser\Public
    $jPublicGeneral = "$FTP_ROOT\LocalUser\Public\general"
    if (Test-Path $jPublicGeneral) { cmd /c "rmdir `"$jPublicGeneral`"" | Out-Null }
    cmd /c "mklink /J `"$jPublicGeneral`" `"$FTP_ROOT\general`"" | Out-Null

    Write-Host "Estructura creada correctamente" -ForegroundColor Green
    Log "Estructura FTP creada"
}

# ==============================================================================
#  5) ASIGNAR PERMISOS BASE
# ==============================================================================
function Asignar-Permisos {
    Write-Host ""
    Write-Host "Asignando permisos base..." -ForegroundColor Cyan

    # Raiz FTP
    icacls $FTP_ROOT /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "IUSR:(RX)" | Out-Null

    # General: ftpusuarios escribe, IUSR lee
    icacls "$FTP_ROOT\general" /inheritance:r /grant `
        "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" `
        "ftpusuarios:(OI)(CI)M" "IUSR:(OI)(CI)RX" | Out-Null

    # Reprobados: solo el grupo
    icacls "$FTP_ROOT\reprobados" /inheritance:r /grant `
        "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "reprobados:(OI)(CI)M" | Out-Null

    # Recursadores: solo el grupo
    icacls "$FTP_ROOT\recursadores" /inheritance:r /grant `
        "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "recursadores:(OI)(CI)M" | Out-Null

    Write-Host "Permisos base asignados correctamente" -ForegroundColor Green
    Log "Permisos base asignados"
}

# ==============================================================================
#  6) CONFIGURAR SITIO FTP EN IIS
# ==============================================================================
function Configurar-FTP {
    Write-Host ""
    Write-Host "Configurando sitio FTP en IIS..." -ForegroundColor Cyan

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    if (Get-WebSite -Name $FTP_SITE -ErrorAction SilentlyContinue) { Remove-WebSite -Name $FTP_SITE }

    New-WebFtpSite -Name $FTP_SITE -Port 21 -PhysicalPath $FTP_ROOT -Force | Out-Null

    # Aislamiento de usuarios: IIS busca C:\ftp\LocalUser\<usuario>\
    Set-ItemProperty "IIS:\Sites\$FTP_SITE" -Name ftpServer.userIsolation.mode -Value 3

    # Autenticacion anonima y basica
    Set-ItemProperty "IIS:\Sites\$FTP_SITE" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$FTP_SITE" -Name ftpServer.security.authentication.basicAuthentication.enabled    -Value $true

    # SSL opcional
    Set-ItemProperty "IIS:\Sites\$FTP_SITE" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$FTP_SITE" -Name ftpServer.security.ssl.dataChannelPolicy    -Value "SslAllow"

    # Puertos pasivos
    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.ftpServer/firewallSupport" -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" -Filter "system.ftpServer/firewallSupport" -Name "highDataChannelPort" -Value 40100

    # Reglas de autorizacion
    Clear-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath IIS:\ -Location $FTP_SITE

    # Anonimos solo lectura
    Add-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath IIS:\ -Location $FTP_SITE `
        -Value @{accessType="Allow"; users="?"; roles=""; permissions="Read"}

    # ftpusuarios lectura y escritura
    Add-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath IIS:\ -Location $FTP_SITE `
        -Value @{accessType="Allow"; users=""; roles="ftpusuarios"; permissions="Read,Write"}

    Restart-Service ftpsvc -Force

    Write-Host "Sitio FTP configurado correctamente" -ForegroundColor Green
    Log "FTP configurado"
}

# ==============================================================================
#  7) CREAR USUARIOS
# ==============================================================================
function Crear-Usuarios {
    Write-Host ""
    $cantidad = Read-Host "Ingrese el numero de usuarios a capturar"

    for ($i = 1; $i -le [int]$cantidad; $i++) {
        Write-Host ""
        Write-Host "Usuario $i de $cantidad" -ForegroundColor Cyan

        $nombre = Read-Host "Nombre de usuario"

        if (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue) {
            Write-Host "El usuario '$nombre' ya existe" -ForegroundColor Yellow
            continue
        }

        $password = Read-Host "Contrasena" -AsSecureString
        $grupo    = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo invalido" -ForegroundColor Red
            continue
        }

        # Crear usuario
        New-LocalUser -Name $nombre -Password $password -Description "Usuario FTP Tarea5" | Out-Null
        Set-LocalUser -Name $nombre -PasswordNeverExpires $true

        Add-LocalGroupMember -Group $grupo        -Member $nombre -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "ftpusuarios" -Member $nombre -ErrorAction SilentlyContinue

        # Esperar registro del SID
        Start-Sleep -Seconds 2

        # Carpetas
        $userHome    = "$FTP_ROOT\LocalUser\$nombre"
        $userPrivado = "$FTP_ROOT\Data\Usuarios\$nombre"

        New-Item -ItemType Directory -Path $userHome    -Force | Out-Null
        New-Item -ItemType Directory -Path $userPrivado -Force | Out-Null

        # Junctions dentro del home IIS
        cmd /c "mklink /J `"$userHome\general`"  `"$FTP_ROOT\general`""  | Out-Null
        cmd /c "mklink /J `"$userHome\$grupo`"   `"$FTP_ROOT\$grupo`""   | Out-Null
        cmd /c "mklink /J `"$userHome\$nombre`"  `"$userPrivado`""        | Out-Null

        # Permisos home IIS: usuario navega, no puede escribir directamente aqui
        icacls $userHome /inheritance:r /grant `
            "${nombre}:(OI)(CI)RX" "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" | Out-Null

        # Permisos carpeta privada: solo el usuario tiene control total
        icacls $userPrivado /inheritance:r /grant `
            "${nombre}:(OI)(CI)F" "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" | Out-Null

        Write-Host "Usuario '$nombre' creado correctamente" -ForegroundColor Green
        Log "Usuario creado: $nombre grupo: $grupo"
    }

    Restart-Service ftpsvc -Force
    Write-Host ""
    Write-Host "Proceso de creacion de usuarios finalizado" -ForegroundColor Green
}

# ==============================================================================
#  8) ELIMINAR USUARIO
# ==============================================================================
function Eliminar-Usuario {
    Write-Host ""
    $nombre = Read-Host "Ingrese el nombre del usuario a eliminar"

    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario no existe" -ForegroundColor Red
        return
    }

    Remove-LocalUser -Name $nombre

    $userHome = "$FTP_ROOT\LocalUser\$nombre"
    if (Test-Path $userHome) {
        foreach ($j in @("general", "reprobados", "recursadores", $nombre)) {
            if (Test-Path "$userHome\$j") { cmd /c "rmdir `"$userHome\$j`"" | Out-Null }
        }
        Remove-Item $userHome -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Item "$FTP_ROOT\Data\Usuarios\$nombre" -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc -Force
    Write-Host "Usuario '$nombre' eliminado correctamente" -ForegroundColor Green
    Log "Usuario eliminado: $nombre"
}

# ==============================================================================
#  9) CAMBIAR GRUPO DE USUARIO
# ==============================================================================
function Cambiar-GrupoUsuario {
    Write-Host ""
    Write-Host "***** Cambiar de grupo a usuario *****" -ForegroundColor Cyan

    $nombre = Read-Host "Ingrese el nombre del usuario"

    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario no existe" -ForegroundColor Red
        return
    }

    $nuevoGrupo = Read-Host "Ingrese el nuevo grupo (reprobados/recursadores)"

    if ($nuevoGrupo -ne "reprobados" -and $nuevoGrupo -ne "recursadores") {
        Write-Host "Grupo invalido" -ForegroundColor Red
        return
    }

    $enReprobados   = Get-LocalGroupMember -Group "reprobados"   -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$nombre" }
    $enRecursadores = Get-LocalGroupMember -Group "recursadores" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$nombre" }

    if     ($enReprobados)   { $grupoActual = "reprobados"   }
    elseif ($enRecursadores) { $grupoActual = "recursadores" }
    else { Write-Host "No se pudo determinar el grupo actual" -ForegroundColor Red; return }

    if ($grupoActual -eq $nuevoGrupo) {
        Write-Host "El usuario ya pertenece al grupo '$nuevoGrupo'" -ForegroundColor Yellow
        return
    }

    Remove-LocalGroupMember -Group $grupoActual -Member $nombre -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $nuevoGrupo  -Member $nombre -ErrorAction SilentlyContinue

    $userHome = "$FTP_ROOT\LocalUser\$nombre"

    if (Test-Path "$userHome\$grupoActual") { cmd /c "rmdir `"$userHome\$grupoActual`"" | Out-Null }
    cmd /c "mklink /J `"$userHome\$nuevoGrupo`" `"$FTP_ROOT\$nuevoGrupo`"" | Out-Null

    iisreset /noforce | Out-Null

    Write-Host "Grupo de '$nombre' cambiado: '$grupoActual' -> '$nuevoGrupo'" -ForegroundColor Green
    Log "Grupo cambiado: $nombre de $grupoActual a $nuevoGrupo"
}

# ==============================================================================
#  10) VER USUARIOS FTP
# ==============================================================================
function Ver-Usuarios {
    Write-Host ""
    Write-Host "Usuarios FTP registrados:" -ForegroundColor Cyan
    Write-Host ""

    Get-LocalGroupMember -Group "ftpusuarios" -ErrorAction SilentlyContinue | ForEach-Object {
        $u = $_.Name.Split("\")[-1]
        $grupo = "sin grupo"
        if (Get-LocalGroupMember -Group "reprobados"   -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$u" }) { $grupo = "reprobados" }
        elseif (Get-LocalGroupMember -Group "recursadores" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*\$u" }) { $grupo = "recursadores" }
        Write-Host "  Usuario: $u  |  Grupo: $grupo"
    }
}

# ==============================================================================
#  11) ESTADO DEL SERVIDOR
# ==============================================================================
function Estado-Servidor {
    Write-Host ""
    Write-Host "Estado del servicio FTP:" -ForegroundColor Cyan
    Get-Service ftpsvc | Format-Table Name, Status, StartType -AutoSize
    Write-Host "Puerto 21:" -ForegroundColor Cyan
    netstat -an | findstr ":21"
}

# ==============================================================================
#  12) REINICIAR FTP
# ==============================================================================
function Reiniciar-FTP {
    Restart-Service ftpsvc -Force
    Write-Host "Servicio FTP reiniciado" -ForegroundColor Green
    Log "FTP reiniciado"
}

# ==============================================================================
#  MENU PRINCIPAL
# ==============================================================================
function Menu {
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    while ($true) {
        Write-Host ""
        Write-Host "****** Tarea 5: Automatizacion de Servidor FTP ********" -ForegroundColor White
        Write-Host "***** Menu FTP *****" -ForegroundColor Cyan
        Write-Host "1)  Instalar servicio FTP (IIS)"
        Write-Host "2)  Configurar Firewall"
        Write-Host "3)  Crear grupos"
        Write-Host "4)  Crear estructura de directorios"
        Write-Host "5)  Asignar permisos base"
        Write-Host "6)  Configurar sitio FTP en IIS"
        Write-Host "7)  Crear usuarios"
        Write-Host "8)  Eliminar usuario"
        Write-Host "9)  Cambiar grupo de usuario"
        Write-Host "10) Ver usuarios FTP"
        Write-Host "11) Estado del servidor"
        Write-Host "12) Reiniciar FTP"
        Write-Host "0)  Salir"

        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {
            "1"  { Instalar-FTP        }
            "2"  { Configurar-Firewall  }
            "3"  { Crear-Grupos        }
            "4"  { Crear-Estructura    }
            "5"  { Asignar-Permisos    }
            "6"  { Configurar-FTP      }
            "7"  { Crear-Usuarios      }
            "8"  { Eliminar-Usuario    }
            "9"  { Cambiar-GrupoUsuario }
            "10" { Ver-Usuarios        }
            "11" { Estado-Servidor     }
            "12" { Reiniciar-FTP       }
            "0"  { exit 0              }
            default { Write-Host "Opcion invalida" -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

Menu
