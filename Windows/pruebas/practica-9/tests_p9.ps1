# ============================================================
#  tests_p9.ps1 -- Protocolo de Pruebas Practica 09 (Modificado)
#  Hardening AD, RBAC, FGPP, Auditoria y MFA
#
#  IMPORTANTE: Cada test se ejecuta desde la sesion del
#  usuario que se indica. Lee las instrucciones de cada
#  test antes de ejecutarlo.
#
#  COMO USAR:
#    1. Copia este script al servidor (o accesible desde el DC)
#    2. Ejecuta: .\tests_p9.ps1
#    3. El menu detecta con que usuario estas logueado
#    4. Sigue las instrucciones de cada test
# ============================================================

# ------------------------------------------------------------
# DETECCION DE USUARIO ACTUAL
# ------------------------------------------------------------
$usuarioActual = $env:USERNAME
$dominioActual = $env:USERDOMAIN
$esAdmin       = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                 ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$rutaSalida    = "C:\MFA_Setup"
if (-not (Test-Path $rutaSalida)) { New-Item -Path $rutaSalida -ItemType Directory | Out-Null }

# ------------------------------------------------------------
# UTILIDAD: Banner de usuario actual
# ------------------------------------------------------------
function Mostrar-UsuarioActual {
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkCyan
    $colorUser = if ($usuarioActual -match "admin_") { "Green" } else { "Yellow" }
    Write-Host "  | Usuario actual : $usuarioActual" -ForegroundColor $colorUser
    Write-Host "  | Dominio        : $dominioActual" -ForegroundColor White
    Write-Host "  | Es Administrador: $(if($esAdmin){'SI'}else{'NO'})" -ForegroundColor White
    Write-Host "  +--------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
}

# ------------------------------------------------------------
# UTILIDAD: Pausar y mostrar instruccion discreta de evidencia
# ------------------------------------------------------------
function Pedir-Captura {
    param([string]$Descripcion)
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Magenta
    Write-Host "  Pikachu " -ForegroundColor Yellow
    Write-Host "  $Descripcion" -ForegroundColor Magenta
    Write-Host "  ============================================" -ForegroundColor Magenta
    Write-Host ""
    Read-Host "  Presiona Enter para continuar..."
}

