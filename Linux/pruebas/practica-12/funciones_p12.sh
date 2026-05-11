#!/bin/bash
# ==============================================================================
# Script: funciones_p12.sh
# Descripción: Módulo de procesamiento y funciones para main_p12.sh.
# Cuentas configuradas: gustavo@reprobados.com | edna@reprobados.com
# ==============================================================================

# ==============================================================================
# Función 1: Preparación de la infraestructura externa
# ==============================================================================
preparar_entorno_base() {
    echo ""
    echo "[PROCESO] Iniciando construcción de infraestructura en $BASE_DIR..."

    if [[ -d "$BASE_DIR" ]]; then
        echo "[INFO] El directorio raíz ya existe. Verificando subdirectorios..."
    else
        echo "[INFO] Creando directorio raíz..."
        mkdir -p "$BASE_DIR"
    fi

    local directorios=(
        "mail_data" "mail_state" "mail_logs" "mail_config" "webmail_html" "webmail_db" "ssl_export"
    )

    for dir in "${directorios[@]}"; do
        if [[ ! -d "$BASE_DIR/$dir" ]]; then
            mkdir -p "$BASE_DIR/$dir"
            echo "  -> Creado: $BASE_DIR/$dir"
        else
            echo "  -> Omitido ya existe: $BASE_DIR/$dir"
        fi
    done

    echo "[PROCESO] Ajustando propiedad de los directorios a $DETECTED_USER..."
    chown -R "$DETECTED_USER:$DETECTED_USER" "$BASE_DIR"
    chmod -R 755 "$BASE_DIR"

    echo "[PROCESO] Configurando reglas de Firewall firewalld..."
    if systemctl is-active --quiet firewalld; then
        local puertos=(25/tcp 143/tcp 587/tcp 993/tcp 465/tcp 8080/tcp)
        for p in "${puertos[@]}"; do
            firewall-cmd --permanent --add-port="$p" >/dev/null 2>&1
        done
        firewall-cmd --reload >/dev/null 2>&1
        echo "  -> [ÉXITO] Puertos expuestos en el firewall nativo."
    else
        echo "  -> [INFO] Firewalld no está activo. Omitiendo configuración de puertos."
    fi

    # Generar certificado SSL automáticamente si no existe
    echo "[PROCESO] Verificando certificado SSL..."
    local ssl_dir="$BASE_DIR/mail_config/ssl"
    local cert="$ssl_dir/mail.reprobados.com-cert.pem"
    local key="$ssl_dir/mail.reprobados.com-key.pem"

    mkdir -p "$ssl_dir"

    if [[ -f "$cert" && -f "$key" ]]; then
        echo "  -> [INFO] Certificado SSL ya existe. Omitiendo generación."
    else
        echo "  -> Generando certificado SSL autofirmado con CA propia..."
        openssl req -new -x509 -days 3650 -nodes             -subj "/C=MX/ST=Sinaloa/L=LosMochis/O=Reprobados CA/CN=Reprobados Root CA"             -addext "basicConstraints=critical,CA:TRUE"             -addext "keyUsage=critical,keyCertSign,cRLSign"             -addext "subjectAltName=DNS:mail.reprobados.com,DNS:reprobados.com,IP:$DETECTED_IP"             -keyout "$key"             -out "$cert" 2>/dev/null
        chmod 600 "$key"
        chmod 644 "$cert"
        # Copiar también al directorio de exportación
        mkdir -p "$BASE_DIR/ssl_export"
        cp "$cert" "$BASE_DIR/ssl_export/reprobados_mail.crt"
        echo "  -> [ÉXITO] Certificado generado y listo para exportar."
    fi

    echo "[ÉXITO] Infraestructura de directorios preparada y securizada."
}

