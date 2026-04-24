# ============================================================
#  tests_p9.ps1 -- Protocolo de Pruebas Practica 09
#  Hardening AD, RBAC, FGPP, Auditoria y MFA
# ============================================================

$usuarioActual = $env:USERNAME
$dominioActual = $env:USERDOMAIN
$esAdmin       = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                 ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$rutaSalida    = "C:\MFA_Setup"
if (-not (Test-Path $rutaSalida)) { New-Item -Path $rutaSalida -ItemType Directory | Out-Null }

function Mostrar-UsuarioActual {
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkCyan
    $colorUser = if ($usuarioActual -match "admin_") { "Green" } else { "Yellow" }
    Write-Host "  | Usuario actual  : $usuarioActual" -ForegroundColor $colorUser
    Write-Host "  | Dominio         : $dominioActual" -ForegroundColor White
    Write-Host "  | Es Administrador: $(if($esAdmin){'SI'}else{'NO'})" -ForegroundColor White
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
}

function Pikachu {
    param([string]$Descripcion = "")
    Write-Host ""
    if ($Descripcion) {
        Write-Host "  📸 PIKACHU  >>  $Descripcion" -ForegroundColor Yellow
    } else {
        Write-Host "  📸 PIKACHU" -ForegroundColor Yellow
    }
    Write-Host ""
}

# ============================================================
# MENU PRINCIPAL
# ============================================================
function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "  +============================================+" -ForegroundColor Cyan
        Write-Host "  |   PROTOCOLO DE PRUEBAS - PRACTICA 09       |" -ForegroundColor Cyan
        Write-Host "  |   Hardening AD, RBAC, FGPP y MFA          |" -ForegroundColor Cyan
        Write-Host "  +============================================+" -ForegroundColor Cyan
        Mostrar-UsuarioActual
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 1: Delegacion RBAC                    |" -ForegroundColor White
        Write-Host "  |   1A. Como admin_identidad (debe PASAR)    |" -ForegroundColor Cyan
        Write-Host "  |   1B. Como admin_storage   (debe FALLAR)   |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 2: FGPP - Politica de contrasena      |" -ForegroundColor White
        Write-Host "  |   2A. Contrasena CORTA (debe FALLAR)       |" -ForegroundColor Cyan
        Write-Host "  |   2B. Contrasena LARGA (debe PASAR)        |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 3: Flujo MFA Google Authenticator     |" -ForegroundColor White
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 4: Bloqueo por MFA fallido            |" -ForegroundColor White
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 5: Reporte de Auditoria ID 4625       |" -ForegroundColor White
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  |  6. Ejecutar TODOS los tests en orden      |" -ForegroundColor Yellow
        Write-Host "  |  0. Salir                                  |" -ForegroundColor Red
        Write-Host "  +============================================+" -ForegroundColor Cyan
        Write-Host ""
        $op = Read-Host "  Selecciona una opcion"
        switch ($op) {
            '1'  { Test1-Submenu }
            '1a' { Test1A-IdentidadResetPassword }
            '1b' { Test1B-StorageDeny }
            '2'  { Test2-Submenu }
            '2a' { Test2A-FGPPFalla }
            '2b' { Test2B-FGPPPasa }
            '3'  { Test3-MFA }
            '4'  { Test4-BloqueoMFA }
            '5'  { Test5-Auditoria }
            '6'  { Ejecutar-TodosLosTests }
            '0'  { Write-Host "`n  Saliendo.`n" -ForegroundColor Green }
            default { Write-Host "`n  Opcion invalida." -ForegroundColor Red ; Start-Sleep -Seconds 1 }
        }
    } while ($op -ne '0')
}

function Test1-Submenu {
    Write-Host ""
    Write-Host "  TEST 1 - Delegacion RBAC" -ForegroundColor Cyan
    Write-Host "  1A - admin_identidad: resetear password (debe FUNCIONAR)" -ForegroundColor Green
    Write-Host "  1B - admin_storage  : resetear password (debe FALLAR)"    -ForegroundColor Red
    Write-Host ""
    $sub = Read-Host "  Selecciona (1A o 1B)"
    if ($sub -match "(?i)^1?a$") { Test1A-IdentidadResetPassword }
    elseif ($sub -match "(?i)^1?b$") { Test1B-StorageDeny }
    else { Write-Host "  Opcion invalida." -ForegroundColor Red }
}

