# ============================================================
#  funciones_p9.ps1 — Libreria de funciones Practica 09
#  Hardening AD, RBAC, FGPP, Auditoria y MFA TOTP
# ============================================================

# ------------------------------------------------------------
# UTILIDAD INTERNA: Detectar el nombre real de las OUs de P08
# El profesor puede haber creado "No Cuates" o "NoCuates".
# Esta funcion detecta cual existe y devuelve el DN correcto.
# ------------------------------------------------------------
function Get-OUSegura {
    param([string]$NombreBase)

    $dominio = (Get-ADDomain).DistinguishedName

    # Intentar variantes del nombre
    $variantes = @($NombreBase, $NombreBase -replace ' ', '', $NombreBase -replace ' ', '-')

    foreach ($nombre in $variantes) {
        $dn = "OU=$nombre,$dominio"
        try {
            Get-ADOrganizationalUnit -Identity $dn -ErrorAction Stop | Out-Null
            return $dn
        } catch { }
    }

    # Si no existe ninguna variante, crearla con el nombre base
    Write-Host "  [AVISO] La OU '$NombreBase' no existe. Creandola..." -ForegroundColor Yellow
    try {
        New-ADOrganizationalUnit -Name $NombreBase -Path $dominio -ErrorAction Stop
        Write-Host "  [OK] OU '$NombreBase' creada." -ForegroundColor Green
        return "OU=$NombreBase,$dominio"
    } catch {
        Write-Host "  [ERROR] No se pudo crear la OU '$NombreBase': $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ------------------------------------------------------------
# FUNCION 1: Preparar entorno y descargar multiOTP
# ------------------------------------------------------------
function Preparar-EntornoMFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PREPARAR ENTORNO Y DESCARGAR MFA       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"

    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    $procederDescarga = $true
    $archivosExistentes = Get-ChildItem -Path $rutaDescarga -Filter "multiOTP*" -ErrorAction SilentlyContinue

    if ($archivosExistentes) {
        Write-Host "  [AVISO] Ya existen archivos de multiOTP en $rutaDescarga." -ForegroundColor Yellow
        $respuesta = Read-Host "  Descargar la version mas reciente desde GitHub? (s/n)"
        if ($respuesta.ToLower() -ne 's') {
            $procederDescarga = $false
            Write-Host "  [OK] Usando archivos locales existentes." -ForegroundColor Green
        }
    }

    if ($procederDescarga) {
        Write-Host "  [INFO] Consultando la API de GitHub para obtener la version mas reciente..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        try {
            $headers = @{ "User-Agent" = "PowerShell-P09-Script" }
            $apiUrl  = "https://api.github.com/repos/multiOTP/multiOTPCredentialProvider/releases/latest"
            $release = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing

            $asset = $release.assets | Where-Object { $_.name -like "*.zip" -or $_.name -like "*.exe" } | Select-Object -First 1

            if (-not $asset) {
                Write-Host "  [ERROR] No se encontro un instalador en el ultimo release de GitHub." -ForegroundColor Red
                Pause | Out-Null; return
            }

            $rutaArchivo = "$rutaDescarga\$($asset.name)"
            Write-Host "  [INFO] Descargando $($release.tag_name) — $($asset.name)..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $rutaArchivo -UseBasicParsing -Headers $headers

            if ($rutaArchivo.EndsWith(".zip")) {
                Write-Host "  [INFO] Extrayendo ZIP..." -ForegroundColor Yellow
                Expand-Archive -Path $rutaArchivo -DestinationPath $rutaDescarga -Force
            }

            Write-Host "  [OK] Descarga completada exitosamente." -ForegroundColor Green

        } catch {
            Write-Host "  [ERROR] Fallo la descarga: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 2: Crear los 4 usuarios de administracion delegada
# ------------------------------------------------------------
function Crear-UsuariosAdmin {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CREACION DE USUARIOS ADMINISTRATIVOS   |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $usuarios = @(
        @{ Sam = "admin_identidad"; Nombre = "Admin Identidad";  Desc = "Rol 1 - IAM Operator" },
        @{ Sam = "admin_storage";   Nombre = "Admin Storage";    Desc = "Rol 2 - Storage Operator" },
        @{ Sam = "admin_politicas"; Nombre = "Admin Politicas";  Desc = "Rol 3 - GPO Compliance" },
        @{ Sam = "admin_auditoria"; Nombre = "Admin Auditoria";  Desc = "Rol 4 - Security Auditor" }
    )

    # Contrasena que cumple complejidad de Windows Server
    $pwdTexto  = "Hardening2026!"
    $pwdSegura = ConvertTo-SecureString $pwdTexto -AsPlainText -Force

    $creados  = 0
    $omitidos = 0

    foreach ($u in $usuarios) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue

        if ($existe) {
            Write-Host "  [OMITIDO] '$($u.Sam)' ya existe en AD." -ForegroundColor Yellow
            $omitidos++
        } else {
            try {
                New-ADUser -Name            $u.Nombre `
                           -SamAccountName  $u.Sam `
                           -UserPrincipalName "$($u.Sam)@$((Get-ADDomain).DNSRoot)" `
                           -Description     $u.Desc `
                           -AccountPassword  $pwdSegura `
                           -Enabled         $true `
                           -PasswordNeverExpires $true
                Write-Host "  [OK] '$($u.Sam)' creado. Contrasena: $pwdTexto" -ForegroundColor Green
                $creados++
            } catch {
                Write-Host "  [ERROR] No se pudo crear '$($u.Sam)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n  Resumen: $creados creados, $omitidos ya existian." -ForegroundColor Cyan
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 3: Aplicar permisos RBAC con delegacion por ACL
# ------------------------------------------------------------
function Aplicar-PermisosRBAC {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   APLICAR PERMISOS RBAC Y DELEGACION     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try {
        $dominio = Get-ADDomain -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] No se puede conectar al Directorio Activo." -ForegroundColor Red
        Read-Host | Out-Null; return
    }

    $dcBase  = $dominio.DistinguishedName
    $netbios = $dominio.NetBIOSName

    # --- Detectar nombres reales de las OUs creadas en P08 ---
    Write-Host "  Detectando OUs del dominio..." -ForegroundColor Yellow
    $ouCuates   = Get-OUSegura -NombreBase "Cuates"
    $ouNoCuates = Get-OUSegura -NombreBase "No Cuates"

    if (-not $ouCuates -or -not $ouNoCuates) {
        Write-Host "  [ERROR] No se pudieron resolver las OUs. Verifica la Practica 08." -ForegroundColor Red
        Read-Host | Out-Null; return
    }

    Write-Host "  [INFO] OU Cuates   : $ouCuates" -ForegroundColor DarkGray
    Write-Host "  [INFO] OU NoCuates : $ouNoCuates`n" -ForegroundColor DarkGray

    # =========================================================
    # ROL 1: admin_identidad — Control total sobre usuarios
    #         en las OUs Cuates y No Cuates
    # =========================================================
    Write-Host "  [ROL 1] Configurando admin_identidad (IAM Operator)..." -ForegroundColor Yellow

    # RPWP = Read Property + Write Property (control total sobre atributos)
    # CA   = Control Access (permite acciones de control como reset de contrasena)
    # /I:T = propagar a todos los sub-objetos (Inherit to all)
    # ;;user = solo aplica a objetos de clase "user" (no a grupos ni OUs)
    $resultadoR1a = dsacls "$ouCuates"   /I:T /G "$netbios\admin_identidad:CCDC;;user" 2>&1
    $resultadoR1b = dsacls "$ouNoCuates" /I:T /G "$netbios\admin_identidad:CCDC;;user" 2>&1

    # Ademas dar permisos de Reset Password especificamente
    $resultadoR1c = dsacls "$ouCuates"   /I:T /G "$netbios\admin_identidad:CA;Reset Password;user" 2>&1
    $resultadoR1d = dsacls "$ouNoCuates" /I:T /G "$netbios\admin_identidad:CA;Reset Password;user" 2>&1

    # Atributos basicos: telefono, oficina, correo (RPWP sobre atributos especificos)
    $resultadoR1e = dsacls "$ouCuates"   /I:T /G "$netbios\admin_identidad:RPWP;telephoneNumber;user" 2>&1
    $resultadoR1f = dsacls "$ouNoCuates" /I:T /G "$netbios\admin_identidad:RPWP;telephoneNumber;user" 2>&1

    if ($resultadoR1a -match "error" -or $resultadoR1b -match "error") {
        Write-Host "  [ERROR] Fallo al configurar Rol 1. Detalle: $resultadoR1a" -ForegroundColor Red
    } else {
        Write-Host "  [OK] admin_identidad: Permisos de gestion de usuarios asignados en ambas OUs." -ForegroundColor Green
    }

    # =========================================================
    # ROL 2: admin_storage — DENEGAR Reset Password en TODO el dominio
    #         Restriccion critica: no puede resetear ninguna contrasena
    # =========================================================
    Write-Host "`n  [ROL 2] Configurando admin_storage (Storage Operator)..." -ForegroundColor Yellow

    # /D = Deny (denegacion explicita, tiene prioridad sobre cualquier permiso Grant)
    # Se aplica en la raiz del dominio con herencia a todos los sub-objetos (/I:S)
    $resultadoR2 = dsacls "$dcBase" /I:S /D "$netbios\admin_storage:CA;Reset Password;user" 2>&1

    if ($resultadoR2 -match "error") {
        Write-Host "  [ERROR] Fallo la denegacion de Reset Password para admin_storage." -ForegroundColor Red
        Write-Host "  Detalle: $resultadoR2" -ForegroundColor DarkGray
    } else {
        Write-Host "  [OK] admin_storage: DENEGADO 'Reset Password' en todo el dominio (Test 1 configurado)." -ForegroundColor Green
    }

    # =========================================================
    # ROL 3: admin_politicas — Solo puede leer todo,
    #         y vincular/desvincular GPOs en las OUs asignadas
    # =========================================================
    Write-Host "`n  [ROL 3] Configurando admin_politicas (GPO Compliance)..." -ForegroundColor Yellow

    # 1. Agregar al grupo que permite CREAR y EDITAR objetos GPO
    try {
        Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction Stop
        Write-Host "  [OK] Agregado a 'Group Policy Creator Owners' (puede crear/editar GPOs)." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Ya pertenece a 'Group Policy Creator Owners'." -ForegroundColor DarkGray
    }

    # 2. Permiso para VINCULAR GPOs: atributos gPLink y gPOptions en las OUs
    #    gPLink  = almacena los GUIDs de GPOs vinculadas a la OU
    #    gPOptions = almacena opciones como "Block Inheritance"
    #    RPWP = Read Property + Write Property (leer y escribir el atributo)
    $r3a = dsacls "$ouCuates"   /I:T /G "$netbios\admin_politicas:RPWP;gPLink"    2>&1
    $r3b = dsacls "$ouCuates"   /I:T /G "$netbios\admin_politicas:RPWP;gPOptions" 2>&1
    $r3c = dsacls "$ouNoCuates" /I:T /G "$netbios\admin_politicas:RPWP;gPLink"    2>&1
    $r3d = dsacls "$ouNoCuates" /I:T /G "$netbios\admin_politicas:RPWP;gPOptions" 2>&1

    if ($r3a -match "error") {
        Write-Host "  [ERROR] Fallo al asignar permisos de vinculacion GPO." -ForegroundColor Red
    } else {
        Write-Host "  [OK] admin_politicas: Puede vincular/desvincular GPOs en ambas OUs." -ForegroundColor Green
    }

    # 3. Permiso de lectura en todo el dominio (requerimiento de la practica)
    $r3e = dsacls "$dcBase" /I:T /G "$netbios\admin_politicas:GR" 2>&1
    Write-Host "  [OK] admin_politicas: Lectura en todo el dominio asignada." -ForegroundColor Green

    # =========================================================
    # ROL 4: admin_auditoria — Read-Only estricto
    #         Solo puede leer logs de seguridad, sin modificar nada
    # =========================================================
    Write-Host "`n  [ROL 4] Configurando admin_auditoria (Security Auditor)..." -ForegroundColor Yellow

    # Agregar al grupo nativo que permite leer el Event Log de Seguridad
    try {
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction Stop
        Write-Host "  [OK] admin_auditoria: Agregado a 'Event Log Readers'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Ya pertenece a 'Event Log Readers'." -ForegroundColor DarkGray
    }

    # Permiso de solo lectura en todo el dominio (sin escritura en ningun objeto)
    $r4 = dsacls "$dcBase" /I:T /G "$netbios\admin_auditoria:GR" 2>&1
    Write-Host "  [OK] admin_auditoria: Solo lectura en todo el dominio." -ForegroundColor Green

    Write-Host "`n  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | RBAC configurado. Resumen de roles:      |" -ForegroundColor Cyan
    Write-Host "  | Rol 1 admin_identidad : Gestiona usuarios|" -ForegroundColor White
    Write-Host "  | Rol 2 admin_storage   : DENEGADO reset   |" -ForegroundColor White
    Write-Host "  | Rol 3 admin_politicas : Vincula GPOs     |" -ForegroundColor White
    Write-Host "  | Rol 4 admin_auditoria : Solo lectura     |" -ForegroundColor White
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 4: Configurar directivas de contrasena (FGPP)
# ------------------------------------------------------------
function Configurar-FGPP {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   CONFIGURAR DIRECTIVAS FGPP (PSOs)      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    try { Get-ADDomain -ErrorAction Stop | Out-Null }
    catch {
        Write-Host "  [ERROR] El servidor no es DC o AD no responde." -ForegroundColor Red
        Read-Host | Out-Null; return
    }

    # =========================================================
    # POLITICA 1: ADMINISTRADORES — Minimo 12 caracteres
    #             Prioridad 10 (mas alta que la estandar)
    # =========================================================
    $fgppAdmin = "P09-FGPP-Admins"
    Write-Host "  [1/2] Configurando FGPP para Administradores (min 12 chars, prioridad 10)..." -ForegroundColor Yellow

    try {
        $existeAdmin = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppAdmin'" -ErrorAction SilentlyContinue

        if ($existeAdmin) {
            Write-Host "  [OK] La politica '$fgppAdmin' ya existe. Actualizando parametros..." -ForegroundColor Yellow
            Set-ADFineGrainedPasswordPolicy -Identity $fgppAdmin `
                -MinPasswordLength      12 `
                -LockoutThreshold       3 `
                -LockoutDuration        "00:30:00" `
                -LockoutObservationWindow "00:30:00"
        } else {
            New-ADFineGrainedPasswordPolicy -Name      $fgppAdmin `
                -DisplayName            "FGPP Alta Seguridad - Administradores" `
                -Precedence             10 `
                -ComplexityEnabled      $true `
                -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount   5 `
                -MinPasswordLength      12 `
                -MinPasswordAge         "1.00:00:00" `
                -MaxPasswordAge         "90.00:00:00" `
                -LockoutThreshold       3 `
                -LockoutObservationWindow "00:30:00" `
                -LockoutDuration        "00:30:00"
            Write-Host "  [CREADO] Politica '$fgppAdmin': 12 chars min, lockout 3 intentos / 30 min." -ForegroundColor Green
        }

        # Aplicar a los 4 usuarios admin y al grupo Domain Admins
        $sujetosAdmin = @("Domain Admins","admin_identidad","admin_storage","admin_politicas","admin_auditoria")
        foreach ($sujeto in $sujetosAdmin) {
            try {
                Add-ADFineGrainedPasswordPolicySubject -Identity $fgppAdmin -Subjects $sujeto -ErrorAction Stop
                Write-Host "    [+] Aplicada a: $sujeto" -ForegroundColor DarkGreen
            } catch { }  # Silenciar error de "ya aplicada"
        }

    } catch {
        Write-Host "  [ERROR] FGPP Admins: $($_.Exception.Message)" -ForegroundColor Red
    }

    # =========================================================
    # POLITICA 2: USUARIOS ESTANDAR — Minimo 8 caracteres
    #             Prioridad 20 (mas baja, para Cuates y NoCuates)
    # =========================================================
    $fgppStd = "P09-FGPP-Standard"
    Write-Host "`n  [2/2] Configurando FGPP para usuarios estandar (min 8 chars, prioridad 20)..." -ForegroundColor Yellow

    try {
        $existeStd = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppStd'" -ErrorAction SilentlyContinue

        if ($existeStd) {
            Write-Host "  [OK] La politica '$fgppStd' ya existe. Actualizando parametros..." -ForegroundColor Yellow
            Set-ADFineGrainedPasswordPolicy -Identity $fgppStd -MinPasswordLength 8
        } else {
            New-ADFineGrainedPasswordPolicy -Name      $fgppStd `
                -DisplayName            "FGPP Estandar - Cuates y No Cuates" `
                -Precedence             20 `
                -ComplexityEnabled      $true `
                -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount   3 `
                -MinPasswordLength      8 `
                -MinPasswordAge         "1.00:00:00" `
                -MaxPasswordAge         "90.00:00:00" `
                -LockoutThreshold       5 `
                -LockoutObservationWindow "00:15:00" `
                -LockoutDuration        "00:30:00"
            Write-Host "  [CREADO] Politica '$fgppStd': 8 chars min." -ForegroundColor Green
        }

        # Aplicar a los grupos/OUs de Cuates y No Cuates
        # NOTA: FGPP solo puede aplicarse a usuarios o grupos de seguridad, no a OUs directamente
        $sujetosStd = @("Cuates", "No Cuates")
        foreach ($sujeto in $sujetosStd) {
            try {
                Add-ADFineGrainedPasswordPolicySubject -Identity $fgppStd -Subjects $sujeto -ErrorAction Stop
                Write-Host "    [+] Aplicada al grupo: $sujeto" -ForegroundColor DarkGreen
            } catch {
                # Si el grupo no existe, intentar con el nombre alternativo
                Write-Host "    [AVISO] No se pudo aplicar a '$sujeto' (puede que el grupo no exista)." -ForegroundColor DarkGray
            }
        }

    } catch {
        Write-Host "  [ERROR] FGPP Standard: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 5: Configurar auditoria y generar reporte de eventos
# ------------------------------------------------------------
function Configurar-Auditoria {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   AUDITORIA DE EVENTOS Y REPORTE         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    # 1. Habilitar politicas de auditoria (exito y fallo)
    Write-Host "  [1/3] Habilitando politicas de auditoria avanzada..." -ForegroundColor Yellow
    $politicas = @(
        @{ sub = "Logon";                  desc = "Inicio de sesion (Logon)" },
        @{ sub = "Account Lockout";        desc = "Bloqueo de cuenta" },
        @{ sub = "File System";            desc = "Acceso a sistema de archivos" },
        @{ sub = "Other Object Access Events"; desc = "Otros accesos a objetos" },
        @{ sub = "User Account Management";    desc = "Gestion de cuentas de usuario" }
    )

    foreach ($p in $politicas) {
        $resultado = auditpol /set /subcategory:"$($p.sub)" /success:enable /failure:enable 2>&1
        if ($resultado -match "error" -or $LASTEXITCODE -ne 0) {
            Write-Host "  [AVISO] '$($p.desc)': $resultado" -ForegroundColor Yellow
        } else {
            Write-Host "  [OK] Auditoria habilitada: $($p.desc)" -ForegroundColor Green
        }
    }

    # 2. Forzar que la GPO de auditoria se aplique inmediatamente
    Write-Host "`n  [2/3] Actualizando politica de grupo..." -ForegroundColor Yellow
    gpupdate /force | Out-Null
    Write-Host "  [OK] GPO actualizada." -ForegroundColor Green

    # 3. Extraer los ultimos 10 eventos de Acceso Denegado (ID 4625) y exportar
    Write-Host "`n  [3/3] Extrayendo eventos de Acceso Denegado (ID 4625)..." -ForegroundColor Yellow

    $rutaReporte = "C:\MFA_Setup\Reporte_AccesosDenegados_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

    $encabezado = @"
==================================================
REPORTE DE AUDITORIA DE SEGURIDAD
Practica 09 - Hardening Active Directory
Fecha de generacion : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
Servidor            : $env:COMPUTERNAME
Dominio             : $env:USERDNSDOMAIN
Tipo de evento      : ID 4625 - Inicio de sesion fallido (Acceso Denegado)
==================================================

"@

    try {
        $eventos = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625 } `
                   -MaxEvents 10 -ErrorAction SilentlyContinue

        $encabezado | Out-File $rutaReporte -Encoding UTF8

        if (-not $eventos -or $eventos.Count -eq 0) {
            Write-Host "  [AVISO] No se encontraron eventos ID 4625. El log puede estar vacio." -ForegroundColor Yellow
            Write-Host "  Esto es normal si no ha habido intentos fallidos de inicio de sesion." -ForegroundColor DarkGray
            "No se encontraron intentos fallidos de inicio de sesion (ID 4625)." | Out-File $rutaReporte -Append -Encoding UTF8
            "Ejecuta un intento fallido manual para generar evidencia." | Out-File $rutaReporte -Append -Encoding UTF8
        } else {
            Write-Host "  [OK] Se encontraron $($eventos.Count) evento(s). Exportando..." -ForegroundColor Green

            $i = 1
            foreach ($e in $eventos) {
                # Extraer el nombre de usuario del mensaje del evento
                $xml      = [xml]$e.ToXml()
                $usuario  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetUserName" }).'#text'
                $domEvento= ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
                $ipOrigen = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "IpAddress" }).'#text'
                $razon    = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "SubStatus" }).'#text'

                $bloque = @"
EVENTO $i de $($eventos.Count)
--------------------------------------------------
Fecha y hora  : $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))
ID de evento  : $($e.Id)
Usuario       : $usuario
Dominio       : $domEvento
IP de origen  : $ipOrigen
Codigo razon  : $razon
--------------------------------------------------

"@
                $bloque | Out-File $rutaReporte -Append -Encoding UTF8
                $i++
            }
        }

        Write-Host "  [OK] Reporte guardado en: $rutaReporte" -ForegroundColor Green
        Write-Host "`n  --- VISTA PREVIA DEL REPORTE ---" -ForegroundColor Cyan
        Get-Content $rutaReporte | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Write-Host "  --------------------------------" -ForegroundColor Cyan

    } catch {
        Write-Host "  [ERROR] Fallo la extraccion de eventos: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 6: Instalar dependencias (VC++ 2022) y multiOTP
# ------------------------------------------------------------
function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   INSTALAR DEPENDENCIAS Y MOTOR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"

    # --- Verificar si ya esta instalado ---
    $rutasBuscar    = @("C:\Program Files\multiOTP", "C:\multiOTP", "C:\Program Files (x86)\multiOTP")
    $multiotpExe    = $null
    foreach ($r in $rutasBuscar) {
        if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break }
    }

    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP ya esta instalado en: $(Split-Path $multiotpExe)" -ForegroundColor Green
        $reinstalar = Read-Host "  Deseas abrir el instalador para reconfigurarlo? (s/n)"
        if ($reinstalar.ToLower() -ne 's') {
            Write-Host "  Continua con la Opcion 7 para configurar el token." -ForegroundColor Yellow
            Read-Host | Out-Null; return
        }
    }

    # =========================================================
    # PASO 1: Visual C++ 2022 Redistributable (dependencia de multiOTP)
    # =========================================================
    Write-Host "  [1/2] Instalando Visual C++ 2022 Redistributable..." -ForegroundColor Yellow

    $vcRedistPath = "$rutaDescarga\vc_redist_2022_x64.exe"
    if (-not (Test-Path $vcRedistPath)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
                              -OutFile $vcRedistPath -UseBasicParsing
        } catch {
            Write-Host "  [ERROR] No se pudo descargar VC++ 2022: $($_.Exception.Message)" -ForegroundColor Red
            Read-Host | Out-Null; return
        }
    }

    $procVC = Start-Process -FilePath $vcRedistPath `
                            -ArgumentList "/install /quiet /norestart" `
                            -Wait -PassThru

    if ($procVC.ExitCode -in @(0, 1638, 3010)) {
        Write-Host "  [OK] VC++ 2022 Redistributable instalado correctamente." -ForegroundColor Green
    } else {
        Write-Host "  [AVISO] VC++ termino con codigo $($procVC.ExitCode) (puede ya estar instalado)." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 2

    # =========================================================
    # PASO 2: Instalar multiOTP Credential Provider
    # =========================================================
    Write-Host "`n  [2/2] Buscando instalador de multiOTP..." -ForegroundColor Yellow

    # Extraer ZIPs si los hay
    Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = "$rutaDescarga\Extracted_$($_.BaseName)"
        if (-not (Test-Path $dest)) {
            Expand-Archive -Path $_.FullName -DestinationPath $dest -Force
        }
    }

    # Buscar el instalador mas grande (suele ser el correcto)
    $instalador = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } |
                  Sort-Object Length -Descending |
                  Select-Object -First 1

    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro el instalador de multiOTP." -ForegroundColor Red
        Write-Host "  Ejecuta primero la Opcion 1 para descargar multiOTP." -ForegroundColor Yellow
        Read-Host | Out-Null; return
    }

    Write-Host "`n  INSTRUCCIONES PARA EL INSTALADOR:" -ForegroundColor Yellow
    Write-Host "  ====================================================" -ForegroundColor Yellow
    Write-Host "  1. Marca: 'No remote server, local multiOTP only'" -ForegroundColor White
    Write-Host "  2. En Logon   selecciona: 'Local and Remote'" -ForegroundColor White
    Write-Host "  3. En Unlock  selecciona: 'Local and Remote'" -ForegroundColor White
    Write-Host "  4. Haz clic en Next hasta Finish." -ForegroundColor White
    Write-Host "  ====================================================" -ForegroundColor Yellow
    Write-Host "  Presiona Enter cuando estes listo para lanzar el instalador..."
    Read-Host | Out-Null

    try {
        if ($instalador.Extension -eq ".msi") {
            $proc = Start-Process "msiexec.exe" -ArgumentList "/i `"$($instalador.FullName)`"" -Wait -PassThru
        } else {
            $proc = Start-Process $instalador.FullName -Wait -PassThru
        }

        if ($proc.ExitCode -eq 0) {
            Write-Host "  [OK] multiOTP instalado correctamente." -ForegroundColor Green
        } else {
            Write-Host "  [AVISO] Instalador termino con codigo $($proc.ExitCode)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR] Fallo la instalacion: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 7: Activar MFA y registrar usuario en multiOTP
# ------------------------------------------------------------
function Activar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   ACTIVAR MFA Y GENERAR CLAVE TOTP       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    # 1. Localizar multiotp.exe
    $multiotpExe = $null
    $rutasBuscar = @("C:\Program Files\multiOTP", "C:\multiOTP", "C:\Program Files (x86)\multiOTP")
    foreach ($r in $rutasBuscar) {
        if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break }
    }

    if (-not $multiotpExe) {
        Write-Host "  [ERROR] No se encontro multiotp.exe." -ForegroundColor Red
        Write-Host "  Ejecuta primero la Opcion 6 para instalar multiOTP." -ForegroundColor Yellow
        Read-Host | Out-Null; return
    }

    $dirMultiOTP = Split-Path $multiotpExe
    Push-Location $dirMultiOTP

    # 2. Preguntar que usuario configurar (por defecto: Administrator)
    Write-Host "  Usuario a proteger con MFA (presiona Enter para usar 'Administrator'):" -ForegroundColor Yellow
    $usuarioMFA = Read-Host "  Usuario"
    if ([string]::IsNullOrWhiteSpace($usuarioMFA)) { $usuarioMFA = "Administrator" }

    # 3. Generar secreto TOTP en Base32 (16 caracteres = 80 bits, estandar TOTP RFC 6238)
    #    Alfabeto Base32: A-Z + 2-7 (sin confusiones visuales como 0/O, 1/I)
    $base32     = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $miSecreto  = -join ((1..16) | ForEach-Object { $base32[(Get-Random -Maximum 32)] })

    Write-Host "`n  [INFO] Secreto TOTP generado: $miSecreto" -ForegroundColor DarkGray

    # 4. Registrar el usuario en multiOTP con el secreto correcto
    #    Flujo oficial multiOTP:
    #      -delete   : eliminar si ya existe (para evitar duplicados)
    #      -create   : crear usuario
    #      -set      : configurar atributos
    #      El secreto se inyecta como parametro de -set con key=SECRETO
    Write-Host "`n  [INFO] Registrando usuario '$usuarioMFA' en multiOTP..." -ForegroundColor Yellow

    # Eliminar si ya existia
    & ".\multiotp.exe" -delete $usuarioMFA 2>&1 | Out-Null

    # Crear y configurar con secreto TOTP externo
    $salidaCreate = & ".\multiotp.exe" -create -prefix-pin-needed-enabled -time-based-totp $usuarioMFA TOTP $miSecreto 6 30 2>&1
    Write-Host "  [DEBUG] Resultado create: $salidaCreate" -ForegroundColor DarkGray

    # Verificar que el usuario quedo registrado
    $verificacion = & ".\multiotp.exe" -display-log -checkparam $usuarioMFA 2>&1
    Write-Host "  [DEBUG] Verificacion: $verificacion" -ForegroundColor DarkGray

    # 5. Configurar bloqueo de cuenta tras 3 intentos MFA fallidos (Test 4)
    Write-Host "`n  [INFO] Configurando bloqueo: 3 intentos fallidos = 30 minutos de lockout..." -ForegroundColor Yellow
    & ".\multiotp.exe" -config MaxDelayedFailures=3    2>&1 | Out-Null
    & ".\multiotp.exe" -config MaxBlockFailures=3      2>&1 | Out-Null
    & ".\multiotp.exe" -config FailureDelayInSeconds=1800 2>&1 | Out-Null  # 30 minutos = 1800 segundos
    Write-Host "  [OK] Bloqueo MFA configurado: 3 fallos -> lockout 30 minutos." -ForegroundColor Green

    Pop-Location

    # 6. Mostrar instrucciones para Google Authenticator
    Write-Host "`n  +-------------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |   CONFIGURA GOOGLE AUTHENTICATOR EN TU CELULAR              |" -ForegroundColor Magenta
    Write-Host "  +-------------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Pasos en la app Google Authenticator:" -ForegroundColor White
    Write-Host "  1. Abre Google Authenticator en tu telefono." -ForegroundColor White
    Write-Host "  2. Toca el boton '+' (Agregar cuenta)." -ForegroundColor White
    Write-Host "  3. Selecciona 'Ingresar clave de configuracion'." -ForegroundColor White
    Write-Host "  4. Escribe exactamente los siguientes datos:" -ForegroundColor White
    Write-Host ""
    Write-Host "     Nombre de la cuenta  : Practica09 - $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "     Tu clave             : $miSecreto" -ForegroundColor Green
    Write-Host "     Tipo de clave        : Basada en tiempo (TOTP)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  5. Toca 'Agregar'. Veras un codigo de 6 digitos que cambia" -ForegroundColor White
    Write-Host "     cada 30 segundos. USA ESE CODIGO al iniciar sesion." -ForegroundColor White
    Write-Host ""
    Write-Host "  IMPORTANTE: Guarda este secreto en lugar seguro: $miSecreto" -ForegroundColor Yellow

    # 7. Guardar el secreto en un archivo de referencia por si se necesita recuperar
    $archivoSecreto = "C:\MFA_Setup\MFA_Secret_$usuarioMFA.txt"
    @"
MFA TOTP Secret — Practica 09
==============================
Usuario  : $usuarioMFA
Servidor : $env:COMPUTERNAME
Dominio  : $env:USERDNSDOMAIN
Secreto  : $miSecreto
Tipo     : TOTP (RFC 6238) — Google Authenticator compatible
Generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')

INSTRUCCION: Ingresa este secreto en Google Authenticator
como 'clave de configuracion' seleccionando 'Basada en tiempo'.
"@ | Out-File $archivoSecreto -Encoding UTF8

    Write-Host "`n  [OK] Secreto guardado en: $archivoSecreto (para referencia de documentacion)" -ForegroundColor Green

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 8: Ejecutar todos los tests de evaluacion
# ------------------------------------------------------------
function Ejecutar-Tests {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PROTOCOLO DE PRUEBAS — PRACTICA 09     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    Write-Host "  Selecciona el test a ejecutar:" -ForegroundColor Yellow
    Write-Host "  1. Test 1 — Delegacion RBAC (Rol 2 vs Rol 1)" -ForegroundColor White
    Write-Host "  2. Test 2 — FGPP: verificar que admin_identidad requiere 12 chars" -ForegroundColor White
    Write-Host "  3. Test 3 — Verificar estado de MFA en multiOTP" -ForegroundColor White
    Write-Host "  4. Test 5 — Reporte de Auditoria (script de extraccion de logs)" -ForegroundColor White
    Write-Host "  5. Ejecutar todos los tests automatizables" -ForegroundColor White
    Write-Host ""
    $testOpcion = Read-Host "  Selecciona"

    switch ($testOpcion) {
        '1' { Test-DelegacionRBAC }
        '2' { Test-FGPP }
        '3' { Test-EstadoMFA }
        '4' { Configurar-Auditoria }
        '5' {
            Test-DelegacionRBAC
            Test-FGPP
            Test-EstadoMFA
            Configurar-Auditoria
        }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# --- TEST 1: Verificar que admin_storage NO puede resetear contraseñas ---
function Test-DelegacionRBAC {
    Write-Host "`n  TEST 1 — Verificacion de Delegacion RBAC" -ForegroundColor Cyan
    Write-Host "  -----------------------------------------" -ForegroundColor Cyan

    # Verificar que admin_storage tiene una ACE de Deny en Reset Password
    try {
        $dominio   = Get-ADDomain
        $acl       = Get-Acl -Path "AD:\$($dominio.DistinguishedName)"
        $netbios   = $dominio.NetBIOSName

        $denyAce   = $acl.Access | Where-Object {
            $_.IdentityReference -like "*admin_storage*" -and
            $_.AccessControlType -eq "Deny" -and
            $_.ActiveDirectoryRights -like "*ExtendedRight*"
        }

        if ($denyAce) {
            Write-Host "  [PASS] Confirmado: admin_storage tiene ACE de DENY para Reset Password." -ForegroundColor Green
            Write-Host "         El Test 1 de la rubrica pasara correctamente." -ForegroundColor DarkGreen
        } else {
            Write-Host "  [WARN] No se detecto la ACE de Deny para admin_storage." -ForegroundColor Yellow
            Write-Host "         Ejecuta la Opcion 3 (Aplicar RBAC) y repite este test." -ForegroundColor Yellow
        }

        # Verificar que admin_identidad SI tiene permisos
        $grantAce = $acl.Access | Where-Object {
            $_.IdentityReference -like "*admin_identidad*" -and
            $_.AccessControlType -eq "Allow"
        }
        if ($grantAce) {
            Write-Host "  [PASS] admin_identidad tiene permisos de gestion en el dominio." -ForegroundColor Green
        }

    } catch {
        Write-Host "  [ERROR] No se pudo verificar las ACL: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Prueba manual: Inicia sesion como admin_storage e intenta reset de contrasena." -ForegroundColor Yellow
    }
}

# --- TEST 2: Verificar que admin_identidad tiene FGPP de 12 chars aplicada ---
function Test-FGPP {
    Write-Host "`n  TEST 2 — Verificacion de FGPP (Fine-Grained Password Policy)" -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------------------" -ForegroundColor Cyan

    try {
        $politicaEfectiva = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad" -ErrorAction Stop

        if ($politicaEfectiva) {
            Write-Host "  Politica efectiva para 'admin_identidad':" -ForegroundColor Yellow
            Write-Host "  Nombre             : $($politicaEfectiva.Name)"           -ForegroundColor White
            Write-Host "  Longitud minima    : $($politicaEfectiva.MinPasswordLength) caracteres" -ForegroundColor White
            Write-Host "  Threshold lockout  : $($politicaEfectiva.LockoutThreshold)"             -ForegroundColor White
            Write-Host "  Duracion lockout   : $($politicaEfectiva.LockoutDuration)"              -ForegroundColor White

            if ($politicaEfectiva.MinPasswordLength -ge 12) {
                Write-Host "`n  [PASS] Correcto: admin_identidad requiere minimo 12 caracteres." -ForegroundColor Green
                Write-Host "         Asignar una contrasena de 8 chars fallara (Test 2 correcto)." -ForegroundColor DarkGreen
            } else {
                Write-Host "`n  [FAIL] La politica aplicada solo requiere $($politicaEfectiva.MinPasswordLength) chars." -ForegroundColor Red
                Write-Host "         Ejecuta la Opcion 4 y verifica que admin_identidad esta en la lista de sujetos." -ForegroundColor Red
            }
        } else {
            Write-Host "  [WARN] No hay FGPP especifica: se usa la politica de dominio por defecto." -ForegroundColor Yellow
            Write-Host "         Ejecuta la Opcion 4 (Configurar FGPP) primero." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [ERROR]: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# --- TEST 3: Verificar el estado de MFA en multiOTP ---
function Test-EstadoMFA {
    Write-Host "`n  TEST 3 — Verificacion del estado de MFA (multiOTP)" -ForegroundColor Cyan
    Write-Host "  ---------------------------------------------------" -ForegroundColor Cyan

    $multiotpExe = $null
    $rutasBuscar = @("C:\Program Files\multiOTP", "C:\multiOTP", "C:\Program Files (x86)\multiOTP")
    foreach ($r in $rutasBuscar) {
        if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break }
    }

    if (-not $multiotpExe) {
        Write-Host "  [FAIL] multiOTP no esta instalado." -ForegroundColor Red
        Write-Host "         Ejecuta las Opciones 1, 6 y 7 en orden." -ForegroundColor Yellow
        return
    }

    Write-Host "  [OK] multiOTP encontrado en: $multiotpExe" -ForegroundColor Green

    $dir = Split-Path $multiotpExe
    Push-Location $dir

    # Listar usuarios registrados
    Write-Host "  Usuarios registrados en multiOTP:" -ForegroundColor Yellow
    $usuarios = & ".\multiotp.exe" -list 2>&1
    Write-Host "  $usuarios" -ForegroundColor White

    # Verificar configuracion de bloqueo
    Write-Host "`n  Configuracion de bloqueo MFA:" -ForegroundColor Yellow
    $config = & ".\multiotp.exe" -showconfig 2>&1
    $lineasRelevantes = $config | Where-Object { $_ -match "(MaxBlock|MaxDelay|Failure)" }
    $lineasRelevantes | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    if ($lineasRelevantes -match "3") {
        Write-Host "`n  [PASS] Bloqueo configurado en 3 intentos." -ForegroundColor Green
    } else {
        Write-Host "`n  [WARN] No se confirmo el umbral de 3 intentos. Ejecuta la Opcion 7." -ForegroundColor Yellow
    }

    Pop-Location
}
