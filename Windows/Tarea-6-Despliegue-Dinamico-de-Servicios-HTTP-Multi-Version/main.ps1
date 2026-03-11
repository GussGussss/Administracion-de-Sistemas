. .\funciones.ps1

while ($true) {

Write-Host "=============================="
Write-Host " DESPLIEGUE SERVIDORES HTTP "
Write-Host "=============================="

Write-Host "1) IIS"
Write-Host "2) Apache"
Write-Host "3) Nginx"
Write-Host "4) Instalar Winget"
Write-Host "5) Salir"

$opcion = Read-Host "Seleccione una opción"

switch ($opcion) {

"1" {

listar_versiones_iis

$puerto = [int](Read-Host "Ingrese puerto")

if (validar_puerto $puerto) {

instalar_iis $puerto

}

}

"2" {

listar_versiones_apache_win

$version = Read-Host "Seleccione versión"

$puerto = [int](Read-Host "Ingrese puerto")

if (validar_puerto $puerto) {

instalar_apache_win $version $puerto

}

}

"3" {

listar_versiones_nginx_win

$version = Read-Host "Seleccione versión"

$puerto = [int](Read-Host "Ingrese puerto")

if (validar_puerto $puerto) {

instalar_nginx_win $version $puerto

}

}

"4" {

instalar_winget

}

"5" {

exit

}

default {

Write-Host "Opción inválida"

}

}

}