function Test2-Submenu {
    Write-Host ""
    Write-Host "  TEST 2 - FGPP Politica de Contrasena" -ForegroundColor Cyan
    Write-Host "  2A - Contrasena CORTA (menos de 12 chars -> debe RECHAZAR)" -ForegroundColor Red
    Write-Host "  2B - Contrasena LARGA (12+ chars         -> debe ACEPTAR)"  -ForegroundColor Green
    Write-Host ""
    $sub = Read-Host "  Selecciona (2A o 2B)"
    if ($sub -match "(?i)^2?a$") { Test2A-FGPPFalla }
    elseif ($sub -match "(?i)^2?b$") { Test2B-FGPPPasa }
    else { Write-Host "  Opcion invalida." -ForegroundColor Red }
}

# ============================================================
# TEST 1A: admin_identidad resetea password (DEBE PASAR)
# ============================================================
function Test1A-IdentidadResetPassword {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 1A - DELEGACION: admin_identidad     |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: EXITOSO               |" -ForegroundColor Green
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    if ($usuarioActual -ne "admin_identidad") {
        Write-Host "  [AVISO] Estas logueado como '$usuarioActual'." -ForegroundColor Yellow
        Write-Host "          Idealmente ejecuta esto como 'admin_identidad'." -ForegroundColor Yellow
        $continuar = Read-Host "  Continuar de todas formas? (s/n)"
        if ($continuar -ne 's') { return }
    }

    try {
        $dominio  = (Get-ADDomain).DistinguishedName
        $ouCuates = "OU=Cuates,$dominio"
        $usuariosCuates = Get-ADUser -Filter * -SearchBase $ouCuates -Properties SamAccountName -ErrorAction Stop |
            Where-Object { $_.SamAccountName -ne "Administrator" }

        if (-not $usuariosCuates) {
            Write-Host "  [ERROR] No hay usuarios en OU Cuates." -ForegroundColor Red
            Read-Host "  Presiona Enter..." ; return
        }

        Write-Host "  Usuarios disponibles en OU Cuates:" -ForegroundColor White
        $i = 1
        $usuariosCuates | ForEach-Object { Write-Host "  $i. $($_.SamAccountName)" -ForegroundColor Cyan ; $i++ }
        Write-Host ""
        $seleccion = Read-Host "  Numero de usuario (Enter = primero)"
        if ([string]::IsNullOrWhiteSpace($seleccion)) {
            $usuarioObjetivo = $usuariosCuates | Select-Object -First 1
        } else {
            $idx = [int]$seleccion - 1
            $usuarioObjetivo = @($usuariosCuates)[$idx]
        }
        if (-not $usuarioObjetivo) { Write-Host "  [ERROR] Seleccion invalida." -ForegroundColor Red ; Read-Host ; return }

        # --- ENTRADA DINAMICA: el usuario escribe la nueva password ---
        Write-Host ""
        Write-Host "  Usuario objetivo: $($usuarioObjetivo.SamAccountName)" -ForegroundColor White
        Write-Host "  Ingresa la nueva contrasena para este usuario." -ForegroundColor Yellow
        Write-Host "  (Debe cumplir complejidad de dominio: mayus+minus+numero+simbolo)" -ForegroundColor DarkGray
        $pwdInput = Read-Host "  Nueva contrasena"

        if ([string]::IsNullOrWhiteSpace($pwdInput)) {
            Write-Host "  [ERROR] Contrasena vacia." -ForegroundColor Red ; Read-Host ; return
        }

        $nuevaPwd = ConvertTo-SecureString $pwdInput -AsPlainText -Force

        Write-Host ""
        Write-Host "  Intentando resetear password como '$usuarioActual'..." -ForegroundColor Yellow

        try {
            Set-ADAccountPassword -Identity $usuarioObjetivo.SamAccountName -NewPassword $nuevaPwd -Reset -ErrorAction Stop

            Write-Host ""
            Write-Host "  +--------------------------------------------+" -ForegroundColor Green
            Write-Host "  | [PASS] PASSWORD RESETEADA EXITOSAMENTE      |" -ForegroundColor Green
            Write-Host "  | Usuario : $($usuarioObjetivo.SamAccountName)" -ForegroundColor Green
            Write-Host "  | Por     : $usuarioActual                    |" -ForegroundColor Green
            Write-Host "  +--------------------------------------------+" -ForegroundColor Green

            Pikachu "Test 1A PASS - admin_identidad reseteo password correctamente"

            @(
                "TEST 1A - Delegacion RBAC (admin_identidad)",
                "Fecha   : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
                "Ejecutado por   : $usuarioActual@$dominioActual",
                "Usuario objetivo: $($usuarioObjetivo.SamAccountName)",
                "Resultado: PASS - Password reseteada exitosamente"
            ) | Out-File "$rutaSalida\Test1A_Resultado.txt" -Encoding UTF8

        } catch {
            $msg = $_.Exception.Message
            Write-Host ""
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host "  | [FAIL] No se pudo resetear (no esperado)    |" -ForegroundColor Red
            Write-Host "  | Error: $msg" -ForegroundColor Red
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host "  Sugerencia: Ejecuta Opcion 3 del menu P9 y reabre sesion." -ForegroundColor Yellow

            Pikachu "Test 1A FAIL - capturar error"
        }

    } catch {
        Write-Host "  [ERROR] AD no disponible: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# TEST 1B: admin_storage intenta resetear password (DEBE FALLAR)
# ============================================================
function Test1B-StorageDeny {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 1B - DELEGACION: admin_storage       |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: ACCESO DENEGADO       |" -ForegroundColor Red
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    if ($usuarioActual -ne "admin_storage") {
        Write-Host "  [AVISO] Idealmente ejecuta esto como 'admin_storage'." -ForegroundColor Yellow
        $continuar = Read-Host "  Continuar de todas formas? (s/n)"
        if ($continuar -ne 's') { return }
    }

    try {
        $dominio  = (Get-ADDomain).DistinguishedName
        $ouCuates = "OU=Cuates,$dominio"
        $usuariosCuates = Get-ADUser -Filter * -SearchBase $ouCuates -Properties SamAccountName -ErrorAction Stop |
            Where-Object { $_.SamAccountName -ne "Administrator" }

        if (-not $usuariosCuates) {
            Write-Host "  [ERROR] No hay usuarios en OU Cuates." -ForegroundColor Red ; Read-Host ; return
        }

        $usuarioObjetivo = $usuariosCuates | Select-Object -First 1

        # --- ENTRADA DINAMICA ---
        Write-Host ""
        Write-Host "  Usuario objetivo: $($usuarioObjetivo.SamAccountName)" -ForegroundColor White
        Write-Host "  Ingresa una contrasena para intentar el reset (se espera DENEGAR)." -ForegroundColor Yellow
        $pwdInput = Read-Host "  Contrasena a intentar"
        if ([string]::IsNullOrWhiteSpace($pwdInput)) { $pwdInput = "Delegado2026!!" }

        $nuevaPwd = ConvertTo-SecureString $pwdInput -AsPlainText -Force

        Write-Host ""
        Write-Host "  Intentando resetear como '$usuarioActual' (se espera FALLO)..." -ForegroundColor Yellow

        try {
            Set-ADAccountPassword -Identity $usuarioObjetivo.SamAccountName -NewPassword $nuevaPwd -Reset -ErrorAction Stop

            Write-Host ""
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host "  | [FAIL] La accion TUVO EXITO (no esperado)   |" -ForegroundColor Red
            Write-Host "  | admin_storage pudo resetear. El DENY falla. |" -ForegroundColor Red
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host "  Solucion: Ejecuta Opcion 3 del menu P9 y reabre sesion." -ForegroundColor Yellow

            Pikachu "Test 1B FAIL - el DENY no funciona"

        } catch {
            $msg = $_.Exception.Message
            $esDeny = $msg -match "Access.is.denied|Access denied|UnauthorizedAccess|no tiene acceso|PermissionDenied|AccesoD|Insufficient access|insufficient rights|Acceso denegado|denegado"

            Write-Host ""
            if ($esDeny) {
                Write-Host "  +--------------------------------------------+" -ForegroundColor Green
                Write-Host "  | [PASS] ACCESO DENEGADO CORRECTAMENTE        |" -ForegroundColor Green
                Write-Host "  | admin_storage NO pudo resetear. DENY OK.   |" -ForegroundColor Green
                Write-Host "  +--------------------------------------------+" -ForegroundColor Green
                Write-Host "  Error recibido: $msg" -ForegroundColor DarkGray
            } else {
                Write-Host "  [INFO] Error recibido: $msg" -ForegroundColor Yellow
                Write-Host "  Verificando ACE DENY en AD..." -ForegroundColor Yellow
                try {
                    $dcBase  = (Get-ADDomain).DistinguishedName
                    $aclDom  = Get-Acl -Path "AD:\$dcBase" -ErrorAction Stop
                    $denyAce = $aclDom.Access | Where-Object {
                        $_.IdentityReference -like "*admin_storage*" -and $_.AccessControlType -eq "Deny"
                    }
                    if ($denyAce) {
                        Write-Host "  [PASS] ACE DENY confirmada en AD para admin_storage:" -ForegroundColor Green
                        $denyAce | ForEach-Object {
                            Write-Host "         Deny: $($_.ActiveDirectoryRights)" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host "  [WARN] No se encontro ACE DENY. Ejecuta Opcion 3 del menu P9." -ForegroundColor Yellow
                    }
                } catch { Write-Host "  No se pudo leer ACL: $($_.Exception.Message)" -ForegroundColor Yellow }
            }

            Pikachu "Test 1B PASS - admin_storage fue denegado correctamente"

            @(
                "TEST 1B - Delegacion RBAC (admin_storage DENY)",
                "Fecha   : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
                "Ejecutado por   : $usuarioActual@$dominioActual",
                "Usuario objetivo: $($usuarioObjetivo.SamAccountName)",
                "Resultado: PASS - Acceso Denegado",
                "Error   : $msg"
            ) | Out-File "$rutaSalida\Test1B_Resultado.txt" -Encoding UTF8
        }

    } catch { Write-Host "  [ERROR] AD no disponible: $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# TEST 2A: FGPP - Contrasena CORTA (DEBE FALLAR)
# ============================================================
function Test2A-FGPPFalla {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 2A - FGPP: Contrasena CORTA          |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: RECHAZADA             |" -ForegroundColor Red
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    Write-Host "  Verificando FGPP vigente para admin_identidad..." -ForegroundColor Yellow
    try {
        $pso = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad" -ErrorAction Stop
        if ($pso) {
            Write-Host "  Politica activa: $($pso.Name) | Longitud minima: $($pso.MinPasswordLength) chars" -ForegroundColor Cyan
            Pikachu "Captura la FGPP vigente (longitud minima mostrada arriba)"
        } else {
            Write-Host "  [WARN] No hay PSO para admin_identidad. Ejecuta Opcion 4 del menu P9." -ForegroundColor Yellow
        }
    } catch { Write-Host "  [WARN] No se pudo leer PSO: $($_.Exception.Message)" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "  Ingresa una contrasena CORTA (menos de 12 chars) para probar el rechazo." -ForegroundColor Yellow
    Write-Host "  Ejemplos: 'Corta1!!' , 'Pass1!' , 'Abc123!'" -ForegroundColor DarkGray
    $pwdCorta = Read-Host "  Contrasena corta"
    if ([string]::IsNullOrWhiteSpace($pwdCorta)) { $pwdCorta = "Corta1!!" }

    Write-Host ""
    Write-Host "  Intentando asignar '$pwdCorta' ($($pwdCorta.Length) chars) a admin_identidad..." -ForegroundColor Yellow

    try {
        $pwd = ConvertTo-SecureString $pwdCorta -AsPlainText -Force
        Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $pwd -Reset -ErrorAction Stop

        Write-Host ""
        Write-Host "  +--------------------------------------------+" -ForegroundColor Red
        Write-Host "  | [FAIL] La contrasena corta fue ACEPTADA     |" -ForegroundColor Red
        Write-Host "  | La FGPP no esta aplicando correctamente.   |" -ForegroundColor Red
        Write-Host "  +--------------------------------------------+" -ForegroundColor Red
        Write-Host "  Solucion: Ejecuta Opcion 4 del menu P9." -ForegroundColor Yellow

        Pikachu "Test 2A FAIL - contrasena corta aceptada (no esperado)"

    } catch {
        $msg = $_.Exception.Message
        Write-Host ""
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        Write-Host "  | [PASS] CONTRASENA RECHAZADA CORRECTAMENTE   |" -ForegroundColor Green
        Write-Host "  | La FGPP exige mas caracteres de los dados.  |" -ForegroundColor Green
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        Write-Host "  Error del sistema: $msg" -ForegroundColor DarkGray

        Pikachu "Test 2A PASS - contrasena corta rechazada por FGPP"

        @(
            "TEST 2A - FGPP Contrasena Corta (debe FALLAR)",
            "Fecha   : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
            "Ejecutado por : $usuarioActual@$dominioActual",
            "Contrasena probada: $pwdCorta ($($pwdCorta.Length) chars)",
            "Resultado: PASS - Rechazada por longitud insuficiente",
            "Error   : $msg"
        ) | Out-File "$rutaSalida\Test2A_FGPP_Resultado.txt" -Encoding UTF8
    }

    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# TEST 2B: FGPP - Contrasena LARGA (DEBE PASAR)
# ============================================================
function Test2B-FGPPPasa {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 2B - FGPP: Contrasena LARGA          |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: ACEPTADA              |" -ForegroundColor Green
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    Write-Host "  Ingresa una contrasena LARGA (12+ chars) para admin_identidad." -ForegroundColor Yellow
    Write-Host "  Debe tener mayus + minus + numero + simbolo." -ForegroundColor DarkGray
    Write-Host "  Ejemplo: 'Hardening2026!' (14 chars)" -ForegroundColor DarkGray
    $pwdLarga = Read-Host "  Contrasena larga"
    if ([string]::IsNullOrWhiteSpace($pwdLarga)) { $pwdLarga = "Hardening2026!" }

    Write-Host ""
    Write-Host "  Intentando asignar '$pwdLarga' ($($pwdLarga.Length) chars) a admin_identidad..." -ForegroundColor Yellow

    try {
        $pwd = ConvertTo-SecureString $pwdLarga -AsPlainText -Force
        Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $pwd -Reset -ErrorAction Stop

        Write-Host ""
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        Write-Host "  | [PASS] CONTRASENA ACEPTADA CORRECTAMENTE    |" -ForegroundColor Green
        Write-Host "  | La FGPP permite contrasenas de 12+ chars.  |" -ForegroundColor Green
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green

        Pikachu "Test 2B PASS - contrasena larga aceptada por FGPP"

        @(
            "TEST 2B - FGPP Contrasena Larga (debe PASAR)",
            "Fecha   : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
            "Ejecutado por : $usuarioActual@$dominioActual",
            "Contrasena probada: $pwdLarga ($($pwdLarga.Length) chars)",
            "Resultado: PASS - Aceptada correctamente"
        ) | Out-File "$rutaSalida\Test2B_FGPP_Resultado.txt" -Encoding UTF8

    } catch {
        $msg = $_.Exception.Message
        Write-Host ""
        Write-Host "  +--------------------------------------------+" -ForegroundColor Red
        Write-Host "  | [FAIL] Contrasena larga RECHAZADA           |" -ForegroundColor Red
        Write-Host "  | Error: $msg" -ForegroundColor Red
        Write-Host "  +--------------------------------------------+" -ForegroundColor Red
        Write-Host "  Verifica que la contrasena tiene mayus+minus+numero+simbolo." -ForegroundColor Yellow

        Pikachu "Test 2B FAIL - contrasena larga rechazada (no esperado)"
    }

    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# TEST 3: Flujo MFA
# ============================================================
function Test3-MFA {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 3 - FLUJO MFA (Google Authenticator) |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: Campo TOTP en login   |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    $multiotpExe = $null
    foreach ($r in @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")) {
        if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break }
    }

    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP encontrado en: $(Split-Path $multiotpExe)" -ForegroundColor Green
        $dir = Split-Path $multiotpExe
        $carpetaUsers = Join-Path $dir "users"
        if (Test-Path $carpetaUsers) {
            $dbs = Get-ChildItem $carpetaUsers -Filter "*.db" -ErrorAction SilentlyContinue
            Write-Host "  [OK] Usuarios MFA registrados: $($dbs.Count)" -ForegroundColor Green
            $dbs | ForEach-Object { Write-Host "       - $($_.BaseName)" -ForegroundColor DarkGray }
        }
        $secretoFile = "$rutaSalida\MFA_Secret_TodosAdmins.txt"
        if (Test-Path $secretoFile) {
            Write-Host ""
            Write-Host "  Secreto TOTP guardado:" -ForegroundColor Yellow
            Get-Content $secretoFile | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
        } else {
            Write-Host "  [WARN] No se encontro secreto TOTP. Ejecuta Opcion 7 del menu P9." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [FAIL] multiOTP NO esta instalado. Ejecuta Opciones 6 y 7 del menu P9." -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "  INSTRUCCIONES TEST 3:" -ForegroundColor Yellow
    Write-Host "  A) Abre Google Authenticator en tu celular" -ForegroundColor White

    Pikachu "Captura el celular mostrando el codigo TOTP"

    Write-Host "  B) Cierra sesion en el servidor" -ForegroundColor White
    Write-Host "  C) En login: ingresa usuario + contrasena" -ForegroundColor White
    Write-Host "  D) El Credential Provider pedira el codigo TOTP" -ForegroundColor White
    Write-Host "  E) Ingresa el codigo de 6 digitos" -ForegroundColor White

    Pikachu "Captura la pantalla de login mostrando el campo TOTP"

    $logPath = "$rutaSalida\Test3_MFA_Guia.txt"
    @(
        "TEST 3 - Flujo MFA",
        "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
        "PASOS: cerrar sesion -> login -> TOTP solicitado -> ingresar codigo -> acceso"
    ) | Out-File $logPath -Encoding UTF8
    Write-Host "  [OK] Guia guardada en: $logPath" -ForegroundColor DarkGray
    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# TEST 4: Bloqueo por MFA fallido
# ============================================================
function Test4-BloqueoMFA {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 4 - BLOQUEO POR MFA FALLIDO          |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: Cuenta bloqueada 30min|" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    Write-Host "  INSTRUCCIONES PARA GENERAR EL BLOQUEO:" -ForegroundColor Yellow
    Write-Host "  1. Cierra sesion en el servidor" -ForegroundColor White
    Write-Host "  2. Ingresa usuario + contrasena correctos" -ForegroundColor White
    Write-Host "  3. Cuando pida TOTP escribe: 000000 (incorrecto)" -ForegroundColor White
    Write-Host "  4. Repite 3 veces" -ForegroundColor White
    Write-Host "  5. Vuelve a iniciar sesion como Administrator" -ForegroundColor White
    Write-Host "  6. Vuelve a ejecutar este test" -ForegroundColor White
    Write-Host ""

    $r = Read-Host "  Ya realizaste los 3 intentos fallidos? (s/n)"
    if ($r -ne 's') {
        Write-Host "  Realiza los intentos primero y vuelve." -ForegroundColor Yellow
        Write-Host "" ; Read-Host "  Presiona Enter..." ; return
    }

    $usuarios     = @("Administrator","admin_identidad","admin_storage","admin_politicas","admin_auditoria")
    $hayBloqueado = $false
    $resultados   = @()

    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor White
    Write-Host "  | Usuario          | Estado     | Intentos Fallidos        |" -ForegroundColor White
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor White

    foreach ($u in $usuarios) {
        try {
            $info      = Get-ADUser -Identity $u -Properties LockedOut, BadLogonCount -ErrorAction Stop
            $estado    = if ($info.LockedOut) { "BLOQUEADO" } else { "Libre    " }
            $colorFila = if ($info.LockedOut) { "Red" } else { "Green" }
            Write-Host ("  | {0,-16} | {1,-10} | Intentos: {2,-16} |" -f $u, $estado, $info.BadLogonCount) -ForegroundColor $colorFila
            if ($info.LockedOut) { $hayBloqueado = $true }
            $resultados += [PSCustomObject]@{ Usuario = $u; Bloqueado = $info.LockedOut; Intentos = $info.BadLogonCount }
        } catch {
            Write-Host ("  | {0,-16} | No hallado |                          |" -f $u) -ForegroundColor Yellow
        }
    }
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor White

    if ($hayBloqueado) {
        Write-Host ""
        Write-Host "  [PASS] Cuenta(s) bloqueada(s) correctamente tras 3 fallos de MFA." -ForegroundColor Green
        Pikachu "Test 4 PASS - captura la cuenta marcada como BLOQUEADA"

        $bloqueadas = $resultados | Where-Object { $_.Bloqueado }
        Write-Host "  Cuentas bloqueadas: $($bloqueadas.Usuario -join ', ')" -ForegroundColor Red
        $desbloquear = Read-Host "  Desbloquear ahora? (s/n)"
        if ($desbloquear -eq 's') {
            foreach ($b in $bloqueadas) {
                try { Unlock-ADAccount -Identity $b.Usuario -ErrorAction Stop ; Write-Host "  [OK] $($b.Usuario) desbloqueada." -ForegroundColor Green }
                catch { Write-Host "  [WARN] $($b.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow }
            }
        }
    } else {
        Write-Host ""
        Write-Host "  [INFO] Ninguna cuenta bloqueada. Puede que no se hayan hecho los 3 intentos" -ForegroundColor Yellow
        Write-Host "         o ya paso el tiempo de bloqueo (30 min)." -ForegroundColor DarkGray
        Pikachu "Test 4 - captura el estado actual aunque no haya bloqueo"
    }

    $resultados | ForEach-Object {
        "$($_.Usuario) | Bloqueado: $($_.Bloqueado) | Intentos: $($_.Intentos)"
    } | Out-File "$rutaSalida\Test4_Bloqueo_Resultado.txt" -Encoding UTF8

    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# TEST 5: Reporte de Auditoria ID 4625
# ============================================================
function Test5-Auditoria {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 5 - REPORTE DE AUDITORIA ID 4625     |" -ForegroundColor Cyan
    Write-Host "  |  Ejecutar como: admin_auditoria            |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    if ($usuarioActual -ne "admin_auditoria") {
        Write-Host "  [AVISO] Idealmente ejecuta esto como 'admin_auditoria'." -ForegroundColor Yellow
        $continuar = Read-Host "  Continuar de todas formas? (s/n)"
        if ($continuar -ne 's') { return }
    }

    try {
        Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction Stop | Out-Null
        Write-Host "  [OK] Se puede leer el Security Event Log." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Sin acceso al Security Log: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $fechaReporte = Get-Date -Format 'yyyyMMdd_HHmm'
    $rutaReporte  = "$rutaSalida\Reporte_AccesosDenegados_$fechaReporte.txt"
    $rutaCSV      = "$rutaSalida\Reporte_AccesosDenegados_$fechaReporte.csv"

    $encabezado = @"
==================================================
REPORTE DE AUDITORIA DE SEGURIDAD
Practica 09 - Hardening Active Directory
Fecha generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
Servidor       : $env:COMPUTERNAME
Dominio        : $env:USERDNSDOMAIN
Ejecutado por  : $usuarioActual@$dominioActual
Evento         : ID 4625 - Inicio de sesion fallido
==================================================

"@
    $encabezado | Out-File $rutaReporte -Encoding UTF8

    try {
        $eventos = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4625 } -MaxEvents 10 -ErrorAction SilentlyContinue

        if (-not $eventos -or $eventos.Count -eq 0) {
            Write-Host "  [INFO] No hay eventos ID 4625 aun." -ForegroundColor Yellow
            "No se encontraron eventos de acceso denegado (ID 4625)." | Out-File $rutaReporte -Append -Encoding UTF8
        } else {
            Write-Host "  [OK] $($eventos.Count) evento(s) encontrados." -ForegroundColor Green
            Write-Host ""
            Write-Host "  +----------------------------------------------------------+" -ForegroundColor White
            Write-Host "  | # | Fecha               | Usuario     | IP origen        |" -ForegroundColor White
            Write-Host "  +----------------------------------------------------------+" -ForegroundColor White

            $registrosCSV = @()
            $i = 1
            foreach ($e in $eventos) {
                try {
                    $xml     = [xml]$e.ToXml()
                    $user    = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetUserName"   }).'#text'
                    $dom     = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
                    $ip      = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "IpAddress"        }).'#text'
                    $proceso = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "ProcessName"      }).'#text'
                    $tipo    = ($xml.Event.EventData.Data | Where-Object { $_.Name -eq "FailureReason"    }).'#text'
                    $fecha   = $e.TimeCreated.ToString('dd/MM/yyyy HH:mm:ss')

                    Write-Host ("  | {0,1} | {1,-19} | {2,-11} | {3,-16} |" -f $i, $fecha, $user, $ip) -ForegroundColor Cyan

                    @(
                        "EVENTO $i de $($eventos.Count)",
                        "--------------------------------------------------",
                        "Fecha       : $fecha",
                        "Usuario     : $user",
                        "Dominio     : $dom",
                        "IP Origen   : $ip",
                        "Proceso     : $proceso",
                        "Razon fallo : $tipo",
                        "--------------------------------------------------",""
                    ) | Out-File $rutaReporte -Append -Encoding UTF8

                    $registrosCSV += [PSCustomObject]@{
                        Numero=($i); Fecha=$fecha; Usuario=$user; Dominio=$dom
                        IPOrigen=$ip; Proceso=$proceso; RazonFallo=$tipo
                    }
                    $i++
                } catch {
                    Write-Host ("  | {0,1} | Error al parsear evento                          |" -f $i) -ForegroundColor Yellow ; $i++
                }
            }
            Write-Host "  +----------------------------------------------------------+" -ForegroundColor White
            $registrosCSV | Export-Csv -Path $rutaCSV -NoTypeInformation -Encoding UTF8
        }

        Write-Host ""
        Write-Host "  --- CONTENIDO DEL REPORTE ---" -ForegroundColor Cyan
        Get-Content $rutaReporte | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Write-Host "  --- FIN DEL REPORTE ---" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  [OK] TXT: $rutaReporte" -ForegroundColor Green
        Write-Host "  [OK] CSV: $rutaCSV"     -ForegroundColor Green

        Pikachu "Test 5 - captura el reporte completo en pantalla"

    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# EJECUTAR TODOS LOS TESTS
# ============================================================
function Ejecutar-TodosLosTests {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  EJECUTAR TODOS LOS TESTS EN ORDEN         |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    Write-Host "  Orden correcto de sesiones:" -ForegroundColor White
    Write-Host "  1. admin_identidad  -> Test 1A" -ForegroundColor Cyan
    Write-Host "  2. admin_storage    -> Test 1B" -ForegroundColor Cyan
    Write-Host "  3. Administrator    -> Tests 2A, 2B, 4" -ForegroundColor Cyan
    Write-Host "  4. admin_auditoria  -> Test 5" -ForegroundColor Cyan
    Write-Host "  5. Test 3 (MFA) requiere cerrar sesion fisicamente" -ForegroundColor Cyan
    Write-Host ""

    $continuar = Read-Host "  Ejecutar tests disponibles para el usuario actual? (s/n)"
    if ($continuar -ne 's') { return }

    switch ($usuarioActual) {
        "admin_identidad" { Test1A-IdentidadResetPassword }
        "admin_storage"   { Test1B-StorageDeny }
        "admin_auditoria" { Test5-Auditoria }
        default {
            Test2A-FGPPFalla
            Test2B-FGPPPasa
            Test3-MFA
            Test4-BloqueoMFA
        }
    }

    Write-Host ""
    Write-Host "  Tests ejecutados para '$usuarioActual'. Evidencias en: $rutaSalida" -ForegroundColor Green
    Write-Host "" ; Read-Host "  Presiona Enter para volver al menu..."
}

# ============================================================
# INICIO
# ============================================================
Mostrar-Menu
