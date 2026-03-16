# ============================================================
# preparar_repositorio.ps1
# Prepara la estructura del repositorio FTP privado para P7
# Debe ejecutarse EN el servidor FTP (el de P5) como Admin
#
# Lo que hace:
#   1. Crea carpetas /http/Windows/<Servicio>/ en C:\FTP_Data
#   2. Descarga instaladores reales de Apache y Nginx
#   3. Crea un instalador de prueba para IIS (no tiene MSI descargable)
#   4. Genera archivos .sha256 para cada instalador
#   5. Aplica permisos NTFS para lectura por ftpusuarios e IUSR
#   6. Crea junction links desde el home FTP para que sea accesible
#   7. Muestra resumen final
#
# REQUISITO: El servidor FTP de P5 debe estar instalado y
#            C:\FTP_Data debe existir
# ============================================================

# ── Verificar Administrador ───────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar como Administrador." -ForegroundColor Red
    exit 1
}

# ── Variables base (deben coincidir con P5) ───────────────────────────────────
$ftpData    = "C:\FTP_Data"
$ftpRoot    = "C:\Users"
$serverName = $env:COMPUTERNAME
$repoBase   = "$ftpData\http\Windows"
$tmpDir     = "$env:TEMP\repo_p7"
$logFile    = "$ftpData\repo_preparacion.log"

# ── Servicios a preparar ──────────────────────────────────────────────────────
# Cada entrada: Nombre, URL de descarga, nombre del archivo local
$servicios = @(
    @{
        Nombre   = "Apache"
        # Apache Haus: distribución oficial para Windows, ZIPs validos y sin antivirus
        UrlLTS      = "https://www.apachehaus.com/cgi-bin/download.plx/datas/httpd-2.4.62-o111s-x64-vs17.zip"
        ArchivoLTS  = "apache_2.4.62_win64.zip"
        UrlLatest   = "https://www.apachehaus.com/cgi-bin/download.plx/datas/httpd-2.4.63-o111s-x64-vs17.zip"
        ArchivoLatest = "apache_2.4.63_win64_latest.zip"
    },
    @{
        Nombre   = "Nginx"
        UrlLTS   = "https://nginx.org/download/nginx-1.24.0.zip"
        ArchivoLTS = "nginx_1.24.0_win64.zip"
        UrlLatest   = "https://nginx.org/download/nginx-1.26.2.zip"
        ArchivoLatest = "nginx_1.26.2_win64.zip"
    },
    @{
        Nombre   = "IIS"
        UrlLTS      = $null   # IIS no tiene MSI descargable, se genera uno de prueba
        ArchivoLTS  = "iis_10.0_placeholder.zip"
        UrlLatest   = $null
        ArchivoLatest = "iis_10.0_latest_placeholder.zip"
    }
)

# ============================================================
# LOG
# ============================================================
function Escribir-Log {
    param([string]$msg)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content $logFile "$fecha - $msg" -ErrorAction SilentlyContinue
    Write-Host $msg
}

# ============================================================
# CREAR DIRECTORIOS DEL REPOSITORIO
# ============================================================
function Crear-Directorios {
    Write-Host ""
    Write-Host "[ 1/5 ] Creando estructura de directorios..." -ForegroundColor Cyan

    foreach ($svc in $servicios) {
        $ruta = "$repoBase\$($svc.Nombre)"
        New-Item $ruta -ItemType Directory -Force | Out-Null
        Write-Host "  Creado: $ruta" -ForegroundColor Gray
    }

    New-Item $tmpDir -ItemType Directory -Force | Out-Null
    Escribir-Log "Estructura de directorios creada en $repoBase"
}

