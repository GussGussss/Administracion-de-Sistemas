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
#
# AD almacena los horarios en UTC internamente.
# Zona horaria: Los Mochis, Sinaloa = UTC-7 (sin cambio de horario)
#
# Conversion local -> UTC (sumar 7 horas):
#   Cuates   : 08:00-15:00 local  =>  15:00-22:00 UTC  (horas 15 a 21)
#   NoCuates : 15:00-02:00 local  =>  22:00-09:00 UTC  (horas 22,23 y 0 a 8)
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

    # ----------------------------------------------------------
    # HELPER: Construir array de 21 bytes para LogonHours
    # Recibe horas UTC permitidas (0-23) y aplica el mismo
    # horario para los 7 dias de la semana.
    # ----------------------------------------------------------
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

    # ----------------------------------------------------------
    # Horas UTC permitidas por grupo
    # UTC-7: hora local + 7 = hora UTC
    #
    # Cuates: local 08:00-14:59 => UTC 15:00-21:59 => horas 15..21
    # NoCuates: local 15:00-23:59 => UTC 22:00-06:59 => horas 22,23,0,1,2,3,4,5,6
    #           local 00:00-01:59 => UTC 07:00-08:59 => horas 7,8
    #           Combinado: 22,23,0,1,2,3,4,5,6,7,8
    # ----------------------------------------------------------
    $horasUTC_Cuates   = @(15,16,17,18,19,20,21)
    $horasUTC_NoCuates = @(22,23,0,1,2,3,4,5,6,7,8)

    $bytesCuates   = Build-LogonHours -HorasUTC $horasUTC_Cuates
    $bytesNoCuates = Build-LogonHours -HorasUTC $horasUTC_NoCuates

    # ----------------------------------------------------------
    # Aplicar horarios a cada usuario segun su grupo
    # ----------------------------------------------------------
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
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = $bytesCuates}
                Write-Host "  [OK] $($u.Usuario) -> Cuates (08:00-15:00 local)" -ForegroundColor Green
            } elseif ($u.Departamento -eq "NoCuates") {
                Set-ADUser -Identity $u.Usuario -Replace @{logonHours = $bytesNoCuates}
                Write-Host "  [OK] $($u.Usuario) -> NoCuates (15:00-02:00 local)" -ForegroundColor Green
            } else {
                Write-Host "  [AVISO] $($u.Usuario): departamento desconocido '$($u.Departamento)'" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [ERROR] No se pudo aplicar horario a '$($u.Usuario)': $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # ----------------------------------------------------------
    # GPO: forzar cierre de sesion al expirar horario
    # ----------------------------------------------------------
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
