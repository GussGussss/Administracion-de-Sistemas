#!/bin/bash
# ============================================================
# http_functions.sh
# Archivo de funciones para despliegue HTTP en Oracle Linux
# Práctica 6 - Despliegue Dinámico de Servicios HTTP
# ============================================================

# ─────────────────────────────────────────────
# COLORES PARA OUTPUT
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────
# FUNCIÓN: Imprimir mensajes formateados
# ─────────────────────────────────────────────
msg_ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
msg_info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
msg_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
msg_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ─────────────────────────────────────────────
# FUNCIÓN: Verificar si se ejecuta como root
# ─────────────────────────────────────────────
verificar_root() {
    if [[ $EUID -ne 0 ]]; then
        msg_error "Este script debe ejecutarse como root o con sudo."
        exit 1
    fi
}

# ─────────────────────────────────────────────
# FUNCIÓN: Validar entrada (sin caracteres especiales, no vacío)
# ─────────────────────────────────────────────
validar_entrada() {
    local valor="$1"
    local nombre_campo="$2"

    if [[ -z "$valor" ]]; then
        msg_error "El campo '$nombre_campo' no puede estar vacío."
        return 1
    fi
    if [[ "$valor" =~ [^a-zA-Z0-9._\-] ]]; then
        msg_error "El campo '$nombre_campo' contiene caracteres no permitidos."
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────────
# FUNCIÓN: Validar número de puerto
# ─────────────────────────────────────────────
validar_puerto() {
    local puerto="$1"

    # Debe ser numérico
    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        msg_error "El puerto debe ser un número entero."
        return 1
    fi

    # Rango válido
    if (( puerto < 1 || puerto > 65535 )); then
        msg_error "El puerto debe estar entre 1 y 65535."
        return 1
    fi

    # Puertos reservados del sistema (no HTTP)
    local puertos_reservados=(22 25 53 110 143 443 3306 5432 27017)
    for p in "${puertos_reservados[@]}"; do
        if [[ "$puerto" -eq "$p" ]]; then
            msg_error "El puerto $puerto está reservado para otro servicio del sistema."
            return 1
        fi
    done

    return 0
}

# ─────────────────────────────────────────────
# FUNCIÓN: Verificar si un puerto está en uso
# ─────────────────────────────────────────────
puerto_en_uso() {
    local puerto="$1"
    if ss -tlnp | grep -q ":${puerto} "; then
        return 0  # Puerto en uso
    fi
    return 1  # Puerto libre
}

# ─────────────────────────────────────────────
# FUNCIÓN: Solicitar y validar puerto al usuario
# ─────────────────────────────────────────────
solicitar_puerto() {
    local puerto
    while true; do
        echo -ne "${CYAN}Ingresa el puerto de escucha (ej. 80, 8080, 8888): ${NC}"
        read -r puerto
        if validar_puerto "$puerto"; then
            if puerto_en_uso "$puerto"; then
                msg_warn "El puerto $puerto ya está en uso por otro proceso."
                echo -ne "¿Deseas usar otro puerto? [s/n]: "
                read -r resp
                [[ "$resp" =~ ^[sS]$ ]] && continue || { msg_error "Abortando."; exit 1; }
            else
                echo "$puerto"
                return 0
            fi
        fi
    done
}

# ─────────────────────────────────────────────
# FUNCIÓN: Configurar firewall (UFW o IPTables)
# ─────────────────────────────────────────────
configurar_firewall() {
    local puerto="$1"
    local puertos_default=(80 8080 8888)

    msg_info "Configurando firewall para el puerto $puerto..."

    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$puerto/tcp" &>/dev/null
        msg_ok "UFW: Puerto $puerto abierto."
        # Cerrar puertos HTTP default que no se usen
        for p in "${puertos_default[@]}"; do
            if [[ "$p" -ne "$puerto" ]]; then
                ufw deny "$p/tcp" &>/dev/null 2>&1 || true
                msg_info "UFW: Puerto por defecto $p bloqueado."
            fi
        done
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="$puerto/tcp" &>/dev/null
        firewall-cmd --reload &>/dev/null
        msg_ok "firewalld: Puerto $puerto abierto."
    else
        # IPTables como fallback
        iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT 2>/dev/null
        msg_ok "iptables: Regla para puerto $puerto añadida."
    fi
}

# ─────────────────────────────────────────────
# FUNCIÓN: Crear usuario dedicado para servicio
# ─────────────────────────────────────────────
crear_usuario_servicio() {
    local usuario="$1"
    local directorio="$2"

    if id "$usuario" &>/dev/null; then
        msg_info "Usuario '$usuario' ya existe."
    else
        useradd --system --no-create-home --shell /sbin/nologin \
                --home-dir "$directorio" "$usuario" 2>/dev/null
        msg_ok "Usuario de sistema '$usuario' creado."
    fi

    # Asegurar permisos restringidos
    if [[ -d "$directorio" ]]; then
        chown -R "$usuario":"$usuario" "$directorio" 2>/dev/null || true
        chmod 750 "$directorio" 2>/dev/null || true
        msg_ok "Permisos aplicados en $directorio para usuario '$usuario'."
    fi
}

# ─────────────────────────────────────────────
# FUNCIÓN: Crear página index.html personalizada
# ─────────────────────────────────────────────
crear_index_html() {
    local ruta="$1"
    local servicio="$2"
    local version="$3"
    local puerto="$4"

    mkdir -p "$ruta"
    cat > "$ruta/index.html" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${servicio} - Práctica 6</title>
    <style>
        body { font-family: Arial, sans-serif; background: #1a1a2e; color: #e0e0e0;
               display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: #16213e; border-radius: 12px; padding: 40px 60px;
                text-align: center; box-shadow: 0 8px 32px rgba(0,0,0,0.4); }
        h1 { color: #00d4ff; margin-bottom: 10px; }
        .badge { display: inline-block; background: #0f3460; border-radius: 8px;
                 padding: 8px 20px; margin: 8px; font-size: 1.1em; }
        .label { color: #888; font-size: 0.85em; }
    </style>
</head>
<body>
    <div class="card">
        <h1>🖥️ Servidor HTTP Activo</h1>
        <div class="badge"><span class="label">Servidor: </span><strong>${servicio}</strong></div>
        <div class="badge"><span class="label">Versión: </span><strong>${version}</strong></div>
        <div class="badge"><span class="label">Puerto: </span><strong>${puerto}</strong></div>
        <p style="color:#555; margin-top:20px; font-size:0.8em;">Práctica 6 - Despliegue Dinámico de Servicios HTTP</p>
    </div>
</body>
</html>
EOF
    msg_ok "Página index.html creada en $ruta"
}

# ═══════════════════════════════════════════════════════════
#   MÓDULO APACHE
# ═══════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# FUNCIÓN: Obtener versiones disponibles de Apache
# ─────────────────────────────────────────────
obtener_versiones_apache() {
    msg_info "Consultando versiones disponibles de Apache..."
    local ver_repo ver_instalada versiones=""

    # repoquery es mucho más rápido que dnf list --showduplicates
    ver_repo=$(timeout 8 dnf repoquery --queryformat "%{version}-%{release}" httpd \
        2>/dev/null | sort -V | uniq | tail -1)
    ver_instalada=$(rpm -q httpd --queryformat "%{version}-%{release}" 2>/dev/null)

    if [[ -n "$ver_instalada" && "$ver_instalada" != *"not installed"* ]]; then
        versiones="${ver_instalada} (Instalada-actual)"$'\n'
    fi
    if [[ -n "$ver_repo" ]]; then
        versiones+="${ver_repo} (Repositorio-latest)"
    fi

    if [[ -z "$versiones" ]]; then
        msg_warn "Usando versiones conocidas de Oracle Linux 10."
        versiones="2.4.62-1.0.1.el10 (Stable-LTS)"$'\n'"2.4.62-2.0.1.el10 (Latest)"
    fi

    echo "$versiones"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Mostrar menú de versiones y seleccionar
# ─────────────────────────────────────────────
seleccionar_version_apache() {
    local versiones
    versiones=$(obtener_versiones_apache)

    echo ""
    echo -e "${BOLD}Versiones disponibles de Apache:${NC}"
    local i=1
    declare -A mapa_versiones
    while IFS= read -r ver; do
        echo "  [$i] $ver"
        mapa_versiones[$i]="$ver"
        ((i++))
    done <<< "$versiones"
    echo "  [L] Última versión disponible (Latest)"
    echo "  [S] Versión estable del repositorio (Stable/LTS)"
    echo ""

    local seleccion version_elegida
    while true; do
        echo -ne "${CYAN}Selecciona una opción: ${NC}"
        read -r seleccion

        if [[ "$seleccion" =~ ^[Ll]$ ]]; then
            version_elegida=$(echo "$versiones" | tail -1)
            break
        elif [[ "$seleccion" =~ ^[Ss]$ ]]; then
            version_elegida=$(echo "$versiones" | head -1)
            break
        elif [[ "$seleccion" =~ ^[0-9]+$ ]] && [[ -n "${mapa_versiones[$seleccion]}" ]]; then
            version_elegida="${mapa_versiones[$seleccion]}"
            break
        else
            msg_warn "Opción inválida. Intenta de nuevo."
        fi
    done

    echo "$version_elegida"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Instalar Apache
# ─────────────────────────────────────────────
instalar_apache() {
    local puerto version

    version=$(seleccionar_version_apache)
    puerto=$(solicitar_puerto)

    msg_info "Instalando Apache ($version) en puerto $puerto..."

    # Instalación silenciosa
    if command -v dnf &>/dev/null; then
        dnf install -y httpd 2>/dev/null
    else
        apt-get install -y apache2 2>/dev/null
    fi

    if [[ $? -ne 0 ]]; then
        msg_error "Falló la instalación de Apache. Verifica conectividad o repositorios."
        return 1
    fi
    msg_ok "Apache instalado correctamente."

    # Cambio de puerto
    configurar_puerto_apache "$puerto"

    # Seguridad: ocultar versión
    configurar_seguridad_apache

    # Seguridad: control de métodos HTTP
    configurar_metodos_http_apache

    # Crear usuario y página
    crear_index_html "/var/www/html" "Apache" "$version" "$puerto"

    # Reiniciar servicio
    if command -v systemctl &>/dev/null; then
        systemctl enable httpd &>/dev/null || systemctl enable apache2 &>/dev/null
        systemctl restart httpd 2>/dev/null || systemctl restart apache2 2>/dev/null
    fi

    # Firewall
    configurar_firewall "$puerto"

    msg_ok "Apache desplegado exitosamente en el puerto $puerto."
    echo -e "${GREEN}Prueba con: curl -I http://localhost:${puerto}${NC}"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Cambiar puerto de Apache
# ─────────────────────────────────────────────
configurar_puerto_apache() {
    local puerto="$1"

    # Detectar archivo de puertos según distro
    local ports_conf
    if [[ -f /etc/apache2/ports.conf ]]; then
        ports_conf="/etc/apache2/ports.conf"
        sed -i "s/Listen [0-9]*/Listen $puerto/g" "$ports_conf"
        # Ajustar VirtualHost en 000-default.conf si existe
        [[ -f /etc/apache2/sites-enabled/000-default.conf ]] && \
            sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:$puerto>/g" \
                /etc/apache2/sites-enabled/000-default.conf
    elif [[ -f /etc/httpd/conf/httpd.conf ]]; then
        ports_conf="/etc/httpd/conf/httpd.conf"
        sed -i "s/^Listen [0-9]*/Listen $puerto/" "$ports_conf"
    fi
    msg_ok "Puerto de Apache configurado: $puerto"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Ocultar versión de Apache (security.conf)
# ─────────────────────────────────────────────
configurar_seguridad_apache() {
    local conf_file

    # Oracle/RHEL: httpd.conf o conf.d/security.conf
    if [[ -f /etc/httpd/conf.d/security.conf ]]; then
        conf_file="/etc/httpd/conf.d/security.conf"
    elif [[ -f /etc/apache2/conf-available/security.conf ]]; then
        conf_file="/etc/apache2/conf-available/security.conf"
        a2enconf security &>/dev/null || true
    else
        conf_file="/etc/httpd/conf.d/security.conf"
        touch "$conf_file"
    fi

    # Establecer ServerTokens y ServerSignature
    grep -q "ServerTokens" "$conf_file" 2>/dev/null \
        && sed -i "s/^ServerTokens.*/ServerTokens Prod/" "$conf_file" \
        || echo "ServerTokens Prod" >> "$conf_file"

    grep -q "ServerSignature" "$conf_file" 2>/dev/null \
        && sed -i "s/^ServerSignature.*/ServerSignature Off/" "$conf_file" \
        || echo "ServerSignature Off" >> "$conf_file"

    # Encabezados de seguridad
    if ! grep -q "Header always set X-Frame-Options" "$conf_file" 2>/dev/null; then
        cat >> "$conf_file" <<'SECEOF'

# Security Headers
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
SECEOF
        # Asegurar que mod_headers esté habilitado
        command -v a2enmod &>/dev/null && a2enmod headers &>/dev/null || true
    fi

    msg_ok "Configuración de seguridad Apache aplicada (ServerTokens Prod, ServerSignature Off, Security Headers)."
}

# ─────────────────────────────────────────────
# FUNCIÓN: Restringir métodos HTTP peligrosos en Apache
# ─────────────────────────────────────────────
configurar_metodos_http_apache() {
    local htaccess="/var/www/html/.htaccess"
    local conf_extra

    if [[ -f /etc/httpd/conf.d/security.conf ]]; then
        conf_extra="/etc/httpd/conf.d/security.conf"
    else
        conf_extra="/etc/apache2/conf-available/security.conf"
    fi

    if ! grep -q "LimitExcept GET POST" "$conf_extra" 2>/dev/null; then
        cat >> "$conf_extra" <<'METHEOF'

# Restringir métodos HTTP peligrosos
<Location "/">
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Location>

# Deshabilitar TRACE
TraceEnable Off
METHEOF
    fi

    msg_ok "Métodos HTTP peligrosos (TRACE, TRACK, DELETE) restringidos en Apache."
}

# ═══════════════════════════════════════════════════════════
#   MÓDULO NGINX
# ═══════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# FUNCIÓN: Obtener versiones disponibles de Nginx
# ─────────────────────────────────────────────
obtener_versiones_nginx() {
    msg_info "Consultando versiones disponibles de Nginx..."
    local ver_repo ver_instalada versiones=""

    ver_repo=$(timeout 8 dnf repoquery --queryformat "%{version}-%{release}" nginx \
        2>/dev/null | sort -V | uniq | tail -1)
    ver_instalada=$(rpm -q nginx --queryformat "%{version}-%{release}" 2>/dev/null)

    if [[ -n "$ver_instalada" && "$ver_instalada" != *"not installed"* ]]; then
        versiones="${ver_instalada} (Instalada-actual)"$'\n'
    fi
    if [[ -n "$ver_repo" ]]; then
        versiones+="${ver_repo} (Repositorio-latest)"
    fi

    if [[ -z "$versiones" ]]; then
        msg_warn "Usando versiones conocidas de Oracle Linux 10."
        versiones="1.26.3-1.0.1.el10 (Stable-LTS)"$'\n'"1.27.3-1.0.1.el10 (Latest)"
    fi

    echo "$versiones"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Seleccionar versión de Nginx
# ─────────────────────────────────────────────
seleccionar_version_nginx() {
    local versiones
    versiones=$(obtener_versiones_nginx)

    echo ""
    echo -e "${BOLD}Versiones disponibles de Nginx:${NC}"
    local i=1
    declare -A mapa_versiones
    while IFS= read -r ver; do
        echo "  [$i] $ver"
        mapa_versiones[$i]="$ver"
        ((i++))
    done <<< "$versiones"
    echo "  [L] Última versión disponible (Latest)"
    echo "  [S] Versión estable (Stable)"
    echo ""

    local seleccion version_elegida
    while true; do
        echo -ne "${CYAN}Selecciona una opción: ${NC}"
        read -r seleccion

        if [[ "$seleccion" =~ ^[Ll]$ ]]; then
            version_elegida=$(echo "$versiones" | tail -1)
            break
        elif [[ "$seleccion" =~ ^[Ss]$ ]]; then
            version_elegida=$(echo "$versiones" | head -1)
            break
        elif [[ "$seleccion" =~ ^[0-9]+$ ]] && [[ -n "${mapa_versiones[$seleccion]}" ]]; then
            version_elegida="${mapa_versiones[$seleccion]}"
            break
        else
            msg_warn "Opción inválida. Intenta de nuevo."
        fi
    done

    echo "$version_elegida"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Instalar Nginx
# ─────────────────────────────────────────────
instalar_nginx() {
    local puerto version

    version=$(seleccionar_version_nginx)
    puerto=$(solicitar_puerto)

    msg_info "Instalando Nginx ($version) en puerto $puerto..."

    if command -v dnf &>/dev/null; then
        dnf install -y nginx 2>/dev/null
    else
        apt-get install -y nginx 2>/dev/null
    fi

    if [[ $? -ne 0 ]]; then
        msg_error "Falló la instalación de Nginx."
        return 1
    fi
    msg_ok "Nginx instalado correctamente."

    # Cambio de puerto
    configurar_puerto_nginx "$puerto"

    # Seguridad
    configurar_seguridad_nginx

    # Métodos HTTP
    configurar_metodos_http_nginx

    # Usuario dedicado y página
    crear_usuario_servicio "nginx" "/var/www/html"
    crear_index_html "/var/www/html" "Nginx" "$version" "$puerto"

    # Reiniciar
    systemctl enable nginx &>/dev/null
    systemctl restart nginx 2>/dev/null

    # Firewall
    configurar_firewall "$puerto"

    msg_ok "Nginx desplegado exitosamente en el puerto $puerto."
    echo -e "${GREEN}Prueba con: curl -I http://localhost:${puerto}${NC}"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Cambiar puerto de Nginx
# ─────────────────────────────────────────────
configurar_puerto_nginx() {
    local puerto="$1"
    local nginx_conf

    # Detectar config file
    if [[ -f /etc/nginx/nginx.conf ]]; then
        nginx_conf="/etc/nginx/nginx.conf"
    else
        msg_error "No se encontró nginx.conf"
        return 1
    fi

    # Reemplazar puerto en el bloque listen
    sed -i "s/listen [0-9]*;/listen $puerto;/g" "$nginx_conf"
    sed -i "s/listen \[::\]:[0-9]* default_server;/listen [::]:$puerto default_server;/g" "$nginx_conf"
    sed -i "s/listen [0-9]* default_server;/listen $puerto default_server;/g" "$nginx_conf"

    # También en conf.d si existe
    if [[ -d /etc/nginx/conf.d ]]; then
        for f in /etc/nginx/conf.d/*.conf; do
            [[ -f "$f" ]] && sed -i "s/listen [0-9]*;/listen $puerto;/g" "$f"
        done
    fi

    msg_ok "Puerto de Nginx configurado: $puerto"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Configurar seguridad de Nginx
# ─────────────────────────────────────────────
configurar_seguridad_nginx() {
    local nginx_conf="/etc/nginx/nginx.conf"

    # Ocultar versión de Nginx
    if ! grep -q "server_tokens off" "$nginx_conf"; then
        sed -i "/http {/a\\    server_tokens off;" "$nginx_conf"
        msg_ok "Nginx: server_tokens off aplicado (versión oculta)."
    fi

    # Crear snippet de security headers si no existe
    local sec_snippet="/etc/nginx/conf.d/security_headers.conf"
    if [[ ! -f "$sec_snippet" ]]; then
        cat > "$sec_snippet" <<'SNIPEOF'
# Security Headers - Práctica 6
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
SNIPEOF
        msg_ok "Nginx: Security Headers configurados."
    fi
}

# ─────────────────────────────────────────────
# FUNCIÓN: Restringir métodos HTTP en Nginx
# ─────────────────────────────────────────────
configurar_metodos_http_nginx() {
    local sec_snippet="/etc/nginx/conf.d/security_headers.conf"

    if ! grep -q "limit_except" "$sec_snippet" 2>/dev/null; then
        cat >> "$sec_snippet" <<'METHEOF'

# Bloquear métodos peligrosos
server {
    if ($request_method !~ ^(GET|HEAD|POST|OPTIONS)$) {
        return 405;
    }
}
METHEOF
    fi

    msg_ok "Nginx: Métodos HTTP peligrosos (TRACE, DELETE) bloqueados."
}

# ═══════════════════════════════════════════════════════════
#   MÓDULO TOMCAT
# ═══════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
# FUNCIÓN: Obtener versiones disponibles de Tomcat
# ─────────────────────────────────────────────
obtener_versiones_tomcat() {
    msg_info "Consultando versiones disponibles de Tomcat..."
    local ver_repo ver_instalada versiones=""

    ver_repo=$(timeout 8 dnf repoquery --queryformat "%{version}-%{release}" tomcat \
        2>/dev/null | sort -V | uniq | tail -1)
    ver_instalada=$(rpm -q tomcat --queryformat "%{version}-%{release}" 2>/dev/null)

    if [[ -n "$ver_instalada" && "$ver_instalada" != *"not installed"* ]]; then
        versiones="${ver_instalada} (Instalada-actual)"$'\n'
    fi
    if [[ -n "$ver_repo" ]]; then
        versiones+="${ver_repo} (Repositorio)"
    fi

    # Tomcat usualmente no está en repos estándar, usar versiones conocidas
    if [[ -z "$versiones" ]]; then
        versiones="10.1.39 (LTS-Stable)"$'\n'"11.0.7 (Latest)"
    fi

    echo "$versiones"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Seleccionar versión de Tomcat
# ─────────────────────────────────────────────
seleccionar_version_tomcat() {
    local versiones
    versiones=$(obtener_versiones_tomcat)

    echo ""
    echo -e "${BOLD}Versiones disponibles de Tomcat:${NC}"
    local i=1
    declare -A mapa_versiones
    while IFS= read -r ver; do
        echo "  [$i] $ver"
        mapa_versiones[$i]="$ver"
        ((i++))
    done <<< "$versiones"
    echo "  [L] Última versión (Latest - Tomcat 11)"
    echo "  [S] Versión LTS (Stable - Tomcat 10.1)"
    echo ""

    local seleccion version_elegida
    while true; do
        echo -ne "${CYAN}Selecciona una opción: ${NC}"
        read -r seleccion

        if [[ "$seleccion" =~ ^[Ll]$ ]]; then
            version_elegida=$(echo "$versiones" | tail -1 | awk '{print $1}')
            break
        elif [[ "$seleccion" =~ ^[Ss]$ ]]; then
            version_elegida=$(echo "$versiones" | head -1 | awk '{print $1}')
            break
        elif [[ "$seleccion" =~ ^[0-9]+$ ]] && [[ -n "${mapa_versiones[$seleccion]}" ]]; then
            version_elegida=$(echo "${mapa_versiones[$seleccion]}" | awk '{print $1}')
            break
        else
            msg_warn "Opción inválida. Intenta de nuevo."
        fi
    done

    echo "$version_elegida"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Instalar Tomcat (via binarios tar.gz)
# ─────────────────────────────────────────────
instalar_tomcat() {
    local version puerto major_version
    local install_dir="/opt/tomcat"
    local tomcat_user="tomcat"

    version=$(seleccionar_version_tomcat)
    puerto=$(solicitar_puerto)

    # Extraer versión major (ej: 10 de 10.1.39)
    major_version=$(echo "$version" | cut -d'.' -f1)

    msg_info "Preparando instalación de Apache Tomcat $version en puerto $puerto..."

    # Verificar Java
    if ! command -v java &>/dev/null; then
        msg_info "Java no encontrado. Instalando OpenJDK 17..."
        dnf install -y java-17-openjdk 2>/dev/null || \
        apt-get install -y openjdk-17-jdk 2>/dev/null
    fi

    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
    export JAVA_HOME

    # Descargar Tomcat
    local download_url="https://dlcdn.apache.org/tomcat/tomcat-${major_version}/v${version}/bin/apache-tomcat-${version}.tar.gz"
    local tarball="/tmp/apache-tomcat-${version}.tar.gz"

    msg_info "Descargando Tomcat $version desde Apache mirrors..."
    if ! curl -fsSL -o "$tarball" "$download_url" 2>/dev/null; then
        msg_warn "Descarga directa falló. Intentando con wget..."
        wget -q -O "$tarball" "$download_url" 2>/dev/null || {
            msg_error "No se pudo descargar Tomcat $version. Verifica conectividad."
            return 1
        }
    fi
    msg_ok "Tomcat $version descargado."

    # Crear directorio de instalación
    rm -rf "$install_dir" 2>/dev/null
    mkdir -p "$install_dir"
    tar -xzf "$tarball" -C "$install_dir" --strip-components=1
    rm -f "$tarball"

    # Crear usuario dedicado
    crear_usuario_servicio "$tomcat_user" "$install_dir"
    chown -R "$tomcat_user":"$tomcat_user" "$install_dir"
    chmod -R 750 "$install_dir"

    # Configurar puerto en server.xml
    configurar_puerto_tomcat "$puerto" "$install_dir"

    # Seguridad: ocultar versión
    configurar_seguridad_tomcat "$install_dir"

    # Crear index personalizado
    crear_index_html "$install_dir/webapps/ROOT" "Tomcat" "$version" "$puerto"

    # Variables de entorno
    cat > /etc/profile.d/tomcat.sh <<ENVEOF
export CATALINA_HOME=$install_dir
export JAVA_HOME=$JAVA_HOME
ENVEOF

    # Crear servicio systemd
    crear_servicio_systemd_tomcat "$install_dir" "$tomcat_user" "$JAVA_HOME"

    # Firewall
    configurar_firewall "$puerto"

    msg_ok "Tomcat $version desplegado correctamente en el puerto $puerto."
    echo -e "${GREEN}Prueba con: curl -I http://localhost:${puerto}${NC}"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Configurar puerto de Tomcat (server.xml)
# ─────────────────────────────────────────────
configurar_puerto_tomcat() {
    local puerto="$1"
    local install_dir="$2"
    local server_xml="$install_dir/conf/server.xml"

    if [[ ! -f "$server_xml" ]]; then
        msg_error "No se encontró server.xml en $install_dir/conf/"
        return 1
    fi

    # Reemplazar el puerto del Connector HTTP
    sed -i "s/port=\"8080\"/port=\"$puerto\"/" "$server_xml"
    sed -i "s/port=\"[0-9]*\" protocol=\"HTTP\/1.1\"/port=\"$puerto\" protocol=\"HTTP\/1.1\"/" "$server_xml"

    msg_ok "Puerto de Tomcat configurado: $puerto en server.xml"
}

# ─────────────────────────────────────────────
# FUNCIÓN: Ocultar versión de Tomcat
# ─────────────────────────────────────────────
configurar_seguridad_tomcat() {
    local install_dir="$1"
    local server_xml="$install_dir/conf/server.xml"
    local catalina_props="$install_dir/conf/catalina.properties"

    # Ocultar cabecera Server
    if [[ -f "$server_xml" ]]; then
        # Añadir server="" al Connector si no existe
        sed -i 's/protocol="HTTP\/1.1"/protocol="HTTP\/1.1" server="Apache"/' "$server_xml" 2>/dev/null || true
    fi

    # Deshabilitar métodos peligrosos via web.xml
    local web_xml="$install_dir/conf/web.xml"
    if [[ -f "$web_xml" ]] && ! grep -q "TRACE" "$web_xml"; then
        # Agregar Security Constraint para bloquear TRACE
        sed -i '/<\/web-app>/i\
    <security-constraint>\
        <web-resource-collection>\
            <web-resource-name>Restrict TRACE</web-resource-name>\
            <url-pattern>/*</url-pattern>\
            <http-method>TRACE</http-method>\
            <http-method>TRACK</http-method>\
        </web-resource-collection>\
        <auth-constraint />\
    </security-constraint>' "$web_xml" 2>/dev/null || true
    fi

    msg_ok "Tomcat: Cabeceras de versión ocultadas, TRACE/TRACK bloqueados."
}

# ─────────────────────────────────────────────
# FUNCIÓN: Crear servicio systemd para Tomcat
# ─────────────────────────────────────────────
crear_servicio_systemd_tomcat() {
    local install_dir="$1"
    local tomcat_user="$2"
    local java_home="$3"

    cat > /etc/systemd/system/tomcat.service <<SVCEOF
[Unit]
Description=Apache Tomcat Web Application Server
After=network.target

[Service]
Type=forking
User=$tomcat_user
Group=$tomcat_user
Environment="JAVA_HOME=$java_home"
Environment="CATALINA_HOME=$install_dir"
Environment="CATALINA_BASE=$install_dir"
Environment="CATALINA_PID=$install_dir/temp/tomcat.pid"
ExecStart=$install_dir/bin/startup.sh
ExecStop=$install_dir/bin/shutdown.sh
Restart=on-failure
SuccessExitStatus=143
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=tomcat

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable tomcat &>/dev/null
    systemctl restart tomcat 2>/dev/null
    msg_ok "Servicio systemd de Tomcat creado y activado."
}

# ═══════════════════════════════════════════════════════════
#   MÓDULO: DESINSTALAR SERVICIO
# ═══════════════════════════════════════════════════════════
desinstalar_servicio() {
    echo ""
    echo -e "${BOLD}¿Qué servicio deseas desinstalar?${NC}"
    echo "  [1] Apache"
    echo "  [2] Nginx"
    echo "  [3] Tomcat"
    echo ""
    local opcion
    echo -ne "${CYAN}Selecciona: ${NC}"
    read -r opcion

    case "$opcion" in
        1)
            systemctl stop httpd 2>/dev/null || systemctl stop apache2 2>/dev/null
            dnf remove -y httpd 2>/dev/null || apt-get purge -y apache2 2>/dev/null
            msg_ok "Apache desinstalado."
            ;;
        2)
            systemctl stop nginx 2>/dev/null
            dnf remove -y nginx 2>/dev/null || apt-get purge -y nginx 2>/dev/null
            msg_ok "Nginx desinstalado."
            ;;
        3)
            systemctl stop tomcat 2>/dev/null
            systemctl disable tomcat 2>/dev/null
            rm -rf /opt/tomcat /etc/systemd/system/tomcat.service
            systemctl daemon-reload
            msg_ok "Tomcat desinstalado."
            ;;
        *)
            msg_warn "Opción inválida."
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════
#   MÓDULO: ESTADO DE SERVICIOS
# ═══════════════════════════════════════════════════════════
mostrar_estado_servicios() {
    echo ""
    echo -e "${BOLD}══════════════════════════════════════${NC}"
    echo -e "${BOLD}   Estado de Servicios HTTP            ${NC}"
    echo -e "${BOLD}══════════════════════════════════════${NC}"

    for svc in httpd apache2 nginx tomcat; do
        if systemctl list-units --type=service --all | grep -q "$svc"; then
            local status
            status=$(systemctl is-active "$svc" 2>/dev/null)
            if [[ "$status" == "active" ]]; then
                echo -e "  ${GREEN}●${NC} $svc: ${GREEN}Activo${NC}"
            else
                echo -e "  ${RED}●${NC} $svc: ${RED}Inactivo${NC}"
            fi
        fi
    done

    echo ""
    msg_info "Puertos en escucha actualmente:"
    ss -tlnp | grep -E ":(80|8080|8888|[0-9]{4,5}) " | awk '{print "  "$4}' | sort -u
    echo ""
}
