Write-Host "*************** SCRIPT DE BIENVENIDA **************"
$nombre=hostname
$ip=Get-NetIPAddress -AddressFamily IPv4
$disco=Get-Volume -DriveLetter C | Format-Table -Autosize | Out-String
Write-Host "`nNombre de equipo: $nombre"
Write-Host "`nIP del equipo: $ip"
Write-Host "`nEspacio en el disco: $disco"