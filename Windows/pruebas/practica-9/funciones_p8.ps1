# ============================================================
#  funciones_p8.ps1 - Libreria de funciones para la Practica 8
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
# ============================================================

# ------------------------------------------------------------
# CONSTANTES GLOBALES
# Definidas una sola vez aqui. perfiles_moviles_p8.ps1 las
# hereda via dot-sourcing de este archivo.
# ------------------------------------------------------------
$script:CARPETA_PERFILES  = "C:\PerfilesMoviles"
$script:SHARE_NAME        = "Perfiles`$"
$script:SERVIDOR          = "192.168.1.202"
$script:SHARE_UNC         = "\\$($script:SERVIDOR)\Perfiles`$"
$script:CARPETA_USUARIOS  = "C:\Usuarios"
$script:UNC_USUARIOS      = "\\$($script:SERVIDOR)\Usuarios"

# ------------------------------------------------------------
# UTILIDAD GLOBAL: Build-LogonHours
# Construye el array de 21 bytes para el atributo logonHours
# de AD. Definida UNA SOLA VEZ aqui para que la usen tanto
# Configurar-Horarios como Crear-UsuarioDinamico.
# ------------------------------------------------------------
function Build-LogonHours {
    param([int[]]$HorasUTC)
    $bits = New-Object bool[] 168
    for ($dia = 0; $dia -lt 7; $dia++) {
        foreach ($hora in $HorasUTC) {
            $bits[$dia * 24 + $hora] = $true
        }
    }
    $bytes = New-Object byte[] 21
    for ($i = 0; $i -lt 168; $i++) {
        if ($bits[$i]) {
            $bytes[[math]::Floor($i / 8)] = $bytes[[math]::Floor($i / 8)] -bor (1 -shl ($i % 8))
        }
    }
    return $bytes
}

