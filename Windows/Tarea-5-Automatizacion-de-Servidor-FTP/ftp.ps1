# ============================================================
#  Script de Automatizacion FTP - Windows Server 2019 (No GUI)
#  Tarea 5 - Servidor FTP con IIS
# ============================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Configurar-Firewall {
    if (-not (Get-NetFirewallRule -DisplayName "FTP Server Port 21" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Server Port 21" -Direction Inbound -LocalPort 21 -Protocol TCP -Action Allow
    }
    if (-not (Get-NetFirewallRule -DisplayName "FTP Passive Port Range" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP Passive Port Range" -Direction Inbound -LocalPort 40000-40100 -Protocol TCP -Action Allow
    }
    Write-Host "Firewall configurado para FTP." -ForegroundColor Green
}

function Instalar-FTP {
    Write-Host "`nVerificando si IIS + FTP estan instalados...`n"

    $features = @("Web-Server","Web-FTP-Server","Web-FTP-Service","Web-FTP-Ext")

    foreach ($feature in $features) {
        $estado = Get-WindowsFeature $feature
        if (-not $estado.Installed) {
            Write-Host "Instalando $feature ..."
            Install-WindowsFeature $feature -IncludeManagementTools
        } else {
            Write-Host "$feature ya esta instalado."
        }
    }

    Write-Host "`nIniciando servicios..."
    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Set-Service ftpsvc -StartupType Automatic
    Start-Service W3SVC -ErrorAction SilentlyContinue
    Set-Service W3SVC -StartupType Automatic

    Configurar-Firewall
    Write-Host "`nInstalacion de IIS + FTP completada." -ForegroundColor Green
}

function Configurar-FTP {
    Import-Module WebAdministration

    $ftpSiteName = "FTP_Servidor"
    $ftpRoot     = "C:\ftp"

    # ── Carpeta raíz ──────────────────────────────────────────────────────────
    if (-not (Test-Path $ftpRoot)) {
        New-Item -Path $ftpRoot -ItemType Directory | Out-Null
    }

    # ── Eliminar sitio previo ─────────────────────────────────────────────────
    if (Get-WebSite -Name $ftpSiteName -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSiteName
    }

    Write-Host "Creando sitio FTP..."
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $ftpRoot -Force

    # ── Autenticación ─────────────────────────────────────────────────────────
    Write-Host "Configurando autenticacion..."

    # Anónimo: se usa la cuenta IUSR del sistema (NO dejar vacío)
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.authentication.anonymousAuthentication.userName -Value "IUSR"

    # Básica (usuarios locales con contraseña)
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # ── Aislamiento de usuarios ───────────────────────────────────────────────
    # Modo 3 = IsolateRootDirectoryOnly  →  cada usuario ve SOLO su home
    # Modo 0 = sin aislamiento (todos ven C:\ftp completo) — NO usar
    Write-Host "Configurando aislamiento de usuarios..."
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.userIsolation.mode -Value 1

    # ── Puertos pasivos ───────────────────────────────────────────────────────
    Write-Host "Configurando puertos pasivos..."
    C:\Windows\System32\inetsrv\appcmd.exe set config `
        -section:system.ftpServer/firewallSupport `
        /lowDataChannelPort:40000 /highDataChannelPort:40100 /commit:apphost

    # ── SSL (desactivado para lab) ────────────────────────────────────────────
    Write-Host "Desactivando SSL obligatorio..."
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" `
        -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

    # ── Reglas de autorización ────────────────────────────────────────────────
    Write-Host "Configurando reglas de acceso..."
    Clear-WebConfiguration -Filter "system.ftpServer/security/authorization" `
        -PSPath IIS:\ -Location $ftpSiteName

    # '?' = usuarios anónimos  → solo lectura
    Add-WebConfiguration `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath IIS:\ -Location $ftpSiteName `
        -Value @{accessType="Allow"; users="?"; permissions="Read"}

    # Grupo ftpusuarios (todos los users autenticados) → lectura + escritura
    Add-WebConfiguration `
        -Filter "system.ftpServer/security/authorization" `
        -PSPath IIS:\ -Location $ftpSiteName `
        -Value @{accessType="Allow"; roles="ftpusuarios"; permissions="Read,Write"}

    # ── CORRECCIÓN CRÍTICA: Directorio virtual para acceso anónimo ────────────
    # El usuario anónimo necesita un "home" bajo LocalUser\Public
    # IIS FTP con aislamiento busca:  <ftpRoot>\LocalUser\<username>
    # Para anónimo busca:             <ftpRoot>\LocalUser\Public
    $anonHome = "$ftpRoot\LocalUser\Public"
    if (-not (Test-Path $anonHome)) {
        New-Item -Path $anonHome -ItemType Directory | Out-Null
        Write-Host "Carpeta home del anonimo creada: $anonHome"
    }

    # Dentro del home anónimo creamos un acceso directo (junction) a \general
    # para que el anónimo vea la carpeta 'general' al conectarse
    $generalReal    = "$ftpRoot\general"
    $generalEnAnon  = "$anonHome\general"

    if (-not (Test-Path $generalReal)) {
        New-Item -Path $generalReal -ItemType Directory | Out-Null
    }
    if (-not (Test-Path $generalEnAnon)) {
        New-Item -Path $generalEnAnon -ItemType Junction -Value $generalReal | Out-Null
        Write-Host "Junction creado: $generalEnAnon -> $generalReal"
    }

    # ── Permisos NTFS para IUSR sobre el home anónimo ────────────────────────
    icacls $anonHome /grant:r "IUSR:(OI)(CI)RX"   2>&1 | Out-Null
    icacls $anonHome /grant:r "IIS_IUSRS:(OI)(CI)RX" 2>&1 | Out-Null
    icacls $generalReal /grant:r "IUSR:(OI)(CI)RX"   2>&1 | Out-Null
    icacls $generalReal /grant:r "IIS_IUSRS:(OI)(CI)RX" 2>&1 | Out-Null

    Restart-Service ftpsvc -Force
    Write-Host "FTP configurado correctamente." -ForegroundColor Green
}

function Crear-Grupos {
    $grupos = @("reprobados", "recursadores", "ftpusuarios")
    foreach ($nombre in $grupos) {
        if (-not (Get-LocalGroup -Name $nombre -ErrorAction SilentlyContinue)) {
            Write-Host "Creando grupo $nombre..."
            New-LocalGroup -Name $nombre
        } else {
            Write-Host "El grupo $nombre ya existe."
        }
    }
    Write-Host "Grupos verificados." -ForegroundColor Green
}

function Crear-Estructura {
    $raiz = "C:\ftp"
    $subcarpetas = @("general","reprobados","recursadores")

    if (-not (Test-Path $raiz)) {
        New-Item -Path $raiz -ItemType Directory | Out-Null
    }

    foreach ($carpeta in $subcarpetas) {
        $path = Join-Path $raiz $carpeta
        if (-not (Test-Path $path)) {
            New-Item -Path $path -ItemType Directory | Out-Null
        }
    }

    # También asegurar que exista LocalUser\Public para el anónimo
    $anonHome = "$raiz\LocalUser\Public"
    if (-not (Test-Path $anonHome)) {
        New-Item -Path $anonHome -ItemType Directory -Force | Out-Null
    }

    Write-Host "Estructura base creada en $raiz" -ForegroundColor Green
}

function Asignar-Permisos {
    $raiz = "C:\ftp"

    # Raíz general
    icacls "$raiz" /grant:r "Administrators:(OI)(CI)F"  2>&1 | Out-Null
    icacls "$raiz" /grant:r "SYSTEM:(OI)(CI)F"          2>&1 | Out-Null
    icacls "$raiz" /grant:r "ftpusuarios:(OI)(CI)M"     2>&1 | Out-Null
    icacls "$raiz" /grant:r "Everyone:(OI)(CI)RX"       2>&1 | Out-Null

    # Carpetas de grupo
    foreach ($g in @("reprobados","recursadores")) {
        $path = "$raiz\$g"
        if (Test-Path $path) {
            icacls "$path" /inheritance:r `
                /grant:r "Administrators:(OI)(CI)F" `
                /grant:r "SYSTEM:(OI)(CI)F" `
                /grant:r "${g}:(OI)(CI)M"  2>&1 | Out-Null
        }
    }

    # Carpeta general: escritura para ftpusuarios, lectura para IUSR (anónimo)
    icacls "$raiz\general" /inheritance:r `
        /grant:r "Administrators:(OI)(CI)F" `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "ftpusuarios:(OI)(CI)M" `
        /grant:r "IUSR:(OI)(CI)RX" `
        /grant:r "IIS_IUSRS:(OI)(CI)RX"  2>&1 | Out-Null

    # Home del anónimo
    $anonHome = "$raiz\LocalUser\Public"
    if (Test-Path $anonHome) {
        icacls "$anonHome" /inheritance:r `
            /grant:r "Administrators:(OI)(CI)F" `
            /grant:r "SYSTEM:(OI)(CI)F" `
            /grant:r "IUSR:(OI)(CI)RX" `
            /grant:r "IIS_IUSRS:(OI)(CI)RX"  2>&1 | Out-Null
    }

    Write-Host "Permisos NTFS aplicados correctamente." -ForegroundColor Green
}

function Crear-Usuarios {
    $num = Read-Host "Ingrese el numero de usuarios a crear"

    for ($i = 1; $i -le $num; $i++) {
        Write-Host "`n--- Usuario $i ---"
        $nombre = Read-Host "Nombre de usuario"

        if (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue) {
            Write-Host "El usuario '$nombre' ya existe. Saltando..." -ForegroundColor Yellow
            continue
        }

        $pass   = Read-Host -AsSecureString "Contrasena"
        $grupo  = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo invalido. Saltando usuario..." -ForegroundColor Red
            continue
        }

        # Crear usuario local
        New-LocalUser -Name $nombre -Password $pass -FullName $nombre -Description "Usuario FTP"
        Add-LocalGroupMember -Group $grupo      -Member $nombre
        Add-LocalGroupMember -Group "ftpusuarios" -Member $nombre

        # ── Estructura de carpetas para este usuario ──────────────────────────
        # Con modo de aislamiento 3, IIS busca el home en:
        #   C:\ftp\LocalUser\<nombreDeUsuario>
        # Dentro de ese home creamos:
        #   general    → junction a C:\ftp\general
        #   <grupo>    → junction a C:\ftp\<grupo>
        #   <nombre>   → carpeta personal exclusiva

        $userHome      = "C:\ftp\LocalUser\$nombre"
        $userPersonal  = "$userHome\$nombre"
        $userGenJunc   = "$userHome\general"
        $userGrpJunc   = "$userHome\$grupo"

        New-Item -Path $userHome     -ItemType Directory -Force | Out-Null
        New-Item -Path $userPersonal -ItemType Directory -Force | Out-Null

        # Junction a general (carpeta publica compartida)
        if (-not (Test-Path $userGenJunc)) {
            New-Item -Path $userGenJunc -ItemType Junction -Value "C:\ftp\general" | Out-Null
        }

        # Junction a la carpeta del grupo
        if (-not (Test-Path $userGrpJunc)) {
            New-Item -Path $userGrpJunc -ItemType Junction -Value "C:\ftp\$grupo" | Out-Null
        }

        # Permisos NTFS sobre el home del usuario
        # IMPORTANTE: primero /grant, luego /inheritance:r
        # Si se rompe herencia antes de dar acceso, IIS no puede abrir el directorio (error 530)
        icacls $userHome /grant:r "${nombre}:(OI)(CI)M"      2>&1 | Out-Null
        icacls $userHome /grant:r "Administrators:(OI)(CI)F" 2>&1 | Out-Null
        icacls $userHome /grant:r "SYSTEM:(OI)(CI)F"         2>&1 | Out-Null
        icacls $userHome /grant:r "IIS_IUSRS:(OI)(CI)RX"     2>&1 | Out-Null
        icacls $userHome /inheritance:r                       2>&1 | Out-Null

        # Permisos sobre la carpeta personal
        icacls $userPersonal /grant:r "${nombre}:(OI)(CI)M"      2>&1 | Out-Null
        icacls $userPersonal /grant:r "Administrators:(OI)(CI)F" 2>&1 | Out-Null
        icacls $userPersonal /grant:r "SYSTEM:(OI)(CI)F"         2>&1 | Out-Null
        icacls $userPersonal /inheritance:r                       2>&1 | Out-Null

        Write-Host "Usuario '$nombre' creado. Estructura:" -ForegroundColor Green
        Write-Host "  $userHome\"
        Write-Host "    [+] general      (junction -> C:\ftp\general)"
        Write-Host "    [+] $grupo       (junction -> C:\ftp\$grupo)"
        Write-Host "    [+] $nombre      (carpeta personal)"
    }
}

function Cambiar-Grupo-Usuario {
    Write-Host "`n***** Cambiar de grupo a usuario *****"
    $nombre = Read-Host "Ingrese el nombre del usuario"

    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario '$nombre' no existe." -ForegroundColor Red
        return
    }

    $nuevo_grupo = Read-Host "Ingrese el nuevo grupo (reprobados/recursadores)"
    if ($nuevo_grupo -ne "reprobados" -and $nuevo_grupo -ne "recursadores") {
        Write-Host "Grupo invalido." -ForegroundColor Red
        return
    }

    # Determinar grupo actual y quitarlo
    foreach ($g in @("reprobados","recursadores")) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -like "*\$nombre" -or $_.Name -eq $nombre }) {
            if ($g -eq $nuevo_grupo) {
                Write-Host "El usuario ya pertenece al grupo '$nuevo_grupo'." -ForegroundColor Yellow
                return
            }
            Remove-LocalGroupMember -Group $g -Member $nombre -Confirm:$false
            Write-Host "Removido del grupo '$g'."

            # Eliminar la junction del grupo anterior en el home del usuario
            $juncAntigua = "C:\ftp\LocalUser\$nombre\$g"
            if (Test-Path $juncAntigua) {
                # Remove-Item sobre una junction elimina el enlace, NO el destino real
                Remove-Item -Path $juncAntigua -Force | Out-Null
                Write-Host "Junction al grupo anterior eliminada."
            }
        }
    }

    # Agregar al nuevo grupo
    Add-LocalGroupMember -Group $nuevo_grupo -Member $nombre

    # Crear junction al nuevo grupo en el home del usuario
    $juncNueva = "C:\ftp\LocalUser\$nombre\$nuevo_grupo"
    if (-not (Test-Path $juncNueva)) {
        New-Item -Path $juncNueva -ItemType Junction -Value "C:\ftp\$nuevo_grupo" | Out-Null
        Write-Host "Junction al nuevo grupo creada: $juncNueva"
    }

    Restart-Service ftpsvc -Force
    Write-Host "Grupo del usuario '$nombre' actualizado a '$nuevo_grupo'." -ForegroundColor Green
}

