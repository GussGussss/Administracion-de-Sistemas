#!/bin/bash
# ==============================================================================
# Script: main_p12.sh
# Descripción: Controlador principal para despliegue de infraestructura de correo.
# ==============================================================================

# 1. Validación estricta de privilegios root
if [[ $EUID -ne 0 ]]; then
   echo "[ERROR] Permisos insuficientes. Este script debe ser ejecutado con 'sudo'."
   exit 1
fi

# 2. Carga del módulo de funciones
if [[ -f "./funciones_p12.sh" ]]; then
    source ./funciones_p12.sh
else
    echo "[ERROR] No se encuentra el archivo dependiente 'funciones_p12.sh'."
    exit 1
fi

# 3. Autodetección de red y usuario
export DETECTED_USER=${SUDO_USER:-root}
export DETECTED_IP=$(ip -4 addr show enp0s3 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
export BASE_DIR="/opt/practica12"
export DOMAIN="reprobados.com"

# Validación de seguridad para la IP
if [[ -z "$DETECTED_IP" ]]; then
    DETECTED_IP="127.0.0.1"
    echo "[ADVERTENCIA] No se pudo detectar IPv4 en enp0s3. Se usará localhost como fallback."
fi

# 4. Menú Interactivo (Bucle de control)
while true; do
    echo ""
    echo "======================================================================"
    echo "       SISTEMA DE DESPLIEGUE - PRÁCTICA 12 (CORREO & WEBMAIL)         "
    echo "======================================================================"
    echo " [INFO] Usuario host: $DETECTED_USER"
    echo " [INFO] IP enp0s3:    $DETECTED_IP"
    echo " [INFO] Ruta externa: $BASE_DIR"
    echo "======================================================================"
    echo " 1. Preparar Entorno Base (Directorios y Permisos)"
    echo " 2. Generar Stack Docker (Compose y Verificación de Imágenes)"
    echo " 3. Levantar Infraestructura y Sincronizar DNS Local"
    echo " 4. Gestión de Cuentas de Correo (Crear/Listar)"
    echo " 5. Generar Claves Criptográficas (OpenDKIM)"
    echo " 6. Configurar Automatización de Respaldos (Cron)"
    echo " 7. Personalización Institucional (Webmail)"
    echo " 8. Panel de Auditoría y Seguridad (Logs/Fail2Ban)"
    echo " 0. Salir del sistema"
    echo "======================================================================"
    read -p " Seleccione una opción de ejecución: " opcion

    case $opcion in
        1) preparar_entorno_base ;;
        2) generar_stack_docker ;;
        3) levantar_servicios_y_dns ;;
        4) gestionar_cuentas_correo ;;
        5) generar_claves_dkim ;;
        6) configurar_respaldo_cron ;;
        7) personalizar_webmail ;;
        8) auditar_seguridad_logs ;;
        0)
            echo "[INFO] Finalizando ejecución y cerrando descriptores."
            exit 0
            ;;
        *)
            echo "[ERROR] Entrada no reconocida. Seleccione una opción válida."
            ;;
    esac
    
    echo ""
    read -p "Presione ENTER para retornar al menú principal..."
done
