# ==============================================================================
#  Tarea 5: Automatizacion de Servidor FTP - Windows Server 2019 (Sin GUI)
#  Equivalente al script bash original hecho para Oracle Linux Server 10.0
#  Requiere ejecutarse como Administrador (equivalente a root en Linux)
# ==============================================================================

#region ── Verificar privilegios de Administrador (equivalente a $EUID -ne 0) ──
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "El script debe ejecutarse como Administrador :D" -ForegroundColor Red
    exit 1
}
#endregion

# ── Ruta base FTP (equivalente a /ftp en Linux) ───────────────────────────────
$FTP_ROOT = "C:\ftp"

# ==============================================================================
#  FUNCIONES AUXILIARES
# ==============================================================================

#region ── Configurar Firewall (equivalente a configurar_firewall con firewall-cmd) ──
function Configurar-Firewall {
    Write-Host "Configurando Windows Firewall para FTP..." -ForegroundColor Cyan

    # Puerto 21 FTP Control
    if (-not (Get-NetFirewallRule -DisplayName "FTP - Control (TCP-In)" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP - Control (TCP-In)" `
            -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
    }

    # Puertos pasivos 40000-40100 (equivalente a --add-port=40000-40100/tcp)
    if (-not (Get-NetFirewallRule -DisplayName "FTP - Pasivo (TCP-In)" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP - Pasivo (TCP-In)" `
            -Direction Inbound -Protocol TCP -LocalPort 40000-40100 -Action Allow | Out-Null
    }

    Write-Host "Firewall configurado para FTP" -ForegroundColor Green
}
#endregion

#region ── Instalar FTP (equivalente a instalar_ftp con dnf install vsftpd) ──
function Instalar-FTP {
    Write-Host ""
    Write-Host "Verificando si el rol IIS/FTP esta instalado....." -ForegroundColor Cyan
    Write-Host ""

    $webServer = Get-WindowsFeature -Name Web-Server
    $ftpServer = Get-WindowsFeature -Name Web-Ftp-Server
    $ftpService = Get-WindowsFeature -Name Web-Ftp-Service

    $yaInstalado = ($webServer.Installed -and $ftpServer.Installed -and $ftpService.Installed)

    if ($yaInstalado) {
        Write-Host "El servicio FTP (IIS) ya esta instalado :D" -ForegroundColor Green

        # Equivalente al bucle while con read -p "Desea reinstalarlo (s/n)?"
        do {
            $opcion = Read-Host "Desea reinstalarlo (s/n)?"
            switch ($opcion.ToLower()) {
                "s" {
                    Write-Host "Reinstalando el servicio FTP (IIS)...." -ForegroundColor Yellow
                    Uninstall-WindowsFeature -Name Web-Ftp-Server, Web-Ftp-Service -ErrorAction SilentlyContinue | Out-Null
                    Install-WindowsFeature -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service `
                        -IncludeManagementTools | Out-Null
                    Write-Host ""
                    Write-Host "Reinstalacion completada :D" -ForegroundColor Green
                    $continuar = $true
                }
                "n" {
                    Write-Host "No se realizara ninguna accion" -ForegroundColor Yellow
                    $continuar = $true
                }
                default {
                    Write-Host "Opcion invalida... ingrese s o n" -ForegroundColor Red
                    $continuar = $false
                }
            }
        } while (-not $continuar)

    } else {
        Write-Host "El servicio FTP (IIS) no esta instalado" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Instalando....." -ForegroundColor Cyan

        # Equivalente a: dnf install -y vsftpd && dnf install -y acl
        $result = Install-WindowsFeature -Name Web-Server, Web-Ftp-Server, Web-Ftp-Service `
            -IncludeManagementTools

        if ($result.Success) {
            Write-Host "Instalacion completada :D" -ForegroundColor Green
        } else {
            Write-Host "Hubo un error en la instalacion." -ForegroundColor Red
        }
    }

    # Equivalente a: systemctl enable vsftpd && systemctl start vsftpd
    $ftpSvc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($ftpSvc) {
        if ($ftpSvc.StartType -ne "Automatic") {
            Set-Service -Name "ftpsvc" -StartupType Automatic
            Write-Host "Servicio FTP configurado para inicio automatico" -ForegroundColor Green
        }
        if ($ftpSvc.Status -ne "Running") {
            Start-Service -Name "ftpsvc"
            Write-Host "Servicio FTP iniciado" -ForegroundColor Green
        }
    }

    Configurar-Firewall
    Read-Host "Presione ENTER para continuar..."
}
#endregion

#region ── Configurar FTP (equivalente a configurarftp / vsftpd.conf) ──
function Configurar-FTP {
    Write-Host ""
    Write-Host "Configurando sitio FTP en IIS..." -ForegroundColor Cyan

    # Cargar modulo IIS WebAdministration (equivalente a editar vsftpd.conf)
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $siteName  = "FTP_Tarea5"
    $ftpPath   = "$FTP_ROOT\public"
    $bindIP    = "*"
    $bindPort  = 21

    # Crear directorio raiz si no existe
    if (-not (Test-Path $ftpPath)) {
        New-Item -ItemType Directory -Path $ftpPath -Force | Out-Null
    }

    # Eliminar sitio previo si existe (equivalente a cp -n vsftpd.conf.bak antes de reconfigurar)
    if (Get-WebSite -Name $siteName -ErrorAction SilentlyContinue) {
        Remove-WebSite -Name $siteName
    }

    # Crear sitio FTP (equivalente a configurar vsftpd.conf desde cero)
    New-WebFtpSite -Name $siteName -PhysicalPath $ftpPath -Port $bindPort -Force | Out-Null

    # ── anonymous_enable=YES (acceso anonimo permitido para lectura) ───────────
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

    # ── local_enable=YES (autenticacion de usuarios locales) ──────────────────
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # ── SSL desactivado (equivalente a ssl_enable=NO por defecto en vsftpd) ───
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.security.ssl.dataChannelPolicy    -Value "SslAllow"

    # ── Rango de puertos pasivos 40000-40100 (equivalente a pasv_min/max_port) ─
    $configPath = "MACHINE/WEBROOT/APPHOST"
    Set-WebConfigurationProperty -PSPath $configPath `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "lowDataChannelPort"  -Value 40000
    Set-WebConfigurationProperty -PSPath $configPath `
        -Filter "system.ftpServer/firewallSupport" `
        -Name "highDataChannelPort" -Value 40100

    # ── Aislar usuarios en su propio directorio (equivalente a chroot_local_user=YES) ─
    Set-ItemProperty "IIS:\Sites\$siteName" -Name ftpServer.userIsolation.mode -Value 3
    # Modo 3 = IsolateRootDirectoryOnly (chroot al home del usuario)

    # ── hide_ids=YES: ocultar UIDs/GIDs reales ────────────────────────────────
    # En IIS FTP esto es comportamiento por defecto (no expone SIDs)

    # ── Permisos anonimos: solo lectura, sin upload ni mkdir ─────────────────
    # (equivalente a anon_upload_enable=NO, anon_mkdir_write_enable=NO)
    Add-WebConfiguration -PSPath "IIS:\Sites\$siteName" `
        -Filter "ftpServer/authorization" `
        -Value @{accessType="Allow"; users="*"; roles=""; permissions="Read"} `
        -ErrorAction SilentlyContinue

    # ── Reiniciar servicio (equivalente a systemctl restart vsftpd) ───────────
    Restart-WebItem "IIS:\Sites\$siteName" -ErrorAction SilentlyContinue
    Restart-Service -Name "ftpsvc" -Force

    Write-Host "Configuracion FTP completada" -ForegroundColor Green
}
#endregion

#region ── Crear grupos (equivalente a groupadd reprobados/recursadores/ftpusuarios) ──
function Crear-Grupos {
    $grupos = @("reprobados", "recursadores", "ftpusuarios")

    foreach ($grupo in $grupos) {
        $existente = Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue
        if ($existente) {
            Write-Host "El grupo '$grupo' ya existe" -ForegroundColor Yellow
        } else {
            Write-Host "Creando grupo '$grupo'...." -ForegroundColor Cyan
            New-LocalGroup -Name $grupo -Description "Grupo FTP $grupo" | Out-Null
            Write-Host "Grupo '$grupo' creado" -ForegroundColor Green
        }
    }
}
#endregion

#region ── Crear estructura de directorios (equivalente a crear_estructura) ──
function Crear-Estructura {
    Write-Host ""
    Write-Host "Creando estructura de directorios FTP..." -ForegroundColor Cyan

    # Equivalente a: mkdir -p /ftp/public/general
    New-Item -ItemType Directory -Path "$FTP_ROOT\public\general"       -Force | Out-Null
    # Equivalente a: mkdir -p /ftp/users/{reprobados,recursadores}
    New-Item -ItemType Directory -Path "$FTP_ROOT\users\reprobados"     -Force | Out-Null
    New-Item -ItemType Directory -Path "$FTP_ROOT\users\recursadores"   -Force | Out-Null
    # Equivalente a: mkdir -p /ftp/general
    New-Item -ItemType Directory -Path "$FTP_ROOT\general"              -Force | Out-Null

    # Equivalente a: mount --bind /ftp/public/general /ftp/general
    # En Windows se usa Junction (mklink /J) en lugar de bind mounts
    if (-not (Test-Path "$FTP_ROOT\general\*") -and
        (Get-Item "$FTP_ROOT\general" -ErrorAction SilentlyContinue).LinkType -ne "Junction") {
        Remove-Item "$FTP_ROOT\general" -Force -ErrorAction SilentlyContinue
        cmd /c "mklink /J `"$FTP_ROOT\general`" `"$FTP_ROOT\public\general`"" | Out-Null
    }

    # Equivalente a: ln -sfn /ftp/users/reprobados /ftp/reprobados
    # En Windows: Junction point en lugar de symlink de directorio
    foreach ($grupo in @("reprobados", "recursadores")) {
        $junctionPath = "$FTP_ROOT\$grupo"
        $targetPath   = "$FTP_ROOT\users\$grupo"
        if (Test-Path $junctionPath) {
            Remove-Item $junctionPath -Force -ErrorAction SilentlyContinue
        }
        cmd /c "mklink /J `"$junctionPath`" `"$targetPath`"" | Out-Null
    }

    # Permisos base (equivalente a chmod 755 /ftp y /ftp/public)
    icacls "$FTP_ROOT"         /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Users:(OI)(CI)RX" | Out-Null
    icacls "$FTP_ROOT\public"  /inheritance:r /grant "Administrators:(OI)(CI)F" "SYSTEM:(OI)(CI)F" "Users:(OI)(CI)RX" | Out-Null

    # chmod 775 /ftp/public/general (equivalente: grupo ftpusuarios puede escribir)
    icacls "$FTP_ROOT\public\general" /inheritance:r `
        /grant "Administrators:(OI)(CI)F" `
               "SYSTEM:(OI)(CI)F" `
               "ftpusuarios:(OI)(CI)M" `
               "Users:(OI)(CI)RX" | Out-Null

    Write-Host "Estructura creada correctamente" -ForegroundColor Green
}
#endregion

#region ── Asignar permisos base (equivalente a asignar_permisos con chown/chmod/setfacl) ──
function Asignar-Permisos {
    Write-Host ""
    Write-Host "Asignando permisos base..." -ForegroundColor Cyan

    # chown root:root /ftp && chmod 755 /ftp
    icacls "$FTP_ROOT" /inheritance:r `
        /grant "Administrators:(OI)(CI)F" `
               "SYSTEM:(OI)(CI)F" `
               "Users:(OI)(CI)RX" | Out-Null

    # chmod 755 /ftp/users
    icacls "$FTP_ROOT\users" /inheritance:r `
        /grant "Administrators:(OI)(CI)F" `
               "SYSTEM:(OI)(CI)F" `
               "Users:(OI)(CI)RX" | Out-Null

    # chown root:reprobados /ftp/users/reprobados && chmod 2770
    # (SGID en Windows = herencia de grupo via ACL con herencia activada)
    icacls "$FTP_ROOT\users\reprobados" /inheritance:r `
        /grant "Administrators:(OI)(CI)F" `
               "SYSTEM:(OI)(CI)F" `
               "reprobados:(OI)(CI)M" | Out-Null

    # chown root:recursadores /ftp/users/recursadores && chmod 2770
    icacls "$FTP_ROOT\users\recursadores" /inheritance:r `
        /grant "Administrators:(OI)(CI)F" `
               "SYSTEM:(OI)(CI)F" `
               "recursadores:(OI)(CI)M" | Out-Null

    # chown root:ftpusuarios /ftp/public/general && chmod 775
    # + setfacl -m g:ftpusuarios:rwx /ftp/public/general
    icacls "$FTP_ROOT\public\general" /inheritance:r `
        /grant "Administrators:(OI)(CI)F" `
               "SYSTEM:(OI)(CI)F" `
               "ftpusuarios:(OI)(CI)M" `
               "Users:(OI)(CI)RX" | Out-Null

    # setfacl -m u:ftp:rx /ftp /ftp/public /ftp/public/general
    # En Windows: el usuario IUSR es el equivalente al usuario "ftp" anonimo de vsftpd
    foreach ($path in @($FTP_ROOT, "$FTP_ROOT\public", "$FTP_ROOT\public\general")) {
        icacls $path /grant "IUSR:(OI)(CI)RX" | Out-Null
    }

    Write-Host "Permisos base asignados correctamente" -ForegroundColor Green
}
#endregion

#region ── Crear usuarios (equivalente a crear_usuarios con useradd/chpasswd/mount --bind) ──
function Crear-Usuarios {
    $cantidad = Read-Host "Ingrese el numero de usuarios a capturar"

    for ($i = 1; $i -le [int]$cantidad; $i++) {
        Write-Host ""
        Write-Host "Usuario $i" -ForegroundColor Cyan

        $nombre = Read-Host "Nombre de usuario"

        # Equivalente a: id "$nombre" &>/dev/null
        if (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue) {
            Write-Host "El usuario ya existe" -ForegroundColor Yellow
            continue
        }

        $passwordRaw = Read-Host "Contrasena"
        $grupo       = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo invalido" -ForegroundColor Red
            continue
        }

        $password = ConvertTo-SecureString $passwordRaw -AsPlainText -Force
        $homeDir  = "$FTP_ROOT\users\$nombre"

        # Equivalente a: useradd -m -d /ftp/users/$nombre -s /bin/bash -g "$grupo" -G ftpusuarios "$nombre"
        # Nota: -PasswordNeverExpires y -UserMayNotChangePassword se aplican via Set-LocalUser
        # para evitar el error "positional parameter cannot be found" en WS2019
        New-LocalUser -Name $nombre `
                      -Password $password `
                      -Description "Usuario FTP Tarea5" | Out-Null

        Set-LocalUser -Name $nombre `
                      -PasswordNeverExpires $true `
                      -UserMayChangePassword $false

        Add-LocalGroupMember -Group $grupo          -Member $nombre -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group "ftpusuarios"   -Member $nombre -ErrorAction SilentlyContinue

        # Esperar a que el sistema registre el SID del usuario nuevo
        # antes de llamar a icacls (evita "No mapping between account names and SIDs")
        Start-Sleep -Seconds 2

        # Equivalente a: mkdir -p /ftp/users/$nombre/{general,$grupo,$nombre}
        New-Item -ItemType Directory -Path "$homeDir\general" -Force | Out-Null
        New-Item -ItemType Directory -Path "$homeDir\$grupo"  -Force | Out-Null
        New-Item -ItemType Directory -Path "$homeDir\$nombre" -Force | Out-Null

        # Equivalente a: mount --bind /ftp/public/general /ftp/users/$nombre/general
        $jGeneral = "$homeDir\general"
        Remove-Item $jGeneral -Force -ErrorAction SilentlyContinue
        cmd /c "mklink /J `"$jGeneral`" `"$FTP_ROOT\public\general`"" | Out-Null

        # Equivalente a: mount --bind /ftp/users/$grupo /ftp/users/$nombre/$grupo
        $jGrupo = "$homeDir\$grupo"
        Remove-Item $jGrupo -Force -ErrorAction SilentlyContinue
        cmd /c "mklink /J `"$jGrupo`" `"$FTP_ROOT\users\$grupo`"" | Out-Null

        # Equivalente a: chown -R $nombre:$grupo /ftp/users/$nombre/$nombre && chmod 700
        icacls "$homeDir\$nombre" /inheritance:r `
            /grant "${nombre}:(OI)(CI)F" `
                   "Administrators:(OI)(CI)F" `
                   "SYSTEM:(OI)(CI)F" | Out-Null

        # Equivalente a: chown :$grupo /ftp/users/$nombre/$grupo && chmod 775
        icacls "$homeDir\$grupo" /inheritance:r `
            /grant "${grupo}:(OI)(CI)M" `
                   "Administrators:(OI)(CI)F" `
                   "SYSTEM:(OI)(CI)F" | Out-Null

        # Permisos sobre el home raiz del usuario (para que IIS FTP pueda leer)
        icacls "$homeDir" /inheritance:r `
            /grant "${nombre}:(OI)(CI)RX" `
                   "Administrators:(OI)(CI)F" `
                   "SYSTEM:(OI)(CI)F" `
                   "IUSR:(OI)(CI)RX" | Out-Null

        # Registrar el home del usuario en IIS para aislamiento de usuarios
        # Equivalente a chroot_local_user=YES: IIS FTP modo 3 usa %FTP_ROOT%\LocalUser\$nombre
        $iisHome = "$FTP_ROOT\LocalUser\$nombre"
        if (-not (Test-Path $iisHome)) {
            New-Item -ItemType Directory -Path $iisHome -Force | Out-Null
            # Crear Junction desde el home IIS al home real del usuario
            Remove-Item $iisHome -Force -ErrorAction SilentlyContinue
            cmd /c "mklink /J `"$iisHome`" `"$homeDir`"" | Out-Null
        }

        Write-Host "Usuario $nombre creado correctamente" -ForegroundColor Green
    }
}
#endregion

#region ── Cambiar grupo de usuario (equivalente a cambiar_grupo_usuario / usermod -g) ──
function Cambiar-GrupoUsuario {
    Write-Host ""
    Write-Host "***** Cambiar de grupo a usuario *****" -ForegroundColor Cyan

    $nombre = Read-Host "Ingrese el nombre del usuario"

    # Equivalente a: id "$nombre" &>/dev/null
    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario no existe" -ForegroundColor Red
        return
    }

    $nuevoGrupo = Read-Host "Ingrese el nuevo grupo (reprobados/recursadores)"

    if ($nuevoGrupo -ne "reprobados" -and $nuevoGrupo -ne "recursadores") {
        Write-Host "Grupo invalido" -ForegroundColor Red
        return
    }

    # Detectar grupo actual (equivalente a: grupo_actual=$(id -gn $nombre))
    $gruposActuales = (Get-LocalGroupMember -Group "reprobados" -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -like "*\$nombre" }) -ne $null

    if ($gruposActuales) { $grupoActual = "reprobados" } else { $grupoActual = "recursadores" }

    # Verificar si ya pertenece al grupo destino
    $yaEnGrupo = Get-LocalGroupMember -Group $nuevoGrupo -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -like "*\$nombre" }

    if ($yaEnGrupo) {
        Write-Host "El usuario ya pertenece a ese grupo" -ForegroundColor Yellow
        return
    }

    # Equivalente a: usermod -g "$nuevo_grupo" "$nombre"
    Remove-LocalGroupMember -Group $grupoActual -Member $nombre -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $nuevoGrupo  -Member $nombre -ErrorAction SilentlyContinue

    $homeDir = "$FTP_ROOT\users\$nombre"

    # Equivalente a: chown -R $nombre:$nuevo_grupo /ftp/users/$nombre
    icacls $homeDir /setowner $nombre /T /Q | Out-Null

    # Equivalente a: umount -l /ftp/users/$nombre/$grupo_actual && rm -rf ...
    $jGrupoViejo = "$homeDir\$grupoActual"
    if (Test-Path $jGrupoViejo) {
        # Eliminar junction (equivalente a umount + rm)
        cmd /c "rmdir `"$jGrupoViejo`"" | Out-Null
    }

    # Equivalente a: mkdir -p + mount --bind del nuevo grupo
    $jGrupoNuevo = "$homeDir\$nuevoGrupo"
    if (-not (Test-Path $jGrupoNuevo)) {
        New-Item -ItemType Directory -Path $jGrupoNuevo -Force | Out-Null
    }
    Remove-Item $jGrupoNuevo -Force -ErrorAction SilentlyContinue
    cmd /c "mklink /J `"$jGrupoNuevo`" `"$FTP_ROOT\users\$nuevoGrupo`"" | Out-Null

    # Equivalente a: chown :$nuevo_grupo ... && chmod 775
    icacls $jGrupoNuevo /inheritance:r `
        /grant "${nuevoGrupo}:(OI)(CI)M" `
               "Administrators:(OI)(CI)F" `
               "SYSTEM:(OI)(CI)F" | Out-Null

    Write-Host "Grupo del usuario actualizado correctamente" -ForegroundColor Green
}
#endregion

# ==============================================================================
#  MENU PRINCIPAL (equivalente a la funcion menu() del script bash)
# ==============================================================================
function Menu {
    Write-Host ""
    while ($true) {
        Write-Host ""
        Write-Host "****** Tarea 5: Automatizacion de Servidor FTP ********" -ForegroundColor White
        Write-Host "***** Menu FTP *****"                                    -ForegroundColor White
        Write-Host "1) Instalar servicio FTP (IIS FTP)"
        Write-Host "2) Configurar IIS FTP (sitio + puertos pasivos)"
        Write-Host "3) Crear grupos (reprobados, recursadores, ftpusuarios)"
        Write-Host "4) Crear estructura base de directorios"
        Write-Host "5) Asignar permisos base"
        Write-Host "6) Crear usuarios"
        Write-Host "7) Cambiar grupo de usuario"
        Write-Host "0) Salir"

        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {
            "1" { Instalar-FTP         }
            "2" { Configurar-FTP       }
            "3" { Crear-Grupos         }
            "4" { Crear-Estructura     }
            "5" { Asignar-Permisos     }
            "6" { Crear-Usuarios       }
            "7" { Cambiar-GrupoUsuario }
            "0" { exit 0               }
            default {
                Write-Host "Opcion invalida" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ── Punto de entrada ──────────────────────────────────────────────────────────
Menu
