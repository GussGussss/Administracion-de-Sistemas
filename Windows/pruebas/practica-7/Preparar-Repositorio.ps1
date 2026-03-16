# ============================================================
# Preparar-Repositorio.ps1
# Prepara la estructura del repositorio FTP privado para P7
# Debe ejecutarse UNA SOLA VEZ antes del script principal
# Ejecutar como Administrador
# ============================================================
#
# Estructura que crea:
# C:\FTP_Data\http\Windows\IIS\
# C:\FTP_Data\http\Windows\Apache\
# C:\FTP_Data\http\Windows\Nginx\
# C:\FTP_Data\http\Windows\Tomcat\
#
# Para cada servicio coloca un instalador de ejemplo (.zip/.msi)
# y su archivo .sha256 correspondiente.
# En un entorno real, aqui colocarias los binarios reales descargados.
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
# Variables de configuracion
# ------------------------------------------------------------
$ftpData   = "C:\FTP_Data"
$repoBase  = "$ftpData\http\Windows"

$servicios = @{
    "IIS"    = @{
        archivo = "iis_10.0_win64.zip"
        version = "10.0"
    }
    "Apache" = @{
        archivo = "apache_2.4.62_win64.zip"
        version = "2.4.62"
    }
    "Nginx"  = @{
        archivo = "nginx_1.26.2_win64.zip"
        version = "1.26.2"
    }
    "Tomcat" = @{
        archivo = "tomcat_10.1.msi"
        version = "10.1"
    }
}

# ------------------------------------------------------------
# Funcion: crear carpetas del repositorio
# ------------------------------------------------------------
function Crear-Estructura-Repositorio {

    Write-Host ""
    Write-Host "Creando estructura del repositorio FTP..." -ForegroundColor Cyan

    foreach ($servicio in $servicios.Keys) {
        $ruta = "$repoBase\$servicio"
        New-Item -ItemType Directory -Path $ruta -Force | Out-Null
        Write-Host "  Carpeta creada: $ruta" -ForegroundColor Gray
    }

    Write-Host "Estructura de carpetas lista." -ForegroundColor Green
}

# ------------------------------------------------------------
# Funcion: generar archivo de prueba y su SHA256
# En produccion real, aqui colocarias el binario verdadero
# y calcularias su hash sobre el archivo real.
# ------------------------------------------------------------
function Generar-Archivos-Prueba {

    Write-Host ""
    Write-Host "Generando archivos de instalador y sus hashes SHA256..." -ForegroundColor Cyan

    foreach ($servicio in $servicios.Keys) {
        $info    = $servicios[$servicio]
        $archivo = $info.archivo
        $version = $info.version
        $ruta    = "$repoBase\$servicio"
        $rutaArchivo = "$ruta\$archivo"
        $rutaHash    = "$ruta\$archivo.sha256"

        # Crear archivo de prueba si no existe un binario real
        # (simula el instalador; en produccion reemplazar por el binario real)
        if (-not (Test-Path $rutaArchivo)) {
            $contenidoPrueba = "INSTALADOR_SIMULADO:`nServicio: $servicio`nVersion: $version`nArchivo: $archivo`nFecha: $(Get-Date)"
            [System.IO.File]::WriteAllText($rutaArchivo, $contenidoPrueba, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Archivo creado (simulado): $archivo" -ForegroundColor Yellow
        } else {
            Write-Host "  Archivo ya existe (real): $archivo" -ForegroundColor Green
        }

        # Calcular SHA256 del archivo y guardar en .sha256
        $hash = (Get-FileHash -Path $rutaArchivo -Algorithm SHA256).Hash.ToLower()
        $lineaHash = "$hash  $archivo"
        [System.IO.File]::WriteAllText($rutaHash, $lineaHash, [System.Text.UTF8Encoding]::new($false))

        Write-Host "  Hash generado : $($hash.Substring(0,16))...  -> $archivo.sha256" -ForegroundColor Gray
    }

    Write-Host "Archivos e hashes listos." -ForegroundColor Green
}

# ------------------------------------------------------------
# Funcion: generar archivo de indice por servicio
# El script principal lo leerá para saber que versiones hay
# ------------------------------------------------------------
function Generar-Indices {

    Write-Host ""
    Write-Host "Generando archivos de indice por servicio..." -ForegroundColor Cyan

    foreach ($servicio in $servicios.Keys) {
        $info    = $servicios[$servicio]
        $archivo = $info.archivo
        $version = $info.version
        $ruta    = "$repoBase\$servicio"
        $rutaIndice = "$ruta\index.txt"

        $contenido = "SERVICIO=$servicio`nVERSION=$version`nARCHIVO=$archivo"
        [System.IO.File]::WriteAllText($rutaIndice, $contenido, [System.Text.UTF8Encoding]::new($false))

        Write-Host "  Indice creado: $servicio\index.txt" -ForegroundColor Gray
    }

    Write-Host "Indices listos." -ForegroundColor Green
}

# ------------------------------------------------------------
# Funcion: mostrar resumen de lo creado
# ------------------------------------------------------------
function Mostrar-Resumen {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " REPOSITORIO FTP LISTO" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Ruta base  : $repoBase"
    Write-Host ""
    Write-Host "Estructura:" -ForegroundColor Yellow

    Get-ChildItem $repoBase -Recurse | ForEach-Object {
        $nivel  = ($_.FullName.Replace($repoBase, "").Split("\").Count - 2)
        $indent = "  " * $nivel
        if ($_.PSIsContainer) {
            Write-Host "$indent[$($_.Name)]" -ForegroundColor Cyan
        } else {
            $tamano = "{0:N0} bytes" -f $_.Length
            Write-Host "$indent  $($_.Name)  ($tamano)" -ForegroundColor Gray
        }
    }

    Write-Host ""
    Write-Host "NOTA: Los archivos .zip/.msi son simulados." -ForegroundColor Yellow
    Write-Host "Para produccion real, reemplazalos por los binarios verdaderos" -ForegroundColor Yellow
    Write-Host "y vuelve a ejecutar este script para recalcular los hashes." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "IMPORTANTE: El servidor FTP (P5) debe estar corriendo" -ForegroundColor Yellow
    Write-Host "y apuntando a C:\FTP_Data para que el script P7 pueda" -ForegroundColor Yellow
    Write-Host "acceder a estos archivos via FTP." -ForegroundColor Yellow
    Write-Host ""
}

# ------------------------------------------------------------
# Ejecucion principal
# ------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  PREPARACION DE REPOSITORIO FTP - P7      " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

Crear-Estructura-Repositorio
Generar-Archivos-Prueba
Generar-Indices
Mostrar-Resumen
