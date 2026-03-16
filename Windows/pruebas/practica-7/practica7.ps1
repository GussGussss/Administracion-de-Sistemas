# ============================================================
# practica7.ps1
# Orquestador de Instalacion Hibrida + SSL/TLS - Practica 7
# Windows Server 2019 Core (sin GUI) - PowerShell
# Ejecutar como Administrador
# ============================================================
#
# Requiere en la misma carpeta:
#   - ssl_funciones.ps1        (generado en P7)
#   - funciones.ps1            (de P6 - servidores HTTP)
#   - ftp_admin.ps1            (de P5 - servidor FTP)
#
# Requiere haber ejecutado antes:
#   - Preparar-Repositorio.ps1 (estructura FTP lista)
# ============================================================

# ------------------------------------------------------------
# Verificar que se ejecuta como Administrador
# ------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar este script como Administrador." -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------
# Cargar scripts de practicas anteriores
# ------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$archivos = @{
    "ssl_funciones.ps1" = "$scriptDir\ssl_funciones.ps1"
    "funciones.ps1"     = "$scriptDir\funciones.ps1"
}

foreach ($nombre in $archivos.Keys) {
    $ruta = $archivos[$nombre]
    if (Test-Path $ruta) {
        . $ruta
        Write-Host "Cargado: $nombre" -ForegroundColor Gray
    } else {
        Write-Host "ADVERTENCIA: No se encontro $ruta" -ForegroundColor Yellow
        Write-Host "Algunas funciones pueden no estar disponibles." -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# Variables globales de la practica
# ------------------------------------------------------------
$global:FTP_HOST    = "127.0.0.1"
$global:FTP_PORT    = 21
$global:FTP_USER    = ""
$global:FTP_PASS    = ""
$global:FTP_REPO    = "/http/Windows"
$global:LOG_FILE    = "C:\FTP_Data\practica7_log.txt"
$global:REPORTE     = @{}

# ------------------------------------------------------------
# Funcion: log
# ------------------------------------------------------------
function Log7 {
    param($msg)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linea = "$fecha - $msg"
    Add-Content $global:LOG_FILE $linea -ErrorAction SilentlyContinue
    Write-Host $linea -ForegroundColor DarkGray
}

# ============================================================
# BLOQUE 1: CLIENTE FTP DINAMICO
# ============================================================

# ------------------------------------------------------------
# Funcion: pedir credenciales FTP al usuario
# ------------------------------------------------------------
function Pedir-Credenciales-FTP {

    Write-Host ""
    Write-Host "--- Credenciales del servidor FTP ---" -ForegroundColor Cyan
    Write-Host "Servidor : $global:FTP_HOST"
    Write-Host "Puerto   : $global:FTP_PORT"
    Write-Host ""

    $global:FTP_USER = Read-Host "Usuario FTP"
    $passSegura      = Read-Host "Contrasena FTP" -AsSecureString
    $global:FTP_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passSegura)
    )
}

