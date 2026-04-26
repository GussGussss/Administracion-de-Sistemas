#!/bin/bash
# Archivo: main_p10.sh

# 1. Validación estricta de privilegios (sudo)
if [ "$EUID" -ne 0 ]; then
    echo "============================================================"
    echo " ERROR: Este script requiere privilegios administrativos."
    echo " Por favor, ejecútalo usando: sudo ./main_p10.sh"
    echo "============================================================"
    exit 1
fi

# 2. Carga de las funciones
# Validamos que el archivo de funciones exista antes de cargarlo
if [ -f "./funciones_p10.sh" ]; then
    source ./funciones_p10.sh
else
    echo "ERROR: No se encontró el archivo funciones_p10.sh en el directorio actual."
    exit 1
fi

# 3. Bucle infinito del Menú Principal
while true; do
    echo "=========================================================="
    echo " Práctica 10: Virtualización Nativa y Contenedores"
    echo "=========================================================="
    echo "1. Validar e Instalar Dependencias (Docker, Compose)"
    echo "2. Preparar Estructura de Carpetas y Red (infra_red)"
    echo ""
    echo "0. Salir del script"
    echo "=========================================================="
    read -p "Selecciona una opción: " opcion

    case $opcion in
        1)
            instalar_dependencias
            ;;
        2)
            preparar_entorno_docker
            ;;
        3)
            generar_archivos_configuracion
            ;;
        0)
            echo "Saliendo del asistente. ¡Hasta luego!"
            exit 0
            ;;
        *)
            echo "Opción no válida. Por favor, selecciona una opción del menú."
            sleep 2
            ;;
    esac
done