# ==============================================================================
# Función 2: Generación del stack y validación de imágenes offline
# ==============================================================================
generar_stack_docker() {
    echo ""
    echo "[PROCESO] Generando archivo de orquestación docker-compose.yml..."

    local compose_file="$BASE_DIR/docker-compose.yml"

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

    verificar_motor_docker

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

# ------------------------------------------------------------------------------
# Sub-función: Validación e instalación de Docker CE
# ------------------------------------------------------------------------------
verificar_motor_docker() {
    echo ""
    echo "[PROCESO] Verificando dependencias del sistema Motor Docker..."
    if ! command -v docker &> /dev/null; then
        echo "  -> [FALTANTE] El comando 'docker' no se encontró en Oracle Linux."
        read -p "     ¿Desea configurar el repositorio y descargar Docker CE vía dnf ahora? (s/N): " instalar_dkr
        if [[ "$instalar_dkr" == "s" || "$instalar_dkr" == "S" ]]; then
            dnf install -y dnf-plugins-core > /dev/null 2>&1
            local repo_file="/etc/yum.repos.d/docker-ce.repo"
            if [[ ! -f "$repo_file" ]]; then
                dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null 2>&1
            else
                echo "     [CACHÉ] Repositorio docker-ce.repo ya existe. Omitiendo descarga."
            fi
            dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null 2>&1
            systemctl enable --now docker
            echo "  -> [ÉXITO] Motor Docker instalado y operando correctamente."
        else
            echo "     [ADVERTENCIA] Instalación omitida."
        fi
    else
        echo "  -> [OK] Motor Docker detectado en el sistema."
        if ! systemctl is-active --quiet docker; then
            echo "     [PROCESO] El servicio Docker estaba inactivo. Levantando daemon..."
            systemctl start docker
        fi
    fi
}

# ------------------------------------------------------------------------------
# Sub-función: Escritura del YAML con red Docker explícita (FIX CRÍTICO)
# Sin red nombrada, el contenedor 'webmail' no puede resolver 'mailserver'
# por nombre dentro de Docker. También se añade ROUNDCUBEMAIL_SMTP_PORT y
# ROUNDCUBEMAIL_DEFAULT_PORT para que no queden en los defaults incorrectos.
# ------------------------------------------------------------------------------
crear_archivo_compose() {
    local archivo=$1
    cat << 'EOF' > "$archivo"
networks:
  mail_network:
    driver: bridge

services:
  mailserver:
    image: mailserver/docker-mailserver:latest
    container_name: mta_dovecot_reprobados
    hostname: mail.reprobados.com
    domainname: reprobados.com
    networks:
      - mail_network
    ports:
      - "25:25"
      - "143:143"
      - "587:587"
      - "993:993"
      - "465:465"
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
      - SSL_TYPE=manual
      - SSL_CERT_PATH=/tmp/docker-mailserver/ssl/mail.reprobados.com-cert.pem
      - SSL_KEY_PATH=/tmp/docker-mailserver/ssl/mail.reprobados.com-key.pem
    cap_add:
      - NET_ADMIN
    restart: unless-stopped

  webmail:
    image: roundcube/roundcubemail:latest
    container_name: webmail_reprobados
    networks:
      - mail_network
    ports:
      - "8080:80"
    environment:
      # Se usa el nombre del servicio Docker 'mailserver' para resolución interna
      # ssl:// fuerza IMAPS puerto 993 internamente entre contenedores
      - ROUNDCUBEMAIL_DEFAULT_HOST=ssl://mailserver
      - ROUNDCUBEMAIL_DEFAULT_PORT=993
      - ROUNDCUBEMAIL_SMTP_SERVER=tls://mailserver
      - ROUNDCUBEMAIL_SMTP_PORT=587
      # Dominio predeterminado en el login (el usuario escribe solo "gustavo")
      - ROUNDCUBEMAIL_USERNAME_DOMAIN=reprobados.com
      # Tiempo de expiración de sesión: 30 minutos de inactividad
      - ROUNDCUBEMAIL_SESSION_LIFETIME=30
    volumes:
      - ./webmail_html:/var/www/html/custom
      - ./webmail_db:/var/roundcube/db
    depends_on:
      - mailserver
    restart: unless-stopped
EOF
    echo "  -> Archivo escrito correctamente en: $archivo"
}

# ------------------------------------------------------------------------------
# Sub-función: Control de descargas offline
# ------------------------------------------------------------------------------
verificar_imagen() {
    local imagen=$1
    if docker images -q "$imagen" | grep -q .; then
        echo "  -> [CACHÉ] La imagen '$imagen' ya existe localmente. Omitiendo descarga."
    else
        echo "  -> [FALTANTE] La imagen '$imagen' no está en el repositorio local."
        read -p "     ¿Desea descargarla desde Docker Hub ahora? (s/N): " descargar
        if [[ "$descargar" == "s" || "$descargar" == "S" ]]; then
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

    docker compose up -d

    if [[ $? -eq 0 ]]; then
        echo "  -> [ÉXITO] Contenedores inicializados correctamente."
        echo "  -> [INFO] Esperando 15 segundos para que docker-mailserver termine de inicializar..."
        sleep 15
    else
        echo "  -> [ERROR] Falló la inicialización de contenedores. Revise los logs de docker."
        return 1
    fi

    echo ""
    echo "[PROCESO] Sincronizando DNS dinámico en /etc/hosts..."

    local host_entry="$DETECTED_IP mail.$DOMAIN $DOMAIN"

    cp /etc/hosts /etc/hosts.bak_practica12
    echo "  -> Respaldo de seguridad creado en /etc/hosts.bak_practica12"

    if grep -q "$DOMAIN" /etc/hosts; then
        echo "  -> [INFO] Entrada previa para $DOMAIN detectada. Actualizando..."
        sed -i "/$DOMAIN/d" /etc/hosts
        echo -e "\n$host_entry" >> /etc/hosts
    else
        echo -e "\n$host_entry" >> /etc/hosts
    fi

    sed -i '/^$/N;/^\n$/D' /etc/hosts

    echo "  -> [ÉXITO] DNS configurado. Tráfico hacia mail.$DOMAIN -> $DETECTED_IP"
    echo ""
    echo "  ================================================================"
    echo "  IMPORTANTE: En su PC física Windows, agregue esta línea al"
    echo "  archivo C:\\Windows\\System32\\drivers\\etc\\hosts como Administrador:"
    echo ""
    echo "  $DETECTED_IP    mail.$DOMAIN $DOMAIN"
    echo ""
    echo "  Esto permite que Thunderbird resuelva el hostname del certificado."
    echo "  ================================================================"
}

# ==============================================================================
# Función 4: Interfaz de gestión de cuentas
# ==============================================================================
gestionar_cuentas_correo() {
    echo ""
    echo "[PROCESO] Módulo de Gestión de Identidades Dovecot"

    if ! docker ps | grep -q "mta_dovecot_reprobados"; then
        echo "  -> [ERROR] El contenedor principal de correo no está en ejecución."
        echo "  -> Ejecute la opción 3 primero."
        return 1
    fi

    echo "  Opciones de Identidad:"
    echo "  a Crear nueva cuenta de correo"
    echo "  b Listar cuentas existentes"
    read -p "  Seleccione una acción (a/b): " sub_opcion

    if [[ "$sub_opcion" == "a" || "$sub_opcion" == "A" ]]; then
        read -p "  Ingrese la dirección de correo (ej. gustavo@$DOMAIN): " nueva_cuenta
        read -s -p "  Ingrese la contraseña para $nueva_cuenta: " password
        echo ""
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
# Función 5: Generación de claves DKIM
# ==============================================================================
generar_claves_dkim() {
    echo ""
    echo "[PROCESO] Generando pares de claves criptográficas DKIM..."

    if ! docker ps | grep -q "mta_dovecot_reprobados"; then
        echo "  -> [ERROR] El contenedor principal de correo no está en ejecución."
        return 1
    fi

    if docker exec mta_dovecot_reprobados ls /tmp/docker-mailserver/opendkim/keys/$DOMAIN/mail.private &>/dev/null; then
        echo "  -> [INFO] Las claves DKIM para $DOMAIN ya existen. No se sobreescribirán."
    else
        echo "  -> [PROCESO] Ejecutando generación interna setup config dkim..."
        docker exec mta_dovecot_reprobados setup config dkim
        if [[ $? -eq 0 ]]; then
            echo "  -> [ÉXITO] Claves DKIM generadas exitosamente."
        else
            echo "  -> [ERROR] Falló la generación de las claves DKIM."
            return 1
        fi
    fi

    echo "  -> Registro TXT para DNS clave pública:"
    echo "----------------------------------------------------------------------"
    cat "$BASE_DIR/mail_config/opendkim/keys/$DOMAIN/mail.txt" 2>/dev/null \
        || echo "     [ADVERTENCIA] No se pudo leer el archivo localmente."
    echo "----------------------------------------------------------------------"
}

# ==============================================================================
# Función 6: Respaldos automatizados con cron
# ==============================================================================
configurar_respaldo_cron() {
    echo ""
    echo "[PROCESO] Configurando política de respaldos automatizados..."

    local backup_dir="$BASE_DIR/backups"
    local script_path="$BASE_DIR/backup_diario.sh"

    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir"
        chown "$DETECTED_USER:$DETECTED_USER" "$backup_dir"
        echo "  -> Creado directorio de respaldos en: $backup_dir"
    fi

    cat << EOF > "$script_path"
#!/bin/bash
# Script de respaldo automatizado - Práctica 12

FECHA=\$(date +"%Y%m%d_%H%M%S")
ARCHIVO_RESPALDO="$backup_dir/mail_backup_\$FECHA.tar.gz"

echo "[INFO] Iniciando respaldo a las \$date" >> "$backup_dir/backup.log"
tar -czf "\$ARCHIVO_RESPALDO" -C "$BASE_DIR" mail_data >> "$backup_dir/backup.log" 2>&1

if [[ \$? -eq 0 ]]; then
    echo "[ÉXITO] Respaldo creado: \$ARCHIVO_RESPALDO" >> "$backup_dir/backup.log"
else
    echo "[ERROR] Falló la creación del respaldo." >> "$backup_dir/backup.log"
fi

# Eliminar respaldos mayores a 7 días
find "$backup_dir" -name "mail_backup_*.tar.gz" -type f -mtime +7 -exec rm {} \;
EOF

    chmod +x "$script_path"
    echo "  -> Script de respaldo generado en: $script_path"

    local cron_job="0 2 * * * root $script_path"
    if grep -q "$script_path" /etc/crontab; then
        echo "  -> [INFO] La tarea ya existe en /etc/crontab. Omitiendo inyección."
    else
        echo "$cron_job" >> /etc/crontab
        systemctl reload crond 2>/dev/null || systemctl restart cron 2>/dev/null
        echo "  -> [ÉXITO] Tarea programada: respaldos diarios a las 02:00 AM."
    fi
}

# ==============================================================================
# Función 7: Personalización institucional de Roundcube
# ==============================================================================
personalizar_webmail() {
    echo ""
    echo "[PROCESO] Aplicando personalización institucional a Roundcube..."

    # El volumen mapea ./webmail_html -> /var/www/html/custom dentro del contenedor
    # El config real de roundcube está en /var/roundcube/config/ dentro del contenedor
    local logo_dir="$BASE_DIR/webmail_html"
    local logo_file="$logo_dir/logo_institucional.svg"

    mkdir -p "$logo_dir"

    # 1. Generar logotipo vectorial
    cat << 'EOF' > "$logo_file"
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="50">
  <rect width="200" height="50" fill="#1c2833" rx="5"/>
  <text x="20" y="32" font-family="monospace" font-weight="bold" font-size="18" fill="#f1c40f">REPROBADOS</text>
  <text x="135" y="32" font-family="monospace" font-size="18" fill="#ecf0f1">.COM</text>
</svg>
EOF
    chmod 644 "$logo_file"
    echo "  -> [ÉXITO] Logotipo corporativo generado en el volumen."

    # 2. Aplicar configuración adicional vía exec dentro del contenedor
    if docker ps | grep -q "webmail_reprobados"; then
        echo "  -> [PROCESO] Inyectando configuración adicional en el contenedor Roundcube..."
        docker exec webmail_reprobados sh -c "
            CONFIG_FILE='/var/roundcube/config/config.inc.php'
            if [ -f \"\$CONFIG_FILE\" ]; then
                # Dominio predeterminado
                grep -q 'username_domain' \"\$CONFIG_FILE\" || \
                    echo \"\\\$config['username_domain'] = 'reprobados.com';\" >> \"\$CONFIG_FILE\"
                # Timeout de sesión (30 min)
                grep -q 'session_lifetime' \"\$CONFIG_FILE\" || \
                    echo \"\\\$config['session_lifetime'] = 30;\" >> \"\$CONFIG_FILE\"
                echo 'Config aplicada exitosamente.'
            else
                echo 'ADVERTENCIA: config.inc.php no encontrado aún.'
            fi
        " 2>/dev/null && echo "  -> [ÉXITO] Parámetros de sesión y dominio aplicados." \
                       || echo "  -> [ADVERTENCIA] No se pudo inyectar config. El contenedor puede estar inicializando."
    else
        echo "  -> [ADVERTENCIA] El contenedor webmail_reprobados no está corriendo."
        echo "     Ejecute la opción 3 primero y luego regrese aquí."
    fi

    echo "  -> [INFO] Acceso desde su PC física: http://$DETECTED_IP:8080"
    echo "  -> [INFO] Usuario de prueba: gustavo sin @$DOMAIN si DOMAIN está configurado"
}

# ==============================================================================
# Función 8: Panel de auditoría y gestión de bloqueos
# ==============================================================================
auditar_seguridad_logs() {
    echo ""
    echo "[PROCESO] Subsistema de Auditoría y Detección de Intrusos"
    echo "  a) Consultar estado del Firewall (Fail2Ban)"
    echo "  b) Extraer últimos registros de transferencia (mail.log)"
    echo "  c) Liberar TODAS las IPs bloqueadas (Unban All)"
    read -p "  Seleccione una acción (a/b/c): " sub_opcion

    if [[ "$sub_opcion" == "a" || "$sub_opcion" == "A" ]]; then
        echo "  -> [SEGURIDAD] Estado global de Fail2Ban:"
        docker exec -it mta_dovecot_reprobados fail2ban-client status
        echo ""
        echo "  -> [SEGURIDAD] Celda específica de Dovecot:"
        docker exec -it mta_dovecot_reprobados fail2ban-client status dovecot
        
    elif [[ "$sub_opcion" == "b" || "$sub_opcion" == "B" ]]; then
        echo "  -> [AUDITORÍA] Últimas 20 transacciones registradas:"
        echo "----------------------------------------------------------------------"
        tail -n 20 "$BASE_DIR/mail_logs/mail.log" 2>/dev/null \
            || docker logs mta_dovecot_reprobados 2>&1 | tail -n 20
        echo "----------------------------------------------------------------------"
        
    elif [[ "$sub_opcion" == "c" || "$sub_opcion" == "C" ]]; then
        echo "  -> [SEGURIDAD] Ejecutando liberación masiva de IPs..."
        local ips_liberadas=$(docker exec -it mta_dovecot_reprobados fail2ban-client unban --all 2>/dev/null)
        
        # Filtrar la salida para que sea amigable a la vista
        ips_liberadas=$(echo "$ips_liberadas" | tr -d '\r')
        if [[ "$ips_liberadas" == "0" ]]; then
            echo "  -> [INFO] No había ninguna IP bloqueada en este momento."
        elif [[ "$ips_liberadas" =~ ^[0-9]+$ ]]; then
            echo "  -> [ÉXITO] Se han desbloqueado y perdonado $ips_liberadas direcciones IP."
        else
            echo "  -> [ÉXITO] Limpieza ejecutada. (Salida del sistema: $ips_liberadas)"
        fi
        
    else
        echo "  -> [ERROR] Opción inválida."
    fi
}

# ==============================================================================
# Función 10: Exportar certificado SSL e instrucciones para Thunderbird en Windows
# FIX CRÍTICO: Thunderbird en Windows necesita el .crt físico para importarlo
# como CA de confianza ANTES de configurar la cuenta con SSL/TLS estricto.
# ==============================================================================
exportar_certificado_ssl() {
    echo ""
    echo "[PROCESO] Exportando certificado SSL autofirmado del contenedor..."

    if ! docker ps | grep -q "mta_dovecot_reprobados"; then
        echo "  -> [ERROR] El contenedor no está corriendo. Ejecute la opción 3 primero."
        return 1
    fi

    local cert_dir="$BASE_DIR/ssl_export"
    mkdir -p "$cert_dir"

    # Esperar hasta 60 segundos a que docker-mailserver genere el certificado
    echo "  -> Esperando que docker-mailserver genere el certificado hasta 60s..."
    local intentos=0
    # Con SSL_TYPE=manual el certificado vive en el volumen del host.
    # No hay que buscarlo dentro del contenedor: ya está en mail_config/ssl/
    local cert_origen="$BASE_DIR/mail_config/ssl/mail.reprobados.com-cert.pem"

    echo "  -> Buscando certificado en el volumen del host $cert_origen..."
    if [[ -f "$cert_origen" ]]; then
        echo "  -> [ÉXITO] Certificado encontrado en el volumen."
        cp "$cert_origen" "$cert_dir/reprobados_mail.crt"
    else
        echo "  -> [ERROR] No se encontró el certificado en $cert_origen"
        echo "     Genérelo con:"
        echo "     sudo mkdir -p /opt/practica12/mail_config/ssl"
        echo "     sudo openssl req -new -x509 -days 3650 -nodes"
        echo "       -subj /CN=mail.reprobados.com"
        echo "       -keyout /opt/practica12/mail_config/ssl/mail.reprobados.com-key.pem"
        echo "       -out /opt/practica12/mail_config/ssl/mail.reprobados.com-cert.pem"
                return 1
    fi

    if [[ -s "$cert_dir/reprobados_mail.crt" ]]; then
        # Mostrar info del certificado
        echo ""
        echo "  -> [ÉXITO] Certificado exportado en: $cert_dir/reprobados_mail.crt"
        echo "  -> Información del certificado:"
        echo "----------------------------------------------------------------------"
        openssl x509 -in "$cert_dir/reprobados_mail.crt" -noout \
            -subject -issuer -dates 2>/dev/null \
            || echo "     openssl no disponible para mostrar detalles"
        echo "----------------------------------------------------------------------"

        echo ""
        echo "  ================================================================"
        echo "  PASO 1: COPIAR EL CERTIFICADO A SU PC WINDOWS"
        echo "  ================================================================"
        echo "  El archivo está en el servidor Oracle Linux en:"
        echo "  $cert_dir/reprobados_mail.crt"
        echo ""
        echo "  Cópielo a su PC Windows con SCP desde PowerShell o CMD:"
        echo "  scp $DETECTED_USER@$DETECTED_IP:$cert_dir/reprobados_mail.crt C:\\Users\\%USERNAME%\\Desktop\\"
        echo ""
        echo "  O si usa una VM con carpeta compartida, cópielo desde ahí."
        echo ""
        echo "  ================================================================"
        echo "  PASO 2: AGREGAR HOSTNAME AL ARCHIVO HOSTS DE WINDOWS"
        echo "  ================================================================"
        echo "  Abra NOTEPAD como Administrador y edite:"
        echo "  C:\\Windows\\System32\\drivers\\etc\\hosts"
        echo ""
        echo "  Agregue esta línea al final:"
        echo "  $DETECTED_IP    mail.reprobados.com reprobados.com"
        echo ""
        echo "  Esto es OBLIGATORIO para que el CN del certificado coincida."
        echo ""
        echo "  ================================================================"
        echo "  PASO 3: IMPORTAR EL CERTIFICADO EN THUNDERBIRD WINDOWS"
        echo "  ================================================================"
        echo "  1. Abra Thunderbird"
        echo "  2. Menú hamburguesa ≡ -> Herramientas -> Opciones"
        echo "  3. Panel izquierdo: 'Privacidad y seguridad'"
        echo "  4. Baje hasta la sección 'Certificados'"
        echo "  5. Clic en 'Administrar certificados...'"
        echo "  6. Pestaña 'Autoridades' -> clic en 'Importar...'"
        echo "  7. Seleccione: reprobados_mail.crt del escritorio"
        echo "  8. Marque AMBAS casillas:"
        echo "     [x] Confiar en esta CA para identificar sitios web"
        echo "     [x] Confiar en esta CA para identificar usuarios de correo"
        echo "  9. Clic en OK y cierre el administrador de certificados"
        echo ""
        echo "  ================================================================"
        echo "  PASO 4: CONFIGURAR LA CUENTA EN THUNDERBIRD"
        echo "  ================================================================"
        echo "  Menú ≡ -> Nueva cuenta -> Correo electrónico existente"
        echo ""
        echo "  Nombre:    Gustavo o el que prefiera mostrar"
        echo "  Email:     gustavo@reprobados.com"
        echo "  Contraseña: la que asignó en la opción 4"
        echo ""
        echo "  -> Clic en 'Configurar manualmente' y use ESTOS valores exactos:"
        echo ""
        echo "  ENTRANTE IMAP:"
        echo "    Servidor:   mail.reprobados.com   <- NO use la IP aquí"
        echo "    Puerto:     993"
        echo "    Seguridad:  SSL/TLS"
        echo "    Autent.:    Contraseña normal"
        echo "    Usuario:    gustavo@reprobados.com"
        echo ""
        echo "  SALIENTE SMTP:"
        echo "    Servidor:   mail.reprobados.com   <- NO use la IP aquí"
        echo "    Puerto:     465"
        echo "    Seguridad:  SSL/TLS"
        echo "    Autent.:    Contraseña normal"
        echo "    Usuario:    gustavo@reprobados.com"
        echo ""
        echo "  IMPORTANTE: Debe usar 'mail.reprobados.com' no la IP porque"
        echo "  el certificado fue emitido para ese hostname. Si usa la IP"
        echo "  directa, el certificado no coincidirá y Thunderbird rechazará."
        echo "  ================================================================"
    else
        echo "  -> [ERROR] No se pudo extraer el certificado."
        echo "     Ejecute: docker logs mta_dovecot_reprobados | tail -30"
        echo "     para ver si hay errores de inicialización."
    fi
}

# ==============================================================================
# Función 11: Instrucciones definitivas para Thunderbird sin ciclo de error
# El problema del ciclo ocurre porque Thunderbird verifica SSL en tiempo real.
# La solución es importar el cert en Windows Certificate Store (no solo Thunderbird)
# ==============================================================================
configurar_thunderbird_windows() {
    echo ""
    echo "[PROCESO] Guía definitiva para configurar Thunderbird sin errores de SSL"
    echo ""
    local cert_path="$BASE_DIR/ssl_export/reprobados_mail.crt"

    if [[ ! -f "$cert_path" ]]; then
        cp "$BASE_DIR/mail_config/ssl/mail.reprobados.com-cert.pem" "$cert_path" 2>/dev/null
    fi

    echo "  ================================================================"
    echo "  SOLUCIÓN AL CICLO DE ERROR EN THUNDERBIRD"
    echo "  ================================================================"
    echo "  El ciclo ocurre porque Thunderbird verifica el certificado"
    echo "  en tiempo real al hacer 'Probar'. La solución es instalar"
    echo "  el certificado en Windows ANTES de abrir Thunderbird."
    echo ""
    echo "  PASO 1: Copiar el certificado a Windows"
    echo "  En PowerShell de Windows como Administrador:"
    echo "  scp \$DETECTED_USER@\$DETECTED_IP:\$cert_path  ->  Escritorio de Windows"
    echo ""
    echo "  PASO 2: Instalar en el almacen de Windows, no solo en Thunderbird"
    echo "  En PowerShell como Administrador ejecute:"
    echo '  Import-Certificate -FilePath "$env:USERPROFILE\Desktop\reprobados_mail.crt" -CertStoreLocation Cert:\LocalMachine\Root'
    echo ""
    echo "  PASO 3: Importar también en Thunderbird"
    echo "  Herramientas -> Opciones -> Privacidad -> Administrar certificados"
    echo "  -> Autoridades -> Importar -> seleccionar reprobados_mail.crt"
    echo "  -> Marcar AMBAS casillas -> Aceptar"
    echo ""
    echo "  PASO 4: Configurar cuenta en Thunderbird SIN usar el boton Probar"
    echo "  - Nueva cuenta -> Correo electrónico existente"
    echo "  - Email: gustavo@reprobados.com  Contraseña: la que asigno en la opcion 4"
    echo "  - Clic en 'Configuración manual'"
    echo "  - IMAP: mail.reprobados.com  Puerto: 993  SSL/TLS  gustavo@reprobados.com"
    echo "  - SMTP: mail.reprobados.com  Puerto: 465  SSL/TLS  gustavo@reprobados.com"
    echo "  - Clic en 'Continuar', no en Probar"
    echo "  - Si pide contraseña: ingresarla y marcar 'Recordar'"
    echo "  - La cuenta se creará y conectará correctamente"
    echo ""
    echo "  IMPORTANTE: El boton Probar falla con certificados autofirmados"
    echo "  incluso cuando el certificado está instalado. Usar 'Continuar'"
    echo "  directamente es el flujo correcto para servidores locales."
    echo "  ================================================================"
    echo ""
    echo "  Certificado disponible en: $cert_path"
    echo "  SCP desde Windows: scp $DETECTED_USER@$DETECTED_IP:$cert_path ."
}

# ==============================================================================
# Función 9: Submenú de Pruebas de Aceptación
# ==============================================================================
submenu_pruebas() {
    while true; do
        echo ""
        echo "======================================================================"
        echo "                 SUBMENÚ - PRUEBAS DE ACEPTACIÓN                      "
        echo "======================================================================"
        echo " 1. Prueba 12.1: Envío y recepción local Thunderbird"
        echo " 2. Prueba 12.2: Auditoría de registros Logging"
        echo " 3. Prueba 12.3: Verificación de seguridad Fail2ban"
        echo " 4. Prueba 13.4: Integridad de respaldo"
        echo " 5. Prueba 13.5: Inicio de sesión institucional Webmail"
        echo " 6. Prueba 13.6: Envío de adjuntos y seguridad Webmail"
        echo " 7. Prueba 13.7: Persistencia de preferencias Webmail"
        echo " 0. Retornar al Menú Principal"
        echo "======================================================================"
        read -p " Seleccione la prueba a ejecutar: " op_prueba

        case $op_prueba in
            1) prueba_12_1 ;;
            2) prueba_12_2 ;;
            3) prueba_12_3 ;;
            4) prueba_13_4 ;;
            5) prueba_13_5 ;;
            6) prueba_13_6 ;;
            7) prueba_13_7 ;;
            0)
                echo "  -> [INFO] Cerrando módulo de pruebas y retornando..."
                break
                ;;
            *)
                echo "  -> [ERROR] Opción no válida."
                ;;
        esac
    done
}

