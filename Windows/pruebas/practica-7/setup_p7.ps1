# ============================================================
# setup_p7.ps1
# Script Maestro - Practica 7
# Orquesta en orden:
#   PASO 1 -> ftp_p5.ps1            (Instala FTP + crea usuario repo)
#   PASO 2 -> preparar_repositorio.ps1 (Descarga archivos + genera .sha256)
#   PASO 3 -> main_p7.ps1           (Instala HTTP + SSL/TLS)
#
# El usuario solo ejecuta este archivo. El script detecta
# que pasos ya fueron completados y no los repite.
# ============================================================

# ── Verificar Administrador ───────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host "ERROR: Ejecutar como Administrador." -ForegroundColor Red
    exit 1
}

# ── Directorio donde estan todos los scripts ──────────────────────────────────
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ── Archivo de estado (guarda que pasos ya se completaron) ───────────────────
$estadoFile = "$scriptDir\.setup_estado.txt"

# ============================================================
# FUNCIONES DE ESTADO
# Guarda y lee que pasos ya fueron completados
# Asi si el usuario reinicia el script, no repite lo que ya hizo
# ============================================================
function Paso-Completado {
    param([string]$Paso)
    if (-not (Test-Path $estadoFile)) { return $false }
    $contenido = Get-Content $estadoFile -ErrorAction SilentlyContinue
    return ($contenido -contains $Paso)
}

function Marcar-Completado {
    param([string]$Paso)
    Add-Content $estadoFile $Paso
}

function Resetear-Estado {
    if (Test-Path $estadoFile) {
        Remove-Item $estadoFile -Force
        Write-Host "Estado reseteado. Se ejecutaran todos los pasos." -ForegroundColor Yellow
    }
}

# ============================================================
# FUNCION: Encabezado de paso
# ============================================================
function Mostrar-Paso {
    param([int]$Num, [string]$Titulo, [string]$Descripcion)
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  PASO $Num de 3 : $Titulo" -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  $Descripcion" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================
# FUNCION: Preguntar si continuar con un paso
# ============================================================
function Confirmar-Paso {
    param([string]$Pregunta)
    while ($true) {
        Write-Host "$Pregunta [S/N]: " -NoNewline -ForegroundColor Yellow
        $r = Read-Host
        if ($r -match "^[Ss]$") { return $true  }
        if ($r -match "^[Nn]$") { return $false }
        Write-Host "Responda S o N." -ForegroundColor Red
    }
}

# ============================================================
# FUNCION: Verificar que un script existe
# ============================================================
function Verificar-Script {
    param([string]$NombreArchivo)
    $ruta = "$scriptDir\$NombreArchivo"
    if (-not (Test-Path $ruta)) {
        Write-Host "ERROR: No se encuentra '$NombreArchivo' en $scriptDir" -ForegroundColor Red
        Write-Host "Asegurese de que todos los scripts esten en la misma carpeta." -ForegroundColor Yellow
        return $false
    }
    return $true
}

# ============================================================
# FUNCION: Detectar si FTP ya esta instalado y configurado
# ============================================================
function FTP-EstaConfigurado {
    # Verificar servicio FTP activo
    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne "Running") { return $false }

    # Verificar que existe C:\FTP_Data (estructura de P5)
    if (-not (Test-Path "C:\FTP_Data")) { return $false }

    # Verificar que existe el sitio FTP en IIS
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $sitio = Get-WebSite -Name "FTP_SERVER" -ErrorAction SilentlyContinue
    if (-not $sitio) { return $false }

    return $true
}

# ============================================================
# FUNCION: Detectar si el repositorio ya fue preparado
# ============================================================
function Repositorio-EstaListo {
    $rutaRepo = "C:\FTP_Data\http\Windows"
    if (-not (Test-Path $rutaRepo)) { return $false }

    # Verificar que hay al menos un .sha256 en alguna subcarpeta
    $sha256 = Get-ChildItem $rutaRepo -Filter "*.sha256" -Recurse -ErrorAction SilentlyContinue
    return ($sha256.Count -gt 0)
}