# ------------------------------------------------------------
# UTILIDAD GLOBAL: Get-TamanoMB
# Calcula el tamano recursivo de una carpeta en MB.
# Devuelve 0 si la carpeta no existe o esta vacia.
# ------------------------------------------------------------
function Get-TamanoMB {
    param([string]$Ruta)
    if (-not (Test-Path $Ruta)) { return 0 }
    $bytes = (Get-ChildItem $Ruta -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($bytes) { return [math]::Round($bytes / 1MB, 2) } else { return 0 }
}

# ------------------------------------------------------------
# UTILIDAD GLOBAL: Crear-PlantillasFSRM
# Crea (si no existen) las plantillas de cuota y el grupo/
# plantilla de apantallamiento. Llamada desde opcion 5 y
# desde perfiles_moviles_p8.ps1. Sin duplicacion.
# ------------------------------------------------------------
function Crear-PlantillasFSRM {
    $plantillas = @(
        @{ Nombre = "Practica8-Cuates-10MB";  Tamano = 10MB },
        @{ Nombre = "Practica8-NoCuates-5MB"; Tamano = 5MB  }
    )
    foreach ($p in $plantillas) {
        try {
            if (-not (Get-FsrmQuotaTemplate -Name $p.Nombre -ErrorAction SilentlyContinue)) {
                New-FsrmQuotaTemplate -Name $p.Nombre -Size $p.Tamano -SoftLimit:$false | Out-Null
                Write-Host "  [OK] Plantilla cuota '$($p.Nombre)' creada." -ForegroundColor Green
            }
        } catch {
            Write-Host "  [WARN] Plantilla '$($p.Nombre)': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    $grupoNombre = "Practica8-ArchivosProhibidos"
    try {
        if (Get-FsrmFileGroup -Name $grupoNombre -ErrorAction SilentlyContinue) {
            Set-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
        } else {
            New-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Host "  [OK] Grupo archivos prohibidos creado." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Grupo FSRM: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $plantillaScreen = "Practica8-Apantallamiento"
    try {
        if (Get-FsrmFileScreenTemplate -Name $plantillaScreen -ErrorAction SilentlyContinue) {
            Set-FsrmFileScreenTemplate -Name $plantillaScreen -Active:$true -IncludeGroup @($grupoNombre) | Out-Null
        } else {
            New-FsrmFileScreenTemplate -Name $plantillaScreen -Active:$true -IncludeGroup @($grupoNombre) | Out-Null
            Write-Host "  [OK] Plantilla apantallamiento creada." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Plantilla screen: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# ------------------------------------------------------------
# FUNCION 1: Instalar Dependencias
# ------------------------------------------------------------
function Instalar-Dependencias {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |       INSTALACION DE DEPENDENCIAS        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $dependencias = @(
        @{ Nombre = "AD-Domain-Services";  Descripcion = "Active Directory Domain Services" },
        @{ Nombre = "DNS";                 Descripcion = "Servidor DNS"                     },
        @{ Nombre = "FS-Resource-Manager"; Descripcion = "FSRM (Cuotas y Apantallamiento)"  },
        @{ Nombre = "RSAT-AD-PowerShell";  Descripcion = "Herramientas PowerShell para AD"  },
        @{ Nombre = "RSAT-ADDS";           Descripcion = "Herramientas de administracion AD" }
    )

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

    if ($porInstalar.Count -eq 0) {
        Write-Host "  Todas las dependencias ya estan instaladas." -ForegroundColor Green
        Write-Host ""
        $respuesta = Read-Host "  Deseas reinstalar de todas formas? (s/n)"
        if ($respuesta -ne "s") {
            Write-Host ""
            Write-Host "  Instalacion cancelada." -ForegroundColor Yellow
            Write-Host ""
            return
        }
        $porInstalar = $dependencias
    }

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

    Write-Host ""
    Write-Host "  Iniciando instalacion..." -ForegroundColor Cyan
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
    Write-Host "  | Siguiente paso: opcion 2 del menu.       |" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 2: Promover servidor a Domain Controller
# ------------------------------------------------------------
function Promover-DomainController {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |     PROMOVER A DOMAIN CONTROLLER         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $adds = Get-WindowsFeature -Name "AD-Domain-Services"
    if ($adds.InstallState -ne "Installed") {
        Write-Host "  [ERROR] AD-Domain-Services no esta instalado." -ForegroundColor Red
        Write-Host "  Ejecuta primero la opcion 1." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $esDC = $false
    try {
        $domainInfo = Get-ADDomain -ErrorAction Stop
        $esDC = $true
    } catch {
        $esDC = $false
    }

    if ($esDC) {
        Write-Host "  [INFO] Este servidor ya es Domain Controller:" -ForegroundColor Yellow
        Write-Host "         $($domainInfo.DNSRoot)" -ForegroundColor White
        Write-Host ""
        return
    }

    Write-Host "  Parametros del nuevo bosque:" -ForegroundColor White
    Write-Host "    Dominio : practica8.local" -ForegroundColor Cyan
    Write-Host "    IP      : 192.168.1.202"   -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  ADVERTENCIA: El servidor se reiniciara." -ForegroundColor Red
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    $dsrmPassword = Read-Host "  Ingresa la contrasena DSRM" -AsSecureString

    Write-Host ""
    Write-Host "  Configurando DNS estatico..." -ForegroundColor Yellow

    $adaptador = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object {
        $ip = Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        if ($ip.IPAddress -eq "192.168.1.202") { $_ }
    }

    if ($adaptador) {
        Set-DnsClientServerAddress -InterfaceIndex $adaptador.ifIndex -ServerAddresses "192.168.1.202"
        Write-Host "  [OK] DNS configurado: $($adaptador.Name)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  Iniciando promocion..." -ForegroundColor Cyan

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
    } catch {
        Write-Host ""
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }
}


# ------------------------------------------------------------
# FUNCION 3: Crear OUs y usuarios desde CSV
# ------------------------------------------------------------
function Crear-OUsYUsuarios {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |       CREAR OUs Y USUARIOS DESDE CSV     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] AD no disponible. Ejecuta opciones 1 y 2 primero." -ForegroundColor Red
        return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv en: $csvPath" -ForegroundColor Red
        return
    }

    $usuarios = Import-Csv -Path $csvPath
    Write-Host "  $($usuarios.Count) usuarios encontrados en el CSV." -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Crear OUs y usuarios? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""
    $dcBase = $dominio.DistinguishedName

    foreach ($ou in @("Cuates", "NoCuates")) {
        $ouPath = "OU=$ou,$dcBase"
        try {
            Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
            Write-Host "  [OK] OU '$ou' ya existe." -ForegroundColor Yellow
        } catch {
            try {
                New-ADOrganizationalUnit -Name $ou -Path $dcBase -ProtectedFromAccidentalDeletion $false
                Write-Host "  [CREADO] OU '$ou'." -ForegroundColor Green
            } catch {
                Write-Host "  [ERROR] OU '$ou': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "  Creando usuarios..." -ForegroundColor Yellow
    Write-Host ""

    $creados  = 0
    $omitidos = 0
    $errores  = 0

    foreach ($u in $usuarios) {
        $ouDestino = "OU=$($u.Departamento),$dcBase"
        try {
            Get-ADUser -Identity $u.Usuario -ErrorAction Stop | Out-Null
            Write-Host "  [OMITIDO] '$($u.Usuario)' ya existe." -ForegroundColor Yellow
            $omitidos++
            continue
        } catch {}

        try {
            $passwordSegura = ConvertTo-SecureString $u.Password -AsPlainText -Force
            New-ADUser `
                -Name "$($u.Nombre) $($u.Apellido)" `
                -GivenName $u.Nombre `
                -Surname $u.Apellido `
                -SamAccountName $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@practica8.local" `
                -Path $ouDestino `
                -AccountPassword $passwordSegura `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -ChangePasswordAtLogon $false
            Write-Host "  [CREADO] $($u.Nombre) $($u.Apellido) -> $($u.Departamento)" -ForegroundColor Green
            $creados++
        } catch {
            Write-Host "  [ERROR] '$($u.Usuario)': $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    Write-Host ""
    Write-Host "  Creando grupos de seguridad..." -ForegroundColor Yellow

    foreach ($g in @(
        @{ Nombre = "Cuates";   OU = "OU=Cuates,$dcBase"   },
        @{ Nombre = "NoCuates"; OU = "OU=NoCuates,$dcBase" }
    )) {
        try {
            Get-ADGroup -Identity $g.Nombre -ErrorAction Stop | Out-Null
            Write-Host "  [OK] Grupo '$($g.Nombre)' ya existe." -ForegroundColor Yellow
        } catch {
            try {
                New-ADGroup -Name $g.Nombre -GroupScope Global -GroupCategory Security -Path $g.OU
                Write-Host "  [CREADO] Grupo '$($g.Nombre)'." -ForegroundColor Green
            } catch {
                Write-Host "  [ERROR] Grupo '$($g.Nombre)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "  Agregando usuarios a grupos..." -ForegroundColor Yellow
    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity $u.Departamento -Members $u.Usuario -ErrorAction Stop
            Write-Host "  [OK] $($u.Usuario) -> $($u.Departamento)" -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Creados : $creados | Omitidos: $omitidos | Errores: $errores |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 4: Configurar horarios de acceso (Logon Hours)
#
# UTC-7 (Los Mochis, Sinaloa)
# Cuates   : 08:00-15:00 local = 15:00-22:00 UTC
# NoCuates : 15:00-12:00 local = 22:00-19:00 UTC (21 horas)
# ------------------------------------------------------------
function Configurar-Horarios {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |     CONFIGURAR HORARIOS DE ACCESO        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] AD no disponible." -ForegroundColor Red
        return
    }

    Write-Host "  Zona horaria: UTC-7 (Los Mochis, Sinaloa)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Horarios locales:" -ForegroundColor White
    Write-Host "    Cuates   : 08:00 AM - 03:00 PM" -ForegroundColor Cyan
    Write-Host "    NoCuates : 03:00 PM - 12:00 PM (mediodia siguiente)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Equivalencia UTC:" -ForegroundColor White
    Write-Host "    Cuates   : 15:00 - 22:00 UTC  (7 horas)" -ForegroundColor DarkCyan
    Write-Host "    NoCuates : 22:00 - 19:00 UTC  (21 horas)" -ForegroundColor DarkCyan
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    # Usa la funcion global Build-LogonHours definida al inicio del archivo
    $horasUTC_Cuates   = @(15,16,17,18,19,20,21)
    $horasUTC_NoCuates = @(22,23,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18)

    $bytesCuates   = Build-LogonHours -HorasUTC $horasUTC_Cuates
    $bytesNoCuates = Build-LogonHours -HorasUTC $horasUTC_NoCuates

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red
        return
    }

    $usuarios = Import-Csv -Path $csvPath

    Write-Host ""
    Write-Host "  Aplicando horarios..." -ForegroundColor Yellow
    Write-Host ""

    foreach ($u in $usuarios) {
        try {
            if ($u.Departamento -eq "Cuates") {
                Set-ADUser -Identity $u.Usuario -Clear logonHours
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = ([byte[]]$bytesCuates)}
                Write-Host "  [OK] $($u.Usuario) -> Cuates (08:00-15:00 local)" -ForegroundColor Green
            } elseif ($u.Departamento -eq "NoCuates") {
                Set-ADUser -Identity $u.Usuario -Clear logonHours
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = ([byte[]]$bytesNoCuates)}
                Write-Host "  [OK] $($u.Usuario) -> NoCuates (15:00-12:00 local)" -ForegroundColor Green
            } else {
                Write-Host "  [AVISO] $($u.Usuario): departamento desconocido." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [ERROR] $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Configurando GPO de cierre de sesion forzado..." -ForegroundColor Yellow

    $gpoNombre = "Practica8-LogonHours"
    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre'." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO ya existe, se actualiza." -ForegroundColor Yellow
        }

        Set-GPRegistryValue `
            -Name $gpoNombre `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
            -ValueName "EnableForcedLogOff" `
            -Type DWord `
            -Value 1 | Out-Null

        Write-Host "  [OK] Cierre forzado configurado." -ForegroundColor Green

        $dcBase = $dominio.DistinguishedName
        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya estaba vinculada." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] GPO: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Horarios configurados.                   |" -ForegroundColor Cyan
    Write-Host "  | Cuates   : 08:00-15:00 local             |" -ForegroundColor Cyan
    Write-Host "  | NoCuates : 15:00-12:00 local (21 horas)  |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 5: Configurar perfiles moviles + FSRM integrado
# ------------------------------------------------------------
function Configurar-PerfilesYFSRM {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PERFILES MOVILES + CUOTAS FSRM         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] AD no disponible." -ForegroundColor Red
        return
    }

    $fsrm = Get-WindowsFeature -Name "FS-Resource-Manager"
    if ($fsrm.InstallState -ne "Installed") {
        Write-Host "  [ERROR] FSRM no instalado. Ejecuta opcion 1." -ForegroundColor Red
        return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red
        return
    }

    $usuarios = Import-Csv -Path $csvPath

    Write-Host "  Configuracion que se aplicara:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Carpeta perfiles : $($script:CARPETA_PERFILES)" -ForegroundColor Cyan
    Write-Host "    Ruta de red      : $($script:SHARE_UNC)"        -ForegroundColor Cyan
    Write-Host "    Cuates           : 10 MB por usuario"           -ForegroundColor Cyan
    Write-Host "    NoCuates         :  5 MB por usuario"           -ForegroundColor Cyan
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""

    # PASO A: Crear carpeta raiz
    Write-Host "  [A] Creando carpeta de perfiles moviles..." -ForegroundColor Yellow
    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        New-Item -Path $script:CARPETA_PERFILES -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $($script:CARPETA_PERFILES)" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Carpeta ya existe: $($script:CARPETA_PERFILES)" -ForegroundColor Yellow
    }

    # PASO B: Permisos NTFS
    Write-Host "  [B] Configurando permisos NTFS..." -ForegroundColor Yellow
    try {
        $acl = Get-Acl $script:CARPETA_PERFILES
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM", "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Admins", "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "CREATOR OWNER", "FullControl",
            "ContainerInherit,ObjectInherit", "InheritOnly", "Allow")))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users", "ReadAndExecute, CreateDirectories",
            "None", "None", "Allow")))
        Set-Acl $script:CARPETA_PERFILES $acl
        Write-Host "  [OK] Permisos NTFS configurados." -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Permisos NTFS: $($_.Exception.Message)" -ForegroundColor Red
    }

    # PASO C: Compartir carpeta
    Write-Host "  [C] Configurando recurso compartido..." -ForegroundColor Yellow
    $shareExiste = Get-SmbShare -Name $script:SHARE_NAME -ErrorAction SilentlyContinue
    if ($shareExiste) {
        Remove-SmbShare -Name $script:SHARE_NAME -Force -ErrorAction SilentlyContinue
        Write-Host "  [INFO] Share anterior eliminado para recrear." -ForegroundColor DarkGray
    }
    try {
        New-SmbShare `
            -Name        $script:SHARE_NAME `
            -Path        $script:CARPETA_PERFILES `
            -FullAccess  "Everyone" `
            -Description "Perfiles Moviles Practica 08" | Out-Null
        Write-Host "  [OK] Compartido como: $($script:SHARE_UNC)" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Share: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # PASO D: Plantillas FSRM (usa la funcion global, sin duplicacion)
    Write-Host "  [D] Creando plantillas FSRM..." -ForegroundColor Yellow
    Crear-PlantillasFSRM

    Write-Host ""
    Write-Host "  Asignando perfiles y cuotas por usuario..." -ForegroundColor Yellow
    Write-Host ""

    $ok      = 0
    $errores = 0

    foreach ($u in $usuarios) {
        if ($u.Departamento -eq "Cuates") {
            $plantillaNombre = "Practica8-Cuates-10MB"
            $tamanoBytes     = 10MB
            $tamanoTexto     = "10 MB"
        } elseif ($u.Departamento -eq "NoCuates") {
            $plantillaNombre = "Practica8-NoCuates-5MB"
            $tamanoBytes     = 5MB
            $tamanoTexto     = " 5 MB"
        } else {
            Write-Host "  [AVISO] $($u.Usuario): departamento desconocido." -ForegroundColor Yellow
            continue
        }

        $rutaUNC      = "$($script:SHARE_UNC)\$($u.Usuario)"
        $carpetaLocal = "$($script:CARPETA_PERFILES)\$($u.Usuario)"

        try {
            Set-ADUser -Identity $u.Usuario -ProfilePath $rutaUNC -ErrorAction Stop
            Write-Host "  [AD] $($u.Usuario) ProfilePath -> $rutaUNC" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] ProfilePath $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
            continue
        }

        if (-not (Test-Path $carpetaLocal)) {
            try {
                New-Item -Path $carpetaLocal -ItemType Directory | Out-Null
                Write-Host "  [DIR] Creada: $carpetaLocal" -ForegroundColor DarkGreen
            } catch {
                Write-Host "  [ERROR] Carpeta $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
                $errores++
                continue
            }
        }

        try {
            $cuotaExistente  = Get-FsrmQuota -Path $carpetaLocal -ErrorAction SilentlyContinue
            $existePlantilla = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue

            if ($cuotaExistente) {
                if ($existePlantilla) { Set-FsrmQuota -Path $carpetaLocal -Template $plantillaNombre | Out-Null }
                else { Set-FsrmQuota -Path $carpetaLocal -Size $tamanoBytes -SoftLimit:$false | Out-Null }
                Write-Host "  [CUOTA] $($u.Usuario) ($($u.Departamento)) -> $tamanoTexto (actualizada)" -ForegroundColor Yellow
            } else {
                if ($existePlantilla) { New-FsrmQuota -Path $carpetaLocal -Template $plantillaNombre | Out-Null }
                else { New-FsrmQuota -Path $carpetaLocal -Size $tamanoBytes -SoftLimit:$false | Out-Null }
                Write-Host "  [CUOTA] $($u.Usuario) ($($u.Departamento)) -> $tamanoTexto" -ForegroundColor Green
            }
            $ok++
        } catch {
            Write-Host "  [ERROR] FSRM $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    # PASO E: GPO de perfiles moviles
    Write-Host ""
    Write-Host "  [E] Configurando GPO de perfiles moviles..." -ForegroundColor Yellow
    try {
        $gpoNombre = "Practica8-PerfilesMoviles"
        $dcBase    = $dominio.DistinguishedName

        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre'." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO ya existe, actualizando." -ForegroundColor Yellow
        }

        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
            -ValueName "CompatibleRUPSecurity" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkDefaultProfile" -Type DWord -Value 1 | Out-Null
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkTimeOut" -Type DWord -Value 0 | Out-Null

        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya vinculada." -ForegroundColor Yellow
        }
        gpupdate /force 2>&1 | Out-Null
        Write-Host "  [OK] GPO aplicada." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] GPO perfiles: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | PERFILES MOVILES + FSRM CONFIGURADOS     |" -ForegroundColor Cyan
    Write-Host "  | Cuotas OK: $ok | Errores: $errores"        -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 6: Configurar apantallamiento de archivos (FSRM)
# Aplica sobre C:\PerfilesMoviles\usuario
# Bloquea: .mp3 .mp4 .exe .msi  (Active Screening)
# ------------------------------------------------------------
function Configurar-Apantallamiento {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR APANTALLAMIENTO DE ARCHIVOS |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $fsrm = Get-WindowsFeature -Name "FS-Resource-Manager"
    if ($fsrm.InstallState -ne "Installed") {
        Write-Host "  [ERROR] FSRM no instalado. Ejecuta opcion 1." -ForegroundColor Red
        return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv" -ForegroundColor Red
        return
    }

    $usuarios = Import-Csv -Path $csvPath

    Write-Host "  Archivos bloqueados en carpetas de perfil:" -ForegroundColor White
    Write-Host "    Multimedia  : *.mp3, *.mp4" -ForegroundColor Cyan
    Write-Host "    Ejecutables : *.exe, *.msi" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Carpeta objetivo: $($script:CARPETA_PERFILES)\<usuario>" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        Write-Host "  [ERROR] No existe $($script:CARPETA_PERFILES). Ejecuta opcion 5." -ForegroundColor Red
        return
    }

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""

    # Crear/actualizar grupo y plantilla (usa funcion global)
    Crear-PlantillasFSRM

    $plantillaNombre = "Practica8-Apantallamiento"
    $creados  = 0
    $omitidos = 0
    $errores  = 0

    foreach ($u in $usuarios) {
        $carpetasAplicar = @()
        $carpetaBase = "$($script:CARPETA_PERFILES)\$($u.Usuario)"
        $carpetaV6   = "$($script:CARPETA_PERFILES)\$($u.Usuario).V6"

        if (Test-Path $carpetaBase) { $carpetasAplicar += $carpetaBase }
        if (Test-Path $carpetaV6)   { $carpetasAplicar += $carpetaV6   }

        if ($carpetasAplicar.Count -eq 0) {
            try {
                New-Item -Path $carpetaBase -ItemType Directory -Force | Out-Null
                $carpetasAplicar += $carpetaBase
            } catch {}
        }

        foreach ($carpeta in $carpetasAplicar) {
            try {
                $screenExistente = Get-FsrmFileScreen -Path $carpeta -ErrorAction SilentlyContinue
                if ($screenExistente) {
                    Set-FsrmFileScreen -Path $carpeta -Template $plantillaNombre | Out-Null
                    Write-Host "  [OK] $($u.Usuario) ($carpeta) -> actualizado" -ForegroundColor Yellow
                    $omitidos++
                } else {
                    New-FsrmFileScreen -Path $carpeta -Template $plantillaNombre | Out-Null
                    Write-Host "  [OK] $($u.Usuario) ($carpeta) -> .mp3 .mp4 .exe .msi bloqueados" -ForegroundColor Green
                    $creados++
                }
            } catch {
                Write-Host "  [ERROR] $($u.Usuario) ($carpeta): $($_.Exception.Message)" -ForegroundColor Red
                $errores++
            }
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | APANTALLAMIENTO                          |" -ForegroundColor Cyan
    Write-Host "  | Creados     : $creados"                    -ForegroundColor Green
    Write-Host "  | Actualizados: $omitidos"                   -ForegroundColor Yellow
    Write-Host "  | Errores     : $errores"                    -ForegroundColor Red
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 7: Configurar AppLocker
# ------------------------------------------------------------
function Configurar-AppLocker {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |         CONFIGURAR APPLOCKER             |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] AD no disponible." -ForegroundColor Red
        return
    }

    Write-Host "  Reglas:" -ForegroundColor White
    Write-Host "    Cuates   : notepad.exe PERMITIDO" -ForegroundColor Cyan
    Write-Host "    NoCuates : notepad.exe BLOQUEADO por Hash" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Hash (notepad.exe Windows 10 Pro):" -ForegroundColor White
    Write-Host "  0x70152C176B629E51FD283BD2F30ACFBDB1A129EA14D94889C1D32A742C104BBF" -ForegroundColor DarkGray
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""

    Write-Host "  Obteniendo SID del grupo NoCuates..." -ForegroundColor Yellow
    try {
        $sidNoCuates = (Get-ADGroup -Identity "NoCuates").SID.Value
        Write-Host "  [OK] SID NoCuates: $sidNoCuates" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] No se pudo obtener el SID: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    $hashValor   = "0x70152C176B629E51FD283BD2F30ACFBDB1A129EA14D94889C1D32A742C104BBF"
    $archivoSize = 200704
    $guid1       = [System.Guid]::NewGuid().ToString()

    Write-Host ""
    Write-Host "  Construyendo politica AppLocker..." -ForegroundColor Yellow

    $xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Permitir Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a23e-47ff-8e4a-4e3d41bc98b0" Name="Permitir ProgramFiles" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="b61c8b2c-a23e-47ff-8e4a-4e3d41bc98b1" Name="Permitir ProgramFiles x86" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES(X86)%\*"/></Conditions>
    </FilePathRule>
    <FileHashRule Id="$guid1" Name="Bloquear Notepad NoCuates" Description="Bloquea notepad.exe por hash" UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$hashValor" SourceFileName="notepad.exe" SourceFileLength="$archivoSize"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
  </RuleCollection>
  <RuleCollection Type="Appx" EnforcementMode="Enabled">
    <FilePublisherRule Id="a9e18c21-ff8f-43cf-b9fc-db40eed693ba" Name="Permitir apps Microsoft" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <FilePublisherRule Id="b9e18c21-ff8f-43cf-b9fc-db40eed693bb" Name="Permitir apps Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="CN=Microsoft Windows, O=Microsoft Corporation, L=Redmond, S=Washington, C=US" ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@

    $xmlPath = "C:\Windows\Temp\applocker_final.xml"
    $xmlPolicy | Out-File $xmlPath -Encoding UTF8 -Force
    Write-Host "  [OK] XML generado." -ForegroundColor Green

    Write-Host ""
    Write-Host "  Configurando GPO de AppLocker..." -ForegroundColor Yellow

    $gpoNombre = "Practica8-AppLocker"
    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre'." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO ya existe, actualizando." -ForegroundColor Yellow
        }

        $gpoId  = $gpo.Id.ToString()
        $dcBase = $dominio.DistinguishedName

        Set-AppLockerPolicy -XmlPolicy $xmlPath -Ldap "LDAP://CN={$gpoId},CN=Policies,CN=System,DC=practica8,DC=local"
        Write-Host "  [OK] Politica AppLocker aplicada." -ForegroundColor Green

        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya vinculada." -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "  Habilitando AppIDSvc..." -ForegroundColor Yellow
        sc.exe config AppIDSvc start= auto | Out-Null
        sc.exe start AppIDSvc 2>$null | Out-Null
        Write-Host "  [OK] AppIDSvc configurado." -ForegroundColor Green

    } catch {
        Write-Host "  [ERROR] GPO AppLocker: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | AppLocker configurado.                   |" -ForegroundColor Cyan
    Write-Host "  | Cuates   : notepad.exe PERMITIDO         |" -ForegroundColor Green
    Write-Host "  | NoCuates : notepad.exe BLOQUEADO (hash)  |" -ForegroundColor Red
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 8: Crear usuario dinamicamente
# ------------------------------------------------------------
function Crear-UsuarioDinamico {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |       CREAR USUARIO DINAMICAMENTE        |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] AD no disponible." -ForegroundColor Red
        return
    }

    $dcBase = $dominio.DistinguishedName

    $nombre = Read-Host "  Nombre"
    if ([string]::IsNullOrWhiteSpace($nombre)) { Write-Host "  [ERROR] Nombre vacio." -ForegroundColor Red; return }

    $apellido = Read-Host "  Apellido"
    if ([string]::IsNullOrWhiteSpace($apellido)) { Write-Host "  [ERROR] Apellido vacio." -ForegroundColor Red; return }

    $usuario = Read-Host "  Usuario (sin espacios)"
    if ([string]::IsNullOrWhiteSpace($usuario)) { Write-Host "  [ERROR] Usuario vacio." -ForegroundColor Red; return }

    try {
        Get-ADUser -Identity $usuario -ErrorAction Stop | Out-Null
        Write-Host "  [ERROR] El usuario '$usuario' ya existe." -ForegroundColor Red
        return
    } catch {}

    $password = Read-Host "  Password"
    if ([string]::IsNullOrWhiteSpace($password)) { Write-Host "  [ERROR] Password vacio." -ForegroundColor Red; return }

    Write-Host ""
    Write-Host "  Departamento:" -ForegroundColor White
    Write-Host "    1. Cuates   (08:00-15:00, cuota 10 MB)" -ForegroundColor Cyan
    Write-Host "    2. NoCuates (15:00-12:00, cuota  5 MB)" -ForegroundColor Cyan
    Write-Host ""
    $deptoOpcion = Read-Host "  Selecciona (1 o 2)"

    if ($deptoOpcion -eq "1")     { $departamento = "Cuates" }
    elseif ($deptoOpcion -eq "2") { $departamento = "NoCuates" }
    else { Write-Host "  [ERROR] Opcion invalida." -ForegroundColor Red; return }

    $confirmar = Read-Host "  Confirmar creacion de $usuario en $departamento? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""

    # PASO 1: Crear usuario
    Write-Host "  [1/5] Creando usuario en AD..." -ForegroundColor Yellow
    try {
        $passwordSegura = ConvertTo-SecureString $password -AsPlainText -Force
        New-ADUser `
            -Name "$nombre $apellido" `
            -GivenName $nombre `
            -Surname $apellido `
            -SamAccountName $usuario `
            -UserPrincipalName "$usuario@practica8.local" `
            -Path "OU=$departamento,$dcBase" `
            -AccountPassword $passwordSegura `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -ChangePasswordAtLogon $false
        Write-Host "  [OK] Usuario '$usuario' creado en OU $departamento." -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # PASO 2: Agregar al grupo
    Write-Host ""
    Write-Host "  [2/5] Agregando al grupo $departamento..." -ForegroundColor Yellow
    try {
        Add-ADGroupMember -Identity $departamento -Members $usuario -ErrorAction Stop
        Write-Host "  [OK] Agregado a '$departamento'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # PASO 3: Horario (usa Build-LogonHours global)
    Write-Host ""
    Write-Host "  [3/5] Aplicando horario..." -ForegroundColor Yellow
    try {
        $horasUTC = if ($departamento -eq "Cuates") {
            @(15,16,17,18,19,20,21)
        } else {
            @(22,23,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18)
        }
        $bytesHorario = Build-LogonHours -HorasUTC $horasUTC
        Set-ADUser -Identity $usuario -Clear logonHours
        Set-ADUser -Identity $usuario -Replace @{logonHours = ([byte[]]$bytesHorario)}
        Write-Host "  [OK] Horario aplicado." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Horario: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # PASO 4: Perfil movil + cuota FSRM
    Write-Host ""
    Write-Host "  [4/5] Perfil movil y cuota FSRM..." -ForegroundColor Yellow

    $rutaUNC      = "$($script:SHARE_UNC)\$usuario"
    $carpetaLocal = "$($script:CARPETA_PERFILES)\$usuario"

    try {
        Set-ADUser -Identity $usuario -ProfilePath $rutaUNC -ErrorAction Stop
        Write-Host "  [OK] ProfilePath -> $rutaUNC" -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] ProfilePath: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    if (-not (Test-Path $carpetaLocal)) {
        try {
            New-Item -Path $carpetaLocal -ItemType Directory | Out-Null
            Write-Host "  [OK] Carpeta creada: $carpetaLocal" -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] Carpeta: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    try {
        $plantillaNombre = if ($departamento -eq "Cuates") { "Practica8-Cuates-10MB" } else { "Practica8-NoCuates-5MB" }
        $tamanoBytes     = if ($departamento -eq "Cuates") { 10MB } else { 5MB }
        $tamanoTexto     = if ($departamento -eq "Cuates") { "10 MB" } else { " 5 MB" }

        $existePlantilla = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue
        $cuotaExistente  = Get-FsrmQuota -Path $carpetaLocal -ErrorAction SilentlyContinue

        if ($cuotaExistente) {
            if ($existePlantilla) { Set-FsrmQuota -Path $carpetaLocal -Template $plantillaNombre | Out-Null }
            else { Set-FsrmQuota -Path $carpetaLocal -Size $tamanoBytes -SoftLimit:$false | Out-Null }
        } else {
            if ($existePlantilla) { New-FsrmQuota -Path $carpetaLocal -Template $plantillaNombre | Out-Null }
            else { New-FsrmQuota -Path $carpetaLocal -Size $tamanoBytes -SoftLimit:$false | Out-Null }
        }
        Write-Host "  [OK] Cuota $tamanoTexto aplicada." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Cuota: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # PASO 5: Apantallamiento
    Write-Host ""
    Write-Host "  [5/5] Apantallamiento de archivos..." -ForegroundColor Yellow
    $plantillaScreen = "Practica8-Apantallamiento"
    try {
        if (-not (Get-FsrmFileScreenTemplate -Name $plantillaScreen -ErrorAction SilentlyContinue)) {
            Write-Host "  [AVISO] Plantilla apantallamiento no existe. Ejecuta opcion 6." -ForegroundColor Yellow
        } else {
            $screenExistente = Get-FsrmFileScreen -Path $carpetaLocal -ErrorAction SilentlyContinue
            if ($screenExistente) {
                Set-FsrmFileScreen -Path $carpetaLocal -Template $plantillaScreen | Out-Null
            } else {
                New-FsrmFileScreen -Path $carpetaLocal -Template $plantillaScreen | Out-Null
            }
            Write-Host "  [OK] .mp3 .mp4 .exe .msi bloqueados." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [AVISO] Apantallamiento: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | USUARIO CREADO: $usuario@practica8.local" -ForegroundColor Green
    Write-Host "  | Grupo   : $departamento"                  -ForegroundColor Green
    Write-Host "  | Perfil  : $rutaUNC"                       -ForegroundColor Green
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 9: Ver perfiles almacenados en el servidor
#
# CORRECCION: mide AMBAS ubicaciones:
#   - C:\PerfilesMoviles  (perfil roaming .V6)
#   - C:\Usuarios         (redireccion Desktop/Documents)
# Antes solo media C:\PerfilesMoviles y siempre mostraba 0 MB
# durante sesion activa porque la sincronizacion ocurre al
# cerrar sesion. Los archivos del Escritorio/Documentos van
# a C:\Usuarios en tiempo real.
# ------------------------------------------------------------
function Ver-PerfilesAlmacenados {

    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |   PERFILES ALMACENADOS EN EL SERVIDOR      |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host ""

    # -------------------------------------------------------
    # SECCION 1: C:\PerfilesMoviles (perfil roaming .V6)
    # -------------------------------------------------------
    Write-Host "  SECCION 1: Perfiles Moviles (roaming)" -ForegroundColor Yellow
    Write-Host "  Carpeta : $($script:CARPETA_PERFILES)" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        Write-Host "  [INFO] $($script:CARPETA_PERFILES) no existe. Ejecuta opcion 5." -ForegroundColor Yellow
    } else {
        $carpetas = Get-ChildItem $script:CARPETA_PERFILES -ErrorAction SilentlyContinue
        if (-not $carpetas -or $carpetas.Count -eq 0) {
            Write-Host "  [INFO] Sin perfiles todavia." -ForegroundColor Yellow
            Write-Host "         Los perfiles .V6 aparecen al cerrar sesion en el cliente." -ForegroundColor DarkGray
        } else {
            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  | Nombre                    | Tamano     | Modificado          |" -ForegroundColor White
            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
            foreach ($c in $carpetas) {
                $mb    = Get-TamanoMB -Ruta $c.FullName
                $fecha = $c.LastWriteTime.ToString("dd/MM/yyyy HH:mm")
                $color = if ($c.Name -match "\.V6$") { "Green" } else { "Yellow" }
                Write-Host ("  | {0,-25} | {1,8} MB | {2,-19} |" -f $c.Name, $mb, $fecha) -ForegroundColor $color
            }
            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  Verde    = .V6 sincronizado (primer login completado)" -ForegroundColor Green
            Write-Host "  Amarillo = carpeta base, usuario no ha hecho login aun" -ForegroundColor Yellow
        }
    }

    # -------------------------------------------------------
    # SECCION 2: C:\Usuarios (redireccion Desktop/Documents)
    # -------------------------------------------------------
    Write-Host ""
    Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  SECCION 2: Redireccion de Carpetas (Desktop/Documents)" -ForegroundColor Yellow
    Write-Host "  Carpeta : $($script:CARPETA_USUARIOS)" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path $script:CARPETA_USUARIOS)) {
        Write-Host "  [INFO] $($script:CARPETA_USUARIOS) no existe. Ejecuta opcion 5 de Perfiles Moviles." -ForegroundColor Yellow
    } else {
        $subcarpetas = Get-ChildItem $script:CARPETA_USUARIOS -Directory -ErrorAction SilentlyContinue
        if (-not $subcarpetas -or $subcarpetas.Count -eq 0) {
            Write-Host "  [INFO] Sin carpetas de usuario todavia." -ForegroundColor Yellow
        } else {
            Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  | Usuario       | Desktop (MB) | Documents (MB) | Total (MB) | Cuota  |" -ForegroundColor White
            Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor White

            foreach ($c in $subcarpetas) {
                $mbDesktop   = Get-TamanoMB -Ruta "$($c.FullName)\Desktop"
                $mbDocuments = Get-TamanoMB -Ruta "$($c.FullName)\Documents"
                $mbTotal     = [math]::Round($mbDesktop + $mbDocuments, 2)

                $cuotaInfo = "N/A"
                $color     = "Green"
                $cuota = Get-FsrmQuota -Path $c.FullName -ErrorAction SilentlyContinue
                if ($cuota) {
                    $limMB     = [math]::Round($cuota.Size / 1MB)
                    $usaMB     = [math]::Round($cuota.Usage / 1MB, 2)
                    $cuotaInfo = "$usaMB/$limMB MB"
                    $pct       = if ($cuota.Size -gt 0) { ($cuota.Usage / $cuota.Size) * 100 } else { 0 }
                    if ($pct -ge 80)    { $color = "Red" }
                    elseif ($pct -ge 50){ $color = "Yellow" }
                }

                Write-Host ("  | {0,-13} | {1,12} | {2,14} | {3,10} | {4,-6} |" -f `
                    $c.Name, $mbDesktop, $mbDocuments, $mbTotal, $cuotaInfo) -ForegroundColor $color
            }
            Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  Verde    = uso normal (menos del 50% de cuota)" -ForegroundColor Green
            Write-Host "  Amarillo = uso moderado (50-79% de cuota)"      -ForegroundColor Yellow
            Write-Host "  Rojo     = uso alto (80%+ de cuota)"            -ForegroundColor Red
        }
    }

    # -------------------------------------------------------
    # SECCION 3: Resumen total por usuario del CSV
    # -------------------------------------------------------
    Write-Host ""
    Write-Host "  ------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  SECCION 3: Resumen total por usuario" -ForegroundColor Yellow
    Write-Host ""

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (Test-Path $csvPath) {
        $usuarios = Import-Csv $csvPath -ErrorAction SilentlyContinue
        if ($usuarios) {
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  | Usuario       | Perfil .V6 | Redireccion | TOTAL      | Grp |" -ForegroundColor White
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor White

            foreach ($u in $usuarios) {
                $mbPerfil = 0
                foreach ($sufijo in @(".V6", "")) {
                    $ruta = "$($script:CARPETA_PERFILES)\$($u.Usuario)$sufijo"
                    if (Test-Path $ruta) { $mbPerfil = Get-TamanoMB -Ruta $ruta; break }
                }

                $mbRedir = 0
                $rutaU = "$($script:CARPETA_USUARIOS)\$($u.Usuario)"
                if (Test-Path $rutaU) { $mbRedir = Get-TamanoMB -Ruta $rutaU }

                $mbTotal = [math]::Round($mbPerfil + $mbRedir, 2)
                $color   = if ($u.Departamento -eq "Cuates") { "Cyan" } else { "Magenta" }

                Write-Host ("  | {0,-13} | {1,10} | {2,11} | {3,10} | {4,-3} |" -f `
                    $u.Usuario, "$mbPerfil MB", "$mbRedir MB", "$mbTotal MB",
                    $u.Departamento.Substring(0,3)) -ForegroundColor $color
            }
            Write-Host "  +-------------------------------------------------------------+" -ForegroundColor White
            Write-Host "  Cyan    = Cuates   (cuota 10 MB)" -ForegroundColor Cyan
            Write-Host "  Magenta = NoCuates (cuota  5 MB)" -ForegroundColor Magenta
        }
    }

    Write-Host ""
    Write-Host "  NOTA: Perfil .V6 = 0 MB durante sesion activa es NORMAL." -ForegroundColor DarkGray
    Write-Host "  Los archivos del Escritorio/Documentos van a C:\Usuarios" -ForegroundColor DarkGray
    Write-Host "  en tiempo real. El .V6 se sincroniza al cerrar sesion." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  >>> CAPTURA ESTA PANTALLA como evidencia <<<" -ForegroundColor Magenta
    Write-Host ""
}