# ------------------------------------------------------------
# Funcion: listar contenido de una ruta FTP
# Retorna array de nombres de carpetas/archivos
# ------------------------------------------------------------
function Listar-FTP {
    param([string]$Ruta)

    $url  = "ftp://$global:FTP_HOST`:$global:FTP_PORT$Ruta"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)

    try {
        $request                  = [System.Net.FtpWebRequest]::Create($url)
        $request.Method           = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.Credentials      = $cred
        $request.UsePassive        = $true
        $request.UseBinary         = $true
        $request.KeepAlive         = $false
        $request.Timeout           = 10000

        $response = $request.GetResponse()
        $stream   = $response.GetResponseStream()
        $reader   = New-Object System.IO.StreamReader($stream)
        $contenido = $reader.ReadToEnd()
        $reader.Close()
        $response.Close()

        $items = $contenido.Split("`n") |
                 ForEach-Object { $_.Trim() } |
                 Where-Object   { $_ -ne "" }

        return $items

    } catch {
        Write-Host "ERROR al listar FTP ($Ruta): $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# ------------------------------------------------------------
# Funcion: descargar archivo desde FTP
# Retorna $true si tuvo exito
# ------------------------------------------------------------
function Descargar-FTP {
    param(
        [string]$RutaRemota,
        [string]$RutaLocal
    )

    $url  = "ftp://$global:FTP_HOST`:$global:FTP_PORT$RutaRemota"
    $cred = New-Object System.Net.NetworkCredential($global:FTP_USER, $global:FTP_PASS)

    try {
        Write-Host "  Descargando: $RutaRemota" -ForegroundColor Gray
        Write-Host "  Destino    : $RutaLocal" -ForegroundColor Gray

        $request             = [System.Net.FtpWebRequest]::Create($url)
        $request.Method      = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $request.Credentials = $cred
        $request.UsePassive   = $true
        $request.UseBinary    = $true
        $request.KeepAlive    = $false
        $request.Timeout      = 60000

        $response   = $request.GetResponse()
        $stream     = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($RutaLocal)
        $stream.CopyTo($fileStream)
        $fileStream.Close()
        $response.Close()

        $tamano = (Get-Item $RutaLocal).Length
        Write-Host "  Descargado : $("{0:N0}" -f $tamano) bytes" -ForegroundColor Green
        return $true

    } catch {
        Write-Host "ERROR al descargar ($RutaRemota): $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ------------------------------------------------------------
# Funcion: navegar por el repositorio FTP y elegir instalador
# Retorna objeto con { ArchivoLocal, Servicio, Version }
# o $null si el usuario cancela
# ------------------------------------------------------------
function Navegar-Repositorio-FTP {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " REPOSITORIO FTP PRIVADO" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    # Paso 1: listar servicios disponibles en /http/Windows/
    Write-Host ""
    Write-Host "Conectando a $global:FTP_HOST:$global:FTP_PORT$global:FTP_REPO ..." -ForegroundColor Gray

    $servicios = Listar-FTP -Ruta $global:FTP_REPO

    if ($servicios.Count -eq 0) {
        Write-Host "No se encontraron servicios en el repositorio FTP." -ForegroundColor Red
        Write-Host "Verifica que el servidor FTP este corriendo y el repositorio preparado." -ForegroundColor Yellow
        return $null
    }

    # Mostrar servicios disponibles
    Write-Host ""
    Write-Host "Servicios disponibles:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        Write-Host "  $($i + 1)) $($servicios[$i])"
    }
    Write-Host "  0) Cancelar"
    Write-Host ""

    # Elegir servicio
    do {
        $selSvc = Read-Host "Seleccione un servicio"
        if ($selSvc -eq "0") { return $null }
        $idxSvc = [int]$selSvc - 1
    } while ($idxSvc -lt 0 -or $idxSvc -ge $servicios.Count)

    $servicioElegido = $servicios[$idxSvc]
    $rutaServicio    = "$global:FTP_REPO/$servicioElegido"

    # Paso 2: listar archivos dentro de la carpeta del servicio
    Write-Host ""
    Write-Host "Archivos disponibles en $servicioElegido :" -ForegroundColor Yellow

    $archivos = Listar-FTP -Ruta $rutaServicio

    # Filtrar solo los instaladores (excluir .sha256 e index.txt)
    $instaladores = $archivos | Where-Object {
        $_ -match "\.(zip|msi|exe|deb|tar\.gz)$"
    }

    if ($instaladores.Count -eq 0) {
        Write-Host "No se encontraron instaladores en $rutaServicio" -ForegroundColor Red
        return $null
    }

    for ($i = 0; $i -lt $instaladores.Count; $i++) {
        Write-Host "  $($i + 1)) $($instaladores[$i])"
    }
    Write-Host "  0) Cancelar"
    Write-Host ""

    # Elegir archivo
    do {
        $selArch = Read-Host "Seleccione el instalador"
        if ($selArch -eq "0") { return $null }
        $idxArch = [int]$selArch - 1
    } while ($idxArch -lt 0 -or $idxArch -ge $instaladores.Count)

    $archivoElegido  = $instaladores[$idxArch]
    $rutaRemota      = "$rutaServicio/$archivoElegido"
    $rutaHashRemota  = "$rutaRemota.sha256"
    $destino         = "$env:TEMP\$archivoElegido"
    $destinoHash     = "$destino.sha256"

    # Paso 3: descargar el instalador
    Write-Host ""
    Write-Host "Descargando instalador..." -ForegroundColor Cyan
    $ok = Descargar-FTP -RutaRemota $rutaRemota -RutaLocal $destino
    if (-not $ok) { return $null }

    # Paso 4: descargar el archivo .sha256
    Write-Host "Descargando hash de verificacion..." -ForegroundColor Cyan
    $okHash = Descargar-FTP -RutaRemota $rutaHashRemota -RutaLocal $destinoHash
    if (-not $okHash) {
        Write-Host "ADVERTENCIA: No se pudo descargar el archivo .sha256" -ForegroundColor Yellow
        Write-Host "La verificacion de integridad no podra realizarse." -ForegroundColor Yellow
    }

    return @{
        ArchivoLocal  = $destino
        HashLocal     = $destinoHash
        Servicio      = $servicioElegido
        Archivo       = $archivoElegido
        HashDescargado = $okHash
    }
}

# ============================================================
# BLOQUE 2: VERIFICACION DE INTEGRIDAD (HASH)
# ============================================================

# ------------------------------------------------------------
# Funcion: verificar SHA256 del archivo descargado
# Retorna $true si el hash coincide
# ------------------------------------------------------------
function Verificar-Hash {
    param(
        [string]$ArchivoLocal,
        [string]$ArchivoHash
    )

    Write-Host ""
    Write-Host "--- Verificacion de integridad ---" -ForegroundColor Cyan

    if (-not (Test-Path $ArchivoLocal)) {
        Write-Host "ERROR: Archivo no encontrado: $ArchivoLocal" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $ArchivoHash)) {
        Write-Host "ADVERTENCIA: Archivo .sha256 no encontrado. Omitiendo verificacion." -ForegroundColor Yellow
        return $true
    }

    # Calcular hash del archivo descargado
    Write-Host "  Calculando SHA256 del archivo descargado..." -ForegroundColor Gray
    $hashCalculado = (Get-FileHash -Path $ArchivoLocal -Algorithm SHA256).Hash.ToLower()

    # Leer hash esperado desde el archivo .sha256
    # Formato esperado: "<hash>  <nombre_archivo>"
    $contenidoHash  = Get-Content $ArchivoHash -Raw
    $hashEsperado   = ($contenidoHash.Trim().Split(" ") | Select-Object -First 1).ToLower()
    $nombreArchivo  = Split-Path $ArchivoLocal -Leaf

    Write-Host "  Archivo       : $nombreArchivo" -ForegroundColor Gray
    Write-Host "  Hash esperado : $($hashEsperado.Substring(0, 16))..." -ForegroundColor Gray
    Write-Host "  Hash calculado: $($hashCalculado.Substring(0, 16))..." -ForegroundColor Gray

    if ($hashCalculado -eq $hashEsperado) {
        Write-Host "  Integridad OK: el archivo no fue corrompido." -ForegroundColor Green
        Log7 "Hash OK para $nombreArchivo"
        return $true
    } else {
        Write-Host "  FALLO: Los hashes NO coinciden. El archivo puede estar corrompido." -ForegroundColor Red
        Write-Host "  Esperado  : $hashEsperado" -ForegroundColor Red
        Write-Host "  Calculado : $hashCalculado" -ForegroundColor Red
        Log7 "Hash FALLO para $nombreArchivo"
        return $false
    }
}