# ============================================================
# FUNCION: Detectar si existe el usuario FTP del repositorio
# ============================================================
function Usuario-Repo-Existe {
    param([string]$Usuario)
    return ($null -ne (Get-LocalUser $Usuario -ErrorAction SilentlyContinue))
}

# ============================================================
# BIENVENIDA
# ============================================================
Clear-Host
Write-Host ""
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host "#                                                              #" -ForegroundColor Cyan
Write-Host "#   PRACTICA 7 - Despliegue Seguro e Instalacion Hibrida      #" -ForegroundColor Cyan
Write-Host "#         Script Maestro de Configuracion Completa            #" -ForegroundColor Cyan
Write-Host "#                                                              #" -ForegroundColor Cyan
Write-Host "################################################################" -ForegroundColor Cyan
Write-Host ""
Write-Host "Este asistente configurara todo lo necesario en 3 pasos:" -ForegroundColor White
Write-Host ""
Write-Host "  PASO 1 -> Instalar y configurar el servidor FTP (Practica 5)" -ForegroundColor White
Write-Host "            + Crear usuario para el repositorio privado"
Write-Host ""
Write-Host "  PASO 2 -> Preparar el repositorio FTP" -ForegroundColor White
Write-Host "            + Descargar instaladores de Apache y Nginx"
Write-Host "            + Generar archivos de verificacion .sha256"
Write-Host ""
Write-Host "  PASO 3 -> Instalar servidores HTTP + SSL/TLS (Practica 7)" -ForegroundColor White
Write-Host "            + IIS, Apache, Nginx"
Write-Host "            + Certificados autofirmados"
Write-Host "            + FTPS en el servidor FTP"
Write-Host ""

# Verificar si hay una ejecucion previa incompleta
if (Test-Path $estadoFile) {
    Write-Host "Se detecto una ejecucion previa parcial." -ForegroundColor Yellow
    Write-Host "Pasos ya completados:" -ForegroundColor Yellow
    Get-Content $estadoFile | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
    Write-Host ""
    if (Confirmar-Paso -Pregunta "¿Desea continuar desde donde se quedo") {
        Write-Host "Continuando desde el ultimo paso completado..." -ForegroundColor Green
    } else {
        if (Confirmar-Paso -Pregunta "¿Desea empezar desde cero (resetear estado)") {
            Resetear-Estado
        } else {
            Write-Host "Saliendo." -ForegroundColor Yellow
            exit 0
        }
    }
}

# Verificar que todos los scripts necesarios existen
Write-Host ""
Write-Host "Verificando scripts necesarios..." -ForegroundColor Cyan
$scriptsNecesarios = @("ftp_p5.ps1", "preparar_repositorio.ps1", "main_p7.ps1", "funciones_p7.ps1", "funciones.ps1")
$todosExisten = $true
foreach ($s in $scriptsNecesarios) {
    if (Test-Path "$scriptDir\$s") {
        Write-Host "  OK : $s" -ForegroundColor Green
    } else {
        Write-Host "  FALTA: $s" -ForegroundColor Red
        $todosExisten = $false
    }
}

if (-not $todosExisten) {
    Write-Host ""
    Write-Host "ERROR: Faltan scripts. Coloque todos los archivos en la misma carpeta:" -ForegroundColor Red
    Write-Host "  $scriptDir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Archivos necesarios:" -ForegroundColor Yellow
    foreach ($s in $scriptsNecesarios) {
        Write-Host "  $s"
    }
    exit 1
}

Write-Host "Todos los scripts encontrados." -ForegroundColor Green

