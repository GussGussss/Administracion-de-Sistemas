# ============================================================
#  funciones_p8.ps1 - Libreria de funciones para la Practica 8
#  Dominio  : practica8.local
#  Servidor : 192.168.1.202
# ============================================================

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
            Write-Host "  Instalacion cancelada. No se hizo ningun cambio." -ForegroundColor Yellow
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
# ------------------------------------------------------------
function Promover-DomainController {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |     PROMOVER A DOMAIN CONTROLLER         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    $adds = Get-WindowsFeature -Name "AD-Domain-Services"
    if ($adds.InstallState -ne "Installed") {
        Write-Host "  [ERROR] Active Directory Domain Services no esta instalado." -ForegroundColor Red
        Write-Host "  Ejecuta primero la opcion 1 para instalar las dependencias." -ForegroundColor Yellow
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
        Write-Host "  [INFO] Este servidor ya es Domain Controller del dominio:" -ForegroundColor Yellow
        Write-Host "         $($domainInfo.DNSRoot)" -ForegroundColor White
        Write-Host ""
        Write-Host "  No es necesario volver a promoverlo." -ForegroundColor Yellow
        Write-Host ""
        return
    }

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

    Write-Host ""
    Write-Host "  Se requiere una contrasena para el Modo de Restauracion de AD (DSRM)." -ForegroundColor Yellow
    Write-Host "  Esta contrasena se usa en caso de emergencia para recuperar AD." -ForegroundColor White
    Write-Host ""

    $dsrmPassword = Read-Host "  Ingresa la contrasena DSRM" -AsSecureString

    Write-Host ""
    Write-Host "  Configurando DNS estatico en el adaptador de red interna..." -ForegroundColor Yellow

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

        Write-Host "  [OK] Promocion completada. El servidor se reiniciara ahora." -ForegroundColor Green

    } catch {
        Write-Host ""
        Write-Host "  [ERROR] Fallo la promocion a Domain Controller." -ForegroundColor Red
        Write-Host "  Detalle: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
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
        Write-Host "  [ERROR] Este servidor no es Domain Controller o AD no esta disponible." -ForegroundColor Red
        Write-Host "  Ejecuta primero las opciones 1 y 2." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro el archivo usuarios.csv en:" -ForegroundColor Red
        Write-Host "  $csvPath" -ForegroundColor Red
        Write-Host ""
        return
    }

    $usuarios = Import-Csv -Path $csvPath
    Write-Host "  Se encontraron $($usuarios.Count) usuarios en el CSV." -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Se crearan las OUs y usuarios. Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""
    $dcBase = ($dominio.DistinguishedName)

    $ous = @("Cuates", "NoCuates")
    foreach ($ou in $ous) {
        $ouPath = "OU=$ou,$dcBase"
        try {
            Get-ADOrganizationalUnit -Identity $ouPath -ErrorAction Stop | Out-Null
            Write-Host "  [OK] OU '$ou' ya existe, se omite." -ForegroundColor Yellow
        } catch {
            try {
                New-ADOrganizationalUnit -Name $ou -Path $dcBase -ProtectedFromAccidentalDeletion $false
                Write-Host "  [CREADO] OU '$ou' creada correctamente." -ForegroundColor Green
            } catch {
                Write-Host "  [ERROR] No se pudo crear la OU '$ou': $($_.Exception.Message)" -ForegroundColor Red
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
        $existe = $null
        try {
            $existe = Get-ADUser -Identity $u.Usuario -ErrorAction Stop
        } catch {
            $existe = $null
        }

        if ($existe) {
            Write-Host "  [OMITIDO] El usuario '$($u.Usuario)' ya existe." -ForegroundColor Yellow
            $omitidos++
            continue
        }

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

            Write-Host "  [CREADO] $($u.Nombre) $($u.Apellido) -> OU: $($u.Departamento)" -ForegroundColor Green
            $creados++
        } catch {
            Write-Host "  [ERROR] No se pudo crear '$($u.Usuario)': $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    Write-Host ""
    Write-Host "  Creando grupos de seguridad..." -ForegroundColor Yellow
    Write-Host ""

    $grupos = @(
        @{ Nombre = "Cuates";   OU = "OU=Cuates,$dcBase"   },
        @{ Nombre = "NoCuates"; OU = "OU=NoCuates,$dcBase" }
    )

    foreach ($g in $grupos) {
        try {
            Get-ADGroup -Identity $g.Nombre -ErrorAction Stop | Out-Null
            Write-Host "  [OK] Grupo '$($g.Nombre)' ya existe, se omite." -ForegroundColor Yellow
        } catch {
            try {
                New-ADGroup `
                    -Name $g.Nombre `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Path $g.OU
                Write-Host "  [CREADO] Grupo '$($g.Nombre)' creado." -ForegroundColor Green
            } catch {
                Write-Host "  [ERROR] No se pudo crear el grupo '$($g.Nombre)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "  Agregando usuarios a sus grupos..." -ForegroundColor Yellow
    Write-Host ""

    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity $u.Departamento -Members $u.Usuario -ErrorAction Stop
            Write-Host "  [OK] $($u.Usuario) agregado al grupo $($u.Departamento)." -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] $($u.Usuario) -> $($u.Departamento): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | RESUMEN                                  |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Usuarios creados : $creados" -ForegroundColor Green
    Write-Host "  | Usuarios omitidos: $omitidos (ya existian)" -ForegroundColor Yellow
    Write-Host "  | Errores          : $errores" -ForegroundColor Red
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 4: Configurar horarios de acceso (Logon Hours)
# UTC-7 (Los Mochis, Sinaloa)
# Cuates   : 08:00-15:00 local => 15:00-22:00 UTC => horas 15..21
# NoCuates : 15:00-02:00 local => 22:00-09:00 UTC => horas 22,23,0..8
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
        Write-Host "  [ERROR] Este servidor no es Domain Controller o AD no esta disponible." -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "  Zona horaria aplicada: UTC-7 (Los Mochis, Sinaloa)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Horarios locales que se configuraran:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Cuates   : 08:00 AM - 03:00 PM (hora local)" -ForegroundColor Cyan
    Write-Host "    NoCuates : 03:00 PM - 02:00 AM (hora local)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Equivalencia en UTC (lo que AD almacena):" -ForegroundColor White
    Write-Host ""
    Write-Host "    Cuates   : 15:00 - 22:00 UTC" -ForegroundColor DarkCyan
    Write-Host "    NoCuates : 22:00 - 09:00 UTC" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Ademas se configurara la GPO para forzar cierre" -ForegroundColor White
    Write-Host "  de sesion cuando el horario expire." -ForegroundColor White
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

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

    $horasUTC_Cuates   = @(15,16,17,18,19,20,21)
    $horasUTC_NoCuates = @(22,23,0,1,2,3,4,5,6,7,8)

    $bytesCuates   = Build-LogonHours -HorasUTC $horasUTC_Cuates
    $bytesNoCuates = Build-LogonHours -HorasUTC $horasUTC_NoCuates

    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv en $PSScriptRoot" -ForegroundColor Red
        Write-Host ""
        return
    }

    $usuarios = Import-Csv -Path $csvPath

    Write-Host "  Aplicando horarios a usuarios..." -ForegroundColor Yellow
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
                Write-Host "  [OK] $($u.Usuario) -> NoCuates (15:00-02:00 local)" -ForegroundColor Green
            } else {
                Write-Host "  [AVISO] $($u.Usuario): departamento desconocido '$($u.Departamento)'" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [ERROR] No se pudo aplicar horario a '$($u.Usuario)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Configurando GPO de cierre de sesion forzado..." -ForegroundColor Yellow
    Write-Host ""

    $gpoNombre = "Practica8-LogonHours"

    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre' creada." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO '$gpoNombre' ya existe, se actualiza." -ForegroundColor Yellow
        }

        Set-GPRegistryValue `
            -Name $gpoNombre `
            -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
            -ValueName "EnableForcedLogOff" `
            -Type DWord `
            -Value 1

        Write-Host "  [OK] Politica de cierre forzado configurada." -ForegroundColor Green

        $dcBase = $dominio.DistinguishedName
        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop
            Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya estaba vinculada al dominio." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] No se pudo configurar la GPO: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Verifica que el modulo GroupPolicy este disponible." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | Horarios configurados correctamente.     |" -ForegroundColor Cyan
    Write-Host "  | Zona horaria: UTC-7 (Los Mochis, Sin.)   |" -ForegroundColor Cyan
    Write-Host "  | Los usuarios seran desconectados al      |" -ForegroundColor Cyan
    Write-Host "  | finalizar su turno permitido.            |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 5: Configurar cuotas FSRM
#
# Crea carpetas personales para cada usuario en:
#   C:\Usuarios\<usuario>
# Aplica cuotas con FSRM:
#   Cuates   -> 10 MB (cuota Hard: bloquea al llegar al limite)
#   NoCuates ->  5 MB (cuota Hard: bloquea al llegar al limite)
# Si la cuota ya existe en una carpeta, la sobreescribe.
# ------------------------------------------------------------
function Configurar-CuotasFSRM {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |       CONFIGURAR CUOTAS FSRM             |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # --- Verificar que FSRM este instalado ---
    $fsrm = Get-WindowsFeature -Name "FS-Resource-Manager"
    if ($fsrm.InstallState -ne "Installed") {
        Write-Host "  [ERROR] FSRM no esta instalado." -ForegroundColor Red
        Write-Host "  Ejecuta primero la opcion 1 para instalar las dependencias." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Verificar que el CSV existe ---
    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv en $PSScriptRoot" -ForegroundColor Red
        Write-Host ""
        return
    }

    $usuarios = Import-Csv -Path $csvPath

    # --- Definir tamanos de cuota en bytes ---
    # 1 MB = 1048576 bytes
    $cuotaCuates   = 10MB   # 10485760 bytes
    $cuotaNoCuates =  5MB   #  5242880 bytes

    # --- Carpeta raiz donde vivirán las carpetas de usuarios ---
    $carpetaRaiz = "C:\Usuarios"

    Write-Host "  Configuracion que se aplicara:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Carpeta raiz : $carpetaRaiz\<usuario>" -ForegroundColor Cyan
    Write-Host "    Cuates       : 10 MB por usuario (cuota estricta)" -ForegroundColor Cyan
    Write-Host "    NoCuates     :  5 MB por usuario (cuota estricta)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTA: La cuota es estricta (Hard Quota)." -ForegroundColor Yellow
    Write-Host "  El servidor BLOQUEARA cualquier archivo que supere" -ForegroundColor Yellow
    Write-Host "  el limite asignado al usuario." -ForegroundColor Yellow
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    # --- Crear carpeta raiz si no existe ---
    if (-not (Test-Path $carpetaRaiz)) {
        New-Item -Path $carpetaRaiz -ItemType Directory | Out-Null
        Write-Host "  [CREADO] Carpeta raiz: $carpetaRaiz" -ForegroundColor Green
    } else {
        Write-Host "  [OK] Carpeta raiz ya existe: $carpetaRaiz" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Creando plantillas de cuota FSRM..." -ForegroundColor Yellow
    Write-Host ""

    # --- Crear plantillas de cuota si no existen ---
    # Las plantillas permiten reutilizar la configuracion de cuota
    # en multiples carpetas sin repetir la configuracion cada vez.
    $plantillas = @(
        @{ Nombre = "Practica8-Cuates-10MB";   Tamano = 10MB; Descripcion = "Cuota 10MB para Cuates"   },
        @{ Nombre = "Practica8-NoCuates-5MB";  Tamano = 5MB;  Descripcion = "Cuota 5MB para NoCuates"  }
    )

    foreach ($p in $plantillas) {
        try {
            $existePlantilla = Get-FsrmQuotaTemplate -Name $p.Nombre -ErrorAction SilentlyContinue
            if ($existePlantilla) {
                Write-Host "  [OK] Plantilla '$($p.Nombre)' ya existe, se omite." -ForegroundColor Yellow
            } else {
                # -SoftLimit:$false = Hard Quota (bloquea al llegar al limite)
                New-FsrmQuotaTemplate `
                    -Name $p.Nombre `
                    -Size $p.Tamano `
                    -SoftLimit:$false
                Write-Host "  [CREADO] Plantilla '$($p.Nombre)' ($($p.Tamano / 1MB) MB)." -ForegroundColor Green
            }
        } catch {
            Write-Host "  [ERROR] No se pudo crear la plantilla '$($p.Nombre)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "  Creando carpetas y aplicando cuotas a usuarios..." -ForegroundColor Yellow
    Write-Host ""

    $creadas   = 0
    $omitidas  = 0
    $errores   = 0

    foreach ($u in $usuarios) {

        $carpetaUsuario = "$carpetaRaiz\$($u.Usuario)"

        # Determinar tamano segun el departamento
        if ($u.Departamento -eq "Cuates") {
            $plantillaNombre = "Practica8-Cuates-10MB"
            $tamanoBytes     = 10MB
            $tamanoTexto     = "10 MB"
        } elseif ($u.Departamento -eq "NoCuates") {
            $plantillaNombre = "Practica8-NoCuates-5MB"
            $tamanoBytes     = 5MB
            $tamanoTexto     = "5 MB"
        } else {
            Write-Host "  [AVISO] $($u.Usuario): departamento desconocido, se omite." -ForegroundColor Yellow
            continue
        }

        # Crear la carpeta del usuario si no existe
        if (-not (Test-Path $carpetaUsuario)) {
            try {
                New-Item -Path $carpetaUsuario -ItemType Directory | Out-Null
                Write-Host "  [CARPETA] Creada: $carpetaUsuario" -ForegroundColor DarkGreen
            } catch {
                Write-Host "  [ERROR] No se pudo crear la carpeta '$carpetaUsuario': $($_.Exception.Message)" -ForegroundColor Red
                $errores++
                continue
            }
        }

        # Aplicar o actualizar la cuota FSRM en la carpeta
        try {
            $cuotaExistente = Get-FsrmQuota -Path $carpetaUsuario -ErrorAction SilentlyContinue

            # Verificar si la plantilla existe para usarla, si no usar tamano directo
            $existePlantilla = Get-FsrmQuotaTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue

            if ($cuotaExistente) {
                if ($existePlantilla) {
                    Set-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre
                } else {
                    Set-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false
                }
                Write-Host "  [ACTUALIZADO] $($u.Usuario) ($($u.Departamento)) -> $tamanoTexto" -ForegroundColor Yellow
                $omitidas++
            } else {
                if ($existePlantilla) {
                    New-FsrmQuota -Path $carpetaUsuario -Template $plantillaNombre
                } else {
                    New-FsrmQuota -Path $carpetaUsuario -Size $tamanoBytes -SoftLimit:$false
                }
                Write-Host "  [CUOTA] $($u.Usuario) ($($u.Departamento)) -> $tamanoTexto" -ForegroundColor Green
                $creadas++
            }
        } catch {
            Write-Host "  [ERROR] Cuota para '$($u.Usuario)': $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | RESUMEN DE CUOTAS                        |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Cuotas creadas     : $creadas" -ForegroundColor Green
    Write-Host "  | Cuotas actualizadas: $omitidas" -ForegroundColor Yellow
    Write-Host "  | Errores            : $errores" -ForegroundColor Red
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Carpetas en: $carpetaRaiz" -ForegroundColor White
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 6: Configurar apantallamiento de archivos (FSRM)
#
# Crea un grupo de archivos bloqueados con extensiones:
#   .mp3, .mp4 (multimedia)
#   .exe, .msi (ejecutables)
# Aplica un File Screen de tipo Active (bloqueo real) en
# la carpeta de cada usuario en C:\Usuarios\<usuario>.
# Si el screen ya existe, lo actualiza.
# ------------------------------------------------------------
function Configurar-Apantallamiento {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR APANTALLAMIENTO DE ARCHIVOS |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # --- Verificar que FSRM este instalado ---
    $fsrm = Get-WindowsFeature -Name "FS-Resource-Manager"
    if ($fsrm.InstallState -ne "Installed") {
        Write-Host "  [ERROR] FSRM no esta instalado." -ForegroundColor Red
        Write-Host "  Ejecuta primero la opcion 1 para instalar las dependencias." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Verificar que el CSV existe ---
    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro usuarios.csv en $PSScriptRoot" -ForegroundColor Red
        Write-Host ""
        return
    }

    $usuarios    = Import-Csv -Path $csvPath
    $carpetaRaiz = "C:\Usuarios"
    $grupoNombre = "Practica8-ArchivosProhibidos"

    Write-Host "  Se bloquearan los siguientes tipos de archivo" -ForegroundColor White
    Write-Host "  en las carpetas personales de TODOS los usuarios:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Multimedia  : *.mp3, *.mp4" -ForegroundColor Cyan
    Write-Host "    Ejecutables : *.exe, *.msi" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Tipo de apantallamiento: ACTIVO (Active Screening)" -ForegroundColor Yellow
    Write-Host "  El servidor RECHAZARA el archivo en tiempo real." -ForegroundColor Yellow
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    # --- Crear grupo de archivos prohibidos si no existe ---
    Write-Host "  Creando grupo de archivos prohibidos..." -ForegroundColor Yellow
    Write-Host ""

    try {
        $grupoExistente = Get-FsrmFileGroup -Name $grupoNombre -ErrorAction SilentlyContinue
        if ($grupoExistente) {
            # Actualizar el grupo con las extensiones correctas
            Set-FsrmFileGroup `
                -Name $grupoNombre `
                -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Host "  [OK] Grupo '$grupoNombre' ya existe, actualizado." -ForegroundColor Yellow
        } else {
            New-FsrmFileGroup `
                -Name $grupoNombre `
                -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
            Write-Host "  [CREADO] Grupo '$grupoNombre' creado." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERROR] No se pudo crear el grupo de archivos: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    # --- Crear plantilla de apantallamiento si no existe ---
    Write-Host ""
    Write-Host "  Creando plantilla de apantallamiento..." -ForegroundColor Yellow
    Write-Host ""

    $plantillaNombre = "Practica8-Apantallamiento"

    try {
        $plantillaExistente = Get-FsrmFileScreenTemplate -Name $plantillaNombre -ErrorAction SilentlyContinue
        if ($plantillaExistente) {
            Set-FsrmFileScreenTemplate `
                -Name $plantillaNombre `
                -Active:$true `
                -IncludeGroup @($grupoNombre) | Out-Null
            Write-Host "  [OK] Plantilla '$plantillaNombre' ya existe, actualizada." -ForegroundColor Yellow
        } else {
            New-FsrmFileScreenTemplate `
                -Name $plantillaNombre `
                -Active:$true `
                -IncludeGroup @($grupoNombre) | Out-Null
            Write-Host "  [CREADO] Plantilla '$plantillaNombre' creada." -ForegroundColor Green
        }
    } catch {
        Write-Host "  [ERROR] No se pudo crear la plantilla: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    # --- Aplicar apantallamiento a cada carpeta de usuario ---
    Write-Host ""
    Write-Host "  Aplicando apantallamiento a carpetas de usuarios..." -ForegroundColor Yellow
    Write-Host ""

    $creados  = 0
    $omitidos = 0
    $errores  = 0

    foreach ($u in $usuarios) {
        $carpetaUsuario = "$carpetaRaiz\$($u.Usuario)"

        # Verificar que la carpeta existe (debe haberse creado en opcion 5)
        if (-not (Test-Path $carpetaUsuario)) {
            Write-Host "  [AVISO] No existe la carpeta '$carpetaUsuario'." -ForegroundColor Yellow
            Write-Host "          Ejecuta primero la opcion 5 (Cuotas FSRM)." -ForegroundColor Yellow
            $errores++
            continue
        }

        try {
            $screenExistente = Get-FsrmFileScreen -Path $carpetaUsuario -ErrorAction SilentlyContinue

            if ($screenExistente) {
                Set-FsrmFileScreen `
                    -Path $carpetaUsuario `
                    -Template $plantillaNombre | Out-Null
                Write-Host "  [ACTUALIZADO] $($u.Usuario) -> apantallamiento actualizado" -ForegroundColor Yellow
                $omitidos++
            } else {
                New-FsrmFileScreen `
                    -Path $carpetaUsuario `
                    -Template $plantillaNombre | Out-Null
                Write-Host "  [OK] $($u.Usuario) -> .mp3 .mp4 .exe .msi bloqueados" -ForegroundColor Green
                $creados++
            }
        } catch {
            Write-Host "  [ERROR] $($u.Usuario): $($_.Exception.Message)" -ForegroundColor Red
            $errores++
        }
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | RESUMEN DE APANTALLAMIENTO               |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Screens creados     : $creados" -ForegroundColor Green
    Write-Host "  | Screens actualizados: $omitidos" -ForegroundColor Yellow
    Write-Host "  | Errores             : $errores" -ForegroundColor Red
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Archivos bloqueados: .mp3 .mp4 .exe .msi |" -ForegroundColor White
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}


# ------------------------------------------------------------
# FUNCION 7: Configurar AppLocker
#
# Crea una GPO con reglas de AppLocker:
#   - Cuates   : pueden ejecutar notepad.exe (regla de permiso)
#   - NoCuates : tienen bloqueado notepad.exe por Hash
#                (el hash identifica el archivo sin importar
#                 el nombre, evitando que renombren el .exe)
#
# La GPO se vincula al dominio completo.
# El servicio AppIDSvc debe estar en Automatic para que
# AppLocker funcione en los clientes.
# ------------------------------------------------------------
function Configurar-AppLocker {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |         CONFIGURAR APPLOCKER             |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # --- Verificar que el servidor es DC ---
    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] Este servidor no es Domain Controller o AD no esta disponible." -ForegroundColor Red
        Write-Host ""
        return
    }

    # --- Verificar que notepad.exe existe ---
    $notepadPath = "C:\Windows\System32\notepad.exe"
    if (-not (Test-Path $notepadPath)) {
        Write-Host "  [ERROR] No se encontro notepad.exe en $notepadPath" -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host "  Reglas que se configuraran via GPO:" -ForegroundColor White
    Write-Host ""
    Write-Host "    Cuates   : notepad.exe PERMITIDO (regla de ruta)" -ForegroundColor Cyan
    Write-Host "    NoCuates : notepad.exe BLOQUEADO por Hash" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  La regla de Hash identifica el archivo por su" -ForegroundColor Yellow
    Write-Host "  contenido, no por su nombre. Renombrar el .exe" -ForegroundColor Yellow
    Write-Host "  no permite saltarse el bloqueo." -ForegroundColor Yellow
    Write-Host ""

    $confirmar = Read-Host "  Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    # --- Obtener el hash de notepad.exe ---
    Write-Host "  Calculando hash de notepad.exe..." -ForegroundColor Yellow

    try {
        $fileInfo    = Get-AppLockerFileInformation -Path $notepadPath -ErrorAction Stop
        $hashInfo    = $fileInfo.Hash
        $hashValor   = $hashInfo.HashDataString
        $hashAlgo    = "SHA256"
        $archivoSize = (Get-Item $notepadPath).Length

        Write-Host "  [OK] Hash calculado: $hashValor" -ForegroundColor Green
        Write-Host "       Tamano del archivo: $archivoSize bytes" -ForegroundColor DarkGray
    } catch {
        Write-Host "  [ERROR] No se pudo calcular el hash: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    # --- Obtener SIDs de los grupos Cuates y NoCuates ---
    Write-Host ""
    Write-Host "  Obteniendo SIDs de los grupos..." -ForegroundColor Yellow

    try {
        $sidCuates   = (Get-ADGroup -Identity "Cuates").SID.Value
        $sidNoCuates = (Get-ADGroup -Identity "NoCuates").SID.Value
        Write-Host "  [OK] SID Cuates  : $sidCuates" -ForegroundColor Green
        Write-Host "  [OK] SID NoCuates: $sidNoCuates" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] No se pudieron obtener los SIDs: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Asegurate de haber ejecutado la opcion 3 primero." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Construir el XML de politica AppLocker ---
    # AppLocker se configura mediante un XML que describe las reglas.
    # Cada regla tiene: Id, Name, Action (Allow/Deny), UserOrGroupSid, Conditions
    Write-Host ""
    Write-Host "  Construyendo politica AppLocker en XML..." -ForegroundColor Yellow

    # Generar GUIDs unicos para cada regla
    $guidPermitir = [System.Guid]::NewGuid().ToString()
    $guidBloquear = [System.Guid]::NewGuid().ToString()

    $xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <!-- Regla 1: Permitir a TODOS ejecutar todo lo que esta en Windows y Archivos de Programa -->
    <!-- Esta regla base es necesaria para que el sistema funcione correctamente -->
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20"
                  Name="Permitir archivos en Windows"
                  Description="Regla base: permite ejecutables del sistema"
                  UserOrGroupSid="S-1-1-0"
                  Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*"/>
      </Conditions>
    </FilePathRule>

    <FilePathRule Id="a61c8b2c-a23e-47ff-8e4a-4e3d41bc98b0"
                  Name="Permitir archivos en Archivos de Programa"
                  Description="Regla base: permite ejecutables de Archivos de Programa"
                  UserOrGroupSid="S-1-1-0"
                  Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>

    <!-- Regla 2: Bloquear notepad.exe a NoCuates por Hash -->
    <!-- El hash identifica el archivo sin importar su nombre -->
    <FileHashRule Id="$guidBloquear"
                  Name="Bloquear Notepad a NoCuates"
                  Description="Bloquea notepad.exe a NoCuates por hash - renombrar no evita el bloqueo"
                  UserOrGroupSid="$sidNoCuates"
                  Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="$hashAlgo" Data="$hashValor" SourceFileName="notepad.exe" SourceFileLength="$archivoSize"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

  </RuleCollection>
</AppLockerPolicy>
"@

    # --- Guardar XML en archivo temporal ---
    $xmlPath = "$PSScriptRoot\applocker_policy.xml"
    try {
        $xmlPolicy | Out-File -FilePath $xmlPath -Encoding UTF8 -Force
        Write-Host "  [OK] XML guardado en: $xmlPath" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] No se pudo guardar el XML: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    # --- Crear o actualizar la GPO de AppLocker ---
    Write-Host ""
    Write-Host "  Configurando GPO de AppLocker..." -ForegroundColor Yellow
    Write-Host ""

    $gpoNombre = "Practica8-AppLocker"

    try {
        $gpo = Get-GPO -Name $gpoNombre -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoNombre
            Write-Host "  [CREADO] GPO '$gpoNombre' creada." -ForegroundColor Green
        } else {
            Write-Host "  [OK] GPO '$gpoNombre' ya existe, se actualiza." -ForegroundColor Yellow
        }

        # Aplicar la politica AppLocker a la GPO usando el XML
        # El XML se importa al contexto de la GPO via LGPO path
        $gpoId   = $gpo.Id.ToString()
        $dcBase  = $dominio.DistinguishedName
        $domain  = $dominio.DNSRoot

        # Ruta donde Windows guarda las politicas de AppLocker en SYSVOL
        $sysvolPath = "\\$domain\SYSVOL\$domain\Policies\{$gpoId}\Machine\Microsoft\Windows NT\AppLocker"

        # Crear la carpeta si no existe
        if (-not (Test-Path $sysvolPath)) {
            New-Item -Path $sysvolPath -ItemType Directory -Force | Out-Null
            Write-Host "  [OK] Carpeta AppLocker en SYSVOL creada." -ForegroundColor Green
        }

        # Usar Set-AppLockerPolicy para aplicar la politica localmente
        # y luego copiarla al GPO
        Set-AppLockerPolicy -XmlPolicy $xmlPath -Merge
        Write-Host "  [OK] Politica AppLocker aplicada." -ForegroundColor Green

        # Vincular la GPO al dominio
        try {
            New-GPLink -Name $gpoNombre -Target $dcBase -ErrorAction Stop | Out-Null
            Write-Host "  [OK] GPO vinculada al dominio." -ForegroundColor Green
        } catch {
            Write-Host "  [OK] GPO ya estaba vinculada al dominio." -ForegroundColor Yellow
        }

        # Habilitar el servicio AppIDSvc (necesario para que AppLocker funcione)
        Write-Host ""
        Write-Host "  Habilitando servicio AppIDSvc en el servidor..." -ForegroundColor Yellow
        Set-Service -Name AppIDSvc -StartupType Automatic
        Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
        Write-Host "  [OK] Servicio AppIDSvc configurado como Automatico." -ForegroundColor Green

    } catch {
        Write-Host "  [ERROR] No se pudo configurar la GPO AppLocker: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  | AppLocker configurado correctamente.     |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Cuates   : notepad.exe PERMITIDO         |" -ForegroundColor Green
    Write-Host "  | NoCuates : notepad.exe BLOQUEADO (hash)  |" -ForegroundColor Red
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | IMPORTANTE: En los clientes Windows,     |" -ForegroundColor Yellow
    Write-Host "  | ejecutar: gpupdate /force                |" -ForegroundColor Yellow
    Write-Host "  | para que las reglas surtan efecto.       |" -ForegroundColor Yellow
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""
}