# ============================================================
# BLOQUE 3: INSTALACION HIBRIDA (WEB o FTP)
# ============================================================

# ------------------------------------------------------------
# Funcion: instalar un servicio desde WEB (reutiliza P6)
# ------------------------------------------------------------
function Instalar-Desde-Web {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "Instalando $Servicio desde repositorio WEB..." -ForegroundColor Cyan

    switch ($Servicio.ToUpper()) {
        "IIS" {
            if (Get-Command Listar-Versiones-IIS -ErrorAction SilentlyContinue) {
                Listar-Versiones-IIS
                $ver    = Read-Host "Seleccione version [1-2]"
                $puerto = Read-Host "Puerto de escucha"
                Instalar-IIS -Version "10.0" -Puerto ([int]$puerto)
            } else {
                Write-Host "Instalando IIS directamente..." -ForegroundColor Gray
                Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
                Write-Host "IIS instalado." -ForegroundColor Green
            }
        }
        "APACHE" {
            if (Get-Command Listar-Versiones-Apache -ErrorAction SilentlyContinue) {
                Listar-Versiones-Apache
                $ver    = Read-Host "Seleccione version [1-3]"
                $puerto = Read-Host "Puerto de escucha"
                $version = switch ($ver) {
                    "1" { $global:APACHE_LATEST }
                    "2" { $global:APACHE_LTS }
                    "3" { $global:APACHE_OLDEST }
                    default { $global:APACHE_LTS }
                }
                Instalar-Apache -Version $version -Puerto ([int]$puerto)
            } else {
                Write-Host "Funciones de Apache no disponibles. Carga funciones.ps1 de P6." -ForegroundColor Yellow
            }
        }
        "NGINX" {
            if (Get-Command Listar-Versiones-Nginx -ErrorAction SilentlyContinue) {
                Listar-Versiones-Nginx
                $ver    = Read-Host "Seleccione version [1-3]"
                $puerto = Read-Host "Puerto de escucha"
                $version = switch ($ver) {
                    "1" { $global:NGINX_LATEST }
                    "2" { $global:NGINX_LTS }
                    "3" { $global:NGINX_OLDEST }
                    default { $global:NGINX_LTS }
                }
                Instalar-Nginx -Version $version -Puerto ([int]$puerto)
            } else {
                Write-Host "Funciones de Nginx no disponibles. Carga funciones.ps1 de P6." -ForegroundColor Yellow
            }
        }
        "FTP" {
            Write-Host "El servidor FTP (IIS-FTP) se instala desde el script de P5." -ForegroundColor Yellow
            Write-Host "Ejecuta ftp_admin.ps1 opcion 1 si no esta instalado aun." -ForegroundColor Yellow
        }
        default {
            Write-Host "Servicio '$Servicio' no reconocido." -ForegroundColor Red
        }
    }
}