# ============================================================
# PASO 1: FTP (Practica 5) + Usuario repositorio
# ============================================================
Mostrar-Paso -Num 1 -Titulo "Servidor FTP (Practica 5)" `
    -Descripcion "Instala IIS-FTP, crea grupos, estructura de carpetas y un usuario para el repositorio privado."

if (Paso-Completado -Paso "PASO1") {
    Write-Host "  Este paso ya fue completado anteriormente." -ForegroundColor Green
    Write-Host "  FTP instalado: $(if (FTP-EstaConfigurado) {'SI'} else {'Revisar manualmente'})" -ForegroundColor Gray
}
else {
    # Detectar si FTP ya esta corriendo de una instalacion previa
    if (FTP-EstaConfigurado) {
        Write-Host "  Se detecto que el servidor FTP ya esta instalado y corriendo." -ForegroundColor Yellow
        Write-Host "  Servicio : ftpsvc ACTIVO" -ForegroundColor Gray
        Write-Host "  Datos    : C:\FTP_Data existe" -ForegroundColor Gray
        Write-Host "  Sitio IIS: FTP_SERVER existe" -ForegroundColor Gray
        Write-Host ""

        if (Confirmar-Paso -Pregunta "¿El FTP ya esta configurado correctamente desde P5 y desea omitir este paso") {
            Write-Host "  Paso 1 omitido (FTP ya configurado)." -ForegroundColor Green
            Marcar-Completado -Paso "PASO1"
        }
        else {
            Write-Host "  Se ejecutara el script de P5 para reconfigurar..." -ForegroundColor Cyan
            if (Verificar-Script "ftp_p5.ps1") {
                Write-Host ""
                Write-Host "  Iniciando script de P5..." -ForegroundColor Cyan
                Write-Host "  (Siga las instrucciones del menu de P5)" -ForegroundColor Yellow
                Write-Host "  IMPORTANTE: Cuando termine, elija opcion 0 para volver aqui." -ForegroundColor Yellow
                Write-Host ""
                Read-Host "  Presione Enter para abrir el script de P5"
                & "$scriptDir\ftp_p5.ps1"
                Marcar-Completado -Paso "PASO1"
            }
        }
    }
    else {
        Write-Host "  El servidor FTP NO esta instalado. Se ejecutara el script de P5." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  El script de P5 abrira su propio menu." -ForegroundColor Gray
        Write-Host "  Ejecute las opciones en este orden:" -ForegroundColor Gray
        Write-Host "    1) Instalar FTP" -ForegroundColor Gray
        Write-Host "    2) Configurar Firewall" -ForegroundColor Gray
        Write-Host "    3) Crear Grupos" -ForegroundColor Gray
        Write-Host "    4) Crear Estructura de Carpetas" -ForegroundColor Gray
        Write-Host "    5) Aplicar Permisos" -ForegroundColor Gray
        Write-Host "    6) Configurar Sitio FTP" -ForegroundColor Gray
        Write-Host "    7) Crear Usuario (cree uno llamado 'ftprepo')" -ForegroundColor Gray
        Write-Host "    0) Salir (para regresar aqui)" -ForegroundColor Gray
        Write-Host ""

        if (Confirmar-Paso -Pregunta "¿Desea continuar con la instalacion del FTP") {
            if (Verificar-Script "ftp_p5.ps1") {
                Read-Host "  Presione Enter para abrir el script de P5"
                & "$scriptDir\ftp_p5.ps1"
                Marcar-Completado -Paso "PASO1"
            }
        }
        else {
            Write-Host "  Paso 1 omitido por el usuario." -ForegroundColor Yellow
        }
    }
}

# Verificar usuario del repositorio
Write-Host ""
Write-Host "  Verificando usuario FTP para el repositorio..." -ForegroundColor Cyan
$usuarioRepo = "ftprepo"

if (Usuario-Repo-Existe -Usuario $usuarioRepo) {
    Write-Host "  Usuario '$usuarioRepo' ya existe." -ForegroundColor Green
} else {
    Write-Host "  El usuario '$usuarioRepo' no existe." -ForegroundColor Yellow
    Write-Host "  Este usuario es necesario para que P7 pueda conectarse al FTP privado." -ForegroundColor Gray
    Write-Host ""

    if (Confirmar-Paso -Pregunta "¿Desea crear el usuario '$usuarioRepo' ahora") {

        Write-Host ""
        Write-Host "  Ingrese la contrasena para '$usuarioRepo':" -NoNewline
        $secPass = Read-Host -AsSecureString

        try {
            New-LocalUser $usuarioRepo -Password $secPass -PasswordNeverExpires -ErrorAction Stop

            # Agregar a grupos necesarios para acceder al FTP
            foreach ($g in @("ftpusuarios", "reprobados")) {
                Add-LocalGroupMember $g -Member $usuarioRepo -ErrorAction SilentlyContinue
            }

            # Crear home del usuario en la estructura de P5
            $serverName = $env:COMPUTERNAME
            $userHome   = "C:\Users\$serverName\$usuarioRepo"
            New-Item $userHome -ItemType Directory -Force | Out-Null

            # Junction links estandar de P5
            $ftpData = "C:\FTP_Data"
            foreach ($link in @("general", "reprobados", $usuarioRepo)) {
                if (Test-Path "$userHome\$link") { cmd /c rmdir "$userHome\$link" | Out-Null }
            }
            cmd /c mklink /J "$userHome\general"       "$ftpData\general"      | Out-Null
            cmd /c mklink /J "$userHome\reprobados"    "$ftpData\reprobados"   | Out-Null

            New-Item "$ftpData\usuarios\$usuarioRepo" -ItemType Directory -Force | Out-Null
            cmd /c mklink /J "$userHome\$usuarioRepo" "$ftpData\usuarios\$usuarioRepo" | Out-Null

            # Permisos NTFS
            icacls $userHome                              /grant "${usuarioRepo}:(OI)(CI)RX" | Out-Null
            icacls "$ftpData\usuarios\$usuarioRepo"       /grant "${usuarioRepo}:(OI)(CI)F"  | Out-Null

            Restart-Service ftpsvc -ErrorAction SilentlyContinue

            Write-Host ""
            Write-Host "  Usuario '$usuarioRepo' creado correctamente." -ForegroundColor Green
            Write-Host "  IMPORTANTE: Anote la contrasena, la necesitara en el Paso 3." -ForegroundColor Yellow

            # Guardar usuario en estado para que P7 lo pueda sugerir
            Add-Content $estadoFile "USUARIO_REPO=$usuarioRepo"
        }
        catch {
            Write-Host "  ERROR al crear usuario: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# ============================================================
# PASO 2: Preparar repositorio FTP
# ============================================================
Mostrar-Paso -Num 2 -Titulo "Preparar Repositorio FTP" `
    -Descripcion "Crea la estructura /http/Windows/, descarga instaladores y genera archivos .sha256."

