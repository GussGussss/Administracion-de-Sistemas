#!/bin/bash

# Importar las funciones
source ./funciones_p10.sh

mostrar_menu() {
    clear
    echo "=========================================="
    echo "   ADMINISTRACIÓN DE SISTEMAS - TAREA 10"
    echo "=========================================="
    echo "1. Instalar Dependencias (Docker Engine)"
    echo "2. Preparar Entorno (Carpetas, Red, Volúmenes)"
    echo "3. Desplegar Servidor Web (Nginx + Seguridad)"
    echo "4. Desplegar Base de Datos (PostgreSQL)"
    echo "5. Desplegar Servidor FTP"
    echo "6. Limpiar Contenedores (Reset)"
    echo "0. Salir"
    echo "=========================================="
    echo -n "Seleccione una opción: "
}

while true; do
    mostrar_menu
    read opcion
    case $opcion in
        1) instalar_docker ;;
        2) preparar_entorno ;;
        3) echo "Próximamente: Dockerfile Web..." ;;
        4) echo "Próximamente: Config BD..." ;;
        5) echo "Próximamente: Config FTP..." ;;
        6) limpiar_todo ;;
        0) echo "Saliendo del sistema..."; exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
    echo "Presione enter para continuar..."
    read
done
