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


# ==============================================================================
# Función 3: Despliegue de contenedores y sincronización DNS en /etc/hosts
# ==============================================================================
levantar_servicios_y_dns() {
    echo ""
    echo "[PROCESO] Iniciando orquestación de contenedores..."
    
    cd "$BASE_DIR" || return
    
    # Levantar los contenedores en modo detached (segundo plano)
    docker compose up -d

    if [[ $? -eq 0 ]]; then
        echo "  -> [ÉXITO] Contenedores inicializados correctamente."
    else
        echo "  -> [ERROR] Falló la inicialización de contenedores. Revise los logs de docker."
        return 1
    fi

    echo ""
    echo "[PROCESO] Sincronizando DNS dinámico en /etc/hosts..."
    
    local host_entry="$DETECTED_IP mail.$DOMAIN $DOMAIN"
    
    # Crear respaldo del archivo hosts original por seguridad
    cp /etc/hosts /etc/hosts.bak_practica12
    echo "  -> Respaldo de seguridad creado en /etc/hosts.bak_practica12"

    # Verificar si el dominio ya existe en el archivo
    if grep -q "$DOMAIN" /etc/hosts; then
        echo "  -> [INFO] Se detectó una entrada previa para $DOMAIN. Actualizando..."
        # Eliminar las líneas viejas que contengan el dominio y añadir la nueva asegurando salto de línea
        sed -i "/$DOMAIN/d" /etc/hosts
        echo -e "\n$host_entry" >> /etc/hosts
    else
        # Inyectar la entrada asegurando que empiece en una línea nueva
        echo -e "\n$host_entry" >> /etc/hosts
    fi
    
    # Eliminar posibles líneas en blanco duplicadas generadas por el echo -e
    sed -i '/^$/N;/^\n$/D' /etc/hosts

    echo "  -> [ÉXITO] DNS Local configurado. El tráfico hacia mail.$DOMAIN se enrutará a $DETECTED_IP."
}

# ==============================================================================
# Función 4: Interfaz de gestión de cuentas (Integración con setup.sh)
# ==============================================================================
gestionar_cuentas_correo() {
    echo ""
    echo "[PROCESO] Módulo de Gestión de Identidades (Dovecot)"
    
    # Validar que el contenedor esté corriendo antes de inyectar comandos
    if ! docker ps | grep -q "mta_dovecot_reprobados"; then
        echo "  -> [ERROR] El contenedor principal de correo no está en ejecución."
        echo "  -> Ejecute la opción 3 primero."
        return 1
    fi

    echo "  Opciones de Identidad:"
    echo "  a) Crear nueva cuenta de correo"
    echo "  b) Listar cuentas existentes"
    read -p "  Seleccione una acción (a/b): " sub_opcion

    if [[ "$sub_opcion" == "a" || "$sub_opcion" == "A" ]]; then
        read -p "  Ingrese la dirección de correo (ej. director@$DOMAIN): " nueva_cuenta
        
        # Ocultar la contraseña en la terminal
        read -s -p "  Ingrese la contraseña para $nueva_cuenta: " password
        echo ""

        # Ejecutar el comando dentro del contenedor para añadir la cuenta
        docker exec -it mta_dovecot_reprobados setup email add "$nueva_cuenta" "$password"
        
        if [[ $? -eq 0 ]]; then
            echo "  -> [ÉXITO] Cuenta $nueva_cuenta aprovisionada en la base de datos de Dovecot."
        else
            echo "  -> [ERROR] No se pudo crear la cuenta."
        fi

    elif [[ "$sub_opcion" == "b" || "$sub_opcion" == "B" ]]; then
        echo "  -> Listado de cuentas activas:"
        docker exec -it mta_dovecot_reprobados setup email list
    else
        echo "  -> [ERROR] Opción inválida."
    fi
}