if (Paso-Completado -Paso "PASO2") {
    Write-Host "  Este paso ya fue completado anteriormente." -ForegroundColor Green
    Write-Host "  Repositorio listo: $(if (Repositorio-EstaListo) {'SI'} else {'Revisar manualmente'})" -ForegroundColor Gray
}
else {
    if (Repositorio-EstaListo) {
        Write-Host "  Se detecto que el repositorio ya existe y tiene archivos .sha256." -ForegroundColor Yellow

        Write-Host ""
        Write-Host "  Archivos encontrados:" -ForegroundColor Gray
        Get-ChildItem "C:\FTP_Data\http\Windows" -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "    $($_.FullName)" -ForegroundColor DarkGray }
        Write-Host ""

        if (Confirmar-Paso -Pregunta "¿El repositorio ya esta listo y desea omitir este paso") {
            Marcar-Completado -Paso "PASO2"
            Write-Host "  Paso 2 omitido (repositorio ya preparado)." -ForegroundColor Green
        }
        else {
            if (Verificar-Script "preparar_repositorio.ps1") {
                Read-Host "  Presione Enter para ejecutar preparar_repositorio.ps1"
                & "$scriptDir\preparar_repositorio.ps1"
                Marcar-Completado -Paso "PASO2"
            }
        }
    }
    else {
        Write-Host "  El repositorio no esta listo. Se ejecutara preparar_repositorio.ps1" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Este script descargara automaticamente:" -ForegroundColor Gray
        Write-Host "    - Apache Win64 (LTS + Latest)" -ForegroundColor Gray
        Write-Host "    - Nginx Windows (LTS + Latest)" -ForegroundColor Gray
        Write-Host "    - Placeholder para IIS" -ForegroundColor Gray
        Write-Host "    - Archivos .sha256 para cada uno" -ForegroundColor Gray
        Write-Host ""

        if (Confirmar-Paso -Pregunta "¿Desea preparar el repositorio ahora") {
            if (Verificar-Script "preparar_repositorio.ps1") {
                & "$scriptDir\preparar_repositorio.ps1"
                Marcar-Completado -Paso "PASO2"
            }
        }
        else {
            Write-Host "  Paso 2 omitido por el usuario." -ForegroundColor Yellow
        }
    }
}

