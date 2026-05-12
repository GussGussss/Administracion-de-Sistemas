#!/bin/bash
# main_p11.sh
# Controlador principal de la Práctica 11

# Validación Estricta de Sudo/Root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR CRÍTICO: Este script altera la infraestructura del sistema y gestiona contenedores."
    echo "Debe ser ejecutado con privilegios de superusuario (root o sudo)."
    exit 1
fi

# Importar funciones
source ./funciones_p11.sh

# Bucle principal del menú interactivo
while true; do
    echo "=========================================================="
    echo " Administrador de Infraestructura - Práctica 11"
    echo " Orquestación de Microservicios y Túneles"
    echo "=========================================================="
    echo " 1. Preparar Entorno e Instalar Dependencias"
    echo " 2. Generar Archivos de Configuración (docker-compose y .env)"
    echo " 3. Desplegar Infraestructura (Docker Compose Up)"
    echo " 4. Protocolo de Pruebas Dinámicas"
    echo " 0. Salir del sistema"
    echo "=========================================================="
    read -p "Seleccione una opción [0-4]: " opcion_principal

    case $opcion_principal in
        1) preparar_entorno ;;
        2) generar_archivos ;;
        3) desplegar_infraestructura ;;
        4) submodo_pruebas ;;
        0) 
            echo "Finalizando operaciones. Hasta pronto."
            exit 0 
            ;;
        *) 
            echo "ERROR: Opción inválida. Seleccione un número del 0 al 4."
            sleep 2
            ;;
    esac
done