# ------------------------------------------------------------
# Funcion: instalar un servicio desde FTP privado
# Descarga, verifica hash e instala
# ------------------------------------------------------------
function Instalar-Desde-FTP {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "Instalando $Servicio desde repositorio FTP privado..." -ForegroundColor Cyan

    # Conectar y navegar el repositorio
    $resultado = Navegar-Repositorio-FTP
    if (-not $resultado) {
        Write-Host "Instalacion cancelada o fallida." -ForegroundColor Yellow
        return $false
    }

    # Verificar integridad del archivo descargado
    if ($resultado.HashDescargado) {
        $hashOk = Verificar-Hash `
            -ArchivoLocal $resultado.ArchivoLocal `
            -ArchivoHash  $resultado.HashLocal

        if (-not $hashOk) {
            Write-Host ""
            Write-Host "El archivo descargado esta corrompido o fue modificado." -ForegroundColor Red
            Write-Host "Instalacion cancelada por seguridad." -ForegroundColor Red
            Log7 "Instalacion cancelada: hash invalido para $($resultado.Archivo)"
            return $false
        }
    }

    # Proceder con la instalacion segun el tipo de archivo
    $archivo = $resultado.ArchivoLocal
    $ext     = [System.IO.Path]::GetExtension($archivo).ToLower()

    Write-Host ""
    Write-Host "Instalando $($resultado.Servicio) desde archivo local..." -ForegroundColor Cyan

    switch ($ext) {
        ".msi" {
            Write-Host "  Ejecutando instalador MSI en modo silencioso..." -ForegroundColor Gray
            $proc = Start-Process msiexec.exe `
                -ArgumentList "/i `"$archivo`" /quiet /norestart" `
                -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Host "  Instalacion MSI completada." -ForegroundColor Green
            } else {
                Write-Host "  Error en instalacion MSI (codigo: $($proc.ExitCode))" -ForegroundColor Red
                return $false
            }
        }
        ".zip" {
            Write-Host "  Extrayendo archivo ZIP..." -ForegroundColor Gray
            $destDir = "C:\$($resultado.Servicio)"
            Expand-Archive -Path $archivo -DestinationPath $destDir -Force
            Write-Host "  Extraido en: $destDir" -ForegroundColor Green
            Write-Host "  NOTA: Configuracion manual puede ser necesaria." -ForegroundColor Yellow
        }
        ".exe" {
            Write-Host "  Ejecutando instalador EXE en modo silencioso..." -ForegroundColor Gray
            $proc = Start-Process $archivo `
                -ArgumentList "/S /quiet" `
                -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Host "  Instalacion EXE completada." -ForegroundColor Green
            } else {
                Write-Host "  Error en instalacion EXE (codigo: $($proc.ExitCode))" -ForegroundColor Red
                return $false
            }
        }
        default {
            Write-Host "  Tipo de archivo no reconocido para instalacion automatica: $ext" -ForegroundColor Yellow
            Write-Host "  Archivo guardado en: $archivo" -ForegroundColor Yellow
        }
    }

    Log7 "Instalacion desde FTP completada: $($resultado.Servicio) - $($resultado.Archivo)"
    return $true
}

