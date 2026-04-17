# ============================================================
#  funciones_p9.ps1 - Libreria de funciones para Practica 09
# ============================================================

# ------------------------------------------------------------
# FUNCION 1: Preparar Entorno y Descargar MFA
# ------------------------------------------------------------
function Preparar-EntornoMFA {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    PREPARAR ENTORNO Y DESCARGAR MFA      |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    $rutaDescarga = "C:\MFA_Setup"
    $archivoInstalador = "$rutaDescarga\multiOTP_CP_Installer.exe"
    # URL oficial directa del release de Github de multiOTP
    $urlMFA = "https://github.com/multiOTP/multiOTPCredentialProvider/releases/download/5.9.5.3/multiOTPCredentialProvider-5.9.5.3-x64-Release.exe"

    # 1. Crear carpeta si no existe
    if (-not (Test-Path $rutaDescarga)) {
        New-Item -Path $rutaDescarga -ItemType Directory | Out-Null
        Write-Host "  [OK] Carpeta creada: $rutaDescarga" -ForegroundColor Green
    }

    # 2. Logica de validacion de descarga
    $procederDescarga = $true

    if (Test-Path $archivoInstalador) {
        Write-Host "  [AVISO] El instalador de MFA ya se encuentra descargado en el sistema." -ForegroundColor Yellow
        $respuesta = Read-Host "  Deseas volver a descargarlo y sobreescribirlo? (s/n)"
        
        if ($respuesta.ToLower() -ne 's') {
            $procederDescarga = $false
            Write-Host "  [OK] Omitiendo descarga del instalador..." -ForegroundColor Green
        }
    }

    # 3. Descargar si es necesario
    if ($procederDescarga) {
        Write-Host "  [INFO] Descargando multiOTP Credential Provider. Esto puede tomar un momento..." -ForegroundColor Cyan
        try {
            # Se usa UseBasicParsing porque Server Core no tiene Internet Explorer engine
            Invoke-WebRequest -Uri $urlMFA -OutFile $archivoInstalador -UseBasicParsing
            Write-Host "  [OK] Descarga completada exitosamente." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] Fallo la descarga. Verifica que el servidor tenga salida a internet." -ForegroundColor Red
            Write-Host "  Detalle: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}

# ------------------------------------------------------------
# FUNCION 2: Crear Usuarios de Administracion (Sin permisos aun)
# ------------------------------------------------------------
function Crear-UsuariosAdmin {
    Write-Host "`n  +==========================================+" -ForegroundColor Cyan
    Write-Host "  |    CREACION DE USUARIOS ADMINISTRATIVOS  |" -ForegroundColor Cyan
    Write-Host "  +==========================================+`n" -ForegroundColor Cyan

    # Lista de usuarios a crear basada en tu practica
    $usuarios = @(
        @{ User = "admin_identidad"; Nombre = "Admin"; Apellido = "Identidad" },
        @{ User = "admin_storage";   Nombre = "Admin"; Apellido = "Storage" },
        @{ User = "admin_politicas"; Nombre = "Admin"; Apellido = "Politicas" },
        @{ User = "admin_auditoria"; Nombre = "Admin"; Apellido = "Auditoria" }
    )

    # Vamos a usar una contrasena generica que cumpla la complejidad de Windows Server
    $pwdTexto = "Hardening2026!" 
    $pwdSegura = ConvertTo-SecureString $pwdTexto -AsPlainText -Force

    $creados = 0
    $omitidos = 0

    foreach ($u in $usuarios) {
        # Verificar si existe
        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.User)'" -ErrorAction SilentlyContinue
        
        if ($existe) {
            Write-Host "  [OMITIDO] El usuario '$($u.User)' ya existe." -ForegroundColor Yellow
            $omitidos++
        } else {
            try {
                New-ADUser -Name "$($u.Nombre) $($u.Apellido)" `
                           -GivenName $($u.Nombre) `
                           -Surname $($u.Apellido) `
                           -SamAccountName $($u.User) `
                           -UserPrincipalName "$($u.User)@practica8.local" `
                           -AccountPassword $pwdSegura `
                           -Enabled $true `
                           -PasswordNeverExpires $true

                Write-Host "  [OK] Usuario '$($u.User)' creado exitosamente. (Pass: $pwdTexto)" -ForegroundColor Green
                $creados++
            } catch {
                Write-Host "  [ERROR] No se pudo crear a '$($u.User)': $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Resumen: $creados creados, $omitidos ya existian." -ForegroundColor White
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    
    Write-Host "`n  Presiona Enter para volver al menu..." -ForegroundColor Cyan
    Pause | Out-Null
}
