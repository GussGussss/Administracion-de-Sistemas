# Main.ps1
. .\funciones.ps1

while ($true) {
    Clear-Host
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host " DESPLIEGUE SERVIDORES HTTP (WIN) " -ForegroundColor Cyan
    Write-Host "==============================" -ForegroundColor Cyan
    Write-Host "1) IIS (Internet Information Services)"
    Write-Host "2) Apache Win64"
    Write-Host "3) Nginx para Windows"
    Write-Host "4) Salir"
    
    $opcion = Read-Host "Seleccione una opción"
    
    if ($opcion -eq "4") { break }

    switch ($opcion) {
        "1" {
            # IIS suele venir con el sistema, listamos versiones de la característica
            $version = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\InetStp\").VersionString
            $puerto = Read-Host "Ingrese puerto para IIS"
            if (Test-PuertoValido $puerto) {
                Install-IIS -Puerto $puerto -Version $version
            }
        }
        "2" {
            $versiones = Get-VersionesWinget "ApacheFriends.XAMPP" # Ejemplo con XAMPP o Apache
            # Lógica para elegir entre $versiones[0] (Latest) o $versiones[-1] (LTS/Old)
            $puerto = Read-Host "Ingrese puerto para Apache"
            if (Test-PuertoValido $puerto) {
                Install-ApacheWin -Version $versiones[0] -Puerto $puerto
            }
        }
        "3" {
            $versiones = Get-VersionesWinget "nginx.nginx"
            $puerto = Read-Host "Ingrese puerto para Nginx"
            if (Test-PuertoValido $puerto) {
                Install-NginxWin -Version $versiones[0] -Puerto $puerto
            }
        }
        Default { Write-Host "Opción inválida" -ForegroundColor Red }
    }
    Pause
}
