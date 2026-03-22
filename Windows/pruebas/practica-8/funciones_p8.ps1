# ============================================================
#  funciones.ps1 - Libreria de funciones para la Practica 8
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
# ============================================================

# ------------------------------------------------------------
# FUNCION 1: Instalar Dependencias
# Instala los roles y caracteristicas necesarios para la
# practica: AD DS, DNS, FSRM y herramientas de AD.
# Si ya estan instalados, pregunta si se desea reinstalar.
# ------------------------------------------------------------
function Instalar-Dependencias {

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   INSTALACION DE DEPENDENCIAS             " -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""

    # Lista de roles/caracteristicas que necesitamos
    $dependencias = @(
        @{ Nombre = "AD-Domain-Services";        Descripcion = "Active Directory Domain Services" },
        @{ Nombre = "DNS";                        Descripcion = "Servidor DNS"                    },
        @{ Nombre = "FS-Resource-Manager";        Descripcion = "FSRM (Cuotas y Apantallamiento)" },
        @{ Nombre = "RSAT-AD-PowerShell";         Descripcion = "Herramientas PowerShell para AD" },
        @{ Nombre = "RSAT-ADDS";                  Descripcion = "Herramientas de administracion AD"}
    )

    # Verificar cuales ya estan instaladas
    Write-Host "Verificando estado de las dependencias..." -ForegroundColor Yellow
    Write-Host ""

    $yaInstaladas  = @()
    $porInstalar   = @()

    foreach ($dep in $dependencias) {
        $feature = Get-WindowsFeature -Name $dep.Nombre
        if ($feature.InstallState -eq "Installed") {
            Write-Host "  [OK] $($dep.Descripcion)" -ForegroundColor Green
            $yaInstaladas += $dep
        } else {
            Write-Host "  [--] $($dep.Descripcion)" -ForegroundColor Red
            $porInstalar += $dep
        }
    }

    Write-Host ""

    # --- Caso 1: Todo ya esta instalado ---
    if ($porInstalar.Count -eq 0) {
        Write-Host "Todas las dependencias ya estan instaladas." -ForegroundColor Green
        Write-Host ""
        $respuesta = Read-Host "Deseas reinstalar de todas formas? (s/n)"
        if ($respuesta -ne "s") {
            Write-Host ""
            Write-Host "Instalacion cancelada. No se hizo ningun cambio." -ForegroundColor Yellow
            Write-Host ""
            return
        }
        # Si dijo que si, reinstalamos todo
        $porInstalar = $dependencias
    }

    # --- Caso 2: Algunas o todas faltan, o el usuario quiere reinstalar ---
    Write-Host "Se instalaran las siguientes dependencias:" -ForegroundColor Yellow
    foreach ($dep in $porInstalar) {
        Write-Host "  -> $($dep.Descripcion)" -ForegroundColor White
    }
    Write-Host ""
    $confirmar = Read-Host "Confirmas la instalacion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "Instalacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Instalar ---
    Write-Host ""
    Write-Host "Iniciando instalacion, esto puede tardar unos minutos..." -ForegroundColor Cyan
    Write-Host ""

    foreach ($dep in $porInstalar) {
        Write-Host "Instalando: $($dep.Descripcion)..." -ForegroundColor Yellow
        $resultado = Install-WindowsFeature -Name $dep.Nombre -IncludeManagementTools
        if ($resultado.Success) {
            Write-Host "  [OK] $($dep.Descripcion) instalado correctamente." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Fallo al instalar $($dep.Descripcion)." -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host " Instalacion finalizada." -ForegroundColor Cyan
    Write-Host " IMPORTANTE: Si instalaste AD DS por primera " -ForegroundColor Yellow
    Write-Host " vez, debes ejecutar la opcion 2 del menu   " -ForegroundColor Yellow
    Write-Host " para promover el servidor a Domain Controller" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}