# ==============================================================================
# Controladores de Pruebas Individuales
# ==============================================================================

prueba_12_1() {
    echo ""
    echo "[PRUEBA 12.1: ENVÍO Y RECEPCIÓN LOCAL]"
    echo "----------------------------------------------------------------------"
    echo "  Resultado esperado: Correo entre gustavo@ y edna@ sin errores de cifrado."
    echo ""
    echo "  PRE-REQUISITOS verifique antes de continuar:"
    echo "  [ ] Ha ejecutado la Opción 10 y exportado el certificado"
    echo "  [ ] Ha importado el certificado .crt en Thunderbird Paso 3 de opción 10"
    echo "  [ ] Ha agregado '$DETECTED_IP mail.reprobados.com' al hosts de Windows"
    echo "  [ ] Ha configurado AMBAS cuentas en Thunderbird gustavo y edna"
    echo ""
    echo "  PROCEDIMIENTO:"
    echo "  1. En Thunderbird, seleccione la cuenta gustavo@$DOMAIN"
    echo "  2. Clic en 'Redactar nuevo mensaje'"
    echo "  3. Para: edna@$DOMAIN"
    echo "  4. Asunto: Prueba 12.1 - Verificacion SSL"
    echo "  5. Cuerpo: 'Correo de prueba con SSL/TLS nativo activado.'"
    echo "  6. Clic en Enviar"
    echo "  7. Cambie a la cuenta edna@$DOMAIN"
    echo "  8. Clic en 'Obtener mensajes' y verifique que el correo llega"
    echo "  9. El candado en la barra de estado de Thunderbird debe estar CERRADO"
    echo "     indica que la conexión es cifrada con SSL/TLS"
    echo ""
    echo "  VERIFICACIÓN EXTRA desde el servidor:"
    echo "  Puede ver la entrega en tiempo real ejecutando la Opción 8 -> b"
    echo ""
    read -p "  Presione ENTER una vez validada la prueba..."
}

