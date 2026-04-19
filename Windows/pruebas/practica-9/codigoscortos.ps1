# 1. Definir la ruta del registro donde se activan los Credential Providers
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers"

# 2. El ID unico (GUID) que le pertenece al multiOTP Credential Provider
# (Este GUID es estandar para todas las instalaciones de multiOTP en Windows)
$multiOTP_GUID = "{AC4B6349-9A33-402c-A376-791F60DF1275}"
$fullPath = "$registryPath\$multiOTP_GUID"

# 3. Verificar si el registro existe y activarlo a la fuerza
try {
    if (Test-Path $fullPath) {
        # Si el proveedor esta deshabilitado (Disabled = 1), lo habilitamos (Disabled = 0)
        Set-ItemProperty -Path $fullPath -Name "Disabled" -Value 0 -Type DWord -ErrorAction Stop
        Write-Host "`n[OK] Proveedor de Credenciales multiOTP habilitado exitosamente en el Registro." -ForegroundColor Green
    } else {
        Write-Host "`n[ERROR] No se encontro el registro del proveedor. La instalacion del MSI fallo silenciosamente." -ForegroundColor Red
        Write-Host "Recomendacion: Ejecuta msiexec /i C:\MFA_Setup\Extracted_*\multiOTPCredentialProviderInstaller.msi manualmente." -ForegroundColor Yellow
    }
} catch {
    Write-Host "`n[ERROR] No se pudo modificar el registro: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. (Opcional pero recomendado) Reiniciar el servicio de Logon para aplicar cambios sin reiniciar el PC
Write-Host "[INFO] Reiniciando la pantalla de inicio de sesion..." -ForegroundColor Cyan
Stop-Process -Name LogonUI -Force -ErrorAction SilentlyContinue