# ============================================================
# DESCARGAR ARCHIVO CON REINTENTOS
# ============================================================
function Descargar-Archivo {
    param([string]$Url, [string]$Destino, [string]$Nombre)

    Write-Host "  Descargando $Nombre ..." -ForegroundColor Gray
    Write-Host "  URL: $Url" -ForegroundColor DarkGray

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $intentos = 3
    for ($i = 1; $i -le $intentos; $i++) {
        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $wc.DownloadFile($Url, $Destino)

            if ((Test-Path $Destino) -and (Get-Item $Destino).Length -gt 1000) {
                Write-Host "  OK: $Nombre descargado." -ForegroundColor Green
                return $true
            }
        }
        catch {
            Write-Host "  Intento $i fallido: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($i -lt $intentos) { Start-Sleep -Seconds 3 }
        }
    }

    Write-Host "  ERROR: No se pudo descargar $Nombre tras $intentos intentos." -ForegroundColor Red
    return $false
}

# ============================================================
# GENERAR ARCHIVO SHA256
# ============================================================
function Generar-SHA256 {
    param([string]$Archivo)

    $hash     = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $nombre   = Split-Path $Archivo -Leaf
    $sha256File = "$Archivo.sha256"

    # Formato: <hash>  <nombre_archivo>  (igual que sha256sum en Linux)
    "$hash  $nombre" | Set-Content $sha256File -Encoding UTF8 -NoNewline

    Write-Host "  SHA256 generado: $nombre.sha256" -ForegroundColor Gray
    Write-Host "  Hash: $hash" -ForegroundColor DarkGray
    return $sha256File
}

# ============================================================
# CREAR ARCHIVO PLACEHOLDER PARA IIS
# (IIS es un rol de Windows, no tiene instalador descargable)
# ============================================================
function Crear-Placeholder-IIS {
    param([string]$Destino, [string]$Nombre, [string]$Version)

    Write-Host "  Creando placeholder para IIS $Version ..." -ForegroundColor Gray

    # Crear un ZIP con un README explicativo
    $tmpFolder = "$tmpDir\iis_placeholder_$Version"
    New-Item $tmpFolder -ItemType Directory -Force | Out-Null

    $readme = @"
IIS (Internet Information Services) $Version
=============================================
IIS es un rol de Windows Server y no tiene instalador independiente.

Para instalar IIS ejecutar en PowerShell como Administrador:
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools

Este archivo es un placeholder para demostrar la estructura del
repositorio FTP privado en la Practica 7.

Generado: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Servidor: $env:COMPUTERNAME
"@
    $readme | Set-Content "$tmpFolder\README.txt" -Encoding UTF8

    Compress-Archive -Path "$tmpFolder\*" -DestinationPath $Destino -Force
    Remove-Item $tmpFolder -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "  Placeholder IIS creado: $Nombre" -ForegroundColor Green
}

