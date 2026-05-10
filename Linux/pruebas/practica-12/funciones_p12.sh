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

# ==============================================================================
# Función 2: Generación del stack y validación de imágenes offline
# ==============================================================================
generar_stack_docker() {
    echo ""
    echo "[PROCESO] Generando archivo de orquestación docker-compose.yml..."
    
    local compose_file="$BASE_DIR/docker-compose.yml"
    
    # Validar si el archivo ya existe para no sobreescribir configuraciones manuales
    if [[ -f "$compose_file" ]]; then
        read -p "[ADVERTENCIA] El archivo docker-compose.yml ya existe. ¿Desea sobrescribirlo? (s/N): " sobreescribir
        if [[ "$sobreescribir" != "s" && "$sobreescribir" != "S" ]]; then
            echo "[INFO] Operación cancelada. Conservando el archivo existente."
        else
            crear_archivo_compose "$compose_file"
        fi
    else
        crear_archivo_compose "$compose_file"
    fi

    # Lógica Offline: Validar la existencia del motor Docker antes de operar con imágenes
    verificar_motor_docker
    
    # Si Docker se instaló o ya estaba activo, procedemos con las imágenes
    if command -v docker &> /dev/null; then
        echo ""
        echo "[PROCESO] Verificando caché local de imágenes Docker..."
        verificar_imagen "mailserver/docker-mailserver:latest"
        verificar_imagen "roundcube/roundcubemail:latest"
        echo "[ÉXITO] Generación de stack finalizada."
    else
        echo "[ERROR] El motor Docker no está disponible. Abortando verificación de imágenes."
    fi
}

# Sub-función: Validación e instalación offline de dependencias (Docker CE)
verificar_motor_docker() {
    echo ""
    echo "[PROCESO] Verificando dependencias del sistema (Motor Docker)..."
    if ! command -v docker &> /dev/null; then
        echo "  -> [FALTANTE] El comando 'docker' no se encontró en Oracle Linux."
        read -p "     ¿Desea configurar el repositorio y descargar Docker CE vía dnf ahora? (s/N): " instalar_dkr
        if [[ "$instalar_dkr" == "s" || "$instalar_dkr" == "S" ]]; then
            echo "     [PROCESO] Instalando utilidades core de dnf..."
            dnf install -y dnf-plugins-core > /dev/null 2>&1
            
            # Verificación offline del repositorio
            local repo_file="/etc/yum.repos.d/docker-ce.repo"
            if [[ ! -f "$repo_file" ]]; then
                echo "     [PROCESO] Descargando repositorio oficial de Docker..."
                dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null 2>&1
            else
                echo "     [CACHÉ] El repositorio docker-ce.repo ya existe localmente. Omitiendo descarga."
            fi
            
            echo "     [PROCESO] Ejecutando instalación de paquetes (docker-ce, cli, containerd, compose)..."
            dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1
            
            echo "     [PROCESO] Iniciando y habilitando el daemon de Docker..."
            systemctl enable --now docker
            echo "  -> [ÉXITO] Motor Docker instalado y operando correctamente."
        else
            echo "     [ADVERTENCIA] Instalación omitida. No se podrán gestionar los contenedores."
        fi
    else
        echo "  -> [OK] Motor Docker detectado en el sistema."
        # Garantizar que el demonio no esté apagado (ahorro de recursos manual)
        if ! systemctl is-active --quiet docker; then
            echo "     [PROCESO] El servicio Docker estaba inactivo. Levantando daemon..."
            systemctl start docker
        fi
    fi
}

# Sub-función: Escritura del YAML (Heredoc)
crear_archivo_compose() {
    local archivo=$1
    cat << 'EOF' > "$archivo"
services:
  mailserver:
    image: mailserver/docker-mailserver:latest
    container_name: mta_dovecot_reprobados
    hostname: mail.reprobados.com
    domainname: reprobados.com
    ports:
      - "25:25"     # SMTP entrante
      - "143:143"   # IMAP
      - "587:587"   # Submission
      - "993:993"   # IMAPS
    volumes:
      - ./mail_data:/var/mail
      - ./mail_state:/var/mail-state
      - ./mail_logs:/var/log/mail
      - ./mail_config:/tmp/docker-mailserver
      - /etc/localtime:/etc/localtime:ro
    environment:
      - ENABLE_SPAMASSASSIN=0
      - ENABLE_RSPAMD=1
      - ENABLE_CLAMAV=0
      - ENABLE_FAIL2BAN=1
      - ONE_DIR=1
      - OVERRIDE_HOSTNAME=mail.reprobados.com
    cap_add:
      - NET_ADMIN # Privilegio requerido por fail2ban para manipular iptables
    restart: unless-stopped

  webmail:
    image: roundcube/roundcubemail:latest
    container_name: webmail_reprobados
    ports:
      - "8080:80" # Expuesto al host en puerto 8080 para validación
    environment:
      - ROUNDCUBEMAIL_DEFAULT_HOST=mail.reprobados.com
      - ROUNDCUBEMAIL_SMTP_SERVER=mail.reprobados.com
    volumes:
      - ./webmail_html:/var/www/html
      - ./webmail_db:/var/roundcube/db
    depends_on:
      - mailserver
    restart: unless-stopped
EOF
    echo "  -> Archivo escrito correctamente en: $archivo"
}

# Sub-función: Control de descargas offline
verificar_imagen() {
    local imagen=$1
    # Verifica si la imagen existe evaluando la salida de docker images
    if docker images -q "$imagen" | grep -q .; then
        echo "  -> [CACHÉ] La imagen '$imagen' ya existe localmente. Omitiendo descarga de red."
    else
        echo "  -> [FALTANTE] La imagen '$imagen' no se encuentra en el repositorio local."
        read -p "     ¿Desea consumir ancho de banda y descargarla desde Docker Hub ahora? (s/N): " descargar
        if [[ "$descargar" == "s" || "$descargar" == "S" ]]; then
            echo "     [PROCESO] Ejecutando docker pull para $imagen..."
            docker pull "$imagen"
        else
            echo "     [ADVERTENCIA] Descarga omitida por el usuario."
        fi
    fi
}