# ------------------------------------------------------------
# Funcion: orquestar instalacion de un servicio
# Pregunta WEB o FTP y delega
# ------------------------------------------------------------
function Orquestar-Instalacion {
    param([string]$Servicio)

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " INSTALACION: $($Servicio.ToUpper())" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Fuente de instalacion:"
    Write-Host "  1) WEB  - repositorio oficial (gestor de paquetes)"
    Write-Host "  2) FTP  - repositorio privado (este servidor)"
    Write-Host "  0) Omitir"
    Write-Host ""

    do {
        $fuente = Read-Host "Seleccione fuente [0-2]"
    } while ($fuente -notin @("0","1","2"))

    switch ($fuente) {
        "0" {
            Write-Host "Instalacion de $Servicio omitida." -ForegroundColor Yellow
            $global:REPORTE[$Servicio] = @{ Instalacion = "Omitida"; SSL = "N/A" }
            return
        }
        "1" {
            Instalar-Desde-Web -Servicio $Servicio
            $global:REPORTE[$Servicio] = @{ Instalacion = "WEB"; SSL = "Pendiente" }
        }
        "2" {
            Pedir-Credenciales-FTP
            $ok = Instalar-Desde-FTP -Servicio $Servicio
            $global:REPORTE[$Servicio] = @{
                Instalacion = if ($ok) { "FTP-OK" } else { "FTP-ERROR" }
                SSL         = "Pendiente"
            }
        }
    }

    # Preguntar si activar SSL
    Preguntar-SSL -Servicio $Servicio
}

# ============================================================
# BLOQUE 4: ACTIVACION SSL
# ============================================================