function Configurar-Seguridad {
    $ftpSiteName = "FTP_Servidor"
    Import-Module WebAdministration
    $rules = Get-WebConfiguration -Filter "/system.ftpServer/security/authorization/*" `
        -PSPath "IIS:\Sites\$ftpSiteName"

    if ($rules) {
        Write-Host "Seguridad FTP verificada: $($rules.Count) reglas activas." -ForegroundColor Green
    } else {
        Write-Host "ADVERTENCIA: No se detectaron reglas de seguridad en el sitio FTP." -ForegroundColor Yellow
    }
}

function Reparar-Usuarios {
    # Recorre todos los usuarios locales que pertenezcan a ftpusuarios
    # y recrea su estructura de carpetas + junctions si faltan
    Write-Host "`nReparando estructura de carpetas para todos los usuarios FTP..." -ForegroundColor Cyan

    $miembros = Get-LocalGroupMember -Group "ftpusuarios" -ErrorAction SilentlyContinue
    if (-not $miembros) {
        Write-Host "No hay usuarios en el grupo ftpusuarios." -ForegroundColor Yellow
        return
    }

    foreach ($m in $miembros) {
        # El nombre puede venir como "SERVIDOR\usuario" — extraer solo el nombre
        $nombre = $m.Name -replace ".*\\"

        # Determinar el grupo (reprobados o recursadores)
        $grupo = $null
        foreach ($g in @("reprobados","recursadores")) {
            $enGrupo = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -replace ".*\\" -eq $nombre }
            if ($enGrupo) { $grupo = $g; break }
        }

        if (-not $grupo) {
            Write-Host "  [!] $nombre - sin grupo asignado, saltando." -ForegroundColor Yellow
            continue
        }

        $userHome     = "C:\ftp\LocalUser\$nombre"
        $userPersonal = "$userHome\$nombre"
        $userGenJunc  = "$userHome\general"
        $userGrpJunc  = "$userHome\$grupo"

        # Crear directorios si faltan
        if (-not (Test-Path $userHome))     { New-Item -Path $userHome     -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path $userPersonal)) { New-Item -Path $userPersonal -ItemType Directory -Force | Out-Null }

        # Crear junctions si faltan
        if (-not (Test-Path $userGenJunc)) {
            New-Item -Path $userGenJunc -ItemType Junction -Value "C:\ftp\general" | Out-Null
        }
        if (-not (Test-Path $userGrpJunc)) {
            New-Item -Path $userGrpJunc -ItemType Junction -Value "C:\ftp\$grupo" | Out-Null
        }

        # Reasignar permisos NTFS (grant primero, inheritance:r al final)
        icacls $userHome /grant:r "${nombre}:(OI)(CI)M"      2>&1 | Out-Null
        icacls $userHome /grant:r "Administrators:(OI)(CI)F" 2>&1 | Out-Null
        icacls $userHome /grant:r "SYSTEM:(OI)(CI)F"         2>&1 | Out-Null
        icacls $userHome /grant:r "IIS_IUSRS:(OI)(CI)RX"     2>&1 | Out-Null
        icacls $userHome /inheritance:r                       2>&1 | Out-Null

        icacls $userPersonal /grant:r "${nombre}:(OI)(CI)M"      2>&1 | Out-Null
        icacls $userPersonal /grant:r "Administrators:(OI)(CI)F" 2>&1 | Out-Null
        icacls $userPersonal /grant:r "SYSTEM:(OI)(CI)F"         2>&1 | Out-Null
        icacls $userPersonal /inheritance:r                       2>&1 | Out-Null

        Write-Host "  [OK] $nombre ($grupo) - estructura reparada." -ForegroundColor Green
    }

    Restart-Service ftpsvc -Force
    Write-Host "Reparacion completada." -ForegroundColor Green
}