prueba_12_2() {
    echo ""
    echo "[PRUEBA 12.2: AUDITORÍA DE REGISTROS LOGGING]"
    echo "----------------------------------------------------------------------"
    echo "  [EJECUCIÓN AUTOMATIZADA]"

    # Obtener cuentas y construir menú numerado
    echo "  -> Obteniendo cuentas disponibles en el servidor..."
    local cuentas_raw
    cuentas_raw=$(docker exec mta_dovecot_reprobados setup email list 2>/dev/null)

    if [[ -z "$cuentas_raw" ]]; then
        echo "  -> [ERROR] No hay cuentas creadas. Ejecute la Opción 4 primero."
        read -p "  Presione ENTER para continuar..."
        return 1
    fi

    echo ""
    echo "  Cuentas registradas en el servidor:"
    echo "----------------------------------------------------------------------"
    local i=1
    local -a lista_cuentas
    while IFS= read -r linea; do
        if [[ -n "$linea" ]]; then
            echo "  $i $linea"
            lista_cuentas+=("$linea")
            i=$((i + 1))
        fi
    done <<< "$cuentas_raw"
    echo "----------------------------------------------------------------------"

    local cuenta_destino=""
    while [[ -z "$cuenta_destino" ]]; do
        read -p "  Seleccione el NÚMERO de la cuenta DESTINO del correo de prueba: " seleccion
        if [[ "$seleccion" =~ ^[0-9]+$ ]] && \
           [[ "$seleccion" -ge 1 ]] && \
           [[ "$seleccion" -le "${#lista_cuentas[@]}" ]]; then
            cuenta_destino="${lista_cuentas[$((seleccion - 1))]}"
        else
            echo "  -> [ERROR] Número inválido. Elija entre 1 y ${#lista_cuentas[@]}."
        fi
    done

    echo "  -> Destino seleccionado: $cuenta_destino"
    echo "  -> Inyectando correo de prueba hacia $cuenta_destino ..."
    docker exec mta_dovecot_reprobados sh -c \
        "echo -e 'Subject: Prueba Auditoria Log\nFrom: sistema@$DOMAIN\nTo: $cuenta_destino\n\nVerificacion de trazabilidad completa.' | sendmail $cuenta_destino" 2>/dev/null
    sleep 3

    echo "  -> Extrayendo flujo transaccional del log últimas 20 líneas:"
    echo "----------------------------------------------------------------------"
    # Intentar primero el archivo mapeado al host
    if [[ -f "$BASE_DIR/mail_logs/mail.log" ]]; then
        tail -n 20 "$BASE_DIR/mail_logs/mail.log"
    else
        # Fallback: leer desde docker logs
        docker logs mta_dovecot_reprobados 2>&1 | tail -n 20
    fi
    echo "----------------------------------------------------------------------"
    echo ""
    echo "  ¿Qué buscar en los logs para aprobar esta prueba?"
    echo "  - Líneas con 'postfix/smtp' o 'postfix/local' indican ENTREGA del mensaje"
    echo "  - Líneas con 'status=sent' indican ÉXITO en la transferencia"
    echo "  - Líneas con 'dovecot' indican actividad del protocolo IMAP"
    echo "  - Líneas con 'login:' indican autenticación de usuario"
    echo ""
    read -p "  Presione ENTER para continuar..."
}