# ------------------------------------------------------------
# Funcion: preguntar y configurar SSL para un servicio
# ------------------------------------------------------------
function Preguntar-SSL {
    param([string]$Servicio)

    Write-Host ""
    $respuesta = Read-Host "Desea activar SSL en $Servicio? [S/N]"

    if ($respuesta.ToUpper() -ne "S") {
        Write-Host "SSL no activado en $Servicio." -ForegroundColor Yellow
        if ($global:REPORTE.ContainsKey($Servicio)) {
            $global:REPORTE[$Servicio].SSL = "No activado"
        }
        return
    }

    $ok = $false

    switch ($Servicio.ToUpper()) {
        "IIS"    { $ok = Configurar-SSL-IIS   }
        "APACHE" { $ok = Configurar-SSL-Apache }
        "NGINX"  { $ok = Configurar-SSL-Nginx  }
        "FTP"    { $ok = Configurar-SSL-FTP    }
        default  {
            Write-Host "SSL no implementado para '$Servicio'" -ForegroundColor Yellow
        }
    }

    if ($global:REPORTE.ContainsKey($Servicio)) {
        $global:REPORTE[$Servicio].SSL = if ($ok) { "Configurado" } else { "Error" }
    }

    Log7 "SSL para $Servicio : $(if ($ok) { 'OK' } else { 'ERROR' })"
}

# ============================================================
# BLOQUE 5: REPORTE FINAL
# ============================================================

# ------------------------------------------------------------
# Funcion: generar reporte final completo
# ------------------------------------------------------------
function Generar-Reporte-Final {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " GENERANDO REPORTE FINAL..." -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    # Ejecutar verificacion SSL completa
    $verificacionSSL = $null
    if (Get-Command Verificar-SSL-Completo -ErrorAction SilentlyContinue) {
        $verificacionSSL = Verificar-SSL-Completo
    }

    # Construir reporte en texto
    $lineas = @()
    $lineas += "============================================"
    $lineas += " REPORTE FINAL - PRACTICA 7"
    $lineas += " Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lineas += " Servidor: $env:COMPUTERNAME"
    $lineas += "============================================"
    $lineas += ""
    $lineas += "INSTALACIONES:"
    $lineas += ""

    foreach ($svc in $global:REPORTE.Keys) {
        $info = $global:REPORTE[$svc]
        $lineas += "  Servicio    : $svc"
        $lineas += "  Instalacion : $($info.Instalacion)"
        $lineas += "  SSL         : $($info.SSL)"

        if ($verificacionSSL -and $verificacionSSL.ContainsKey($svc)) {
            $v = $verificacionSSL[$svc]
            $lineas += "  Certificado : $(if ($v.Certificado) { 'OK' } else { 'NO ENCONTRADO' })"
            $lineas += "  Puerto SSL  : $(if ($v.Puerto) { 'Respondiendo' } else { 'No responde' })"
            $lineas += "  Estado SSL  : $($v.Estado)"
        }
        $lineas += ""
    }

    $lineas += "CERTIFICADOS INSTALADOS EN EL SISTEMA:"
    $lineas += ""
    Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.FriendlyName -like "P7-SSL-*" } |
        ForEach-Object {
            $lineas += "  $($_.FriendlyName)"
            $lineas += "  Dominio  : $($_.Subject)"
            $lineas += "  Vence    : $($_.NotAfter.ToString('yyyy-MM-dd'))"
            $lineas += "  Thumbprint: $($_.Thumbprint)"
            $lineas += ""
        }

    $lineas += "PUERTOS EN ESCUCHA (HTTP/HTTPS/FTP):"
    $lineas += ""
    $puertos = netstat -an | Select-String ":80 |:443 |:21 |:990 " |
               ForEach-Object { $_.Line.Trim() }
    $lineas += $puertos

    $lineas += ""
    $lineas += "============================================"
    $lineas += " FIN DEL REPORTE"
    $lineas += "============================================"

    # Guardar reporte en archivo
    $reportePath = "C:\FTP_Data\reporte_practica7.txt"
    $lineas | Set-Content $reportePath -Encoding UTF8
    Log7 "Reporte guardado en $reportePath"

    # Mostrar en pantalla
    $lineas | ForEach-Object {
        if ($_ -match "OK|Configurado|WEB-OK|FTP-OK") {
            Write-Host $_ -ForegroundColor Green
        } elseif ($_ -match "ERROR|FALLO|No responde|NO ENCONTRADO") {
            Write-Host $_ -ForegroundColor Red
        } elseif ($_ -match "=====|REPORTE|INSTALACION|CERTIFICADO|PUERTO") {
            Write-Host $_ -ForegroundColor Cyan
        } else {
            Write-Host $_
        }
    }

    Write-Host ""
    Write-Host "Reporte guardado en: $reportePath" -ForegroundColor Green
}

