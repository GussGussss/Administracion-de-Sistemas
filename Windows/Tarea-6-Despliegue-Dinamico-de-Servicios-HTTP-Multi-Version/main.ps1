# main.ps1
. .\funciones.ps1

while ($true) {
    Clear-Host
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "  DESPLIEGUE SERVIDORES HTTP  " -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "1) IIS (Internet Information Services)"
    Write-Host "2) Apache Win64 (vía Winget)"
    Write-Host "3) Nginx for Windows (vía Winget)"
    Write-Host "4) Salir"
    
    $opcion = Read-Host "Seleccione una opción"

    if ($opcion -eq "4") { break }

    switch ($opcion) {
        "1" {
            # IIS es una característica de Windows, no listamos versiones externas
            $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp\").VersionString
            Write-Host "Versión de IIS detectada: $version" -ForegroundColor Yellow
            $puerto = Read-Host "Ingrese puerto de escucha"
            
            if (Test-ValidarPuerto $puerto) {
                Install-IIS -Version $version -Puerto $puerto
            }
        }
        "2" {
            $versiones = Get-VersionesWinget -Id "ApacheFriends.XAMPP.8.2" # O "Apache.Apache"
            Write-Host "1) $($versiones.Latest) (Latest)"
            Write-Host "2) $($versiones.LTS) (Stable)"
            $vNum = Read-Host "Seleccione número de versión"
            $verFinal = if ($vNum -eq "1") { $versiones.Latest } else { $versiones.LTS }
            
            $puerto = Read-Host "Ingrese puerto de escucha"
            if (Test-ValidarPuerto $puerto) {
                Install-ApacheWin -Version $verFinal -Puerto $puerto
            }
        }
        "3" {
            $versiones = Get-VersionesWinget -Id "nginx.nginx"
            Write-Host "1) $($versiones.Latest) (Latest)"
            Write-Host "2) $($versiones.LTS) (Stable)"
            $vNum = Read-Host "Seleccione número de versión"
            $verFinal = if ($vNum -eq "1") { $versiones.Latest } else { $versiones.LTS }

            $puerto = Read-Host "Ingrese puerto de escucha"
            if (Test-ValidarPuerto $puerto) {
                Install-NginxWin -Version $verFinal -Puerto $puerto
            }
        }
        Default { Write-Host "Opción inválida" -ForegroundColor Red; Start-Sleep -Seconds 2 }
    }
    Write-Host "Presione una tecla para continuar..."
    $null = [System.Console]::ReadKey($true)
}
