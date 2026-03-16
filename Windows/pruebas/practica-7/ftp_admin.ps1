# ============================================================
# ADMINISTRADOR SERVIDOR FTP - VERSION WINDOWS SERVER EN INGLES
# Windows Server 2016 / 2019 / 2022 (English, No GUI)
# ============================================================
#
# DIFERENCIAS CON VERSION EN ESPANOL:
# - IsolateAllDirectories en Windows EN busca el home en:
#   C:\Users\<NOMBRE_SERVIDOR>\<usuario>
#   NO en C:\Users\LocalUser\<usuario>
# - El anonimo usa: C:\Users\LocalUser\Public
# - La raiz del sitio FTP apunta a C:\Users
#
# ============================================================

Import-Module ServerManager
Import-Module WebAdministration

$ftpRoot    = "C:\Users"
$ftpData    = "C:\FTP_Data"
$ftpSite    = "FTP_SERVER"
$serverName = $env:COMPUTERNAME
$logFile    = "C:\FTP_Data\ftp_log.txt"

# ------------------------------------------------------------
# LOG
# ------------------------------------------------------------
function Log {
    param($msg)
    if (-not (Test-Path $ftpData)) {
        New-Item $ftpData -ItemType Directory -Force | Out-Null
    }
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content $logFile "$fecha - $msg"
}

# ------------------------------------------------------------
# INSTALAR FTP
# ------------------------------------------------------------
function Instalar-FTP {

    Write-Host "Instalando IIS + FTP..."

    $features = @(
        "Web-Server",
        "Web-FTP-Server",
        "Web-FTP-Service",
        "Web-FTP-Ext"
    )

    foreach ($f in $features) {
        if (!(Get-WindowsFeature $f).Installed) {
            Install-WindowsFeature $f -IncludeManagementTools
        }
    }

    Start-Service W3SVC
    Start-Service ftpsvc
    Set-Service ftpsvc -StartupType Automatic

    Write-Host "FTP instalado." -ForegroundColor Green
    Log "FTP instalado"
}

# ------------------------------------------------------------
# FIREWALL
# ------------------------------------------------------------
function Configurar-Firewall {

    Remove-NetFirewallRule -DisplayName "FTP 21"      -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -DisplayName "FTP Passive" -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "FTP 21" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 21 `
        -Action Allow

    New-NetFirewallRule `
        -DisplayName "FTP Passive" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 50000-51000 `
        -Action Allow

    Write-Host "Firewall configurado" -ForegroundColor Green
    Log "Firewall configurado"
}

# ------------------------------------------------------------
# CREAR GRUPOS
# ------------------------------------------------------------
function Crear-Grupos {

    $grupos = @("reprobados", "recursadores", "ftpusuarios")

    foreach ($g in $grupos) {
        if (!(Get-LocalGroup $g -ErrorAction SilentlyContinue)) {
            New-LocalGroup $g
            Write-Host "Grupo $g creado" -ForegroundColor Green
        } else {
            Write-Host "Grupo $g ya existe" -ForegroundColor Yellow
        }
    }

    Log "Grupos verificados/creados"
}

# ------------------------------------------------------------
# ESTRUCTURA BASE
# Raiz FTP = C:\Users  (requerido por IsolateAllDirectories en EN)
# Anonimo  = C:\Users\LocalUser\Public
# Datos compartidos = C:\FTP_Data\general, reprobados, recursadores
# ------------------------------------------------------------
function Crear-Estructura {

    # Carpetas de datos compartidos (fuera de C:\Users para no exponer el sistema)
    New-Item "$ftpData"                -ItemType Directory -Force | Out-Null
    New-Item "$ftpData\general"        -ItemType Directory -Force | Out-Null
    New-Item "$ftpData\reprobados"     -ItemType Directory -Force | Out-Null
    New-Item "$ftpData\recursadores"   -ItemType Directory -Force | Out-Null
    New-Item "$ftpData\usuarios"       -ItemType Directory -Force | Out-Null

    # Carpeta anonimo: C:\Users\LocalUser\Public
    New-Item "$ftpRoot\LocalUser\Public" -ItemType Directory -Force | Out-Null

    # Junction link de general en Public para acceso anonimo
    if (-not (Test-Path "$ftpRoot\LocalUser\Public\general")) {
        cmd /c mklink /J "$ftpRoot\LocalUser\Public\general" "$ftpData\general"
    }

    Write-Host "Estructura creada" -ForegroundColor Green
    Log "Estructura FTP creada"
}

# ------------------------------------------------------------
# PERMISOS
# S-1-5-18     = SYSTEM
# S-1-5-32-544 = BUILTIN\Administrators
# ------------------------------------------------------------
function Permisos {

    $sidSystem = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $cuentaSystem = $sidSystem.Translate([System.Security.Principal.NTAccount]).Value
    $cuentaAdmins = $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value

    # GENERAL - escritura para ftpusuarios, lectura para IUSR (anonimo)
    icacls "$ftpData\general" /inheritance:r
    icacls "$ftpData\general" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpData\general" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpData\general" /grant "ftpusuarios:(OI)(CI)M"
    icacls "$ftpData\general" /grant "IUSR:(OI)(CI)RX"

    # REPROBADOS - solo para grupo reprobados
    icacls "$ftpData\reprobados" /inheritance:r
    icacls "$ftpData\reprobados" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpData\reprobados" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpData\reprobados" /grant "reprobados:(OI)(CI)M"

    # RECURSADORES - solo para grupo recursadores
    icacls "$ftpData\recursadores" /inheritance:r
    icacls "$ftpData\recursadores" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpData\recursadores" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpData\recursadores" /grant "recursadores:(OI)(CI)M"

    # PUBLIC - lectura para IUSR (anonimo)
    icacls "$ftpRoot\LocalUser\Public" /inheritance:r
    icacls "$ftpRoot\LocalUser\Public" /grant "$cuentaAdmins`:(OI)(CI)F"
    icacls "$ftpRoot\LocalUser\Public" /grant "$cuentaSystem`:(OI)(CI)F"
    icacls "$ftpRoot\LocalUser\Public" /grant "IUSR:(OI)(CI)RX"

    Write-Host "Permisos aplicados correctamente" -ForegroundColor Green
    Log "Permisos aplicados"
}