# ==============================================================================
# Función 5: Generación de claves DKIM para autenticación de origen
# ==============================================================================
generar_claves_dkim() {
    echo ""
    echo "[PROCESO] Generando pares de claves criptográficas DKIM..."

    if ! docker ps | grep -q "mta_dovecot_reprobados"; then
        echo "  -> [ERROR] El contenedor principal de correo no está en ejecución."
        return 1
    fi

    # Verificar si las claves ya existen para evitar sobreescritura (Ahorro de recursos)
    if docker exec -it mta_dovecot_reprobados ls /tmp/docker-mailserver/opendkim/keys/$DOMAIN/mail.private &> /dev/null; then
        echo "  -> [INFO] Las claves DKIM para $DOMAIN ya existen."
    else
        echo "  -> [PROCESO] Ejecutando utilidad de generación interna (setup config dkim)..."
        docker exec -it mta_dovecot_reprobados setup config dkim
        if [[ $? -eq 0 ]]; then
            echo "  -> [ÉXITO] Claves generadas exitosamente."
        else
            echo "  -> [ERROR] Falló la generación de las claves DKIM."
            return 1
        fi
    fi

    echo "  -> [ACCIÓN REQUERIDA] Para validar la práctica, el registro TXT generado se encuentra en:"
    echo "     $BASE_DIR/mail_config/opendkim/keys/$DOMAIN/mail.txt"
    echo "     Contenido de la clave pública para el DNS:"
    echo "----------------------------------------------------------------------"
    cat "$BASE_DIR/mail_config/opendkim/keys/$DOMAIN/mail.txt" 2>/dev/null || echo "     [ADVERTENCIA] No se pudo leer el archivo txt localmente."
    echo "----------------------------------------------------------------------"
}

# ==============================================================================
# Función 6: Sistema de recuperación ante desastres (Respaldos automatizados)
# ==============================================================================
configurar_respaldo_cron() {
    echo ""
    echo "[PROCESO] Configurando política de respaldos automatizados..."

    local backup_dir="$BASE_DIR/backups"
    local script_path="$BASE_DIR/backup_diario.sh"

    # Crear directorio de respaldos si no existe
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir"
        chown "$DETECTED_USER:$DETECTED_USER" "$backup_dir"
        echo "  -> Creado directorio de respaldos en: $backup_dir"
    fi

    # Crear el script de respaldo que ejecutará cron
    cat << EOF > "$script_path"
#!/bin/bash
# Script de respaldo automatizado para la Práctica 12
# Ejecución programada vía cron

FECHA=\$(date +"%Y%m%d_%H%M%S")
ARCHIVO_RESPALDO="$backup_dir/mail_backup_\$FECHA.tar.gz"

echo "[INFO] Iniciando respaldo de /var/mail a las \$(date)" >> "$backup_dir/backup.log"
tar -czf "\$ARCHIVO_RESPALDO" -C "$BASE_DIR" mail_data >> "$backup_dir/backup.log" 2>&1

if [[ \$? -eq 0 ]]; then
    echo "[ÉXITO] Respaldo creado: \$ARCHIVO_RESPALDO" >> "$backup_dir/backup.log"
else
    echo "[ERROR] Falló la creación del respaldo." >> "$backup_dir/backup.log"
fi

# Eliminar respaldos mayores a 7 días para ahorrar espacio
find "$backup_dir" -name "mail_backup_*.tar.gz" -type f -mtime +7 -exec rm {} \;
EOF

    chmod +x "$script_path"
    echo "  -> Script de respaldo generado en: $script_path"

    # Integración con el crontab del sistema (verificando existencia previa)
    local cron_job="0 2 * * * root $script_path"
    
    if grep -q "$script_path" /etc/crontab; then
        echo "  -> [INFO] La tarea programada ya existe en /etc/crontab. Omitiendo inyección."
    else
        echo "$cron_job" >> /etc/crontab
        systemctl reload crond 2>/dev/null || systemctl restart cron 2>/dev/null
        echo "  -> [ÉXITO] Tarea programada inyectada. Los respaldos se ejecutarán diariamente a las 02:00 AM."
    fi
}

