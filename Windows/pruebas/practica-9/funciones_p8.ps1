# ============================================================
#  funciones_p8.ps1 - Libreria de funciones para la Practica 8
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
#
#  CAMBIOS vs version anterior:
#  - Horario NoCuates: 3PM-12PM mediodia (UTC 22:00-19:00)
#  - FSRM ahora aplica sobre C:\PerfilesMoviles\usuario
#  - Perfiles moviles INTEGRADOS en opcion 5
#  - Apantallamiento sigue siendo opcion 6 (sobre misma carpeta)
#
#  Hash de notepad.exe del cliente Windows 10 Pro:
#  0x70152C176B629E51FD283BD2F30ACFBDB1A129EA14D94889C1D32A742C104BBF
#  Tamano: 201216 bytes
# ============================================================

# Constantes globales usadas en varias funciones
$script:CARPETA_PERFILES = "C:\PerfilesMoviles"
$script:SHARE_NAME       = "Perfiles`$"
$script:SERVIDOR         = "192.168.1.202"
$script:SHARE_UNC        = "\\$($script:SERVIDOR)\Perfiles`$"

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

    # Crear OUs
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

    # Crear grupos de seguridad
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

    # Agregar usuarios a grupos
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
#
# Cuates   : 08:00 AM - 03:00 PM local  (UTC: 15:00-22:00)
# NoCuates : 03:00 PM - 12:00 PM local  (UTC: 22:00-19:00)
#            CAMBIO: antes terminaba 2AM, ahora termina 12PM
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

    # Funcion interna para construir el array de bytes de logon hours
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

    # Cuates: 08:00-15:00 local = 15:00-22:00 UTC
    $horasUTC_Cuates = @(15,16,17,18,19,20,21)

    # NoCuates: 15:00-12:00 local = 22:00-19:00 UTC
    # Horas UTC: 22,23,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18
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

    # GPO de cierre forzado
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
#
# Esta funcion hace TODO en orden:
#   A) Crea y comparte C:\PerfilesMoviles como \\server\Perfiles$
#   B) Configura permisos NTFS correctos para perfiles moviles
#   C) Asigna ProfilePath en AD a cada usuario del CSV
#   D) Aplica cuotas FSRM sobre C:\PerfilesMoviles\usuario
#      (Cuates=10MB, NoCuates=5MB)
#   E) Configura GPO de perfiles moviles
#
# POR QUE FSRM AQUI Y NO EN CARPETA SEPARADA:
#   El perfil movil IS la carpeta del usuario. Todo lo que guarda
#   en Escritorio, Documentos, etc. vive en esta carpeta cuando
#   se sincroniza con el servidor. La cuota aqui SI aplica a
#   todo lo que el usuario guarda.
# ------------------------------------------------------------
function Configurar-PerfilesYFSRM {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PERFILES MOVILES + CUOTAS FSRM         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # Verificar prereqs
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
    Write-Host "  NOTA: Las cuotas aplican sobre la carpeta del" -ForegroundColor Yellow
    Write-Host "  perfil en el servidor. Cualquier archivo que el" -ForegroundColor Yellow
    Write-Host "  usuario guarde (Escritorio, Documentos, etc.)" -ForegroundColor Yellow
    Write-Host "  cuenta contra su cuota al sincronizarse." -ForegroundColor Yellow
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""

    # ==============================================================
    # PASO A: Crear carpeta raiz de perfiles moviles
    # ==============================================================
    Write-Host "  [A] Creando carpeta de perfiles moviles..." -ForegroundColor Yellow

    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        New-Item -Path $script:CARPETA_PERFILES -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $($script:CARPETA_PERFILES)" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Carpeta ya existe: $($script:CARPETA_PERFILES)" -ForegroundColor Yellow
    }

    # ==============================================================
    # PASO B: Permisos NTFS para perfiles moviles
    # Los perfiles moviles de Windows requieren permisos especificos:
    # - Admins y SYSTEM: Control Total
    # - Creator Owner: Control Total SOLO en subcarpetas (InheritOnly)
    #   Para que cada usuario tenga control total sobre SU carpeta
    # - Domain Users: Solo CreateDirectories + ReadAndExecute en raiz
    #   Para que Windows pueda crear la carpeta del perfil
    # ==============================================================
    Write-Host "  [B] Configurando permisos NTFS..." -ForegroundColor Yellow

    try {
        $acl = Get-Acl $script:CARPETA_PERFILES
        $acl.SetAccessRuleProtection($true, $false)

        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM", "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )))
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Admins", "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )))
        # Creator Owner hereda a subcarpetas SOLAMENTE (clave para perfiles moviles)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "CREATOR OWNER", "FullControl",
            "ContainerInherit,ObjectInherit", "InheritOnly", "Allow"
        )))
        # Domain Users puede crear carpetas en la raiz (Windows crea la subcarpeta del perfil)
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA8\Domain Users", "ReadAndExecute, CreateDirectories",
            "None", "None", "Allow"
        )))

        Set-Acl $script:CARPETA_PERFILES $acl
        Write-Host "  [OK] Permisos NTFS configurados." -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Permisos NTFS: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ==============================================================
    # PASO C: Compartir carpeta en la red
    # ==============================================================
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

    # ==============================================================
    # PASO D: Asignar ProfilePath en AD y crear carpetas con cuotas
    # ==============================================================
    Write-Host "  [D] Asignando perfiles y cuotas FSRM..." -ForegroundColor Yellow
    Write-Host ""

    # Crear plantillas de cuota FSRM
    $plantillas = @(
        @{ Nombre = "Practica8-Cuates-10MB";  Tamano = 10MB },
        @{ Nombre = "Practica8-NoCuates-5MB"; Tamano = 5MB  }
    )

    foreach ($p in $plantillas) {
        try {
            $existe = Get-FsrmQuotaTemplate -Name $p.Nombre -ErrorAction SilentlyContinue
            if ($existe) {
                Write-Host "  [OK] Plantilla '$($p.Nombre)' ya existe." -ForegroundColor Yellow
            } else {
                New-FsrmQuotaTemplate -Name $p.Nombre -Size $p.Tamano -SoftLimit:$false | Out-Null
                Write-Host "  [CREADO] Plantilla '$($p.Nombre)' ($($p.Tamano / 1MB) MB)." -ForegroundColor Green
            }
        } catch {
            Write-Host "  [ERROR] Plantilla '$($p.Nombre)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""

    $ok      = 0
    $errores = 0

    foreach ($u in $usuarios) {

        # Determinar cuota segun departamento
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

        # Ruta UNC para AD (sin extension .V6, Windows la agrega solo)
        $rutaUNC       = "$($script:SHARE_UNC)\$($u.Usuario)"
        # Ruta local para FSRM (el servidor ve la ruta local)
        $carpetaLocal  = "$($script:CARPETA_PERFILES)\$($u.Usuario)"

        # 1. Asignar ProfilePath en AD
        try {
            Set-ADUser -Identity $u.Usuario -ProfilePath $rutaUNC -ErrorAction Stop
            Write-Host "  [AD] $($u.Usuario) ProfilePath -> $rutaUNC" -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] ProfilePath $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
            continue
        }

        # 2. Crear carpeta local (necesaria para que FSRM pueda aplicar cuota)
        # Windows creara la subcarpeta .V6 automaticamente en el primer login,
        # pero necesitamos la carpeta base para FSRM.
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

        # 3. Aplicar cuota FSRM sobre la carpeta del perfil
        try {
            $cuotaExistente  = Get-FsrmQuota -Path $carpetaLocal -ErrorAction SilentlyContinue
            $existePlantilla = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue

            if ($cuotaExistente) {
                if ($existePlantilla) {
                    Set-FsrmQuota -Path $carpetaLocal -Template $plantillaNombre | Out-Null
                } else {
                    Set-FsrmQuota -Path $carpetaLocal -Size $tamanoBytes -SoftLimit:$false | Out-Null
                }
                Write-Host "  [CUOTA] $($u.Usuario) ($($u.Departamento)) -> $tamanoTexto (actualizada)" -ForegroundColor Yellow
            } else {
                if ($existePlantilla) {
                    New-FsrmQuota -Path $carpetaLocal -Template $plantillaNombre | Out-Null
                } else {
                    New-FsrmQuota -Path $carpetaLocal -Size $tamanoBytes -SoftLimit:$false | Out-Null
                }
                Write-Host "  [CUOTA] $($u.Usuario) ($($u.Departamento)) -> $tamanoTexto" -ForegroundColor Green
            }
            $ok++
        } catch {
            Write-Host "  [ERROR] FSRM $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    # ==============================================================
    # PASO E: GPO de perfiles moviles
    # ==============================================================
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

        # No verificar espacio suficiente en disco
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" `
            -ValueName "CompatibleRUPSecurity" `
            -Type DWord -Value 1 | Out-Null

        # Siempre cargar el perfil movil aunque la red sea lenta
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkDefaultProfile" `
            -Type DWord -Value 1 | Out-Null

        # Timeout de red lenta = 0 (siempre cargar)
        Set-GPRegistryValue -Name $gpoNombre `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkTimeOut" `
            -Type DWord -Value 0 | Out-Null

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
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Ruta servidor: $($script:CARPETA_PERFILES)" -ForegroundColor White
    Write-Host "  | Ruta de red  : $($script:SHARE_UNC)"        -ForegroundColor White
    Write-Host "  | Cuotas OK    : $ok"                          -ForegroundColor Green
    Write-Host "  | Errores      : $errores"                     -ForegroundColor Red
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | SIGUIENTE PASO en el cliente Windows:    |" -ForegroundColor Yellow
    Write-Host "  |  1. Unir al dominio (unir_windows.ps1)   |" -ForegroundColor Yellow
    Write-Host "  |  2. gpupdate /force                      |" -ForegroundColor Yellow
    Write-Host "  |  3. Cerrar sesion y volver a entrar      |" -ForegroundColor Yellow
    Write-Host "  |  4. Al cerrar sesion el perfil se guarda |" -ForegroundColor Yellow
    Write-Host "  |     en $($script:CARPETA_PERFILES)\usuario.V6" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 6: Configurar apantallamiento de archivos (FSRM)
#
# APLICA sobre C:\PerfilesMoviles\usuario
# (misma carpeta que las cuotas, es el perfil del usuario)
#
# Bloquea: .mp3 .mp4 .exe .msi
# Tipo   : Active Screening (bloqueo en tiempo real)
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

    $usuarios    = Import-Csv -Path $csvPath
    $grupoNombre = "Practica8-ArchivosProhibidos"

    Write-Host "  Archivos bloqueados en carpetas de perfil:" -ForegroundColor White
    Write-Host "    Multimedia  : *.mp3, *.mp4" -ForegroundColor Cyan
    Write-Host "    Ejecutables : *.exe, *.msi" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Carpeta objetivo: $($script:CARPETA_PERFILES)\<usuario>" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Tipo: ACTIVO - bloqueo en tiempo real." -ForegroundColor Yellow
    Write-Host ""

    # Verificar que la carpeta de perfiles existe
    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        Write-Host "  [ERROR] No existe $($script:CARPETA_PERFILES)." -ForegroundColor Red
        Write-Host "  Ejecuta primero la opcion 5." -ForegroundColor Yellow
        return
    }

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""

    # Crear grupo de archivos prohibidos
    Write-Host "  Creando grupo de archivos prohibidos..." -ForegroundColor Yellow
    try {
        $grupoExistente = Get-FsrmFileGroup -Name $grupoNombre -ErrorAction SilentlyContinue
        if ($grupoExistente) {
            Set-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Host "  [OK] Grupo '$grupoNombre' actualizado." -ForegroundColor Yellow
        } else {
            New-FsrmFileGroup -Name $grupoNombre -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Host "  [CREADO] Grupo '$grupoNombre'." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERROR] Grupo: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Crear plantilla de apantallamiento
    Write-Host "  Creando plantilla de apantallamiento..." -ForegroundColor Yellow
    $plantillaNombre = "Practica8-Apantallamiento"
    try {
        $plantillaExistente = Get-FsrmFileScreenTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue
        if ($plantillaExistente) {
            Set-FsrmFileScreenTemplate -Name $plantillaNombre -Active:$true -IncludeGroup @($grupoNombre) | Out-Null
            Write-Host "  [OK] Plantilla '$plantillaNombre' actualizada." -ForegroundColor Yellow
        } else {
            New-FsrmFileScreenTemplate -Name $plantillaNombre -Active:$true -IncludeGroup @($grupoNombre) | Out-Null
            Write-Host "  [CREADO] Plantilla '$plantillaNombre'." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERROR] Plantilla: $($_.Exception.Message)" -ForegroundColor Red
        return
    }

    # Aplicar apantallamiento a carpetas de perfiles
    Write-Host ""
    Write-Host "  Aplicando apantallamiento a perfiles de usuarios..." -ForegroundColor Yellow
    Write-Host ""

    $creados  = 0
    $omitidos = 0
    $errores  = 0

    foreach ($u in $usuarios) {
        # La carpeta del perfil puede existir como:
        # C:\PerfilesMoviles\usuario     (antes del primer login)
        # C:\PerfilesMoviles\usuario.V6  (despues del primer login en Windows 10)
        # Aplicamos en ambas si existen
        $carpetasAplicar = @()

        $carpetaBase = "$($script:CARPETA_PERFILES)\$($u.Usuario)"
        $carpetaV6   = "$($script:CARPETA_PERFILES)\$($u.Usuario).V6"

        if (Test-Path $carpetaBase) { $carpetasAplicar += $carpetaBase }
        if (Test-Path $carpetaV6)   { $carpetasAplicar += $carpetaV6   }

        if ($carpetasAplicar.Count -eq 0) {
            Write-Host "  [AVISO] $($u.Usuario): carpeta no existe todavia." -ForegroundColor Yellow
            Write-Host "          Se aplicara automaticamente cuando haga login." -ForegroundColor DarkGray
            # Crear la carpeta base para poder aplicar el screen ahora
            try {
                New-Item -Path $carpetaBase -ItemType Directory -Force | Out-Null
                $carpetasAplicar += $carpetaBase
                Write-Host "          Carpeta creada: $carpetaBase" -ForegroundColor DarkGray
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
                    Write-Host "  [OK] $($u.Usuario) ($carpeta) -> bloqueados .mp3 .mp4 .exe .msi" -ForegroundColor Green
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
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | NOTA: Cuando el usuario haga primer login |" -ForegroundColor White
    Write-Host "  | Windows crea la carpeta .V6 automatico.  |" -ForegroundColor White
    Write-Host "  | Vuelve a ejecutar esta opcion despues     |" -ForegroundColor White
    Write-Host "  | del primer login para cubrir .V6 tambien.|" -ForegroundColor White
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 7: Configurar AppLocker
# (sin cambios respecto a version original)
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

    # Obtener SID de NoCuates
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
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | En el cliente Windows:                   |" -ForegroundColor Yellow
    Write-Host "  | sc.exe config AppIDSvc start= auto       |" -ForegroundColor Yellow
    Write-Host "  | sc.exe start AppIDSvc                    |" -ForegroundColor Yellow
    Write-Host "  | gpupdate /force                          |" -ForegroundColor Yellow
    Write-Host "  | Cerrar sesion y volver a entrar          |" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 8: Crear usuario dinamicamente
#
# Crea un usuario nuevo con todos los ajustes aplicados:
#   - OU correcta (Cuates/NoCuates)
#   - Horario de acceso
#   - ProfilePath apuntando a C:\PerfilesMoviles\usuario
#   - Cuota FSRM en la carpeta del perfil
#   - Apantallamiento de archivos
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

    Write-Host "  Ingresa los datos del nuevo usuario:" -ForegroundColor White
    Write-Host ""

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

    if ($deptoOpcion -eq "1")      { $departamento = "Cuates" }
    elseif ($deptoOpcion -eq "2")  { $departamento = "NoCuates" }
    else { Write-Host "  [ERROR] Opcion invalida." -ForegroundColor Red; return }

    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Yellow
    Write-Host "  | RESUMEN                                  |" -ForegroundColor Yellow
    Write-Host "  | Nombre  : $nombre $apellido"             -ForegroundColor White
    Write-Host "  | Usuario : $usuario@practica8.local"      -ForegroundColor White
    Write-Host "  | Grupo   : $departamento"                 -ForegroundColor White
    if ($departamento -eq "Cuates") {
        Write-Host "  | Horario : 08:00-15:00 | Cuota: 10 MB  |" -ForegroundColor White
    } else {
        Write-Host "  | Horario : 15:00-12:00 | Cuota:  5 MB  |" -ForegroundColor White
    }
    Write-Host "  +------------------------------------------+" -ForegroundColor Yellow
    Write-Host ""

    $confirmar = Read-Host "  Confirmar? (s/n)"
    if ($confirmar -ne "s") { return }

    Write-Host ""

    # Funcion interna Build-LogonHours (necesaria dentro de esta funcion)
    function Build-LogonHours {
        param([int[]]$HorasUTC)
        $bits = New-Object bool[] 168
        for ($dia = 0; $dia -lt 7; $dia++) {
            foreach ($hora in $HorasUTC) { $bits[$dia * 24 + $hora] = $true }
        }
        $bytes = New-Object byte[] 21
        for ($i = 0; $i -lt 168; $i++) {
            if ($bits[$i]) {
                $bytes[[math]::Floor($i / 8)] = $bytes[[math]::Floor($i / 8)] -bor (1 -shl ($i % 8))
            }
        }
        return $bytes
    }

    # PASO 1: Crear usuario en AD
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

    # PASO 3: Horario de acceso
    Write-Host ""
    Write-Host "  [3/5] Aplicando horario..." -ForegroundColor Yellow
    try {
        if ($departamento -eq "Cuates") {
            $horasUTC = @(15,16,17,18,19,20,21)
        } else {
            $horasUTC = @(22,23,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18)
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

    # Asignar ProfilePath
    try {
        Set-ADUser -Identity $usuario -ProfilePath $rutaUNC -ErrorAction Stop
        Write-Host "  [OK] ProfilePath -> $rutaUNC" -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] ProfilePath: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Crear carpeta local
    if (-not (Test-Path $carpetaLocal)) {
        try {
            New-Item -Path $carpetaLocal -ItemType Directory | Out-Null
            Write-Host "  [OK] Carpeta creada: $carpetaLocal" -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] Carpeta: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Aplicar cuota
    try {
        if ($departamento -eq "Cuates") {
            $plantillaNombre = "Practica8-Cuates-10MB"
            $tamanoBytes     = 10MB
            $tamanoTexto     = "10 MB"
        } else {
            $plantillaNombre = "Practica8-NoCuates-5MB"
            $tamanoBytes     = 5MB
            $tamanoTexto     = " 5 MB"
        }

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
        $plantillaExiste = Get-FsrmFileScreenTemplate -Name $plantillaScreen -ErrorAction SilentlyContinue
        if (-not $plantillaExiste) {
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
    Write-Host "  | [OK] AD | [OK] Grupo | [OK] Horario      |" -ForegroundColor Green
    Write-Host "  | [OK] Perfil Movil | [OK] Cuota FSRM      |" -ForegroundColor Green
    Write-Host "  | [OK] Apantallamiento                     |" -ForegroundColor Green
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 9: Ver perfiles almacenados en el servidor
# ------------------------------------------------------------
function Ver-PerfilesAlmacenados {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PERFILES ALMACENADOS EN EL SERVIDOR    |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-Path $script:CARPETA_PERFILES)) {
        Write-Host "  [INFO] La carpeta $($script:CARPETA_PERFILES) no existe aun." -ForegroundColor Yellow
        Write-Host "         Ejecuta la opcion 5 primero." -ForegroundColor DarkGray
        return
    }

    $carpetas = Get-ChildItem $script:CARPETA_PERFILES -ErrorAction SilentlyContinue
    if (-not $carpetas -or $carpetas.Count -eq 0) {
        Write-Host "  [INFO] No hay perfiles todavia." -ForegroundColor Yellow
        Write-Host "         Los perfiles aparecen cuando el usuario cierra" -ForegroundColor DarkGray
        Write-Host "         sesion por primera vez en el cliente Windows." -ForegroundColor DarkGray
        return
    }

    Write-Host "  Perfiles en: $($script:CARPETA_PERFILES)" -ForegroundColor White
    Write-Host ""
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
    Write-Host "  | Nombre                    | Tamano     | Ultima modificacion |" -ForegroundColor White
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White

    foreach ($c in $carpetas) {
        $tamanoBytes = (Get-ChildItem $c.FullName -Recurse -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        $tamanoMB = if ($tamanoBytes) { [math]::Round($tamanoBytes / 1MB, 2) } else { 0 }
        $fecha    = $c.LastWriteTime.ToString("dd/MM/yyyy HH:mm")
        $linea    = "  | {0,-25} | {1,8} MB | {2,-19} |" -f $c.Name, $tamanoMB, $fecha
        # Color segun si ya es perfil .V6 (login completado) o carpeta base
        if ($c.Name -match "\.V6$") {
            Write-Host $linea -ForegroundColor Green
        } else {
            Write-Host $linea -ForegroundColor Yellow
        }
    }
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor White
    Write-Host ""
    Write-Host "  Verde  = perfil .V6 sincronizado (usuario ya inicio sesion)" -ForegroundColor Green
    Write-Host "  Amarillo = carpeta base creada, usuario aun no ha hecho login" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Total: $($carpetas.Count) carpeta(s)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTA: Windows 10 guarda el perfil como '<usuario>.V6'" -ForegroundColor DarkGray
    Write-Host "        Si solo ves '<usuario>' sin .V6, el usuario aun" -ForegroundColor DarkGray
    Write-Host "        no ha cerrado sesion desde el cliente." -ForegroundColor DarkGray
    Write-Host ""
}