prueba_12_3() {
    echo ""
    echo "[PRUEBA 12.3: VERIFICACIÓN DE SEGURIDAD FAIL2BAN]"
    echo "----------------------------------------------------------------------"
    echo "  [EJECUCIÓN AUTOMATIZADA]"
    echo "  -> Simulando 6 intentos de login fallidos contra IMAP SSL puerto 993..."
    echo ""
    echo "  NOTA: Los intentos se realizan desde dentro del contenedor hacia sí"
    echo "  mismo usando una IP de loopback interna. Fail2Ban detectará el patrón"
    echo "  de fallos en los logs de Dovecot y bloqueará la IP de origen."
    echo ""

    # FIX CRÍTICO: El ataque debe hacerse contra el puerto IMAP plano (143) internamente
    # porque Fail2Ban en docker-mailserver monitorea los logs de auth de Dovecot.
    # Usamos 'nc' (netcat) que viene incluido en la imagen docker-mailserver.
    # El protocolo IMAP es texto plano, enviamos LOGIN inválido y cerramos.
    for i in {1..6}; do
        echo "     Intento de login fallido $i/6..."
        # Intentar autenticación IMAP fallida directo al puerto 143 interno
        docker exec mta_dovecot_reprobados sh -c \
            "echo -e 'a$i LOGIN atacante_brute password_incorrecta_$i\r\na$i LOGOUT\r\n' \
            | timeout 3 nc -q 1 127.0.0.1 143 2>/dev/null || true" 2>/dev/null
        sleep 2
    done

    echo ""
    echo "  -> Esperando 5 segundos para que Fail2Ban procese los logs..."
    sleep 5

    echo "  -> Consultando estado de Fail2Ban:"
    echo "----------------------------------------------------------------------"
    docker exec mta_dovecot_reprobados fail2ban-client status 2>/dev/null \
        || echo "  [INFO] Fail2Ban puede estar inicializando. Intente la Opción 8 -> a"
    echo ""
    docker exec mta_dovecot_reprobados fail2ban-client status dovecot 2>/dev/null \
        || echo "  [INFO] La celda 'dovecot' puede no estar activa aún."
    echo "----------------------------------------------------------------------"
    echo ""
    echo "  ¿Qué buscar para aprobar esta prueba?"
    echo "  - 'Currently banned: 1' o mayor en la sección de la celda dovecot"
    echo "  - Si no aparece bloqueada aún, espere 30 segundos y ejecute la Opción 8 -> a"
    echo ""
    echo "  ALTERNATIVA MANUAL desde su PC Windows para un resultado más claro:"
    echo "  Abra PowerShell y ejecute 6 veces seguidas:"
    echo "  telnet $DETECTED_IP 143"
    echo "  Luego escriba: a1 LOGIN usuario password_incorrecta"
    echo "  La IP de su PC $DETECTED_IP física quedará bloqueada."
    echo ""
    read -p "  Presione ENTER para continuar..."
}