# ==============================================================================
# Función 7: Inyección de parámetros corporativos en Roundcube
# ==============================================================================
personalizar_webmail() {
    echo ""
    echo "[PROCESO] Aplicando personalización institucional a Roundcube..."
    
    local config_file="$BASE_DIR/webmail_html/config/config.inc.php"
    local logo_file="$BASE_DIR/webmail_html/logo_institucional.svg"

    # 1. Generar logotipo vectorial offline
    cat << 'EOF' > "$logo_file"
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="50">
  <rect width="200" height="50" fill="#1c2833" rx="5"/>
  <text x="20" y="32" font-family="monospace" font-weight="bold" font-size="18" fill="#f1c40f">REPROBADOS</text>
  <text x="135" y="32" font-family="monospace" font-size="18" fill="#ecf0f1">.COM</text>
</svg>
EOF
    # Ajustar permisos para que el servidor web interno (www-data) pueda leerlo
    chmod 644 "$logo_file"
    echo "  -> [ÉXITO] Logotipo corporativo generado estáticamente en el volumen."

    # 2. Modificar el archivo de configuración si el contenedor ya lo aprovisionó
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "${config_file}.bak_practica12"
        
        # Inyectar el dominio predeterminado
        if grep -q "username_domain" "$config_file"; then
            sed -i "s/\$config\['username_domain'\].*/\$config\['username_domain'\] = '$DOMAIN';/g" "$config_file"
        else
            echo "\$config['username_domain'] = '$DOMAIN';" >> "$config_file"
        fi
        
        # Inyectar el logotipo
        if grep -q "skin_logo" "$config_file"; then
            sed -i "s|\$config\['skin_logo'\].*|\$config\['skin_logo'\] = 'logo_institucional.svg';|g" "$config_file"
        else
            echo "\$config['skin_logo'] = 'logo_institucional.svg';" >> "$config_file"
        fi
        
        echo "  -> [ÉXITO] Parámetros de Webmail actualizados (Dominio base y Logo)."
        echo "  -> [INFO] Puede acceder desde su navegador anfitrión en: http://192.168.1.15:8080"
    else
        echo "  -> [ADVERTENCIA] No se encontró config.inc.php."
        echo "     Asegúrese de que el contenedor de webmail haya inicializado correctamente."
    fi
}

# ==============================================================================
# Función 8: Panel de auditoría para pruebas de aceptación
# ==============================================================================
auditar_seguridad_logs() {
    echo ""
    echo "[PROCESO] Subsistema de Auditoría y Detección de Intrusos"
    echo "  a) Consultar estado del Firewall (Fail2Ban)"
    echo "  b) Extraer últimos registros de transferencia (mail.log)"
    read -p "  Seleccione una acción (a/b): " sub_opcion
    
    if [[ "$sub_opcion" == "a" || "$sub_opcion" == "A" ]]; then
        echo "  -> [SEGURIDAD] Consultando estado global de Fail2Ban..."
        docker exec -it mta_dovecot_reprobados fail2ban-client status
        echo ""
        echo "  -> [SEGURIDAD] Consultando celda específica de Dovecot (IMAP/POP3)..."
        docker exec -it mta_dovecot_reprobados fail2ban-client status dovecot
    elif [[ "$sub_opcion" == "b" || "$sub_opcion" == "B" ]]; then
        echo "  -> [AUDITORÍA] Últimas 15 transacciones registradas:"
        echo "----------------------------------------------------------------------"
        tail -n 15 "$BASE_DIR/mail_logs/mail.log" 2>/dev/null || echo "  [ERROR] Registro no disponible."
        echo "----------------------------------------------------------------------"
    else
        echo "  -> [ERROR] Opción inválida."
    fi
}