# ------------------------------------------------------------
# CONFIGURAR FTP
#
# IMPORTANTE (Windows Server EN):
# IsolateAllDirectories busca el home del usuario en:
#   <ftpRoot>\<NOMBRE_SERVIDOR>\<usuario>
# Por eso ftpRoot = C:\Users y el home queda en:
#   C:\Users\<NOMBRE_SERVIDOR>\<usuario>
#
# El anonimo usa:
#   C:\Users\LocalUser\Public
# ------------------------------------------------------------
function Configurar-FTP {

    Import-Module WebAdministration

    # Eliminar sitio previo si existe
    if (Get-WebSite $ftpSite -ErrorAction SilentlyContinue) {
        Remove-WebSite $ftpSite
    }

    # Crear sitio FTP apuntando a C:\Users
    New-WebFtpSite `
        -Name $ftpSite `
        -Port 21 `
        -PhysicalPath $ftpRoot `
        -Force

    # Escribir configuracion directamente en applicationHost.config
    # (Set-ItemProperty falla en algunas versiones EN por encoding)
    $configPath = "C:\Windows\System32\inetsrv\config\applicationHost.config"
    $utf8NoBOM  = New-Object System.Text.UTF8Encoding $false
    $content    = [System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8)

    # Insertar bloque ftpServer justo antes del cierre </site> de FTP_SERVER
    $viejo = "</bindings>`r`n            </site>"
    $nuevo = "</bindings>`r`n                <ftpServer>`r`n                    <userIsolation mode=""IsolateAllDirectories"" />`r`n                    <security>`r`n                        <ssl controlChannelPolicy=""SslAllow"" dataChannelPolicy=""SslAllow"" />`r`n                        <authentication>`r`n                            <anonymousAuthentication enabled=""true"" />`r`n                            <basicAuthentication enabled=""true"" />`r`n                        </authentication>`r`n                    </security>`r`n                </ftpServer>`r`n            </site>"

    # Solo reemplazar si no esta ya configurado
    if ($content -notmatch "userIsolation") {
        $content = $content.Replace($viejo, $nuevo)
        [System.IO.File]::WriteAllText($configPath, $content, $utf8NoBOM)
    }

    # Reglas de autorizacion via appcmd (mas confiable que PowerShell en EN)
    $appcmd = "C:\Windows\System32\inetsrv\appcmd.exe"

    & $appcmd set config $ftpSite -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='?',permissions='Read']" /commit:apphost 2>$null
    & $appcmd set config $ftpSite -section:system.ftpServer/security/authorization /+"[accessType='Allow',roles='ftpusuarios',permissions='Read,Write']" /commit:apphost 2>$null

    Restart-Service ftpsvc

    Write-Host "FTP configurado correctamente" -ForegroundColor Green
    Write-Host "  Raiz FTP : $ftpRoot" -ForegroundColor Cyan
    Write-Host "  Home usuario: $ftpRoot\$serverName\<usuario>" -ForegroundColor Cyan
    Write-Host "  Home anonimo: $ftpRoot\LocalUser\Public" -ForegroundColor Cyan
    Log "FTP configurado"
}