prueba_13_4() {
    echo ""
    echo "[PRUEBA 13.4: INTEGRIDAD DE RESPALDO]"
    echo "----------------------------------------------------------------------"
    echo "  [EJECUCIÓN HÍBRIDA]"

    # Verificar que el script de backup existe
    if [[ ! -f "$BASE_DIR/backup_diario.sh" ]]; then
        echo "  -> [ERROR] No existe el script de respaldo. Ejecute la Opción 6 primero."
        read -p "  Presione ENTER para continuar..."
        return 1
    fi

    echo "  -> Fase 1: Creando respaldo del estado ACTUAL de los buzones..."
    bash "$BASE_DIR/backup_diario.sh"

    local ultimo_respaldo
    ultimo_respaldo=$(ls -t "$BASE_DIR/backups/"mail_backup_*.tar.gz 2>/dev/null | head -n 1)

    if [[ -z "$ultimo_respaldo" ]]; then
        echo "  -> [ERROR] No se encontró ningún respaldo. Verifique el script de backup."
        read -p "  Presione ENTER para continuar..."
        return 1
    fi

    echo "  -> Respaldo generado: $basename "$ultimo_respaldo""
    echo "  -> Tamaño: $du -sh "$ultimo_respaldo" | cut -f1"
    echo ""
    echo "  -> Fase 2: ACCIÓN MANUAL REQUERIDA"
    echo "     1. Vaya a Thunderbird o Roundcube"
    echo "     2. ELIMINE permanentemente un correo existente Shift+Supr en Thunderbird"
    echo "     3. Confirme la eliminación"
    read -p "     Presione ENTER DESPUÉS de haber eliminado el correo..."

    echo ""
    echo "  -> Fase 3: Deteniendo el contenedor de correo..."
    docker compose -f "$BASE_DIR/docker-compose.yml" stop mailserver
    sleep 3

    echo "  -> Fase 4: Restaurando volumen desde el respaldo comprimido..."
    # Eliminar datos actuales y restaurar desde backup
    rm -rf "$BASE_DIR/mail_data"
    tar -xzf "$ultimo_respaldo" -C "$BASE_DIR"

    if [[ $? -eq 0 ]]; then
        echo "  -> [ÉXITO] Volumen restaurado desde: $basename "$ultimo_respaldo""
    else
        echo "  -> [ERROR] Falló la restauración del volumen."
        read -p "  Presione ENTER para continuar..."
        return 1
    fi

    echo "  -> Fase 5: Reiniciando el contenedor de correo..."
    docker compose -f "$BASE_DIR/docker-compose.yml" start mailserver
    echo "  -> Esperando 10 segundos para que Dovecot reinicialice..."
    sleep 10

    echo ""
    echo "  ================================================================"
    echo "  VERIFICACIÓN:"
    echo "  1. Vaya a Thunderbird -> haga clic en 'Obtener mensajes'"
    echo "  2. El correo que eliminó debería haber reaparecido"
    echo "  3. Abra el correo y verifique que el contenido y metadatos"
    echo "     fecha, remitente, asunto estén intactos"
    echo "  ================================================================"
    echo ""
    read -p "  Presione ENTER una vez confirmada la restauración..."
}