# ============================================================
# DESCARGAR E INSTALAR ARCHIVOS POR SERVICIO
# ============================================================
function Poblar-Repositorio {
    Write-Host ""
    Write-Host "[ 2/5 ] Descargando instaladores..." -ForegroundColor Cyan

    foreach ($svc in $servicios) {
        $rutaSvc = "$repoBase\$($svc.Nombre)"
        Write-Host ""
        Write-Host "  --- $($svc.Nombre) ---" -ForegroundColor Yellow

        # ── Versión LTS ───────────────────────────────────────────────────────
        $destLTS = "$rutaSvc\$($svc.ArchivoLTS)"

        if ($svc.UrlLTS) {
            $ok = Descargar-Archivo -Url $svc.UrlLTS -Destino $destLTS -Nombre $svc.ArchivoLTS
            if (-not $ok) {
                # Fallback: crear placeholder si la descarga falla
                Write-Host "  Fallback: creando placeholder para $($svc.Nombre) LTS..." -ForegroundColor Yellow
                Crear-Placeholder-IIS -Destino $destLTS -Nombre $svc.ArchivoLTS -Version "LTS"
            }
        }
        else {
            Crear-Placeholder-IIS -Destino $destLTS -Nombre $svc.ArchivoLTS -Version "10.0-LTS"
        }

        if (Test-Path $destLTS) { Generar-SHA256 -Archivo $destLTS }

        # ── Versión Latest ────────────────────────────────────────────────────
        $destLatest = "$rutaSvc\$($svc.ArchivoLatest)"

        # Evitar descargar dos veces si LTS y Latest son el mismo archivo
        if ($svc.UrlLatest -and ($svc.UrlLatest -ne $svc.UrlLTS)) {
            $ok = Descargar-Archivo -Url $svc.UrlLatest -Destino $destLatest -Nombre $svc.ArchivoLatest
            if (-not $ok) {
                Write-Host "  Fallback: copiando LTS como Latest para $($svc.Nombre)..." -ForegroundColor Yellow
                Copy-Item $destLTS $destLatest -Force -ErrorAction SilentlyContinue
            }
        }
        elseif (-not $svc.UrlLatest) {
            Crear-Placeholder-IIS -Destino $destLatest -Nombre $svc.ArchivoLatest -Version "10.0-Latest"
        }
        else {
            # Misma URL: copiar el ya descargado
            if (Test-Path $destLTS) {
                Copy-Item $destLTS $destLatest -Force
                Write-Host "  Latest es igual a LTS, copiado como: $($svc.ArchivoLatest)" -ForegroundColor Gray
            }
        }

        if (Test-Path $destLatest) { Generar-SHA256 -Archivo $destLatest }

        Escribir-Log "$($svc.Nombre): archivos colocados en $rutaSvc"
    }
}

# ============================================================
# APLICAR PERMISOS NTFS
# El usuario FTP (ftpusuarios e IUSR) necesita leer la carpeta
# ============================================================
function Aplicar-Permisos {
    Write-Host ""
    Write-Host "[ 3/5 ] Aplicando permisos NTFS al repositorio..." -ForegroundColor Cyan

    $sidSystem = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $cuentaSystem = $sidSystem.Translate([System.Security.Principal.NTAccount]).Value
    $cuentaAdmins = $sidAdmins.Translate([System.Security.Principal.NTAccount]).Value

    # Permisos en la raiz del repositorio http
    $rutaHttp = "$ftpData\http"
    icacls $rutaHttp /inheritance:r | Out-Null
    icacls $rutaHttp /grant "${cuentaAdmins}:(OI)(CI)F"   | Out-Null
    icacls $rutaHttp /grant "${cuentaSystem}:(OI)(CI)F"   | Out-Null
    icacls $rutaHttp /grant "ftpusuarios:(OI)(CI)RX"      | Out-Null
    icacls $rutaHttp /grant "IUSR:(OI)(CI)RX"             | Out-Null

    Write-Host "  Permisos aplicados en $rutaHttp" -ForegroundColor Green
    Escribir-Log "Permisos NTFS aplicados en $rutaHttp"
}