# ------------------------------------------------------------
# CREAR USUARIO
# Home en: C:\Users\<SERVIDOR>\<usuario>
# Carpetas visibles al login: general, <grupo>, <usuario>
# ------------------------------------------------------------
function Crear-Usuario {

    $cantidad = Read-Host "Cuantos usuarios desea crear"

    for ($i = 1; $i -le $cantidad; $i++) {

        Write-Host ""
        Write-Host "--- Usuario $i de $cantidad ---" -ForegroundColor Cyan

        $usuario = Read-Host "Nombre de usuario"
        $pass    = Read-Host "Contrasena" -AsSecureString
        $grupo   = Read-Host "Grupo (reprobados/recursadores)"

        if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
            Write-Host "Grupo invalido. Debe ser reprobados o recursadores." -ForegroundColor Red
            continue
        }

        if (Get-LocalUser $usuario -ErrorAction SilentlyContinue) {
            Write-Host "El usuario $usuario ya existe." -ForegroundColor Yellow
            continue
        }

        # Crear usuario local
        New-LocalUser $usuario -Password $pass -PasswordNeverExpires

        # Agregar a grupos
        Add-LocalGroupMember $grupo        -Member $usuario
        Add-LocalGroupMember "ftpusuarios" -Member $usuario

        # Home del usuario: C:\Users\<SERVIDOR>\<usuario>
        $userHome = "$ftpRoot\$serverName\$usuario"
        New-Item $userHome -ItemType Directory -Force | Out-Null

        # Carpeta personal del usuario en datos
        New-Item "$ftpData\usuarios\$usuario" -ItemType Directory -Force | Out-Null

        # Junction links visibles al hacer login
        # Limpiar primero si existen
        foreach ($link in @("general", $grupo, $usuario)) {
            if (Test-Path "$userHome\$link") {
                cmd /c rmdir "$userHome\$link"
            }
        }

        cmd /c mklink /J "$userHome\general"  "$ftpData\general"
        cmd /c mklink /J "$userHome\$grupo"   "$ftpData\$grupo"
        cmd /c mklink /J "$userHome\$usuario" "$ftpData\usuarios\$usuario"

        # Permisos NTFS
        icacls $userHome                         /grant "${usuario}:(OI)(CI)RX"
        icacls "$ftpData\usuarios\$usuario"      /grant "${usuario}:(OI)(CI)F"

        Write-Host "Usuario $usuario creado en grupo $grupo" -ForegroundColor Green
        Log "Usuario $usuario creado en grupo $grupo"
    }

    Restart-Service ftpsvc
    Write-Host "Usuarios creados correctamente" -ForegroundColor Green
}

# ------------------------------------------------------------
# ELIMINAR USUARIO
# ------------------------------------------------------------
function Eliminar-Usuario {

    $usuario = Read-Host "Usuario a eliminar"

    Remove-LocalUser $usuario -ErrorAction SilentlyContinue
    Remove-Item "$ftpRoot\$serverName\$usuario" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$ftpData\usuarios\$usuario"    -Recurse -Force -ErrorAction SilentlyContinue

    Restart-Service ftpsvc

    Write-Host "Usuario $usuario eliminado" -ForegroundColor Green
    Log "Usuario eliminado: $usuario"
}

