# ============================================================
#  funciones_p8.ps1 - Libreria de funciones para la Practica 8
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
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |       INSTALACION DE DEPENDENCIAS        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # Lista de roles/caracteristicas que necesitamos
    $dependencias = @(
        @{ Nombre = "AD-Domain-Services";  Descripcion = "Active Directory Domain Services" },
        @{ Nombre = "DNS";                 Descripcion = "Servidor DNS"                     },
        @{ Nombre = "FS-Resource-Manager"; Descripcion = "FSRM (Cuotas y Apantallamiento)"  },
        @{ Nombre = "RSAT-AD-PowerShell";  Descripcion = "Herramientas PowerShell para AD"  },
        @{ Nombre = "RSAT-ADDS";           Descripcion = "Herramientas de administracion AD" }
    )

    # Verificar cuales ya estan instaladas
    Write-Host "  Verificando estado de las dependencias..." -ForegroundColor Yellow
    Write-Host ""

    $yaInstaladas = @()
    $porInstalar  = @()

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
        Write-Host "  Todas las dependencias ya estan instaladas." -ForegroundColor Green
        Write-Host ""
        $respuesta = Read-Host "  Deseas reinstalar de todas formas? (s/n)"
        if ($respuesta -ne "s") {
            Write-Host ""
            Write-Host "  Instalacion cancelada. No se hizo ningun cambio." -ForegroundColor Yellow
            Write-Host ""
            return
        }
        $porInstalar = $dependencias
    }

    # --- Caso 2: Faltan dependencias o el usuario quiere reinstalar ---
    Write-Host "  Se instalaran las siguientes dependencias:" -ForegroundColor Yellow
    foreach ($dep in $porInstalar) {
        Write-Host "    -> $($dep.Descripcion)" -ForegroundColor White
    }
    Write-Host ""
    $confirmar = Read-Host "  Confirmas la instalacion? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Instalacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Instalar ---
    Write-Host ""
    Write-Host "  Iniciando instalacion, esto puede tardar unos minutos..." -ForegroundColor Cyan
    Write-Host ""

    foreach ($dep in $porInstalar) {
        Write-Host "  Instalando: $($dep.Descripcion)..." -ForegroundColor Yellow
        $resultado = Install-WindowsFeature -Name $dep.Nombre -IncludeManagementTools
        if ($resultado.Success) {
            Write-Host "  [OK] $($dep.Descripcion) instalado correctamente." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Fallo al instalar $($dep.Descripcion)." -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Instalacion finalizada.                  |" -ForegroundColor Cyan
    Write-Host "  | Siguiente paso: opcion 2 del menu para   |" -ForegroundColor Yellow
    Write-Host "  | promover el servidor a Domain Controller. |" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 2: Promover servidor a Domain Controller
# Verifica que AD DS este instalado, verifica que el servidor
# no sea ya un DC, y crea el bosque practica8.local.
# Al finalizar reinicia el servidor (obligatorio).
# ------------------------------------------------------------
function Promover-DomainController {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |     PROMOVER A DOMAIN CONTROLLER         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # --- Verificar que AD DS este instalado ---
    $adds = Get-WindowsFeature -Name "AD-Domain-Services"
    if ($adds.InstallState -ne "Installed") {
        Write-Host "  [ERROR] Active Directory Domain Services no esta instalado." -ForegroundColor Red
        Write-Host "  Ejecuta primero la opcion 1 para instalar las dependencias." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Verificar si ya es Domain Controller ---
    $esDC = $false
    try {
        $domainInfo = Get-ADDomain -ErrorAction Stop
        $esDC = $true
    } catch {
        $esDC = $false
    }

    if ($esDC) {
        Write-Host "  [INFO] Este servidor ya es Domain Controller del dominio:" -ForegroundColor Yellow
        Write-Host "         $($domainInfo.DNSRoot)" -ForegroundColor White
        Write-Host ""
        Write-Host "  No es necesario volver a promoverlo." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Informar al usuario lo que se va a hacer ---
    Write-Host "  Se creara un nuevo bosque de Active Directory con los" -ForegroundColor White
    Write-Host "  siguientes parametros:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Dominio        : practica8.local" -ForegroundColor Cyan
    Write-Host "    Nivel de bosque: Windows Server 2016" -ForegroundColor Cyan
    Write-Host "    DNS            : Se instalara en este servidor" -ForegroundColor Cyan
    Write-Host "    IP del servidor: 192.168.1.202" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ADVERTENCIA: El servidor se reiniciara automaticamente" -ForegroundColor Red
    Write-Host "  al finalizar. Guarda cualquier trabajo pendiente." -ForegroundColor Red
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Pedir contrasena para el modo de restauracion de AD (DSRM) ---
    # El DSRM es una contrasena de emergencia para recuperar AD si algo falla.
    # Es diferente a la contrasena del Administrador.
    Write-Host ""
    Write-Host "  Se requiere una contrasena para el Modo de Restauracion de AD (DSRM)." -ForegroundColor Yellow
    Write-Host "  Esta contrasena se usa en caso de emergencia para recuperar AD." -ForegroundColor White
    Write-Host "  Debe cumplir los requisitos de complejidad de Windows." -ForegroundColor White
    Write-Host ""

    $dsrmPassword = Read-Host "  Ingresa la contrasena DSRM" -AsSecureString

    # --- Configurar DNS estatico apuntando a si mismo ---
    Write-Host ""
    Write-Host "  Configurando DNS estatico en el adaptador de red interna..." -ForegroundColor Yellow

    # Buscar el adaptador con la IP 192.168.1.202
    $adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ip.IPAddress -eq "192.168.1.202") { $_ }
    }

    if ($adaptador) {
        Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses "192.168.1.202"
        Write-Host "  [OK] DNS configurado en el adaptador: $($adaptador.Name)" -ForegroundColor Green
    } else {
        Write-Host "  [AVISO] No se encontro el adaptador con IP 192.168.1.202." -ForegroundColor Yellow
        Write-Host "  Continuando de todas formas..." -ForegroundColor Yellow
    }

    # --- Promover el servidor ---
    Write-Host ""
    Write-Host "  Iniciando promocion a Domain Controller..." -ForegroundColor Cyan
    Write-Host "  Esto puede tardar varios minutos..." -ForegroundColor Cyan
    Write-Host ""

    try {
        Install-ADDSForest `
            -DomainName "practica8.local" `
            -DomainNetbiosName "PRACTICA8" `
            -ForestMode "WinThreshold" `
            -DomainMode "WinThreshold" `
            -InstallDns:$true `
            -SafeModeAdministratorPassword $dsrmPassword `
            -NoRebootOnCompletion:$false `
            -Force:$true

        # Nota: si -NoRebootOnCompletion es $false, el servidor
        # se reinicia automaticamente y no llega a esta linea.
        Write-Host "  [OK] Promocion completada. El servidor se reiniciara ahora." -ForegroundColor Green

    } catch {
        Write-Host ""
        Write-Host "  [ERROR] Fallo la promocion a Domain Controller." -ForegroundColor Red
        Write-Host "  Detalle: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
    }
}