prueba_13_5() {
    echo ""
    echo "[PRUEBA 13.5: INICIO DE SESIÓN INSTITUCIONAL WEBMAIL]"
    echo "----------------------------------------------------------------------"
    echo "  [VERIFICACIÓN AUTOMATIZADA DEL SERVICIO]"

    # Verificar que el puerto 8080 responde
    echo "  -> Comprobando disponibilidad del portal Roundcube..."
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080" 2>/dev/null | grep -q "200\|302"; then
        echo "  -> [ÉXITO] El portal Roundcube responde correctamente en el puerto 8080."
    else
        echo "  -> [ADVERTENCIA] El portal no respondió. Verificando estado del contenedor..."
        docker ps | grep webmail_reprobados
    fi

    echo ""
    echo "  [EJECUCIÓN MANUAL DESDE SU PC WINDOWS]"
    echo "  1. Abra Chrome o Firefox"
    echo "  2. Navegue a: http://$DETECTED_IP:8080"
    echo "  3. Aparecerá la pantalla de login de Roundcube"
    echo "  4. Usuario:    gustavo  solo el nombre, sin @$DOMAIN si el dominio está preconfigurado"
    echo "     O bien:    gustavo@$DOMAIN  con dominio completo, siempre funciona"
    echo "  5. Contraseña: la que asignó en la Opción 4"
    echo "  6. Clic en 'Entrar'"
    echo "  7. Debe ver la bandeja de entrada con los correos existentes"
    echo ""
    echo "  Si Roundcube da error de conexión al servidor IMAP:"
    echo "  - Espere 2 minutos más docker-mailserver tarda en estabilizarse"
    echo "  - Ejecute: docker logs mta_dovecot_reprobados | tail -20"
    echo ""
    read -p "  Presione ENTER una vez validado el inicio de sesión..."
}

