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
# Lee el archivo usuarios.csv de la misma carpeta que el
# script, crea las OUs Cuates y NoCuates, y distribuye
# los usuarios segun la columna Departamento del CSV.
# Si un usuario ya existe, lo omite sin error.
# ------------------------------------------------------------
function Crear-OUsYUsuarios {

    Write-Host ""
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |       CREAR OUs Y USUARIOS DESDE CSV     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+" -ForegroundColor Cyan
    Write-Host ""

    # --- Verificar que el servidor es DC ---
    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] Este servidor no es Domain Controller o AD no esta disponible." -ForegroundColor Red
        Write-Host "  Ejecuta primero las opciones 1 y 2." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    # --- Verificar que existe el CSV ---
    $csvPath = "$PSScriptRoot\usuarios.csv"
    if (-not (Test-Path $csvPath)) {
        Write-Host "  [ERROR] No se encontro el archivo usuarios.csv en:" -ForegroundColor Red
        Write-Host "  $csvPath" -ForegroundColor Red
        Write-Host ""
        return
    }

    # --- Leer CSV ---
    $usuarios = Import-Csv -Path $csvPath
    Write-Host "  Se encontraron $($usuarios.Count) usuarios en el CSV." -ForegroundColor White
    Write-Host ""

    # --- Confirmar operacion ---
    $confirmar = Read-Host "  Se crearan las OUs y usuarios. Deseas continuar? (s/n)"
    if ($confirmar -ne "s") {
        Write-Host ""
        Write-Host "  Operacion cancelada por el usuario." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    Write-Host ""

    # --- Definir la ruta base del dominio ---
    # Ejemplo: DC=practica8,DC=local
    $dcBase = ($dominio.DistinguishedName)

    # --- Crear OUs si no existen ---
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

    # Contadores para el resumen final
    $creados  = 0
    $omitidos = 0
    $errores  = 0

    # --- Crear usuarios ---
    foreach ($u in $usuarios) {

        # Determinar en que OU va segun el Departamento del CSV
        # El CSV tiene "Cuates" o "NoCuates" en la columna Departamento
        $ouDestino = "OU=$($u.Departamento),$dcBase"

        # Verificar si el usuario ya existe
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

        # Crear el usuario
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

    # --- Crear grupos de seguridad para Cuates y NoCuates ---
    # Los grupos son necesarios para AppLocker y las GPOs
    Write-Host ""
    Write-Host "  Creando grupos de seguridad..." -ForegroundColor Yellow
    Write-Host ""

    $grupos = @(
        @{ Nombre = "Cuates";    OU = "OU=Cuates,$dcBase"    },
        @{ Nombre = "NoCuates";  OU = "OU=NoCuates,$dcBase"  }
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
                Write-Host "  [CREADO] Grupo '$($g.Nombre)' creado en OU $($g.Nombre)." -ForegroundColor Green
            } catch {
                Write-Host "  [ERROR] No se pudo crear el grupo '$($g.Nombre)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    # --- Agregar usuarios a sus grupos segun su OU ---
    Write-Host ""
    Write-Host "  Agregando usuarios a sus grupos..." -ForegroundColor Yellow
    Write-Host ""

    foreach ($u in $usuarios) {
        try {
            Add-ADGroupMember -Identity $u.Departamento -Members $u.Usuario -ErrorAction Stop
            Write-Host "  [OK] $($u.Usuario) agregado al grupo $($u.Departamento)." -ForegroundColor Green
        } catch {
            Write-Host "  [AVISO] No se pudo agregar '$($u.Usuario)' al grupo '$($u.Departamento)': $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # --- Resumen final ---
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