# ============================================================
# CREAR JUNCTION LINK DESDE EL HOME FTP
# Para que el repositorio sea visible al hacer login FTP
# El home del usuario admin queda en:
#   C:\Users\<SERVIDOR>\<usuario>\http  -> C:\FTP_Data\http
# ============================================================
function Crear-Acceso-FTP {
    Write-Host ""
    Write-Host "[ 4/5 ] Creando acceso FTP al repositorio..." -ForegroundColor Cyan

    # Acceso anonimo: C:\Users\LocalUser\Public\http
    $publicHttp = "$ftpRoot\LocalUser\Public\http"
    if (Test-Path $publicHttp) {
        cmd /c rmdir "$publicHttp" | Out-Null
    }
    cmd /c mklink /J "$publicHttp" "$ftpData\http" | Out-Null
    Write-Host "  Junction: $publicHttp -> $ftpData\http" -ForegroundColor Gray

    # Acceso para todos los usuarios autenticados:
    # Crear junction en el home de cada usuario existente en ftpusuarios
    try {
        $miembros = Get-LocalGroupMember "ftpusuarios" -ErrorAction SilentlyContinue
        foreach ($m in $miembros) {
            $usuario  = $m.Name.Split("\")[-1]
            $userHome = "$ftpRoot\$serverName\$usuario"
            if (Test-Path $userHome) {
                $linkHttp = "$userHome\http"
                if (Test-Path $linkHttp) { cmd /c rmdir "$linkHttp" | Out-Null }
                cmd /c mklink /J "$linkHttp" "$ftpData\http" | Out-Null
                Write-Host "  Junction para usuario '$usuario': $linkHttp" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  Advertencia: No se pudieron crear junctions para usuarios existentes." -ForegroundColor Yellow
    }

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "  Servicio FTP reiniciado." -ForegroundColor Green
    Escribir-Log "Acceso FTP al repositorio configurado"
}

# ============================================================
# RESUMEN FINAL
# ============================================================
function Mostrar-Resumen-Repo {
    Write-Host ""
    Write-Host "[ 5/5 ] Verificando repositorio creado..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "         REPOSITORIO FTP LISTO PARA PRACTICA 7                  " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Estructura creada:" -ForegroundColor Yellow
    Write-Host ""

    foreach ($svc in $servicios) {
        $rutaSvc = "$repoBase\$($svc.Nombre)"
        Write-Host "  $($svc.Nombre)/" -ForegroundColor Cyan
        if (Test-Path $rutaSvc) {
            Get-ChildItem $rutaSvc | ForEach-Object {
                $tamano = if ($_.Length -gt 1MB) {
                    "{0:N1} MB" -f ($_.Length / 1MB)
                } else {
                    "{0:N0} KB" -f ($_.Length / 1KB)
                }
                Write-Host ("    {0,-45} {1}" -f $_.Name, $tamano) -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    Write-Host "Ruta fisica : $repoBase" -ForegroundColor Cyan
    Write-Host "Acceso FTP  : ftp://<IP_SERVIDOR>/http/Windows/<Servicio>/<archivo>" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "En el script de P7, cuando elijas FTP, navega asi:" -ForegroundColor Yellow
    Write-Host "  IP FTP   -> IP de este servidor"
    Write-Host "  Ruta FTP -> http/Windows  (sin barra inicial)"
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Escribir-Log "Repositorio preparado correctamente"
}

# ============================================================
# MAIN
# ============================================================
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "   PREPARAR REPOSITORIO FTP - Practica 7 (Windows Server)      " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Verificar que FTP_Data existe (indica que P5 fue ejecutado)
if (-not (Test-Path $ftpData)) {
    Write-Host "ERROR: $ftpData no existe." -ForegroundColor Red
    Write-Host "Ejecute primero el script de la Practica 5 para instalar y configurar el FTP." -ForegroundColor Red
    exit 1
}

Write-Host "Base FTP detectada: $ftpData" -ForegroundColor Green
Write-Host ""
Write-Host "Este script realizara las siguientes acciones:" -ForegroundColor Yellow
Write-Host "  1. Crear carpetas: $repoBase\{IIS,Apache,Nginx}"
Write-Host "  2. Descargar Apache y Nginx (desde sus sitios oficiales)"
Write-Host "  3. Crear placeholders para IIS"
Write-Host "  4. Generar archivos .sha256 para cada instalador"
Write-Host "  5. Aplicar permisos NTFS de lectura para usuarios FTP"
Write-Host "  6. Crear junction links para acceso via FTP"
Write-Host ""

$conf = Read-Host "¿Continuar? [S/N]"
if ($conf -notmatch "^[Ss]$") {
    Write-Host "Cancelado." -ForegroundColor Yellow
    exit 0
}

Crear-Directorios
Poblar-Repositorio
Aplicar-Permisos
Crear-Acceso-FTP
Mostrar-Resumen-Repo
