#!/bin/bash
# ==============================================================================
# Script: funciones_p12.sh
# Descripción: Módulo de procesamiento y funciones para main_p12.sh.
# ==============================================================================

# Función 1: Preparación de la infraestructura externa
preparar_entorno_base() {
    echo ""
    echo "[PROCESO] Iniciando construcción de infraestructura en $BASE_DIR..."

    # Validación de estado previo
    if [[ -d "$BASE_DIR" ]]; then
        echo "[INFO] El directorio raíz ya existe. Verificando subdirectorios..."
    else
        echo "[INFO] Creando directorio raíz..."
        mkdir -p "$BASE_DIR"
    fi

    # Definición de estructura de volúmenes para persistencia de datos
    local directorios=(
        "mail_data"     # Volúmen para buzones
        "mail_state"    # Estado de fail2ban y rspamd
        "mail_logs"     # Auditoría y registros
        "mail_config"   # Configuraciones de Postfix/Dovecot
        "webmail_html"  # Archivos estáticos de Roundcube
        "webmail_db"    # Base de datos local (MariaDB/SQLite)
    )

    for dir in "${directorios[@]}"; do
        if [[ ! -d "$BASE_DIR/$dir" ]]; then
            mkdir -p "$BASE_DIR/$dir"
            echo "  -> Creado: $BASE_DIR/$dir"
        else
            echo "  -> Omitido (ya existe): $BASE_DIR/$dir"
        fi
    done

    # Ajuste de permisos para evitar problemas de montajes en Docker
    echo "[PROCESO] Ajustando propiedad de los directorios a $DETECTED_USER..."
    chown -R "$DETECTED_USER:$DETECTED_USER" "$BASE_DIR"
    chmod -R 755 "$BASE_DIR"

    echo "[ÉXITO] Infraestructura de directorios preparada y securizada."
}
