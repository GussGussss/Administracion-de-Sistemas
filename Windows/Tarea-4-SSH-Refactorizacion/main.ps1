. .\lib\network.ps1
. .\modulos\dhcp.ps1
. .\modulos\dns.ps1
. .\modulos\ssh.ps1

function menu-principal {

    do {
        Write-Host ""
        Write-Host "******** Menu Principal ********"
        Write-Host "1) DHCP"
        Write-Host "2) DNS"
        Write-Host "3) SSH"
        Write-Host "4) Estado general de servicios"
        Write-Host "0) Salir"

        $opcion = Read-Host "Selecciona una opcion"

        switch ($opcion) {

            "1" { menu-dhcp }

            "2" { menu-dns }

            "3" { menu_ssh }

            "4" {
                Write-Host ""
                Write-Host "***** Estado de servicios *****"
                Get-Service DHCPServer
                Get-Service DNS
                Get-Service sshd -ErrorAction SilentlyContinue
                Read-Host "Presiona ENTER para continuar"
            }

            "0" { break }

            default {
                Write-Host "Opcion invalida"
                Read-Host "Presiona ENTER para continuar"
            }
        }

    } while ($true)
}

menu-principal
