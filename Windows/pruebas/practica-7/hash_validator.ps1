# ============================================================
# hash_validator.ps1
# Verificacion de integridad de archivos
# Practica 07
# ============================================================

function Verificar-Hash {

    param(
        [string]$archivo,
        [string]$archivoHash
    )

    Write-Host ""
    Write-Host "Verificando integridad del archivo..." -ForegroundColor Cyan

    # --------------------------------------------------------
    # verificar que los archivos existan
    # --------------------------------------------------------

    if (-not (Test-Path $archivo)) {
        Write-Host "Error: archivo no encontrado." -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path $archivoHash)) {
        Write-Host "Error: archivo hash no encontrado." -ForegroundColor Red
        return $false
    }

    # --------------------------------------------------------
    # calcular hash local
    # --------------------------------------------------------

    $hashLocal = Get-FileHash -Path $archivo -Algorithm SHA256

    # --------------------------------------------------------
    # leer hash esperado
    # --------------------------------------------------------

    $hashEsperado = Get-Content $archivoHash

    # limpiar espacios
    $hashEsperado = $hashEsperado.Trim()

    # --------------------------------------------------------
    # comparar hashes
    # --------------------------------------------------------

    if ($hashLocal.Hash -eq $hashEsperado) {

        Write-Host "Integridad verificada. Hash correcto." -ForegroundColor Green
        return $true
    }
    else {

        Write-Host ""
        Write-Host "ERROR: Hash no coincide. Archivo corrupto." -ForegroundColor Red
        Write-Host "Instalacion cancelada por seguridad." -ForegroundColor Red

        return $false
    }
}