# ------------------------------------------------------------
# CAMBIAR GRUPO
# ------------------------------------------------------------
function Cambiar-Grupo {

    $usuario = Read-Host "Usuario"
    $grupo   = Read-Host "Nuevo grupo (reprobados/recursadores)"

    if ($grupo -ne "reprobados" -and $grupo -ne "recursadores") {
        Write-Host "Grupo invalido." -ForegroundColor Red
        return
    }

    # Quitar de grupos anteriores
    Remove-LocalGroupMember -Group "reprobados"   -Member $usuario -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "recursadores" -Member $usuario -ErrorAction SilentlyContinue

    # Agregar al nuevo grupo
    Add-LocalGroupMember -Group $grupo -Member $usuario

    $userHome = "$ftpRoot\$serverName\$usuario"

    # Eliminar junction links viejos de grupo
    if (Test-Path "$userHome\reprobados")   { cmd /c rmdir "$userHome\reprobados" }
    if (Test-Path "$userHome\recursadores") { cmd /c rmdir "$userHome\recursadores" }

    # Crear nuevo junction link
    cmd /c mklink /J "$userHome\$grupo" "$ftpData\$grupo"

    Restart-Service ftpsvc

    Write-Host "Usuario $usuario cambiado al grupo $grupo" -ForegroundColor Green
    Log "Usuario $usuario cambiado al grupo $grupo"
}

# ------------------------------------------------------------
# VER USUARIOS
# ------------------------------------------------------------
function Ver-Usuarios {

    Write-Host ""
    Write-Host "Usuarios FTP registrados:" -ForegroundColor Cyan
    Write-Host ""

    Get-LocalGroupMember ftpusuarios | ForEach-Object {
        $u = $_.Name.Split("\")[-1]
        $grupos = @()
        if (Get-LocalGroupMember "reprobados"   -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "reprobados" }
        if (Get-LocalGroupMember "recursadores" -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "*$u" }) { $grupos += "recursadores" }
        Write-Host "  Usuario: $u  |  Grupo: $($grupos -join ', ')"
    }
}

# ------------------------------------------------------------
# REINICIAR FTP
# ------------------------------------------------------------
function Reiniciar-FTP {
    Restart-Service ftpsvc
    Write-Host "Servicio FTP reiniciado" -ForegroundColor Green
}

# ------------------------------------------------------------
# ESTADO SERVIDOR
# ------------------------------------------------------------
function Estado {

    Write-Host ""
    Write-Host "Servicio FTP:" -ForegroundColor Cyan
    Get-Service ftpsvc

    Write-Host ""
    Write-Host "Puerto 21:" -ForegroundColor Cyan
    netstat -an | find ":21"

    Write-Host ""
    Write-Host "Sitios IIS:" -ForegroundColor Cyan
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Get-WebSite | Select-Object Name, State, PhysicalPath | Format-Table -AutoSize
}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------
function Menu {

    while ($true) {

        Write-Host ""
        Write-Host "======== ADMIN FTP (Windows EN) ========" -ForegroundColor Cyan
        Write-Host "1  Instalar FTP"
        Write-Host "2  Configurar Firewall"
        Write-Host "3  Crear Grupos"
        Write-Host "4  Crear Estructura de Carpetas"
        Write-Host "5  Aplicar Permisos"
        Write-Host "6  Configurar Sitio FTP"
        Write-Host "7  Crear Usuario(s)"
        Write-Host "8  Eliminar Usuario"
        Write-Host "9  Cambiar Grupo de Usuario"
        Write-Host "10 Ver Usuarios"
        Write-Host "11 Estado del Servidor"
        Write-Host "12 Reiniciar FTP"
        Write-Host "0  Salir"
        Write-Host ""

        $op = Read-Host "Opcion"

        switch ($op) {
            "1"  { Instalar-FTP }
            "2"  { Configurar-Firewall }
            "3"  { Crear-Grupos }
            "4"  { Crear-Estructura }
            "5"  { Permisos }
            "6"  { Configurar-FTP }
            "7"  { Crear-Usuario }
            "8"  { Eliminar-Usuario }
            "9"  { Cambiar-Grupo }
            "10" { Ver-Usuarios }
            "11" { Estado }
            "12" { Reiniciar-FTP }
            "0"  { return }
            default { Write-Host "Opcion no valida" -ForegroundColor Red }
        }
    }
}

Menu