# ============================================================
# MENU PRINCIPAL
# ============================================================

function Menu-Principal {

    while ($true) {

        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "  PRACTICA 7 - DESPLIEGUE SEGURO           " -ForegroundColor Cyan
        Write-Host "  Instalacion Hibrida + SSL/TLS             " -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "--- Instalacion de servicios ---"
        Write-Host "  1) Instalar / configurar IIS"
        Write-Host "  2) Instalar / configurar Apache"
        Write-Host "  3) Instalar / configurar Nginx"
        Write-Host "  4) Instalar / configurar FTP (IIS-FTP)"
        Write-Host ""
        Write-Host "--- SSL/TLS (activar en servicio ya instalado) ---"
        Write-Host "  5) Activar SSL en IIS"
        Write-Host "  6) Activar SSL en Apache"
        Write-Host "  7) Activar SSL en Nginx"
        Write-Host "  8) Activar FTPS en IIS-FTP"
        Write-Host ""
        Write-Host "--- Utilidades ---"
        Write-Host "  9) Verificar SSL en todos los servicios"
        Write-Host " 10) Generar reporte final"
        Write-Host " 11) Preparar repositorio FTP (ejecutar una vez)"
        Write-Host "  0) Salir"
        Write-Host ""

        $op = Read-Host "Opcion"

        switch ($op) {

            "1"  { Orquestar-Instalacion -Servicio "IIS"    }
            "2"  { Orquestar-Instalacion -Servicio "Apache" }
            "3"  { Orquestar-Instalacion -Servicio "Nginx"  }
            "4"  { Orquestar-Instalacion -Servicio "FTP"    }

            "5"  {
                $ok = Configurar-SSL-IIS
                $global:REPORTE["IIS"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }
            "6"  {
                $ok = Configurar-SSL-Apache
                $global:REPORTE["Apache"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }
            "7"  {
                $ok = Configurar-SSL-Nginx
                $global:REPORTE["Nginx"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }
            "8"  {
                $ok = Configurar-SSL-FTP
                $global:REPORTE["FTP"] = @{ Instalacion = "Existente"; SSL = if ($ok) {"Configurado"} else {"Error"} }
            }

            "9"  {
                if (Get-Command Verificar-SSL-Completo -ErrorAction SilentlyContinue) {
                    Verificar-SSL-Completo
                } else {
                    Write-Host "Funcion de verificacion no disponible. Carga ssl_funciones.ps1" -ForegroundColor Yellow
                }
            }

            "10" { Generar-Reporte-Final }

            "11" {
                $prepScript = "$scriptDir\Preparar-Repositorio.ps1"
                if (Test-Path $prepScript) {
                    & $prepScript
                } else {
                    Write-Host "Preparar-Repositorio.ps1 no encontrado en $scriptDir" -ForegroundColor Red
                }
            }

            "0"  {
                Write-Host "Saliendo..." -ForegroundColor Yellow
                exit 0
            }

            default { Write-Host "Opcion no valida." -ForegroundColor Red }
        }
    }
}

# ------------------------------------------------------------
# Punto de entrada
# ------------------------------------------------------------
Menu-Principal