prueba_13_6() {
    echo ""
    echo "[PRUEBA 13.6: ENVÍO DE ADJUNTOS Y SEGURIDAD WEBMAIL]"
    echo "----------------------------------------------------------------------"
    echo "  [EJECUCIÓN MANUAL REQUERIDA]"
    echo ""
    echo "  PROCEDIMIENTO:"
    echo "  1. En Roundcube http://$DETECTED_IP:8080, inicie sesión como gustavo"
    echo "  2. Clic en el botón 'Redactar' ícono de lápiz o botón superior"
    echo "  3. Complete el formulario:"
    echo "     Para:    edna@$DOMAIN"
    echo "     Asunto:  Prueba 13.6 - Adjunto con integridad verificada"
    echo "     Cuerpo:  'Verificación de integridad de archivo adjunto.'"
    echo "  4. Clic en el clip/adjunto e incluya un archivo imagen PNG, PDF, etc."
    echo "     Sugerencia: use una imagen de menos de 1MB para mayor velocidad"
    echo "  5. Clic en 'Enviar'"
    echo ""
    echo "  VERIFICACIÓN DE INTEGRIDAD:"
    echo "  6. Cierre sesión y entre como edna@$DOMAIN"
    echo "  7. Abra el correo recibido de gustavo"
    echo "  8. Descargue el adjunto haciendo clic en él"
    echo "  9. Abra el archivo descargado en su PC"
    echo "  10. Confirme que el archivo se abre sin errores y tiene el contenido correcto"
    echo ""
    echo "  VERIFICACIÓN AVANZADA hash MD5:"
    echo "  Si quiere demostrar integridad matemática:"
    echo "  - Antes de enviar, en PowerShell: Get-FileHash archivo.png -Algorithm MD5"
    echo "  - Después de descargar: Get-FileHash descargado.png -Algorithm MD5"
    echo "  - Ambos hashes deben ser IDÉNTICOS"
    echo ""
    read -p "  Presione ENTER una vez validada la prueba..."
}

prueba_13_7() {
    echo ""
    echo "[PRUEBA 13.7: PERSISTENCIA DE PREFERENCIAS WEBMAIL]"
    echo "----------------------------------------------------------------------"
    echo "  [EJECUCIÓN HÍBRIDA]"
    echo ""
    echo "  -> Fase 1: ACCIÓN MANUAL"
    echo "     En Roundcube http://$DETECTED_IP:8080:"
    echo "     OPCIÓN A - Cambiar idioma:"
    echo "       Configuración ícono engranaje -> Preferencias -> Interfaz de usuario"
    echo "       Cambiar 'Idioma' a 'English US' o cualquier otro"
    echo "       Clic en 'Guardar'"
    echo "     OPCIÓN B - Agregar contacto:"
    echo "       Contactos ícono personas -> Nueva tarjeta de contacto"
    echo "       Nombre: Prueba Persistencia"
    echo "       Email:  test@$DOMAIN"
    echo "       Guardar"
    read -p "     Presione ENTER DESPUÉS de guardar su preferencia en Roundcube..."

    echo ""
    echo "  -> Fase 2: Reiniciando el contenedor de webmail..."
    docker compose -f "$BASE_DIR/docker-compose.yml" restart webmail

    echo "  -> Esperando que Roundcube reinicialice 15 segundos..."
    sleep 15

    echo "  -> [ÉXITO] Contenedor reiniciado."
    echo ""
    echo "  -> Fase 3: VERIFICACIÓN MANUAL"
    echo "     1. Recargue http://$DETECTED_IP:8080 en su navegador"
    echo "     2. Inicie sesión nuevamente"
    echo "     3. Verifique que su cambio persiste:"
    echo "        - Si cambió idioma: debe aparecer en el idioma nuevo"
    echo "        - Si agregó contacto: debe aparecer en la libreta de direcciones"
    echo ""
    echo "  Si los cambios NO persisten:"
    echo "  -> El volumen ./webmail_db no está funcionando correctamente"
    echo "  -> Ejecute: docker inspect webmail_reprobados"
    echo "  -> Verifique que /var/roundcube/db esté mapeado a $BASE_DIR/webmail_db"
    echo ""
    read -p "  Presione ENTER una vez confirmada la persistencia..."
}
