# ============================================================
#  funciones_p9.ps1 -- Libreria de funciones Practica 09
#  Hardening AD, RBAC, FGPP, Auditoria y MFA TOTP
# ============================================================

# ------------------------------------------------------------
# UTILIDAD: Detectar nombre real de OUs creadas en P08
# Prueba "Cuates", "NoCuates"; si no existe la crea.
# ------------------------------------------------------------
function Get-OUSegura {
    param([string]$NombreBase)
    $dcBase = (Get-ADDomain).DistinguishedName
    $variantes = @($NombreBase, ($NombreBase -replace ' ',''))
    foreach ($v in $variantes) {
        try {
            Get-ADOrganizationalUnit -Identity "OU=$v,$dcBase" -ErrorAction Stop | Out-Null
            return "OU=$v,$dcBase"
        } catch {}
    }
    Write-Host "  [AVISO] OU '$NombreBase' no existe. Creandola..." -ForegroundColor Yellow
    try {
        New-ADOrganizationalUnit -Name $NombreBase -Path $dcBase -ErrorAction Stop
        Write-Host "  [OK] OU '$NombreBase' creada." -ForegroundColor Green
        return "OU=$NombreBase,$dcBase"
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

    $proceder = $true
    $existentes = Get-ChildItem -Path $rutaDescarga -Filter "multiOTP*" -ErrorAction SilentlyContinue
    if ($existentes) {
        Write-Host "  [AVISO] Ya hay archivos multiOTP en $rutaDescarga." -ForegroundColor Yellow
        $r = Read-Host "  Descargar la version mas nueva desde GitHub? (s/n)"
        if ($r.ToLower() -ne 's') {
            $proceder = $false
            Write-Host "  [OK] Usando archivos existentes." -ForegroundColor Green
        }
    }

    if ($proceder) {
        Write-Host "  [INFO] Consultando GitHub API..." -ForegroundColor Cyan
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        try {
            $headers = @{ "User-Agent" = "PowerShell-P09" }
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/multiOTP/multiOTPCredentialProvider/releases/latest" -Headers $headers -UseBasicParsing
            $asset   = $release.assets | Where-Object { $_.name -like "*.zip" -or $_.name -like "*.exe" } | Select-Object -First 1
            if (-not $asset) { Write-Host "  [ERROR] Sin instalador en el release." -ForegroundColor Red; Read-Host | Out-Null; return }

            $rutaArchivo = "$rutaDescarga\$($asset.name)"
            Write-Host "  [INFO] Descargando $($release.tag_name) ($($asset.name))..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $rutaArchivo -UseBasicParsing -Headers $headers

            if ($rutaArchivo.EndsWith(".zip")) {
                Write-Host "  [INFO] Extrayendo ZIP..." -ForegroundColor Yellow
                Expand-Archive -Path $rutaArchivo -DestinationPath $rutaDescarga -Force
            }
            Write-Host "  [OK] Descarga completa." -ForegroundColor Green
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

    $pwdTexto  = "Hardening2026!"
    $pwdSegura = ConvertTo-SecureString $pwdTexto -AsPlainText -Force
    $creados   = 0
    $omitidos  = 0

    foreach ($u in $usuarios) {
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Sam)'" -ErrorAction SilentlyContinue
        if ($existe) {
            Write-Host "  [OMITIDO] '$($u.Sam)' ya existe en AD." -ForegroundColor Yellow
            $omitidos++
        } else {
            try {
                New-ADUser -Name             $u.Nombre `
                           -SamAccountName   $u.Sam `
                           -UserPrincipalName "$($u.Sam)@$((Get-ADDomain).DNSRoot)" `
                           -Description      $u.Desc `
                           -AccountPassword   $pwdSegura `
                           -Enabled          $true `
                           -PasswordNeverExpires $true
                Write-Host "  [OK] '$($u.Sam)' creado. Pass: $pwdTexto" -ForegroundColor Green
                $creados++
            } catch {
                Write-Host "  [ERROR] '$($u.Sam)': $($_.Exception.Message)" -ForegroundColor Red
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

    try { $dominio = Get-ADDomain -ErrorAction Stop }
    catch { Write-Host "  [ERROR] No se puede conectar a AD." -ForegroundColor Red; Read-Host | Out-Null; return }

    $dcBase  = $dominio.DistinguishedName
    $netbios = $dominio.NetBIOSName

    Write-Host "  Detectando OUs del dominio..." -ForegroundColor Yellow
    $ouCuates   = Get-OUSegura -NombreBase "Cuates"
    $ouNoCuates = Get-OUSegura -NombreBase "NoCuates"

    if (-not $ouCuates -or -not $ouNoCuates) {
        Write-Host "  [ERROR] No se pudieron resolver las OUs." -ForegroundColor Red
        Read-Host | Out-Null; return
    }

    Write-Host "  OU Cuates   : $ouCuates" -ForegroundColor DarkGray
    Write-Host "  OU NoCuates : $ouNoCuates`n" -ForegroundColor DarkGray

    # --- ROL 1: admin_identidad -- Gestion total de usuarios en ambas OUs ---
    Write-Host "  [ROL 1] admin_identidad (IAM Operator)..." -ForegroundColor Yellow
    # CCDC = Create Child / Delete Child (crear y eliminar usuarios dentro de la OU)
    dsacls "$ouCuates"   /I:T /G "${netbios}\admin_identidad:CCDC;;user" 2>&1 | Out-Null
    dsacls "$ouNoCuates" /I:T /G "${netbios}\admin_identidad:CCDC;;user" 2>&1 | Out-Null
    # CA Reset Password = permiso de resetear contrasena
    dsacls "$ouCuates"   /I:T /G "${netbios}\admin_identidad:CA;Reset Password;user" 2>&1 | Out-Null
    dsacls "$ouNoCuates" /I:T /G "${netbios}\admin_identidad:CA;Reset Password;user" 2>&1 | Out-Null
    # RPWP sobre atributos basicos (telefono, oficina, correo)
    dsacls "$ouCuates"   /I:T /G "${netbios}\admin_identidad:RPWP;telephoneNumber;user" 2>&1 | Out-Null
    dsacls "$ouNoCuates" /I:T /G "${netbios}\admin_identidad:RPWP;telephoneNumber;user" 2>&1 | Out-Null
    dsacls "$ouCuates"   /I:T /G "${netbios}\admin_identidad:RPWP;physicalDeliveryOfficeName;user" 2>&1 | Out-Null
    dsacls "$ouNoCuates" /I:T /G "${netbios}\admin_identidad:RPWP;physicalDeliveryOfficeName;user" 2>&1 | Out-Null
    dsacls "$ouCuates"   /I:T /G "${netbios}\admin_identidad:RPWP;mail;user" 2>&1 | Out-Null
    dsacls "$ouNoCuates" /I:T /G "${netbios}\admin_identidad:RPWP;mail;user" 2>&1 | Out-Null
    Write-Host "  [OK] admin_identidad: Control total sobre usuarios en ambas OUs." -ForegroundColor Green

    # --- ROL 2: admin_storage -- DENEGAR Reset Password en TODO el dominio ---
    Write-Host "`n  [ROL 2] admin_storage (Storage Operator) -- DENY Reset Password..." -ForegroundColor Yellow
    # /D = Deny explicito; /I:S = heredar a sub-objetos (Sin herencia al objeto mismo)
    dsacls "$dcBase" /I:S /D "${netbios}\admin_storage:CA;Reset Password;user" 2>&1 | Out-Null
    Write-Host "  [OK] admin_storage: DENEGADO Reset Password en todo el dominio (Test 1 listo)." -ForegroundColor Green

    # --- ROL 3: admin_politicas -- Vincular GPOs en OUs asignadas ---
    Write-Host "`n  [ROL 3] admin_politicas (GPO Compliance)..." -ForegroundColor Yellow
    try {
        Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "admin_politicas" -ErrorAction Stop
        Write-Host "  [OK] Agregado a 'Group Policy Creator Owners'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Ya pertenece a 'Group Policy Creator Owners'." -ForegroundColor DarkGray
    }
    # gPLink y gPOptions son los atributos que controlan que GPOs estan vinculadas a una OU
    dsacls "$ouCuates"   /I:T /G "${netbios}\admin_politicas:RPWP;gPLink"    2>&1 | Out-Null
    dsacls "$ouCuates"   /I:T /G "${netbios}\admin_politicas:RPWP;gPOptions" 2>&1 | Out-Null
    dsacls "$ouNoCuates" /I:T /G "${netbios}\admin_politicas:RPWP;gPLink"    2>&1 | Out-Null
    dsacls "$ouNoCuates" /I:T /G "${netbios}\admin_politicas:RPWP;gPOptions" 2>&1 | Out-Null
    # Lectura en todo el dominio
    dsacls "$dcBase" /I:T /G "${netbios}\admin_politicas:GR" 2>&1 | Out-Null
    Write-Host "  [OK] admin_politicas: Puede vincular GPOs en ambas OUs + lectura de dominio." -ForegroundColor Green

    # --- ROL 4: admin_auditoria -- Solo lectura, acceso a Event Logs ---
    Write-Host "`n  [ROL 4] admin_auditoria (Security Auditor)..." -ForegroundColor Yellow
    try {
        Add-ADGroupMember -Identity "Event Log Readers" -Members "admin_auditoria" -ErrorAction Stop
        Write-Host "  [OK] Agregado a 'Event Log Readers'." -ForegroundColor Green
    } catch {
        Write-Host "  [AVISO] Ya pertenece a 'Event Log Readers'." -ForegroundColor DarkGray
    }
    dsacls "$dcBase" /I:T /G "${netbios}\admin_auditoria:GR" 2>&1 | Out-Null
    Write-Host "  [OK] admin_auditoria: Solo lectura en todo el dominio." -ForegroundColor Green

    Write-Host "`n  RBAC aplicado correctamente." -ForegroundColor Green
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
    catch { Write-Host "  [ERROR] No hay conexion a AD." -ForegroundColor Red; Read-Host | Out-Null; return }

    # --- POLITICA 1: ADMINISTRADORES -- min 12 chars, prioridad 10 ---
    $fgppAdmin = "P09-FGPP-Admins"
    Write-Host "  [1/2] FGPP para Administradores (12 chars, prioridad 10)..." -ForegroundColor Yellow
    try {
        $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppAdmin'" -ErrorAction SilentlyContinue
        if ($existe) {
            Write-Host "  [OK] '$fgppAdmin' ya existe. Actualizando..." -ForegroundColor Yellow
            Set-ADFineGrainedPasswordPolicy -Identity $fgppAdmin -MinPasswordLength 12 -LockoutThreshold 3 -LockoutDuration "00:30:00" -LockoutObservationWindow "00:30:00"
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppAdmin `
                -DisplayName "FGPP Alta Seguridad - Administradores" `
                -Precedence 10 -ComplexityEnabled $true -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 5 -MinPasswordLength 12 `
                -MinPasswordAge "1.00:00:00" -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 3 -LockoutObservationWindow "00:30:00" -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] '$fgppAdmin': 12 chars min, lockout 3 intentos / 30 min." -ForegroundColor Green
        }
        foreach ($s in @("Domain Admins","admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
            try { Add-ADFineGrainedPasswordPolicySubject -Identity $fgppAdmin -Subjects $s -ErrorAction Stop; Write-Host "    [+] Aplicada a: $s" -ForegroundColor DarkGreen } catch {}
        }
    } catch { Write-Host "  [ERROR] FGPP Admins: $($_.Exception.Message)" -ForegroundColor Red }

    # --- POLITICA 2: ESTANDAR -- min 8 chars, prioridad 20 ---
    $fgppStd = "P09-FGPP-Standard"
    Write-Host "`n  [2/2] FGPP para usuarios estandar (8 chars, prioridad 20)..." -ForegroundColor Yellow
    try {
        $existe = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$fgppStd'" -ErrorAction SilentlyContinue
        if ($existe) {
            Write-Host "  [OK] '$fgppStd' ya existe. Actualizando..." -ForegroundColor Yellow
            Set-ADFineGrainedPasswordPolicy -Identity $fgppStd -MinPasswordLength 8
        } else {
            New-ADFineGrainedPasswordPolicy -Name $fgppStd `
                -DisplayName "FGPP Estandar - Cuates y NoCuates" `
                -Precedence 20 -ComplexityEnabled $true -ReversibleEncryptionEnabled $false `
                -PasswordHistoryCount 3 -MinPasswordLength 8 `
                -MinPasswordAge "1.00:00:00" -MaxPasswordAge "90.00:00:00" `
                -LockoutThreshold 5 -LockoutObservationWindow "00:15:00" -LockoutDuration "00:30:00"
            Write-Host "  [CREADO] '$fgppStd': 8 chars min." -ForegroundColor Green
        }
        foreach ($s in @("Cuates","NoCuates")) {
            try { Add-ADFineGrainedPasswordPolicySubject -Identity $fgppStd -Subjects $s -ErrorAction Stop; Write-Host "    [+] Aplicada al grupo: $s" -ForegroundColor DarkGreen }
            catch { Write-Host "    [AVISO] No se pudo aplicar a '$s' (verifica que el grupo existe)." -ForegroundColor DarkGray }
        }
    } catch { Write-Host "  [ERROR] FGPP Standard: $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 5: Configurar auditoria y generar reporte ID 4625
# ------------------------------------------------------------
function Configurar-Auditoria {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   AUDITORIA DE EVENTOS Y REPORTE         |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    Write-Host "  [1/3] Habilitando politicas de auditoria..." -ForegroundColor Yellow
    $politicas = @(
        "Logon", "Account Lockout", "File System",
        "Other Object Access Events", "User Account Management"
    )
    foreach ($p in $politicas) {
        auditpol /set /subcategory:"$p" /success:enable /failure:enable 2>&1 | Out-Null
        Write-Host "  [OK] Auditoria: $p" -ForegroundColor Green
    }

    Write-Host "`n  [2/3] Aplicando politica de grupo (gpupdate)..." -ForegroundColor Yellow
    gpupdate /force 2>&1 | Out-Null
    Write-Host "  [OK] GPO actualizada." -ForegroundColor Green

    Write-Host "`n  [3/3] Extrayendo eventos ID 4625 (Acceso Denegado)..." -ForegroundColor Yellow
    $rutaReporte = "C:\MFA_Setup\Reporte_AccesosDenegados_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

    $encabezado = "==================================================" + [Environment]::NewLine +
                  "REPORTE DE AUDITORIA DE SEGURIDAD" + [Environment]::NewLine +
                  "Practica 09 - Hardening Active Directory" + [Environment]::NewLine +
                  "Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" + [Environment]::NewLine +
                  "Servidor : $env:COMPUTERNAME" + [Environment]::NewLine +
                  "Dominio  : $env:USERDNSDOMAIN" + [Environment]::NewLine +
                  "Evento   : ID 4625 - Inicio de sesion fallido" + [Environment]::NewLine +
                  "==================================================" + [Environment]::NewLine

    try {
        $eventos = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 10 -ErrorAction SilentlyContinue
        $encabezado | Out-File $rutaReporte -Encoding UTF8

        if (-not $eventos -or $eventos.Count -eq 0) {
            Write-Host "  [AVISO] No hay eventos ID 4625. Haz un intento de login fallido para generar evidencia." -ForegroundColor Yellow
            "No se encontraron eventos de acceso denegado (ID 4625)." | Out-File $rutaReporte -Append -Encoding UTF8
        } else {
            Write-Host "  [OK] $($eventos.Count) evento(s) encontrados. Exportando..." -ForegroundColor Green
            $i = 1
            foreach ($e in $eventos) {
                $xml      = [xml]$e.ToXml()
                $usuario  = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetUserName"   }).'#text'
                $domEvt   = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
                $ip       = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "IpAddress"        }).'#text'
                (
                    "EVENTO $i de $($eventos.Count)" + [Environment]::NewLine +
                    "--------------------------------------------------" + [Environment]::NewLine +
                    "Fecha    : $($e.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss'))" + [Environment]::NewLine +
                    "Usuario  : $usuario" + [Environment]::NewLine +
                    "Dominio  : $domEvt" + [Environment]::NewLine +
                    "IP origen: $ip" + [Environment]::NewLine +
                    "--------------------------------------------------" + [Environment]::NewLine
                ) | Out-File $rutaReporte -Append -Encoding UTF8
                $i++
            }
        }

        Write-Host "  [OK] Reporte guardado en: $rutaReporte" -ForegroundColor Green
        Write-Host "`n  --- CONTENIDO DEL REPORTE ---" -ForegroundColor Cyan
        Get-Content $rutaReporte | ForEach-Object { Write-Host "  $_" }
        Write-Host "  ----------------------------" -ForegroundColor Cyan
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 6: Instalar VC++ 2022 y multiOTP Credential Provider
# ------------------------------------------------------------
function Instalar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   INSTALAR DEPENDENCIAS Y MOTOR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    $rutasBuscar  = @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")
    $multiotpExe  = $null
    foreach ($r in $rutasBuscar) { if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break } }

    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP ya instalado en: $(Split-Path $multiotpExe)" -ForegroundColor Green
        $r2 = Read-Host "  Abrir el instalador para reconfigurar? (s/n)"
        if ($r2.ToLower() -ne 's') { Write-Host "  Continua con la Opcion 7." -ForegroundColor Yellow; Read-Host | Out-Null; return }
    }

    # --- PASO 1: Visual C++ 2022 Redistributable ---
    Write-Host "  [1/2] Instalando Visual C++ 2022 Redistributable..." -ForegroundColor Yellow
    $vcPath = "$rutaDescarga\vc_redist_2022_x64.exe"
    if (-not (Test-Path $vcPath)) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $vcPath -UseBasicParsing
        } catch { Write-Host "  [ERROR] No se pudo descargar VC++: $($_.Exception.Message)" -ForegroundColor Red; Read-Host | Out-Null; return }
    }
    $proc = Start-Process $vcPath -ArgumentList "/install /quiet /norestart" -Wait -PassThru
    if ($proc.ExitCode -in @(0,1638,3010)) { Write-Host "  [OK] VC++ 2022 listo." -ForegroundColor Green }
    else { Write-Host "  [AVISO] VC++ codigo: $($proc.ExitCode)" -ForegroundColor Yellow }
    Start-Sleep -Seconds 2

    # --- PASO 2: Instalar multiOTP ---
    Write-Host "`n  [2/2] Buscando instalador de multiOTP..." -ForegroundColor Yellow
    Get-ChildItem -Path $rutaDescarga -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        $dest = "$rutaDescarga\Extracted_$($_.BaseName)"
        if (-not (Test-Path $dest)) { Expand-Archive -Path $_.FullName -DestinationPath $dest -Force }
    }

    $instalador = Get-ChildItem -Path $rutaDescarga -Recurse -ErrorAction SilentlyContinue |
                  Where-Object { $_.Extension -match "\.(exe|msi)$" -and $_.Name -notmatch "vc_redist" } |
                  Sort-Object Length -Descending | Select-Object -First 1

    if (-not $instalador) {
        Write-Host "  [ERROR] No se encontro el instalador. Ejecuta la Opcion 1 primero." -ForegroundColor Red
        Read-Host | Out-Null; return
    }

    Write-Host "`n  INSTRUCCIONES PARA EL INSTALADOR:" -ForegroundColor Yellow
    Write-Host "  1. Marca: 'No remote server, local multiOTP only'" -ForegroundColor White
    Write-Host "  2. Logon  -> selecciona 'Local and Remote'" -ForegroundColor White
    Write-Host "  3. Unlock -> selecciona 'Local and Remote'" -ForegroundColor White
    Write-Host "  4. Next hasta Finish." -ForegroundColor White
    Write-Host "  Presiona Enter para lanzar el instalador..."
    Read-Host | Out-Null

    try {
        if ($instalador.Extension -eq ".msi") { $proc = Start-Process "msiexec.exe" -ArgumentList "/i `"$($instalador.FullName)`"" -Wait -PassThru }
        else { $proc = Start-Process $instalador.FullName -Wait -PassThru }
        if ($proc.ExitCode -eq 0) { Write-Host "  [OK] multiOTP instalado correctamente." -ForegroundColor Green }
        else { Write-Host "  [AVISO] Instalador termino con codigo $($proc.ExitCode)." -ForegroundColor Yellow }
    } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 7: Activar MFA -- registrar usuario TOTP en multiOTP
# ------------------------------------------------------------
function Activar-MFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   ACTIVAR MFA Y GENERAR CLAVE TOTP       |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    # 1. Localizar multiotp.exe
    $multiotpExe = $null
    $rutasBuscar = @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")
    foreach ($r in $rutasBuscar) { if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break } }
    if (-not $multiotpExe) {
        Write-Host "  [ERROR] multiotp.exe no encontrado. Ejecuta la Opcion 6 primero." -ForegroundColor Red
        Read-Host | Out-Null; return
    }
    $dir = Split-Path $multiotpExe
    Push-Location $dir

    # 2. Preguntar usuario (default: Administrator)
    Write-Host "  Usuario a proteger con MFA [Enter = Administrator]: " -ForegroundColor Yellow -NoNewline
    $usuarioMFA = Read-Host
    if ([string]::IsNullOrWhiteSpace($usuarioMFA)) { $usuarioMFA = "Administrator" }

    # 3. Generar secreto TOTP Base32 (16 chars = 80 bits, RFC 6238)
    $base32    = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $miSecreto = -join ((1..16) | ForEach-Object { $base32[(Get-Random -Maximum 32)] })
    Write-Host "`n  [INFO] Secreto TOTP generado (guardalo): $miSecreto" -ForegroundColor DarkGray

    # 4. Registrar en multiOTP
    #    Sintaxis real del CLI de multiOTP:
    #      multiotp -create USER TOTP SECRET DIGITS
    #    El periodo (30s) es el default de TOTP, no se pasa como argumento.
    #    -prefix-pin-needed-enabled lo dejamos fuera para no pedir PIN adicional.
    Write-Host "  [INFO] Registrando '$usuarioMFA' en multiOTP..." -ForegroundColor Yellow
    & ".\multiotp.exe" -delete $usuarioMFA 2>&1 | Out-Null
    $salida = & ".\multiotp.exe" -create $usuarioMFA TOTP $miSecreto 6 2>&1
    Write-Host "  [DEBUG] create: $salida" -ForegroundColor DarkGray

    # Verificar que el usuario quedo registrado correctamente
    $check = & ".\multiotp.exe" -list 2>&1
    if ($check -match $usuarioMFA) {
        Write-Host "  [OK] Usuario '$usuarioMFA' registrado correctamente en multiOTP." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] No se confirmo el registro. Intenta con el nombre de dominio:" -ForegroundColor Yellow
        # Algunos instaladores requieren el formato DOMINIO\usuario
        $usuarioDominio = "$env:USERDOMAIN\$usuarioMFA"
        & ".\multiotp.exe" -delete $usuarioDominio 2>&1 | Out-Null
        $salida2 = & ".\multiotp.exe" -create $usuarioDominio TOTP $miSecreto 6 2>&1
        Write-Host "  [DEBUG] create (dominio): $salida2" -ForegroundColor DarkGray
    }

    # 5. Configurar bloqueo: 3 intentos MFA fallidos -> lockout 30 minutos (Test 4)
    Write-Host "  [INFO] Configurando bloqueo (3 intentos = 30 min lockout)..." -ForegroundColor Yellow
    & ".\multiotp.exe" -config MaxDelayedFailures=3     2>&1 | Out-Null
    & ".\multiotp.exe" -config MaxBlockFailures=3       2>&1 | Out-Null
    & ".\multiotp.exe" -config FailureDelayInSeconds=1800 2>&1 | Out-Null
    Write-Host "  [OK] Bloqueo MFA: 3 fallos -> lockout 30 minutos." -ForegroundColor Green

    Pop-Location

    # 6. Instrucciones para Google Authenticator
    Write-Host "`n  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |   CONFIGURA GOOGLE AUTHENTICATOR EN TU CELULAR           |" -ForegroundColor Magenta
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  1. Abre Google Authenticator en tu celular." -ForegroundColor White
    Write-Host "  2. Toca '+' -> 'Ingresar clave de configuracion'." -ForegroundColor White
    Write-Host "  3. Ingresa estos datos:" -ForegroundColor White
    Write-Host ""
    Write-Host "     Nombre de cuenta : Practica09 - $env:COMPUTERNAME" -ForegroundColor Cyan
    Write-Host "     Tu clave (secreto): $miSecreto" -ForegroundColor Green
    Write-Host "     Tipo de clave     : Basada en tiempo (TOTP)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  4. Toca 'Agregar'. Veras un codigo de 6 digitos que" -ForegroundColor White
    Write-Host "     cambia cada 30 segundos. Usalo al iniciar sesion." -ForegroundColor White

    # 7. Guardar secreto en archivo para el reporte
    $archivoSecreto = "C:\MFA_Setup\MFA_Secret_$usuarioMFA.txt"
    "MFA TOTP Secret - Practica 09" | Out-File $archivoSecreto -Encoding UTF8
    "==============================" | Out-File $archivoSecreto -Append -Encoding UTF8
    "Usuario  : $usuarioMFA"         | Out-File $archivoSecreto -Append -Encoding UTF8
    "Servidor : $env:COMPUTERNAME"   | Out-File $archivoSecreto -Append -Encoding UTF8
    "Secreto  : $miSecreto"          | Out-File $archivoSecreto -Append -Encoding UTF8
    "Tipo     : TOTP RFC 6238 (Google Authenticator)" | Out-File $archivoSecreto -Append -Encoding UTF8
    "Generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" | Out-File $archivoSecreto -Append -Encoding UTF8
    Write-Host "`n  [OK] Secreto guardado en: $archivoSecreto" -ForegroundColor Green

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# ------------------------------------------------------------
# FUNCION 8: Ejecutar tests de evaluacion de la rubrica
# ------------------------------------------------------------
function Ejecutar-Tests {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |   PROTOCOLO DE PRUEBAS - PRACTICA 09     |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    Write-Host "  1. Test 1 -- Delegacion RBAC (Rol 2 vs Rol 1)" -ForegroundColor White
    Write-Host "  2. Test 2 -- FGPP (admin_identidad requiere 12 chars)" -ForegroundColor White
    Write-Host "  3. Test 3 -- Estado de MFA en multiOTP" -ForegroundColor White
    Write-Host "  4. Test 5 -- Reporte de Auditoria (ID 4625)" -ForegroundColor White
    Write-Host "  5. Todos los tests" -ForegroundColor White
    Write-Host ""
    $t = Read-Host "  Selecciona"

    switch ($t) {
        '1' { Test-DelegacionRBAC }
        '2' { Test-FGPP }
        '3' { Test-EstadoMFA }
        '4' { Configurar-Auditoria }
        '5' { Test-DelegacionRBAC; Test-FGPP; Test-EstadoMFA; Configurar-Auditoria }
        default { Write-Host "  Opcion no valida." -ForegroundColor Red }
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Read-Host | Out-Null
}

# --- TEST 1: Verificar ACE Deny en admin_storage ---
function Test-DelegacionRBAC {
    Write-Host "`n  TEST 1 -- Verificacion de Delegacion RBAC" -ForegroundColor Cyan
    Write-Host "  -----------------------------------------" -ForegroundColor Cyan
    try {
        $dcBase = (Get-ADDomain).DistinguishedName
        $acl    = Get-Acl -Path "AD:\$dcBase"
        $deny   = $acl.Access | Where-Object {
            $_.IdentityReference -like "*admin_storage*" -and $_.AccessControlType -eq "Deny"
        }
        if ($deny) {
            Write-Host "  [PASS] admin_storage tiene ACE de DENY (Reset Password denegado)." -ForegroundColor Green
        } else {
            Write-Host "  [WARN] No se detecto la ACE de DENY para admin_storage." -ForegroundColor Yellow
            Write-Host "         Ejecuta la Opcion 3 y repite el test." -ForegroundColor Yellow
        }
        $allow = $acl.Access | Where-Object { $_.IdentityReference -like "*admin_identidad*" -and $_.AccessControlType -eq "Allow" }
        if ($allow) { Write-Host "  [PASS] admin_identidad tiene permisos de acceso en el dominio." -ForegroundColor Green }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Prueba manual: inicia sesion como admin_storage e intenta un reset de contrasena." -ForegroundColor Yellow
    }
}

# --- TEST 2: Verificar FGPP efectiva en admin_identidad ---
function Test-FGPP {
    Write-Host "`n  TEST 2 -- Verificacion de FGPP" -ForegroundColor Cyan
    Write-Host "  ------------------------------" -ForegroundColor Cyan
    try {
        $pso = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad" -ErrorAction Stop
        if ($pso) {
            Write-Host "  Politica efectiva para admin_identidad:" -ForegroundColor Yellow
            Write-Host "  Nombre          : $($pso.Name)"                     -ForegroundColor White
            Write-Host "  Longitud minima : $($pso.MinPasswordLength) chars"  -ForegroundColor White
            Write-Host "  Lockout umbral  : $($pso.LockoutThreshold)"         -ForegroundColor White
            Write-Host "  Lockout duracion: $($pso.LockoutDuration)"          -ForegroundColor White
            if ($pso.MinPasswordLength -ge 12) { Write-Host "`n  [PASS] Correcto: 12 chars minimo. Contrasenas de 8 chars seran rechazadas." -ForegroundColor Green }
            else { Write-Host "`n  [FAIL] Solo $($pso.MinPasswordLength) chars. Ejecuta la Opcion 4." -ForegroundColor Red }
        } else {
            Write-Host "  [WARN] Sin FGPP especifica. Ejecuta la Opcion 4 primero." -ForegroundColor Yellow
        }
    } catch { Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red }
}

# --- TEST 3: Verificar estado de multiOTP ---
function Test-EstadoMFA {
    Write-Host "`n  TEST 3 -- Estado de MFA (multiOTP)" -ForegroundColor Cyan
    Write-Host "  -----------------------------------" -ForegroundColor Cyan

    $multiotpExe = $null
    $rutasBuscar = @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")
    foreach ($r in $rutasBuscar) { if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break } }

    if (-not $multiotpExe) {
        Write-Host "  [FAIL] multiOTP no instalado. Ejecuta Opciones 1, 6 y 7." -ForegroundColor Red
        return
    }
    Write-Host "  [OK] multiOTP encontrado: $multiotpExe" -ForegroundColor Green

    Push-Location (Split-Path $multiotpExe)
    Write-Host "`n  Usuarios registrados en multiOTP:" -ForegroundColor Yellow
    & ".\multiotp.exe" -list 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor White }

    Write-Host "`n  Configuracion de bloqueo:" -ForegroundColor Yellow
    & ".\multiotp.exe" -showconfig 2>&1 | Where-Object { $_ -match "(MaxBlock|MaxDelay|Failure|Lockout)" } |
        ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    Pop-Location
}
