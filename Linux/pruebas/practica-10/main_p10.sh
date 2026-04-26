#!/bin/bash

# Importar las funciones
source ./funciones_p10.sh

mostrar_menu() {
    clear
    echo "=========================================="
    echo "   ADMINISTRACIÓN DE SISTEMAS - TAREA 10"
    echo "=========================================="
    echo "1. Preparar Entorno (Carpetas, Red, Volúmenes)"
    echo "2. Desplegar Servidor Web (Nginx + Seguridad)"
    echo "3. Desplegar Base de Datos (PostgreSQL)"
    echo "4. Desplegar Servidor FTP"
    echo "5. Limpiar Contenedores (Reset)"
    echo "6. Salir"
    echo "=========================================="
    echo -n "Seleccione una opción: "
}

while true; do
    mostrar_menu
    read opcion
    case $opcion in
        1) preparar_entorno ;;
        2) echo "Próximamente: Dockerfile Web..." ;;
        3) echo "Próximamente: Config BD..." ;;
        4) echo "Próximamente: Config FTP..." ;;
        5) limpiar_todo ;;
        6) exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
    echo "Presione enter para continuar..."
    read
done
