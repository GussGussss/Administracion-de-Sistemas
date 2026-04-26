#!/bin/bash

# Validacion de Privilegios ROOT
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Se requieren privilegios de administrador para gestionar contenedores."
    echo "Use: sudo bash $0"
    exit 1
fi

# Importar funciones
source ./funciones_p10.sh

mostrar_menu() {
    clear
    echo "=========================================="
    echo "   ADMINISTRACION DE SISTEMAS - TAREA 10"
    echo "=========================================="
    echo "1. Descargar Utilidades (Imagenes Docker)"
    echo "2. Instalar Dependencias (Docker Engine)"
    echo "3. Preparar Entorno (Red y Volumenes)"
    echo "4. Desplegar Servidor Web (Nginx Seguro)"
    echo "5. Desplegar Base de Datos"
    echo "6. Desplegar Servidor FTP"
    echo "7. Limpiar Contenedores"
    echo "0. Salir"
    echo "=========================================="
    echo -n "Seleccione una opcion: "
}

while true; do
    mostrar_menu
    read opcion
    case $opcion in
        1) descargar_utilidades ;;
        2) instalar_docker ;;
        3) preparar_entorno ;;
        4) desplegar_web ;;
        5) echo "Proximamente: BD..." ;;
        6) echo "Proximamente: FTP..." ;;
        7) limpiar_todo ;;
        0) echo "Cerrando script..."; exit 0 ;;
        *) echo "Opcion no valida." ;;
    esac
    echo "Presione enter para continuar..."
    read
done
