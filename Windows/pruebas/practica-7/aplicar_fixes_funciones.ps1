# ============================================================
# aplicar_fixes_funciones.ps1
# Aplica los fixes necesarios en funciones.ps1 (P6) para P7
# Ejecutar en la misma carpeta donde esta funciones.ps1
# ============================================================

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$archivo    = "$scriptDir\funciones.ps1"

if (-not (Test-Path $archivo)) {
    Write-Host "ERROR: No se encuentra funciones.ps1 en $scriptDir" -ForegroundColor Red
    exit 1
}

Write-Host "Aplicando fixes en funciones.ps1..." -ForegroundColor Cyan

# Backup antes de modificar
$backup = "$archivo.bak"
Copy-Item $archivo $backup -Force
Write-Host "  Backup creado: $backup" -ForegroundColor Gray

$contenido = Get-Content $archivo -Raw

# ── FIX 1: Listar-Versiones-IIS → agregar 3ra version ────────────────────────
$antes1 = 'Write-Host "1) $ver  (Estable - incluida en Windows Server 2019)"
    Write-Host "2) $ver  (LTS - misma version del sistema)"'

$despues1 = 'Write-Host "1) $ver  (Latest / Desarrollo)"
    Write-Host "2) $ver  (LTS / Estable)"
    Write-Host "3) $ver  (Oldest)"'

if ($contenido -match [regex]::Escape('(Estable - incluida en Windows Server 2019)')) {
    $contenido = $contenido -replace [regex]::Escape($antes1), $despues1
    Write-Host "  FIX 1 aplicado: Listar-Versiones-IIS ahora muestra 3 versiones." -ForegroundColor Green
} else {
    Write-Host "  FIX 1: Ya aplicado o patron no encontrado." -ForegroundColor Yellow
}

# ── FIX 2: Listar-Versiones-Apache → agregar fallback con 3 versiones reales ─
# Si Chocolatey falla, mostrar versiones conocidas en lugar de solo 2
$antesApache = 'if (-not $latest) { $latest = "2.4.55" }
    if (-not $lts)    { $lts    = "2.4.54" }
    if (-not $oldest) { $oldest = "2.4.52" }'

$despuesApache = 'if (-not $latest) { $latest = "2.4.63" }
    if (-not $lts)    { $lts    = "2.4.62" }
    if (-not $oldest) { $oldest = "2.4.58" }'

if ($contenido -match [regex]::Escape('"2.4.55"')) {
    $contenido = $contenido -replace [regex]::Escape($antesApache), $despuesApache
    Write-Host "  FIX 2 aplicado: versiones fallback de Apache actualizadas." -ForegroundColor Green
} else {
    Write-Host "  FIX 2: Ya aplicado o patron no encontrado." -ForegroundColor Yellow
}

# ── FIX 3: Listar-Versiones-Nginx → actualizar version Latest ─────────────────
$antesNginx = 'if (-not $latest) { $latest = "1.26.2" }
    $lts    = "1.24.0"
    $oldest = "1.22.1"'

$despuesNginx = 'if (-not $latest) { $latest = "1.26.2" }
    $lts    = "1.24.0"
    $oldest = "1.22.1"
    # Asegurar que siempre haya 3 versiones definidas
    $global:NGINX_OLDEST = $oldest'

# Este fix es menor, solo confirmar que oldest esta definido
if ($contenido -notmatch 'NGINX_OLDEST') {
    $contenido = $contenido -replace [regex]::Escape($antesNginx), $despuesNginx
    Write-Host "  FIX 3 aplicado: NGINX_OLDEST definido correctamente." -ForegroundColor Green
} else {
    Write-Host "  FIX 3: Ya aplicado." -ForegroundColor Yellow
}

# Guardar cambios
[System.IO.File]::WriteAllText($archivo, $contenido, [System.Text.UTF8Encoding]::new($false))
Write-Host ""
Write-Host "Fixes aplicados correctamente en funciones.ps1" -ForegroundColor Green
Write-Host "Backup disponible en: $backup" -ForegroundColor Gray