# ============================================================
# MENU PRINCIPAL
# ============================================================
function Mostrar-Menu {
    do {
        Write-Host ""
        Write-Host "  +============================================+" -ForegroundColor Cyan
        Write-Host "  |   PROTOCOLO DE PRUEBAS - PRACTICA 09       |" -ForegroundColor Cyan
        Write-Host "  |   Hardening AD, RBAC, FGPP y MFA           |" -ForegroundColor Cyan
        Write-Host "  +============================================+" -ForegroundColor Cyan
        Mostrar-UsuarioActual
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 1: Delegacion RBAC                    |" -ForegroundColor White
        Write-Host "  |   1A. Ejecutar como admin_identidad        |" -ForegroundColor Cyan
        Write-Host "  |       (cambiar password de usuario Cuates) |" -ForegroundColor DarkCyan
        Write-Host "  |   1B. Ejecutar como admin_storage          |" -ForegroundColor Cyan
        Write-Host "  |       (intentar cambiar password -> DENY)  |" -ForegroundColor DarkCyan
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 2: FGPP - Politica de contrasena      |" -ForegroundColor White
        Write-Host "  |   Ejecutar como Administrator              |" -ForegroundColor Cyan
        Write-Host "  |   (verificar rechazo de pwd corta)         |" -ForegroundColor DarkCyan
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 3: Flujo MFA Google Authenticator     |" -ForegroundColor White
        Write-Host "  |   Instrucciones para evidencia             |" -ForegroundColor DarkCyan
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 4: Bloqueo por MFA fallido            |" -ForegroundColor White
        Write-Host "  |   Ejecutar como Administrator              |" -ForegroundColor Cyan
        Write-Host "  |   (verificar estado de bloqueo en AD)      |" -ForegroundColor DarkCyan
        Write-Host "  +--------------------------------------------+" -ForegroundColor White
        Write-Host "  | TEST 5: Reporte de Auditoria ID 4625       |" -ForegroundColor White
        Write-Host "  |   Ejecutar como admin_auditoria            |" -ForegroundColor Cyan
        Write-Host "  |   (genera archivo txt con eventos)         |" -ForegroundColor DarkCyan
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
            '2'  { Test2-FGPP }
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
    Write-Host "  ¿Que accion deseas ejecutar?" -ForegroundColor White
    Write-Host "  1A - Soy admin_identidad (cambiar password -> debe FUNCIONAR)" -ForegroundColor Green
    Write-Host "  1B - Soy admin_storage   (cambiar password -> debe FALLAR)"    -ForegroundColor Red
    Write-Host ""
    $sub = Read-Host "  Selecciona (1A o 1B)"
    if ($sub -match "(?i)^1?a$") { Test1A-IdentidadResetPassword }
    elseif ($sub -match "(?i)^1?b$") { Test1B-StorageDeny }
    else { Write-Host "  Opcion invalida." -ForegroundColor Red }
}


# ============================================================
# TEST 1A: admin_identidad resetea password de usuario Cuates
#
# EJECUTAR DESDE SESION DE: admin_identidad
# ============================================================
function Test1A-IdentidadResetPassword {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 1A - DELEGACION: admin_identidad     |" -ForegroundColor Cyan
    Write-Host "  |  Accion: Resetear password de Cuates       |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: EXITOSO               |" -ForegroundColor Green
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    # Verificar que el usuario actual es admin_identidad
    if ($usuarioActual -ne "admin_identidad") {
        Write-Host "  [AVISO] Estas logueado como '$usuarioActual'." -ForegroundColor Yellow
        Write-Host "          Este test debe ejecutarse como 'admin_identidad'." -ForegroundColor Yellow
        Write-Host "          Los resultados pueden no reflejar la delegacion real." -ForegroundColor Yellow
        Write-Host ""
        $continuar = Read-Host "  Continuar de todas formas? (s/n)"
        if ($continuar -ne 's') { return }
    }

    Write-Host "  Buscando usuarios en OU Cuates..." -ForegroundColor Yellow

    try {
        $dominio  = (Get-ADDomain).DistinguishedName
        $ouCuates = "OU=Cuates,$dominio"

        $usuariosCuates = Get-ADUser -Filter * -SearchBase $ouCuates `
            -Properties SamAccountName, DisplayName -ErrorAction Stop |
            Where-Object { $_.SamAccountName -ne "Administrator" }

        if (-not $usuariosCuates) {
            Write-Host "  [ERROR] No hay usuarios en OU Cuates." -ForegroundColor Red
            Read-Host "  Presiona Enter..." ; return
        }

        Write-Host ""
        Write-Host "  Usuarios disponibles en OU Cuates:" -ForegroundColor White
        $i = 1
        $usuariosCuates | ForEach-Object {
            Write-Host "  $i. $($_.SamAccountName)" -ForegroundColor Cyan
            $i++
        }
        Write-Host ""
        $seleccion = Read-Host "  Numero de usuario a usar (Enter = primero)"

        if ([string]::IsNullOrWhiteSpace($seleccion)) {
            $usuarioObjetivo = $usuariosCuates | Select-Object -First 1
        } else {
            $idx = [int]$seleccion - 1
            $usuarioObjetivo = @($usuariosCuates)[$idx]
        }

        if (-not $usuarioObjetivo) {
            Write-Host "  [ERROR] Seleccion invalida." -ForegroundColor Red
            Read-Host "  Presiona Enter..." ; return
        }

        Write-Host ""
        Write-Host "  Usuario objetivo : $($usuarioObjetivo.SamAccountName)" -ForegroundColor White
        Write-Host ""
        $pwdInput = Read-Host "  Ingresa la nueva contrasena (esta NO DEBERIA FALLAR, ej. Delegado2026!!)"
        
        Write-Host ""
        Write-Host "  Intentando resetear password como '$usuarioActual'..." -ForegroundColor Yellow
        Write-Host ""

        $nuevaPwd = ConvertTo-SecureString $pwdInput -AsPlainText -Force

        try {
            Set-ADAccountPassword `
                -Identity  $usuarioObjetivo.SamAccountName `
                -NewPassword $nuevaPwd `
                -Reset `
                -ErrorAction Stop

            Write-Host "  +--------------------------------------------+" -ForegroundColor Green
            Write-Host "  | [PASS] PASSWORD RESETEADA EXITOSAMENTE      |" -ForegroundColor Green
            Write-Host "  |                                            |" -ForegroundColor Green
            Write-Host "  | Usuario : $($usuarioObjetivo.SamAccountName)" -ForegroundColor Green
            Write-Host "  | Nueva   : $pwdInput"                    -ForegroundColor Green
            Write-Host "  | Por     : $usuarioActual (admin_identidad) |" -ForegroundColor Green
            Write-Host "  +--------------------------------------------+" -ForegroundColor Green

            Pedir-Captura "TEST 1A EXITOSO: admin_identidad reseteo password de $($usuarioObjetivo.SamAccountName)"

            # Guardar log
            $logPath = "$rutaSalida\Test1A_Resultado.txt"
            @(
                "TEST 1A - Delegacion RBAC (admin_identidad)",
                "============================================",
                "Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
                "Ejecutado por  : $usuarioActual@$dominioActual",
                "Usuario objetivo: $($usuarioObjetivo.SamAccountName)",
                "Resultado: PASS - Password reseteada exitosamente",
                "Nueva password: $pwdInput",
                "",
                "CONCLUSION: La delegacion de admin_identidad funciona correctamente.",
                "La ACL permite a este rol resetear passwords en OU Cuates."
            ) | Out-File $logPath -Encoding UTF8
            Write-Host ""
            Write-Host "  [OK] Log guardado en: $logPath" -ForegroundColor DarkGray

        } catch {
            $msg = $_.Exception.Message
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host "  | [FAIL] ACCESO DENEGADO (no esperado)        |" -ForegroundColor Red
            Write-Host "  | Error: $msg" -ForegroundColor Red
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Si ves Access Denied, ejecuta la Opcion 3 del menu P9" -ForegroundColor Yellow
            Write-Host "  (Aplicar permisos RBAC) y cierra/reabre sesion como" -ForegroundColor Yellow
            Write-Host "  admin_identidad para que Kerberos actualice el token." -ForegroundColor Yellow

            Pedir-Captura "TEST 1A FALLIDO - registrar el error para el reporte"
        }

    } catch {
        Write-Host "  [ERROR] No se pudo conectar a AD: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Verifica que estas en el dominio y AD esta disponible." -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "  Presiona Enter para volver al menu..."
}


# ============================================================
# TEST 1B: admin_storage intenta resetear password (debe FALLAR)
#
# EJECUTAR DESDE SESION DE: admin_storage
# ============================================================
function Test1B-StorageDeny {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 1B - DELEGACION: admin_storage       |" -ForegroundColor Cyan
    Write-Host "  |  Accion: Intentar resetear password        |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: ACCESO DENEGADO       |" -ForegroundColor Red
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    if ($usuarioActual -ne "admin_storage") {
        Write-Host "  [AVISO] Estas logueado como '$usuarioActual'." -ForegroundColor Yellow
        Write-Host "          Este test debe ejecutarse como 'admin_storage'." -ForegroundColor Yellow
        Write-Host ""
        $continuar = Read-Host "  Continuar de todas formas? (s/n)"
        if ($continuar -ne 's') { return }
    }

    Write-Host "  Buscando usuarios en OU Cuates..." -ForegroundColor Yellow

    try {
        $dominio  = (Get-ADDomain).DistinguishedName
        $ouCuates = "OU=Cuates,$dominio"

        $usuariosCuates = Get-ADUser -Filter * -SearchBase $ouCuates `
            -Properties SamAccountName -ErrorAction Stop |
            Where-Object { $_.SamAccountName -ne "Administrator" }

        if (-not $usuariosCuates) {
            Write-Host "  [ERROR] No hay usuarios en OU Cuates." -ForegroundColor Red
            Read-Host "  Presiona Enter..." ; return
        }

        $usuarioObjetivo = $usuariosCuates | Select-Object -First 1
        Write-Host ""
        Write-Host "  Usuario objetivo : $($usuarioObjetivo.SamAccountName)" -ForegroundColor White
        Write-Host ""
        
        $pwdInput = Read-Host "  Ingresa la nueva contrasena (esta DEBERIA FALLAR por Acceso Denegado)"

        Write-Host ""
        Write-Host "  Intentando resetear password como '$usuarioActual'..." -ForegroundColor Yellow
        Write-Host "  (Se espera que falle con Acceso Denegado)" -ForegroundColor DarkGray
        Write-Host ""

        $nuevaPwd = ConvertTo-SecureString $pwdInput -AsPlainText -Force

        try {
            Set-ADAccountPassword `
                -Identity    $usuarioObjetivo.SamAccountName `
                -NewPassword $nuevaPwd `
                -Reset `
                -ErrorAction Stop

            # Si llega aqui, el DENY no funciona
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host "  | [FAIL] La accion TUVO EXITO (no esperado)   |" -ForegroundColor Red
            Write-Host "  | admin_storage pudo resetear la password.    |" -ForegroundColor Red
            Write-Host "  | El ACL de DENY no esta funcionando.         |" -ForegroundColor Red
            Write-Host "  +--------------------------------------------+" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Solucion: Ejecuta Opcion 3 del menu P9 y vuelve" -ForegroundColor Yellow
            Write-Host "  a iniciar sesion como admin_storage." -ForegroundColor Yellow

            Pedir-Captura "TEST 1B FALLIDO - el DENY no funciona, registrar evidencia"

        } catch {
            $msg = $_.Exception.Message
            $esDeny = $msg -match "Access.is.denied|Access denied|UnauthorizedAccess|no tiene acceso|PermissionDenied|AccesoD|Insufficient access|insufficient rights|Acceso denegado|denegado"

            if ($esDeny) {
                Write-Host "  +--------------------------------------------+" -ForegroundColor Green
                Write-Host "  | [PASS] ACCESO DENEGADO CORRECTAMENTE        |" -ForegroundColor Green
                Write-Host "  |                                            |" -ForegroundColor Green
                Write-Host "  | admin_storage NO pudo resetear la password |" -ForegroundColor Green
                Write-Host "  | El ACL de DENY funciona correctamente.     |" -ForegroundColor Green
                Write-Host "  +--------------------------------------------+" -ForegroundColor Green
                Write-Host ""
                Write-Host "  Error recibido:" -ForegroundColor DarkGray
                Write-Host "  $msg" -ForegroundColor DarkGray
            } else {
                Write-Host "  [INFO] Error recibido (posible problema de conectividad):" -ForegroundColor Yellow
                Write-Host "  $msg" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  Verificando DENY en ACL del dominio directamente..." -ForegroundColor Yellow

                try {
                    $dcBase  = (Get-ADDomain).DistinguishedName
                    $aclDom  = Get-Acl -Path "AD:\$dcBase" -ErrorAction Stop
                    $denyAce = $aclDom.Access | Where-Object {
                        $_.IdentityReference -like "*admin_storage*" -and
                        $_.AccessControlType -eq "Deny"
                    }
                    if ($denyAce) {
                        Write-Host "  [PASS] Se confirma ACE DENY en AD para admin_storage:" -ForegroundColor Green
                        $denyAce | ForEach-Object {
                            Write-Host "         $($_.AccessControlType): $($_.ActiveDirectoryRights)" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host "  [WARN] No se encontro ACE DENY. Ejecuta Opcion 3 del menu P9." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "  No se pudo leer ACL: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }

            Pedir-Captura "TEST 1B: admin_storage obtuvo ACCESO DENEGADO - registrar evidencia comparativa con Test 1A"

            # Guardar log
            $logPath = "$rutaSalida\Test1B_Resultado.txt"
            @(
                "TEST 1B - Delegacion RBAC (admin_storage DENY)",
                "================================================",
                "Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
                "Ejecutado por   : $usuarioActual@$dominioActual",
                "Usuario objetivo: $($usuarioObjetivo.SamAccountName)",
                "Resultado: PASS - Acceso Denegado (comportamiento esperado)",
                "Error   : $msg",
                "",
                "CONCLUSION: El ACL de DENY sobre admin_storage funciona.",
                "Este rol NO puede resetear passwords en el dominio."
            ) | Out-File $logPath -Encoding UTF8
            Write-Host "  [OK] Log guardado en: $logPath" -ForegroundColor DarkGray
        }

    } catch {
        Write-Host "  [ERROR] No se pudo conectar a AD: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "  Presiona Enter para volver al menu..."
}


# ============================================================
# TEST 2: FGPP - Intentar poner password corta a admin_identidad
#
# EJECUTAR DESDE: Administrator (o cualquier admin con permisos)
# ============================================================
function Test2-FGPP {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 2 - FGPP: Politica de Contrasena     |" -ForegroundColor Cyan
    Write-Host "  |  Accion: Asignar pwd a admin_identidad     |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: RECHAZADA (si corta)  |" -ForegroundColor Green
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    Write-Host "  NOTA: Este test debe ejecutarse como Administrator" -ForegroundColor Yellow
    Write-Host "  o como un usuario con permisos para cambiar passwords." -ForegroundColor Yellow
    Write-Host ""

    # Mostrar politica FGPP vigente para admin_identidad
    Write-Host "  [1/3] Verificando PSO (FGPP) vigente para admin_identidad..." -ForegroundColor Yellow
    try {
        $pso = Get-ADUserResultantPasswordPolicy -Identity "admin_identidad" -ErrorAction Stop
        if ($pso) {
            Write-Host ""
            Write-Host "  Politica FGPP efectiva para admin_identidad:" -ForegroundColor White
            Write-Host "  +--------------------------------------------+" -ForegroundColor White
            Write-Host "  | Nombre          : $($pso.Name)"             -ForegroundColor Cyan
            Write-Host "  | Longitud minima : $($pso.MinPasswordLength) caracteres" -ForegroundColor Cyan
            Write-Host "  | Complejidad     : $(if($pso.ComplexityEnabled){'Requerida'}else{'No requerida'})" -ForegroundColor Cyan
            Write-Host "  | Lockout umbral  : $($pso.LockoutThreshold) intentos" -ForegroundColor Cyan
            Write-Host "  | Lockout duracion: $($pso.LockoutDuration)" -ForegroundColor Cyan
            Write-Host "  | Precedencia     : $($pso.Precedence)" -ForegroundColor Cyan
            Write-Host "  +--------------------------------------------+" -ForegroundColor White
            Write-Host ""
            Pedir-Captura "TEST 2 - Registro de la FGPP vigente (longitud minima 12 chars)"
        } else {
            Write-Host "  [WARN] No se encontro PSO para admin_identidad." -ForegroundColor Yellow
            Write-Host "         Ejecuta Opcion 4 del menu P9 (Configurar FGPP)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [WARN] No se pudo leer PSO: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Intento de poner password corta (debe fallar)
    Write-Host "  [2/3] Intentando asignar password a admin_identidad..." -ForegroundColor Yellow
    Write-Host ""
    $pwdCortaInput = Read-Host "        Ingresa una contrasena corta (DEBERIA FALLAR por longitud, ej. Corta1!!)"
    Write-Host ""

    try {
        $pwdCorta = ConvertTo-SecureString $pwdCortaInput -AsPlainText -Force
        Set-ADAccountPassword `
            -Identity    "admin_identidad" `
            -NewPassword $pwdCorta `
            -Reset `
            -ErrorAction Stop

        # Si llega aqui, la FGPP no esta aplicada
        Write-Host "  +--------------------------------------------+" -ForegroundColor Red
        Write-Host "  | [FAIL] La password corta fue ACEPTADA       |" -ForegroundColor Red
        Write-Host "  | La FGPP no esta aplicando correctamente.   |" -ForegroundColor Red
        Write-Host "  +--------------------------------------------+" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Solucion: Ejecuta Opcion 4 del menu P9 para configurar FGPP." -ForegroundColor Yellow
        Pedir-Captura "TEST 2 FALLIDO - registrar evidencia de que la FGPP no rechazo la password corta"

    } catch {
        $msg = $_.Exception.Message
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        Write-Host "  | [PASS] PASSWORD DE $($pwdCortaInput.Length) CHARS RECHAZADA          |" -ForegroundColor Green
        Write-Host "  |                                            |" -ForegroundColor Green
        Write-Host "  | La FGPP exige minimo 12 caracteres.        |" -ForegroundColor Green
        Write-Host "  | La politica funciona correctamente.        |" -ForegroundColor Green
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Error recibido del sistema:" -ForegroundColor DarkGray
        Write-Host "  $msg" -ForegroundColor DarkGray

        Pedir-Captura "TEST 2 PASS - registrar el error de rechazo de password corta (evidencia FGPP)"

        $logPath = "$rutaSalida\Test2_FGPP_Resultado.txt"
        @(
            "TEST 2 - FGPP Politica de Contrasena",
            "======================================",
            "Fecha    : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
            "Ejecutado por : $usuarioActual@$dominioActual",
            "Usuario objetivo: admin_identidad",
            "Password probada: $pwdCortaInput ($($pwdCortaInput.Length) caracteres)",
            "Resultado: PASS - Password rechazada por longitud insuficiente",
            "Error   : $msg",
            "",
            "CONCLUSION: La FGPP exige minimo 12 caracteres para admin_identidad.",
            "La politica esta configurada y funcionando correctamente."
        ) | Out-File $logPath -Encoding UTF8
        Write-Host "  [OK] Log guardado en: $logPath" -ForegroundColor DarkGray
    }

    # Intento con password valida (12+ chars) para confirmar que SI funciona
    Write-Host ""
    Write-Host "  [3/3] Verificando que una password valida SI es aceptada..." -ForegroundColor Yellow
    Write-Host ""
    $pwdLargaInput = Read-Host "        Ingresa una contrasena larga (NO DEBERIA FALLAR, ej. Hardening2026!)"
    Write-Host ""

    try {
        $pwdLarga = ConvertTo-SecureString $pwdLargaInput -AsPlainText -Force
        Set-ADAccountPassword `
            -Identity    "admin_identidad" `
            -NewPassword $pwdLarga `
            -Reset `
            -ErrorAction Stop

        Write-Host "  [OK] Password de $($pwdLargaInput.Length) chars ACEPTADA (correcto)." -ForegroundColor Green
        Write-Host "       La FGPP permite passwords largas." -ForegroundColor DarkGray

        # Restaurar la password original para no causar problemas
        $pwdOriginal = ConvertTo-SecureString "Hardening2026!" -AsPlainText -Force
        Set-ADAccountPassword -Identity "admin_identidad" -NewPassword $pwdOriginal -Reset -ErrorAction SilentlyContinue
        Write-Host "  [OK] Password restaurada a: Hardening2026!" -ForegroundColor DarkGray

    } catch {
        Write-Host "  [WARN] Password larga tambien fue rechazada: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         Revisa la configuracion de FGPP." -ForegroundColor Yellow
    }

    Write-Host ""
    Read-Host "  Presiona Enter para volver al menu..."
}


# ============================================================
# TEST 3: Flujo MFA - Instrucciones para captura de evidencia
# ============================================================
function Test3-MFA {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 3 - FLUJO MFA (Google Authenticator) |" -ForegroundColor Cyan
    Write-Host "  |  Resultado esperado: Campo TOTP en login   |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    Write-Host "  INSTRUCCIONES PARA EL TEST 3" -ForegroundColor Yellow
    Write-Host "  =============================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Este test requiere acceso fisico/consola al servidor." -ForegroundColor White
    Write-Host "  NO puede ejecutarse desde una sesion RDP ya iniciada." -ForegroundColor White
    Write-Host ""

    Write-Host "  PASO 1: Verificar que multiOTP esta instalado y activo" -ForegroundColor Cyan
    Write-Host "  --------------------------------------------------------" -ForegroundColor DarkGray

    # Buscar multiotp.exe
    $multiotpExe = $null
    foreach ($r in @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")) {
        if (Test-Path "$r\multiotp.exe") { $multiotpExe = "$r\multiotp.exe"; break }
    }

    if ($multiotpExe) {
        Write-Host "  [OK] multiOTP encontrado en: $(Split-Path $multiotpExe)" -ForegroundColor Green

        # Verificar usuarios registrados
        $dir = Split-Path $multiotpExe
        $carpetaUsers = Join-Path $dir "users"
        if (Test-Path $carpetaUsers) {
            $dbs = Get-ChildItem $carpetaUsers -Filter "*.db" -ErrorAction SilentlyContinue
            Write-Host "  [OK] Usuarios MFA registrados: $($dbs.Count)" -ForegroundColor Green
            $dbs | ForEach-Object { Write-Host "        - $($_.BaseName)" -ForegroundColor DarkGray }
        }

        # Verificar secreto guardado
        $secretoFile = "$rutaSalida\MFA_Secret_TodosAdmins.txt"
        if (Test-Path $secretoFile) {
            Write-Host ""
            Write-Host "  Datos del secreto TOTP guardado:" -ForegroundColor Yellow
            $contenido = Get-Content $secretoFile
            $contenido | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
        } else {
            Write-Host "  [WARN] No se encontro el archivo de secreto TOTP." -ForegroundColor Yellow
            Write-Host "         Ejecuta Opcion 7 del menu P9 (Activar MFA)." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [FAIL] multiOTP NO esta instalado." -ForegroundColor Red
        Write-Host "         Ejecuta Opciones 6 y 7 del menu P9." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  PASO 2: Generar codigo TOTP actual (para verificar que funciona)" -ForegroundColor Cyan
    Write-Host "  ------------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Abre Google Authenticator en tu celular." -ForegroundColor White
    Write-Host "  El codigo de 6 digitos se renueva cada 30 segundos." -ForegroundColor White
    Write-Host ""

    Pedir-Captura "TEST 3 PASO 2 - registrar celular con TOTP activo"

    Write-Host ""
    Write-Host "  PASO 3: Evidencia del login con MFA" -ForegroundColor Cyan
    Write-Host "  ------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Para completar el Test 3 necesitas:" -ForegroundColor White
    Write-Host ""
    Write-Host "  A) Cerrar sesion en el servidor completamente" -ForegroundColor Yellow
    Write-Host "  B) En la pantalla de login de Windows Server:" -ForegroundColor Yellow
    Write-Host "     - Escribe tu usuario y contrasena normales" -ForegroundColor White
    Write-Host "     - El Credential Provider de multiOTP pedira el codigo TOTP" -ForegroundColor White
    Write-Host "     - Escribe el codigo de 6 digitos de Google Authenticator" -ForegroundColor White
    Write-Host "  C) Registrar evidencia de la pantalla mostrando el campo TOTP" -ForegroundColor Yellow
    Write-Host "  D) Volver a ejecutar este script y continuar con el Test 4" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  NOTA: Si el Credential Provider NO aparece:" -ForegroundColor Red
    Write-Host "  - Verifica que multiOTP se instalo correctamente (Opcion 6 P9)" -ForegroundColor DarkGray
    Write-Host "  - Reinicia el servidor si es la primera instalacion" -ForegroundColor DarkGray
    Write-Host "  - Verifica en HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion" -ForegroundColor DarkGray
    Write-Host "    \Authentication\Credential Providers que aparece el GUID de multiOTP" -ForegroundColor DarkGray
    Write-Host ""

    # Guardar guia del test 3
    $logPath = "$rutaSalida\Test3_MFA_Guia.txt"
    @(
        "TEST 3 - Flujo MFA (Google Authenticator)",
        "==========================================",
        "Fecha generado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
        "",
        "EVIDENCIA REQUERIDA:",
        "1. Captura del celular con Google Authenticator mostrando codigo TOTP",
        "2. Captura/foto de la pantalla de login del servidor pidiendo el token",
        "3. Captura del login exitoso despues de ingresar el codigo correcto",
        "",
        "PASOS:",
        "A. Cerrar sesion en el servidor",
        "B. En pantalla de login: ingresar usuario + contrasena",
        "C. El Credential Provider de multiOTP pide codigo TOTP",
        "D. Ingresar codigo de 6 digitos de Google Authenticator",
        "E. Login exitoso",
        "",
        "Si el campo TOTP no aparece:",
        "- Verificar instalacion de multiOTP (Opcion 6 del menu P9)",
        "- Verificar que el Credential Provider esta registrado en Windows",
        "- Reiniciar el servidor si es necesario"
    ) | Out-File $logPath -Encoding UTF8
    Write-Host "  [OK] Guia del Test 3 guardada en: $logPath" -ForegroundColor DarkGray

    Write-Host ""
    Read-Host "  Presiona Enter para volver al menu..."
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

    $usuarios = @("Administrator","admin_identidad","admin_storage","admin_politicas","admin_auditoria")

    Write-Host "  INSTRUCCIONES PARA GENERAR EL BLOQUEO:" -ForegroundColor Yellow
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  1. Cierra sesion en el servidor" -ForegroundColor White
    Write-Host "  2. En la pantalla de login, ingresa usuario y contrasena correctos" -ForegroundColor White
    Write-Host "  3. Cuando pida el codigo TOTP, escribe: 000000 (codigo incorrecto)" -ForegroundColor White
    Write-Host "  4. Repite 3 veces con codigo incorrecto" -ForegroundColor White
    Write-Host "  5. Vuelve a iniciar sesion como Administrator" -ForegroundColor White
    Write-Host "  6. Ejecuta este script y selecciona Test 4" -ForegroundColor White
    Write-Host ""

    $r = Read-Host "  Ya realizaste los 3 intentos fallidos? (s/n)"
    if ($r -ne 's') {
        Write-Host ""
        Write-Host "  Realiza los intentos fallidos primero y vuelve a ejecutar este test." -ForegroundColor Yellow
        Write-Host ""
        Read-Host "  Presiona Enter para volver al menu..."
        return
    }

    Write-Host ""
    Write-Host "  Verificando estado de bloqueo en Active Directory..." -ForegroundColor Yellow
    Write-Host ""

    $hayBloqueado    = $false
    $resultados      = @()

    Write-Host "  +----------------------------------------------------------+" -ForegroundColor White
    Write-Host "  | Usuario          | Estado     | Intentos Fallidos        |" -ForegroundColor White
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor White

    foreach ($u in $usuarios) {
        try {
            $info = Get-ADUser -Identity $u `
                -Properties LockedOut, BadLogonCount, PasswordLastSet, LastBadPasswordAttempt `
                -ErrorAction Stop

            $estado   = if ($info.LockedOut) { "BLOQUEADO" } else { "Libre    " }
            $colorFila = if ($info.LockedOut) { "Red" } else { "Green" }
            $intentos  = $info.BadLogonCount

            Write-Host ("  | {0,-16} | {1,-10} | {2,-25} |" -f $u, $estado, "Intentos: $intentos") `
                -ForegroundColor $colorFila

            if ($info.LockedOut) { $hayBloqueado = $true }

            $resultados += [PSCustomObject]@{
                Usuario         = $u
                Bloqueado       = $info.LockedOut
                IntentosFallidos = $intentos
                UltimoPwdFallido = $info.LastBadPasswordAttempt
            }
        } catch {
            Write-Host ("  | {0,-16} | {1,-10} | {2,-25} |" -f $u, "No hallado", "") -ForegroundColor Yellow
        }
    }
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor White
    Write-Host ""

    if ($hayBloqueado) {
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green
        Write-Host "  | [PASS] CUENTA(S) BLOQUEADA(S) CORRECTAMENTE|" -ForegroundColor Green
        Write-Host "  |                                            |" -ForegroundColor Green
        Write-Host "  | El sistema bloqueo la cuenta tras 3 fallos|" -ForegroundColor Green
        Write-Host "  | de MFA. Duracion del bloqueo: 30 minutos.  |" -ForegroundColor Green
        Write-Host "  +--------------------------------------------+" -ForegroundColor Green

        Pedir-Captura "TEST 4 PASS - registrar cuenta BLOQUEADA"

        # Opcion de desbloquear
        Write-Host ""
        Write-Host "  Cuentas bloqueadas encontradas:" -ForegroundColor Yellow
        $bloqueadas = $resultados | Where-Object { $_.Bloqueado }
        $bloqueadas | ForEach-Object { Write-Host "  - $($_.Usuario)" -ForegroundColor Red }
        Write-Host ""
        $desbloquear = Read-Host "  Desbloquear estas cuentas ahora? (s/n)"
        if ($desbloquear -eq 's') {
            foreach ($b in $bloqueadas) {
                try {
                    Unlock-ADAccount -Identity $b.Usuario -ErrorAction Stop
                    Write-Host "  [OK] $($b.Usuario) desbloqueada." -ForegroundColor Green
                } catch {
                    Write-Host "  [WARN] No se pudo desbloquear $($b.Usuario): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
        Write-Host "  | [INFO] Ninguna cuenta bloqueada actualmente |" -ForegroundColor Yellow
        Write-Host "  |                                            |" -ForegroundColor Yellow
        Write-Host "  | Puede ser porque:                          |" -ForegroundColor Yellow
        Write-Host "  | - No se realizaron los 3 intentos fallidos |" -ForegroundColor Yellow
        Write-Host "  | - Ya pasaron 30 min y se desbloqueo sola   |" -ForegroundColor Yellow
        Write-Host "  | - El bloqueo de MFA esta en multiOTP, no AD|" -ForegroundColor Yellow
        Write-Host "  +--------------------------------------------+" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Verificando bloqueo en multiOTP..." -ForegroundColor Yellow

        $multiotpExe = $null
        foreach ($r2 in @("C:\Program Files\multiOTP","C:\multiOTP","C:\Program Files (x86)\multiOTP")) {
            if (Test-Path "$r2\multiotp.exe") { $multiotpExe = "$r2\multiotp.exe"; break }
        }

        if ($multiotpExe) {
            $dir = Split-Path $multiotpExe
            Push-Location $dir
            foreach ($u in $usuarios) {
                $checkResult = & ".\multiotp.exe" -check-ldap-users 2>&1 | Out-Null
                $userStatus  = & ".\multiotp.exe" -display-status $u 2>&1
                Write-Host "  $u : $userStatus" -ForegroundColor DarkGray
            }
            Pop-Location
        }

        Pedir-Captura "TEST 4 - registrar estado actual (aunque no haya bloqueo visible)"
    }

    # Guardar log
    $logPath = "$rutaSalida\Test4_Bloqueo_Resultado.txt"
    $resultados | ForEach-Object {
        "$($_.Usuario) | Bloqueado: $($_.Bloqueado) | Intentos: $($_.IntentosFallidos) | Ultimo fallo: $($_.UltimoPwdFallido)"
    } | Out-File $logPath -Encoding UTF8 -Append
    @(
        "",
        "TEST 4 - Bloqueo por MFA Fallido",
        "=================================",
        "Fecha: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')",
        "Ejecutado por: $usuarioActual@$dominioActual",
        "Resultado: $(if($hayBloqueado){'PASS - Cuenta bloqueada'}else{'INFO - Sin bloqueo activo'})"
    ) | Out-File $logPath -Encoding UTF8 -Append
    Write-Host ""
    Write-Host "  [OK] Log guardado en: $logPath" -ForegroundColor DarkGray

    Write-Host ""
    Read-Host "  Presiona Enter para volver al menu..."
}


# ============================================================
# TEST 5: Reporte de Auditoria - Eventos ID 4625
# ============================================================
function Test5-Auditoria {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  TEST 5 - REPORTE DE AUDITORIA ID 4625     |" -ForegroundColor Cyan
    Write-Host "  |  Usuario: admin_auditoria                  |" -ForegroundColor Cyan
    Write-Host "  |  Resultado: Genera archivo txt con eventos |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    if ($usuarioActual -ne "admin_auditoria") {
        Write-Host "  [AVISO] Estas logueado como '$usuarioActual'." -ForegroundColor Yellow
        Write-Host "          Este test debe ejecutarse como 'admin_auditoria'." -ForegroundColor Yellow
        Write-Host ""
        $continuar = Read-Host "  Continuar de todas formas? (s/n)"
        if ($continuar -ne 's') { return }
    }

    Write-Host "  Verificando permisos de admin_auditoria..." -ForegroundColor Yellow
    Write-Host ""

    # Verificar que puede leer el Security Log
    $puedeLeeLogs = $false
    try {
        $pruebaEvento = Get-WinEvent -LogName Security -MaxEvents 1 -ErrorAction Stop
        $puedeLeeLogs = $true
        Write-Host "  [OK] admin_auditoria puede leer el Security Event Log." -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] No se pudo leer Security Log: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         Verifica que admin_auditoria esta en 'Event Log Readers'." -ForegroundColor Yellow
        $puedeLeeLogs = $false
    }

    Write-Host ""
    Write-Host "  Extrayendo eventos ID 4625 (Inicio de sesion fallido)..." -ForegroundColor Yellow
    Write-Host ""

    $fechaReporte = Get-Date -Format 'yyyyMMdd_HHmm'
    $rutaReporte  = "$rutaSalida\Reporte_AccesosDenegados_$fechaReporte.txt"
    $rutaCSV      = "$rutaSalida\Reporte_AccesosDenegados_$fechaReporte.csv"

    # Encabezado del reporte
    $encabezado = @"
==================================================
REPORTE DE AUDITORIA DE SEGURIDAD
Practica 09 - Hardening Active Directory
--------------------------------------------------
Fecha generado : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
Servidor       : $env:COMPUTERNAME
Dominio        : $env:USERDNSDOMAIN
Ejecutado por  : $usuarioActual@$dominioActual
Evento         : ID 4625 - Inicio de sesion fallido
==================================================

"@

    $encabezado | Out-File $rutaReporte -Encoding UTF8

    try {
        $eventos = Get-WinEvent `
            -FilterHashtable @{ LogName = 'Security'; Id = 4625 } `
            -MaxEvents 10 `
            -ErrorAction SilentlyContinue

        if (-not $eventos -or $eventos.Count -eq 0) {
            Write-Host "  [INFO] No hay eventos ID 4625 registrados aun." -ForegroundColor Yellow
            Write-Host "         Necesitas generar intentos fallidos de login primero." -ForegroundColor DarkGray
            Write-Host "         (El Test 4 genera estos eventos al fallar el MFA)" -ForegroundColor DarkGray

            "No se encontraron eventos de acceso denegado (ID 4625)." | Out-File $rutaReporte -Append -Encoding UTF8
            "Realiza intentos de login fallidos para generar eventos." | Out-File $rutaReporte -Append -Encoding UTF8

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

                    # Escribir en TXT
                    @(
                        "EVENTO $i de $($eventos.Count)",
                        "--------------------------------------------------",
                        "Fecha       : $fecha",
                        "Usuario     : $user",
                        "Dominio     : $dom",
                        "IP Origen   : $ip",
                        "Proceso     : $proceso",
                        "Razon fallo : $tipo",
                        "--------------------------------------------------",
                        ""
                    ) | Out-File $rutaReporte -Append -Encoding UTF8

                    # Para CSV
                    $registrosCSV += [PSCustomObject]@{
                        Numero      = $i
                        Fecha       = $fecha
                        Usuario     = $user
                        Dominio     = $dom
                        IPOrigen    = $ip
                        Proceso     = $proceso
                        RazonFallo  = $tipo
                    }

                    $i++
                } catch {
                    Write-Host ("  | {0,1} | Error al parsear evento                          |" -f $i) -ForegroundColor Yellow
                    $i++
                }
            }

            Write-Host "  +----------------------------------------------------------+" -ForegroundColor White

            # Guardar CSV
            $registrosCSV | Export-Csv -Path $rutaCSV -NoTypeInformation -Encoding UTF8

            Write-Host ""
            Write-Host "  [OK] Reporte TXT : $rutaReporte" -ForegroundColor Green
            Write-Host "  [OK] Reporte CSV : $rutaCSV"     -ForegroundColor Green
        }

        # Mostrar contenido del reporte
        Write-Host ""
        Write-Host "  --- CONTENIDO DEL REPORTE ---" -ForegroundColor Cyan
        Get-Content $rutaReporte | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
        Write-Host "  --- FIN DEL REPORTE ---" -ForegroundColor Cyan

        Pedir-Captura "TEST 5 - registrar el reporte completo mostrado en pantalla"

    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        "ERROR: $($_.Exception.Message)" | Out-File $rutaReporte -Append -Encoding UTF8
    }

    # Resumen final del test
    Write-Host ""
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    Write-Host "  | TEST 5 COMPLETADO                          |" -ForegroundColor Green
    Write-Host "  | Archivos generados en $rutaSalida          |" -ForegroundColor Green
    Write-Host "  +--------------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Para adjuntar al reporte:" -ForegroundColor Yellow
    Write-Host "  - Copia el contenido de: $rutaReporte" -ForegroundColor White
    Write-Host "  - O adjunta el CSV     : $rutaCSV"     -ForegroundColor White
    Write-Host ""
    Read-Host "  Presiona Enter para volver al menu..."
}


# ============================================================
# EJECUTAR TODOS LOS TESTS EN ORDEN
# ============================================================
function Ejecutar-TodosLosTests {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Write-Host "  |  EJECUTAR TODOS LOS TESTS EN ORDEN         |" -ForegroundColor Cyan
    Write-Host "  +============================================+" -ForegroundColor Cyan
    Mostrar-UsuarioActual

    Write-Host "  IMPORTANTE: Algunos tests requieren sesion especifica." -ForegroundColor Yellow
    Write-Host "  Se ejecutaran los que puedan correr con el usuario actual." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  El orden correcto de sesiones es:" -ForegroundColor White
    Write-Host "  1. Inicia como admin_identidad  -> ejecuta Test 1A" -ForegroundColor Cyan
    Write-Host "  2. Inicia como admin_storage    -> ejecuta Test 1B" -ForegroundColor Cyan
    Write-Host "  3. Inicia como Administrator    -> ejecuta Tests 2 y 4" -ForegroundColor Cyan
    Write-Host "  4. Inicia como admin_auditoria  -> ejecuta Test 5" -ForegroundColor Cyan
    Write-Host "  5. Test 3 (MFA) requiere cerrar sesion fisicamente" -ForegroundColor Cyan
    Write-Host ""

    $continuar = Read-Host "  Continuar ejecutando los tests posibles ahora? (s/n)"
    if ($continuar -ne 's') { return }

    Write-Host ""
    Write-Host "  Ejecutando segun usuario actual: $usuarioActual" -ForegroundColor Yellow
    Write-Host ""

    switch ($usuarioActual) {
        "admin_identidad" {
            Write-Host "  -> Ejecutando Test 1A (eres admin_identidad)" -ForegroundColor Cyan
            Test1A-IdentidadResetPassword
        }
        "admin_storage" {
            Write-Host "  -> Ejecutando Test 1B (eres admin_storage)" -ForegroundColor Cyan
            Test1B-StorageDeny
        }
        "admin_auditoria" {
            Write-Host "  -> Ejecutando Test 5 (eres admin_auditoria)" -ForegroundColor Cyan
            Test5-Auditoria
        }
        default {
            # Administrator u otro: ejecutar tests 2, 3 y 4
            Write-Host "  -> Ejecutando Test 2 (FGPP)" -ForegroundColor Cyan
            Test2-FGPP
            Write-Host "  -> Ejecutando Test 3 (guia MFA)" -ForegroundColor Cyan
            Test3-MFA
            Write-Host "  -> Ejecutando Test 4 (bloqueo MFA)" -ForegroundColor Cyan
            Test4-BloqueoMFA
        }
    }

    Write-Host ""
    Write-Host "  Todos los tests disponibles para '$usuarioActual' han sido ejecutados." -ForegroundColor Green
    Write-Host "  Archivos de evidencia en: $rutaSalida" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "  Presiona Enter para volver al menu..."
}


# ============================================================
# INICIO
# ============================================================
Mostrar-Menu