function Mostrar-Menu {
    while ($true) {
        Write-Host "`n======================================" -ForegroundColor Cyan
        Write-Host "   Menu FTP - Windows Server 2019    " -ForegroundColor Cyan
        Write-Host "======================================" -ForegroundColor Cyan
        Write-Host " 1) Instalar servicio FTP"
        Write-Host " 2) Configurar FTP"
        Write-Host " 3) Crear grupos"
        Write-Host " 4) Crear estructura base"
        Write-Host " 5) Asignar permisos base"
        Write-Host " 6) Crear usuarios"
        Write-Host " 7) Cambiar grupo de usuario"
        Write-Host " 8) Verificar seguridad"
        Write-Host " 9) Reparar estructura de usuarios existentes"
        Write-Host " 0) Salir"
        Write-Host "--------------------------------------"

        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {
            "1" { Instalar-FTP }
            "2" { Configurar-FTP }
            "3" { Crear-Grupos }
            "4" { Crear-Estructura }
            "5" { Asignar-Permisos }
            "6" { Crear-Usuarios }
            "7" { Cambiar-Grupo-Usuario }
            "8" { Configurar-Seguridad }
            "9" { Reparar-Usuarios }
            "0" { Write-Host "Saliendo..."; break }
            Default { Write-Host "Opcion invalida." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }

        if ($opcion -eq "0") { break }
    }
}

# ── Punto de entrada ──────────────────────────────────────────────────────────
Mostrar-Menu