# ============================================================
# PASO 3: Instalacion hibrida + SSL/TLS (Practica 7)
# ============================================================
Mostrar-Paso -Num 3 -Titulo "Instalacion Hibrida + SSL/TLS (Practica 7)" `
    -Descripcion "Instala IIS, Apache y Nginx desde WEB o FTP privado. Activa SSL/TLS y FTPS."

if (Paso-Completado -Paso "PASO3") {
    Write-Host "  Este paso ya fue completado anteriormente." -ForegroundColor Green
    Write-Host ""
    if (Confirmar-Paso -Pregunta "¿Desea volver a abrir el menu de P7 de todas formas") {
        if (Verificar-Script "main_p7.ps1") {
            & "$scriptDir\main_p7.ps1"
        }
    }
}
else {
    Write-Host "  Recuerde que si elige la fuente FTP necesitara:" -ForegroundColor Gray

    # Intentar sugerir el usuario creado en el paso 1
    $usuarioSugerido = "ftprepo"
    if (Test-Path $estadoFile) {
        $lineaUsuario = Get-Content $estadoFile | Where-Object { $_ -match "^USUARIO_REPO=" }
        if ($lineaUsuario) { $usuarioSugerido = $lineaUsuario.Split("=")[1] }
    }

    Write-Host "    - IP del servidor FTP (este mismo servidor si es todo en una maquina)" -ForegroundColor Gray
    Write-Host "    - Usuario FTP : $usuarioSugerido" -ForegroundColor Yellow
    Write-Host "    - Contrasena  : la que ingreso en el Paso 1" -ForegroundColor Yellow
    Write-Host ""

    if (Confirmar-Paso -Pregunta "¿Desea iniciar el menu principal de la Practica 7") {
        if (Verificar-Script "main_p7.ps1") {
            & "$scriptDir\main_p7.ps1"
            Marcar-Completado -Paso "PASO3"
        }
    }
    else {
        Write-Host "  Paso 3 omitido por el usuario." -ForegroundColor Yellow
    }
}

# ============================================================
# FINALIZACION
# ============================================================
Write-Host ""
Write-Host "################################################################" -ForegroundColor Green
Write-Host "#                                                              #" -ForegroundColor Green
Write-Host "#             CONFIGURACION COMPLETA                          #" -ForegroundColor Green
Write-Host "#                                                              #" -ForegroundColor Green
Write-Host "################################################################" -ForegroundColor Green
Write-Host ""
Write-Host "Resumen de lo configurado:" -ForegroundColor Cyan
Write-Host ""

$checks = @(
    @{ Nombre = "Servicio FTP (puerto 21)";  Puerto = 21  },
    @{ Nombre = "FTPS (puerto 990)";         Puerto = 990 },
    @{ Nombre = "HTTP puerto 80";            Puerto = 80  },
    @{ Nombre = "HTTPS puerto 443";          Puerto = 443 }
)

foreach ($c in $checks) {
    $test = Test-NetConnection -ComputerName localhost -Port $c.Puerto -WarningAction SilentlyContinue
    $est  = if ($test.TcpTestSucceeded) { "ACTIVO  " } else { "INACTIVO" }
    $col  = if ($test.TcpTestSucceeded) { "Green"    } else { "Gray"    }
    Write-Host ("  {0,-28} -> {1}" -f $c.Nombre, $est) -ForegroundColor $col
}

Write-Host ""
Write-Host "Para verificar individualmente ejecute: .\main_p7.ps1 -> opcion 8" -ForegroundColor Gray
Write-Host ""
