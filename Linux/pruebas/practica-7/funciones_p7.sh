#!/bin/bash
# ================================================================
# funciones_p7_linux.sh
# Practica 7 - Infraestructura de Despliegue Seguro e Instalacion
# Hibrida (FTP/Web) - Oracle Linux Server 10.1
# ================================================================

# ----------------------------------------------------------------
# VARIABLES GLOBALES
# ----------------------------------------------------------------
FTP_IP=""
FTP_USER=""
FTP_PASS=""
FTP_RUTA="http/Linux"
DOMINIO_SSL=""
RESUMEN_FILE="/tmp/p7_resumen.txt"
DOMINIO_DEFAULT="www.reprobados.com"
FTP_DATA="/ftp"
FTP_CONF="/etc/vsftpd/vsftpd.conf"
FTP_ARCHIVO_DESCARGADO=""
FTP_SERVICIO_ELEGIDO=""
FTP_TMP_DIR=""

# ================================================================
# SECCION 1 - UTILIDADES GENERALES
# ================================================================

escribir_titulo() {
    local texto="$1"
    echo ""
    echo "============================================================"
    echo "  $texto"
    echo "============================================================"
    echo ""
}

escribir_subtitulo() {
    echo ""
    echo "--- $1 ---"
}

registrar_resumen() {
    local servicio="$1" accion="$2" estado="$3" detalle="${4:-}"
    echo "$servicio | $accion | $estado | $detalle" >> "$RESUMEN_FILE"
}

abrir_firewall() {
    local puerto="$1"
    echo "  Firewall: abriendo puerto $puerto..."
    firewall-cmd --permanent --add-port=${puerto}/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
}

cerrar_firewall() {
    local puerto="$1"
    firewall-cmd --permanent --remove-port=${puerto}/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
}

permitir_selinux_http() {
    local puerto="$1"
    if command -v semanage &>/dev/null; then
        if ! semanage port -l 2>/dev/null | grep -q "http_port_t.*\b${puerto}\b"; then
            semanage port -a -t http_port_t -p tcp "$puerto" 2>/dev/null || \
            semanage port -m -t http_port_t -p tcp "$puerto" 2>/dev/null
        fi
    fi
    setsebool -P httpd_can_network_connect 1 2>/dev/null
}

# ================================================================
# SECCION 2 - DEPENDENCIAS
# ================================================================

instalar_dependencias() {
    escribir_titulo "INSTALAR DEPENDENCIAS"
    echo "  Instalando openssl, curl, wget, tar, policycoreutils..."
    dnf install -y openssl curl wget tar policycoreutils-python-utils 2>/dev/null
    dnf install -y python3-policycoreutils 2>/dev/null || true
    echo "  Dependencias instaladas."
    registrar_resumen "Dependencias" "Instalacion" "OK" "openssl curl wget"
}

# ================================================================
# SECCION 3 - REPOSITORIO FTP
# ================================================================

archivo_valido() {
    local ruta="$1" min="${2:-100}"
    [[ -f "$ruta" ]] && (( $(stat -c%s "$ruta" 2>/dev/null || echo 0) > min ))
}

generar_sha256() {
    local archivo="$1"
    sha256sum "$archivo" | awk '{print $1}' > "${archivo}.sha256"
    echo "  SHA256: $(cat ${archivo}.sha256)"
}

preparar_repositorio_ftp() {
    escribir_titulo "PREPARAR REPOSITORIO FTP"

    local repo_base="$FTP_DATA/public/http/Linux"

    if [[ ! -d "$FTP_DATA" ]]; then
        echo "  ERROR: $FTP_DATA no existe. Ejecute primero la opcion 1 (FTP)."
        return 1
    fi

    echo "  Se crearan carpetas y descargaran instaladores."
    read -p "  ¿Continuar? [S/N]: " conf
    [[ "$conf" =~ ^[Nn]$ ]] && return 0

    for svc in Apache Nginx Tomcat; do
        mkdir -p "$repo_base/$svc"
        echo "  Carpeta creada: $repo_base/$svc"
    done

    # ── APACHE ────────────────────────────────────────────────────
    escribir_subtitulo "Apache (via DNF)"
    local a_latest="$repo_base/Apache/apache_latest_linux.tar.gz"
    local a_lts="$repo_base/Apache/apache_lts_linux.tar.gz"
    local a_oldest="$repo_base/Apache/apache_oldest_linux.tar.gz"

    if archivo_valido "$a_latest" 1000 && archivo_valido "$a_lts" 1000 && archivo_valido "$a_oldest" 1000; then
        echo "  Apache ya preparado. Omitiendo."
    else
        local versiones
        versiones=$(dnf list --showduplicates httpd 2>/dev/null | grep "httpd\.x86_64" | awk '{print $2}' | sort -V | uniq)
        local v_latest v_lts v_oldest
        v_latest=$(echo "$versiones" | tail -n 1)
        v_lts=$(echo "$versiones" | sed -n '2p')
        v_oldest=$(echo "$versiones" | head -n 1)
        [[ -z "$v_latest" ]] && v_latest="httpd"

        for entry in "latest:$v_latest" "lts:$v_lts" "oldest:$v_oldest"; do
            local tag="${entry%%:*}" ver="${entry##*:}"
            local dest="$repo_base/Apache/apache_${tag}_linux.tar.gz"
            if ! archivo_valido "$dest" 1000; then
                echo "  Descargando Apache $ver ($tag)..."
                local tmpdir; tmpdir=$(mktemp -d)
                dnf download --destdir="$tmpdir" "httpd${ver:+"-$ver"}" 2>/dev/null
                local rpms=("$tmpdir"/*.rpm)
                if [[ -f "${rpms[0]}" ]]; then
                    tar -czf "$dest" -C "$tmpdir" .
                    echo "  OK: apache_${tag}_linux.tar.gz"
                else
                    echo "PLACEHOLDER Apache $tag" > "$tmpdir/README.txt"
                    tar -czf "$dest" -C "$tmpdir" README.txt
                    echo "  PLACEHOLDER: apache_${tag}_linux.tar.gz"
                fi
                rm -rf "$tmpdir"
            fi
            generar_sha256 "$dest"
        done
    fi

    # ── NGINX ─────────────────────────────────────────────────────
    escribir_subtitulo "Nginx (nginx.org)"
    local n_latest="$repo_base/Nginx/nginx_1.26.3_linux.tar.gz"
    local n_lts="$repo_base/Nginx/nginx_1.24.0_linux.tar.gz"
    local n_oldest="$repo_base/Nginx/nginx_1.20.2_linux.tar.gz"

    if archivo_valido "$n_latest" 1000 && archivo_valido "$n_lts" 1000 && archivo_valido "$n_oldest" 1000; then
        echo "  Nginx ya preparado. Omitiendo."
    else
        local base_url="https://nginx.org/packages/rhel/9/x86_64/RPMS"
        for entry in "1.26.3:latest" "1.24.0:lts" "1.20.2:oldest"; do
            local ver="${entry%%:*}" tag="${entry##*:}"
            local dest="$repo_base/Nginx/nginx_${ver}_linux.tar.gz"
            if ! archivo_valido "$dest" 1000; then
                echo "  Descargando Nginx $ver ($tag)..."
                local rpm_name="nginx-${ver}-1.el9.ngx.x86_64.rpm"
                local tmpdir; tmpdir=$(mktemp -d)
                if curl -sSf --max-time 60 "$base_url/$rpm_name" -o "$tmpdir/$rpm_name" 2>/dev/null; then
                    tar -czf "$dest" -C "$tmpdir" "$rpm_name"
                    echo "  OK: nginx_${ver}_linux.tar.gz"
                else
                    echo "PLACEHOLDER Nginx $ver $tag" > "$tmpdir/README.txt"
                    tar -czf "$dest" -C "$tmpdir" README.txt
                    echo "  PLACEHOLDER: nginx_${ver}_linux.tar.gz"
                fi
                rm -rf "$tmpdir"
            fi
            generar_sha256 "$dest"
        done
    fi

    # ── TOMCAT ────────────────────────────────────────────────────
    escribir_subtitulo "Tomcat (archive.apache.org)"
    local t_latest="$repo_base/Tomcat/tomcat_10.1.28_linux.tar.gz"
    local t_lts="$repo_base/Tomcat/tomcat_10.1.26_linux.tar.gz"
    local t_oldest="$repo_base/Tomcat/tomcat_9.0.91_linux.tar.gz"

    if archivo_valido "$t_latest" 1000 && archivo_valido "$t_lts" 1000 && archivo_valido "$t_oldest" 1000; then
        echo "  Tomcat ya preparado. Omitiendo."
    else
        for entry in "10.1.28:latest" "10.1.26:lts" "9.0.91:oldest"; do
            local ver="${entry%%:*}" tag="${entry##*:}"
            local dest="$repo_base/Tomcat/tomcat_${ver}_linux.tar.gz"
            if ! archivo_valido "$dest" 1000; then
                echo "  Descargando Tomcat $ver ($tag)..."
                local major="${ver%%.*}"
                local url="https://archive.apache.org/dist/tomcat/tomcat-${major}/v${ver}/bin/apache-tomcat-${ver}.tar.gz"
                local tmpdir; tmpdir=$(mktemp -d)
                if wget -q --timeout=60 "$url" -O "$tmpdir/tomcat-${ver}.tar.gz" 2>/dev/null; then
                    cp "$tmpdir/tomcat-${ver}.tar.gz" "$dest"
                    echo "  OK: tomcat_${ver}_linux.tar.gz"
                else
                    echo "PLACEHOLDER Tomcat $ver $tag" > "$tmpdir/README.txt"
                    tar -czf "$dest" -C "$tmpdir" README.txt
                    echo "  PLACEHOLDER: tomcat_${ver}_linux.tar.gz"
                fi
                rm -rf "$tmpdir"
            fi
            generar_sha256 "$dest"
        done
    fi

    # Permisos y mount bind para usuarios
    chown -R root:ftpusuarios "$FTP_DATA/public/http" 2>/dev/null
    chmod -R 755 "$FTP_DATA/public/http" 2>/dev/null

    echo ""
    echo "  Configurando acceso FTP al repositorio..."
    getent group ftpusuarios 2>/dev/null | cut -d: -f4 | tr ',' '\n' | while read -r usuario; do
        local user_home="$FTP_DATA/users/$usuario"
        if [[ -d "$user_home" ]]; then
            mountpoint -q "$user_home/http" 2>/dev/null && umount -l "$user_home/http" 2>/dev/null
            mkdir -p "$user_home/http"
            mount --bind "$FTP_DATA/public/http" "$user_home/http" 2>/dev/null && \
                echo "  Mount bind creado para '$usuario'."
        fi
    done

    registrar_resumen "Repositorio-FTP" "Preparacion" "OK" "$repo_base"

    echo ""
    echo "  Repositorio listo. Archivos generados:"
    find "$repo_base" -type f 2>/dev/null | while read -r f; do
        local size; size=$(du -sh "$f" 2>/dev/null | cut -f1)
        printf "    %-50s %s\n" "${f#$repo_base/}" "$size"
    done
    echo ""
    echo "  Al conectarse por FTP, navegue a: http/Linux/"
}

# ================================================================
# SECCION 4 - CLIENTE FTP DINAMICO
# ================================================================

leer_credenciales_ftp() {
    escribir_subtitulo "Conexion al servidor FTP privado"
    echo "  Ingrese las credenciales igual que en FileZilla."
    echo ""

    if [[ -n "$FTP_IP" ]]; then
        read -p "  IP actual: '$FTP_IP' ¿Cambiar? [S/N]: " cambiar
        [[ "$cambiar" =~ ^[Ss]$ ]] && read -p "  IP del servidor FTP: " FTP_IP
    else
        read -p "  IP del servidor FTP: " FTP_IP
    fi

    if [[ -n "$FTP_USER" ]]; then
        read -p "  Usuario FTP (Enter = '$FTP_USER'): " u
        [[ -n "$u" ]] && FTP_USER="$u"
    else
        read -p "  Usuario FTP: " FTP_USER
    fi

    read -s -p "  Contrasena FTP: " FTP_PASS
    echo ""
    echo "  Conectando como '$FTP_USER' a $FTP_IP..."
}

listar_ftp() {
    local ruta="$1"
    curl -s --max-time 15 --user "$FTP_USER:$FTP_PASS" \
        "ftp://$FTP_IP/$ruta/" 2>/dev/null | awk '{print $NF}' | grep -v '^\.\.' | grep -v '^\.$'
}

descargar_ftp() {
    local ruta="$1" destino="$2"
    curl -s --max-time 120 --user "$FTP_USER:$FTP_PASS" \
        "ftp://$FTP_IP/$ruta" -o "$destino" 2>/dev/null
}

verificar_sha256() {
    local archivo="$1" sha_file="$2"
    echo ""
    echo "  Verificando integridad SHA256..."

    local hash_calc; hash_calc=$(sha256sum "$archivo" | awk '{print $1}')
    local hash_esp;  hash_esp=$(awk '{print $1}' "$sha_file")

    echo "  Hash calculado : $hash_calc"
    echo "  Hash esperado  : $hash_esp"

    if [[ "$hash_calc" == "$hash_esp" ]]; then
        echo "  [OK] Integridad verificada."
        registrar_resumen "$(basename $archivo)" "SHA256" "OK" "Hash coincide"
        return 0
    else
        echo "  [ALERTA] El hash NO coincide."
        registrar_resumen "$(basename $archivo)" "SHA256" "ERROR" "Hash NO coincide"
        return 1
    fi
}

navegar_y_descargar_ftp() {
    local servicio_forzado="${1:-}"
    leer_credenciales_ftp

    echo ""
    echo "  Listando servicios en: $FTP_RUTA"
    local servicios; servicios=$(listar_ftp "$FTP_RUTA" | grep -v '\.')

    if [[ -z "$servicios" ]]; then
        echo "  No se encontraron servicios en el repositorio FTP."
        echo "  Verifique: usuario '$FTP_USER', repositorio preparado (op 3), mount bind 'http'."
        return 1
    fi

    local svc_elegido=""
    if [[ -n "$servicio_forzado" ]] && echo "$servicios" | grep -q "^${servicio_forzado}$"; then
        svc_elegido="$servicio_forzado"
        echo "  Servicio preseleccionado: $svc_elegido"
    else
        echo ""
        echo "  Servicios disponibles:"
        local i=1 arr_svc=()
        while IFS= read -r svc; do
            echo "    $i) $svc"
            arr_svc+=("$svc")
            ((i++))
        done <<< "$servicios"
        read -p "  Seleccione servicio: " sel
        svc_elegido="${arr_svc[$((sel-1))]}"
    fi

    local ruta_svc="$FTP_RUTA/$svc_elegido"
    local archivos; archivos=$(listar_ftp "$ruta_svc" | grep -E '\.(tar\.gz|rpm|war)$')

    if [[ -z "$archivos" ]]; then
        echo "  No se encontraron instaladores en $ruta_svc."
        return 1
    fi

    echo ""
    echo "  Versiones disponibles para $svc_elegido:"
    local i=1 arr_arch=()
    while IFS= read -r arch; do
        echo "    $i) $arch"
        arr_arch+=("$arch")
        ((i++))
    done <<< "$archivos"
    read -p "  Seleccione version: " sel2
    local arch_eleg="${arr_arch[$((sel2-1))]}"
    local arch_sha="${arch_eleg}.sha256"

    local tmp_dir; tmp_dir=$(mktemp -d)
    local dest_inst="$tmp_dir/$arch_eleg"
    local dest_sha="$tmp_dir/$arch_sha"

    echo ""
    echo "  Descargando instalador desde FTP..."
    if ! descargar_ftp "$ruta_svc/$arch_eleg" "$dest_inst" || [[ ! -s "$dest_inst" ]]; then
        echo "  ERROR al descargar $arch_eleg."
        registrar_resumen "$svc_elegido" "FTP-Descarga" "ERROR" "$arch_eleg"
        rm -rf "$tmp_dir"
        return 1
    fi
    echo "  Descargado: $arch_eleg"

    echo "  Descargando archivo .sha256..."
    if descargar_ftp "$ruta_svc/$arch_sha" "$dest_sha" && [[ -s "$dest_sha" ]]; then
        echo "  Descargado: $arch_sha"
        if ! verificar_sha256 "$dest_inst" "$dest_sha"; then
            read -p "  ¿Continuar de todas formas? [S/N]: " forzar
            if [[ "$forzar" =~ ^[Nn]$ ]]; then
                echo "  Instalacion cancelada."
                rm -rf "$tmp_dir"
                return 1
            fi
        fi
    else
        echo "  Advertencia: Sin .sha256. Continuando sin verificacion."
    fi

    registrar_resumen "$svc_elegido" "FTP-Descarga" "OK" "$arch_eleg"
    FTP_ARCHIVO_DESCARGADO="$dest_inst"
    FTP_SERVICIO_ELEGIDO="$svc_elegido"
    FTP_TMP_DIR="$tmp_dir"
    return 0
}

# ================================================================
# SECCION 5 - INSTALACION DE SERVICIOS HTTP
# ================================================================

crear_index_html() {
    local servicio="$1" version="$2" puerto="$3" directorio="$4"
    mkdir -p "$directorio"
    cat > "$directorio/index.html" <<HTMLEOF
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><title>$servicio - P7</title>
<style>
body{font-family:Arial,sans-serif;text-align:center;margin-top:80px;background:#f4f4f4}
.card{background:#fff;border-radius:8px;padding:40px;display:inline-block;box-shadow:0 2px 8px rgba(0,0,0,.15)}
h1{color:#2c3e50}h2{color:#27ae60}h3{color:#2980b9}
</style></head>
<body><div class="card">
<h1>Servidor: $servicio</h1>
<h2>Version: $version</h2>
<h3>Puerto: $puerto</h3>
<p>Practica 7 - Infraestructura de Despliegue Seguro</p>
</div></body></html>
HTMLEOF
    echo "  index.html creado en $directorio"
}

instalar_desde_tarball() {
    local archivo="$1" servicio="$2"
    local tmpdir; tmpdir=$(mktemp -d)
    echo "  Extrayendo $servicio desde tarball..."
    tar -xzf "$archivo" -C "$tmpdir" 2>/dev/null

    case "$servicio" in
        Apache)
            local rpm; rpm=$(find "$tmpdir" -name "httpd-*.rpm" | grep -v "devel\|manual\|tools" | head -1)
            if [[ -n "$rpm" ]]; then
                dnf install -y "$rpm" 2>/dev/null || rpm -ivh "$rpm" 2>/dev/null
            else
                dnf install -y httpd 2>/dev/null
            fi
            ;;
        Nginx)
            local rpm; rpm=$(find "$tmpdir" -name "nginx-*.rpm" | head -1)
            if [[ -n "$rpm" ]]; then
                rpm --import https://nginx.org/keys/nginx_signing.key 2>/dev/null
                dnf install -y "$rpm" --allowerasing 2>/dev/null || rpm -ivh "$rpm" 2>/dev/null
            else
                dnf install -y nginx 2>/dev/null
            fi
            ;;
        Tomcat)
            local tomcat_dir; tomcat_dir=$(find "$tmpdir" -maxdepth 1 -name "apache-tomcat-*" -type d | head -1)
            if [[ -z "$tomcat_dir" ]]; then
                local inner; inner=$(find "$tmpdir" -name "apache-tomcat-*.tar.gz" | head -1)
                if [[ -n "$inner" ]]; then
                    local tmpdir2; tmpdir2=$(mktemp -d)
                    tar -xzf "$inner" -C "$tmpdir2"
                    tomcat_dir=$(find "$tmpdir2" -maxdepth 1 -name "apache-tomcat-*" -type d | head -1)
                fi
            fi
            if [[ -n "$tomcat_dir" ]]; then
                pkill -f tomcat 2>/dev/null; sleep 2; rm -rf /opt/tomcat
                mv "$tomcat_dir" /opt/tomcat
                echo "  Tomcat extraido en /opt/tomcat"
            fi
            ;;
    esac
    rm -rf "$tmpdir"
}

# ── APACHE ───────────────────────────────────────────────────────────────────

obtener_puerto_apache() {
    grep -m1 "^Listen " /etc/httpd/conf/httpd.conf 2>/dev/null | awk '{print $2}'
}

instalar_apache_p7() {
    local version="$1" puerto="$2" archivo_tarball="${3:-}"
    local v_instalada; v_instalada=$(rpm -q httpd --queryformat "%{VERSION}" 2>/dev/null)

    if [[ -n "$v_instalada" ]]; then
        echo "  Apache ya instalado (v$v_instalada)."
        local p_actual; p_actual=$(obtener_puerto_apache)
        if [[ "$p_actual" != "$puerto" ]]; then
            echo "  Cambiando puerto $p_actual -> $puerto..."
            sed -i "s/^Listen .*/Listen $puerto/" /etc/httpd/conf/httpd.conf
            cerrar_firewall "$p_actual" 2>/dev/null
            abrir_firewall "$puerto"
            permitir_selinux_http "$puerto"
            systemctl restart httpd
            crear_index_html "Apache" "$v_instalada" "$puerto" "/var/www/html"
            registrar_resumen "Apache" "Puerto-Cambiado" "OK" "$p_actual -> $puerto"
            echo "  Puerto actualizado a $puerto."
        else
            echo "  Puerto ya configurado en $puerto."
        fi
        return 0
    fi

    systemctl stop httpd nginx 2>/dev/null

    if [[ -n "$archivo_tarball" ]]; then
        instalar_desde_tarball "$archivo_tarball" "Apache"
    else
        echo "  Instalando Apache $version via DNF..."
        dnf install -y "httpd${version:+"-$version"}" 2>/dev/null || dnf install -y httpd 2>/dev/null
    fi
    dnf install -y mod_ssl mod_headers 2>/dev/null

    sed -i "s/^Listen .*/Listen $puerto/" /etc/httpd/conf/httpd.conf

    cat > /etc/httpd/conf.d/security.conf <<'SECEOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>
SECEOF

    abrir_firewall "$puerto"
    permitir_selinux_http "$puerto"
    systemctl enable httpd
    systemctl restart httpd

    local v_real; v_real=$(rpm -q httpd --queryformat "%{VERSION}-%{RELEASE}" 2>/dev/null | sed 's/\.noarch$//')
    [[ -n "$v_real" ]] && version="$v_real"
    crear_index_html "Apache" "$version" "$puerto" "/var/www/html"

    local estado="OK"
    ss -tuln | grep -q ":$puerto " || estado="ADVERTENCIA"
    registrar_resumen "Apache" "Instalacion" "$estado" "v$version puerto $puerto"
    echo "  Apache instalado. v$version | Puerto: $puerto | Estado: $estado"
}

# ── NGINX ────────────────────────────────────────────────────────────────────

obtener_puerto_nginx() {
    grep -m1 "listen " /etc/nginx/conf.d/default.conf 2>/dev/null | awk '{print $2}' | tr -d ';'
}

configurar_nginx_puerto() {
    local puerto="$1"
    cat > /etc/nginx/conf.d/default.conf <<NGXEOF
server {
    listen $puerto;
    server_name _;
    root /usr/share/nginx/html;
    location / {
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
NGXEOF
}

instalar_nginx_p7() {
    local version="$1" puerto="$2" archivo_tarball="${3:-}"
    local v_instalada; v_instalada=$(rpm -q nginx --queryformat "%{VERSION}" 2>/dev/null)

    if [[ -n "$v_instalada" ]]; then
        echo "  Nginx ya instalado (v$v_instalada)."
        local p_actual; p_actual=$(obtener_puerto_nginx)
        if [[ "$p_actual" != "$puerto" ]]; then
            echo "  Cambiando puerto $p_actual -> $puerto..."
            configurar_nginx_puerto "$puerto"
            cerrar_firewall "$p_actual" 2>/dev/null
            abrir_firewall "$puerto"
            permitir_selinux_http "$puerto"
            systemctl restart nginx
            crear_index_html "Nginx" "$v_instalada" "$puerto" "/usr/share/nginx/html"
            registrar_resumen "Nginx" "Puerto-Cambiado" "OK" "$p_actual -> $puerto"
        else
            echo "  Puerto ya configurado en $puerto."
        fi
        return 0
    fi

    systemctl stop httpd nginx 2>/dev/null

    if [[ -n "$archivo_tarball" ]]; then
        instalar_desde_tarball "$archivo_tarball" "Nginx"
    else
        echo "  Instalando Nginx $version desde nginx.org..."
        local base_url="https://nginx.org/packages/rhel/9/x86_64/RPMS"
        local rpm_name="nginx-${version}-1.el9.ngx.x86_64.rpm"
        local tmp_rpm; tmp_rpm=$(mktemp)
        if curl -sSf --max-time 60 "$base_url/$rpm_name" -o "$tmp_rpm" 2>/dev/null; then
            rpm --import https://nginx.org/keys/nginx_signing.key 2>/dev/null
            dnf install -y "$tmp_rpm" --allowerasing 2>/dev/null
        else
            dnf install -y nginx 2>/dev/null
        fi
        rm -f "$tmp_rpm"
    fi

    local nginx_user; nginx_user=$(grep -m1 "^user " /etc/nginx/nginx.conf | awk '{print $2}' | tr -d ';')
    [[ -z "$nginx_user" ]] && nginx_user="nginx"
    rm -f /run/nginx.pid; touch /run/nginx.pid
    chown "${nginx_user}:${nginx_user}" /run/nginx.pid 2>/dev/null
    restorecon /run/nginx.pid 2>/dev/null

    if grep -q "server_tokens" /etc/nginx/nginx.conf; then
        sed -i "s/.*server_tokens.*/    server_tokens off;/" /etc/nginx/nginx.conf
    else
        sed -i "/^http[[:space:]]*{/a\    server_tokens off;" /etc/nginx/nginx.conf
    fi

    configurar_nginx_puerto "$puerto"
    abrir_firewall "$puerto"
    permitir_selinux_http "$puerto"
    systemctl enable nginx
    systemctl restart nginx

    local v_real; v_real=$(nginx -v 2>&1 | cut -d'/' -f2)
    [[ -n "$v_real" ]] && version="$v_real"
    crear_index_html "Nginx" "$version" "$puerto" "/usr/share/nginx/html"

    local estado="OK"
    ss -tuln | grep -q ":$puerto " || estado="ADVERTENCIA"
    registrar_resumen "Nginx" "Instalacion" "$estado" "v$version puerto $puerto"
    echo "  Nginx instalado. v$version | Puerto: $puerto | Estado: $estado"
}

# ── TOMCAT ───────────────────────────────────────────────────────────────────

obtener_puerto_tomcat() {
    grep -m1 'Connector port=' /opt/tomcat/conf/server.xml 2>/dev/null | grep -oP 'port="\K[0-9]+'
}

instalar_tomcat_p7() {
    local version="$1" puerto="$2" archivo_tarball="${3:-}"
    local v_instalada=""
    [[ -f /opt/tomcat/.tomcat_version ]] && v_instalada=$(cat /opt/tomcat/.tomcat_version)

    if [[ -n "$v_instalada" ]]; then
        echo "  Tomcat ya instalado (v$v_instalada)."
        local p_actual; p_actual=$(obtener_puerto_tomcat)
        if [[ "$p_actual" != "$puerto" ]]; then
            echo "  Cambiando puerto $p_actual -> $puerto..."
            sed -i "s/Connector port=\"[0-9]*\"/Connector port=\"$puerto\"/" /opt/tomcat/conf/server.xml
            cerrar_firewall "$p_actual" 2>/dev/null
            abrir_firewall "$puerto"
            permitir_selinux_http "$puerto"
            pkill -f tomcat 2>/dev/null; sleep 2
            sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk CATALINA_HOME=/opt/tomcat \
                /opt/tomcat/bin/startup.sh 2>/dev/null
            crear_index_html "Tomcat" "$v_instalada" "$puerto" "/opt/tomcat/webapps/ROOT"
            registrar_resumen "Tomcat" "Puerto-Cambiado" "OK" "$p_actual -> $puerto"
        else
            echo "  Puerto ya configurado en $puerto."
        fi
        return 0
    fi

    dnf install -y java-21-openjdk java-21-openjdk-devel 2>/dev/null

    if [[ -n "$archivo_tarball" ]]; then
        instalar_desde_tarball "$archivo_tarball" "Tomcat"
    else
        echo "  Descargando Tomcat $version..."
        local major="${version%%.*}"
        local url="https://archive.apache.org/dist/tomcat/tomcat-${major}/v${version}/bin/apache-tomcat-${version}.tar.gz"
        local tmpdir; tmpdir=$(mktemp -d)
        wget -q --timeout=120 "$url" -O "$tmpdir/tomcat.tar.gz" || \
            curl -sSf --max-time 120 "$url" -o "$tmpdir/tomcat.tar.gz"
        tar -xzf "$tmpdir/tomcat.tar.gz" -C "$tmpdir"
        pkill -f tomcat 2>/dev/null; sleep 2; rm -rf /opt/tomcat
        mv "$tmpdir/apache-tomcat-$version" /opt/tomcat
        rm -rf "$tmpdir"
    fi

    [[ ! -f /opt/tomcat/bin/startup.sh ]] && { echo "  ERROR: startup.sh no encontrado."; return 1; }

    echo "$version" > /opt/tomcat/.tomcat_version
    id tomcatsvc &>/dev/null || useradd -r -s /sbin/nologin -d /opt/tomcat tomcatsvc
    chown -R tomcatsvc:tomcatsvc /opt/tomcat

    sed -i "s/Connector port=\"8080\"/Connector port=\"$puerto\"/" /opt/tomcat/conf/server.xml
    sed -i 's|protocol="org.apache.coyote.http11.Http11NioProtocol"|protocol="org.apache.coyote.http11.Http11NioProtocol" server="Apache-Tomcat"|' \
        /opt/tomcat/conf/server.xml

    abrir_firewall "$puerto"
    permitir_selinux_http "$puerto"
    crear_index_html "Tomcat" "$version" "$puerto" "/opt/tomcat/webapps/ROOT"

    sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk CATALINA_HOME=/opt/tomcat \
        /opt/tomcat/bin/startup.sh 2>/dev/null

    echo "  Esperando que Tomcat inicie en puerto $puerto..."
    for i in {1..20}; do
        ss -tuln | grep -q ":$puerto " && break
        echo "  Intento $i/20..."; sleep 1
    done

    local estado="OK"
    ss -tuln | grep -q ":$puerto " || estado="ADVERTENCIA"
    registrar_resumen "Tomcat" "Instalacion" "$estado" "v$version puerto $puerto"
    echo "  Tomcat instalado. v$version | Puerto: $puerto | Estado: $estado"
}

# ── FLUJO DE INSTALACION ─────────────────────────────────────────────────────

flujo_instalar_servicio() {
    local servicio="$1"
    escribir_titulo "INSTALAR $servicio"

    echo "  Fuente de instalacion:"
    echo "    1) WEB - Repositorio oficial (DNF / descarga directa)"
    echo "    2) FTP - Repositorio privado (requiere repositorio preparado)"
    echo ""
    read -p "  Seleccione fuente [1/2]: " fuente

    local archivo_tarball="" version="" servicio_real="$servicio"
    FTP_ARCHIVO_DESCARGADO="" FTP_SERVICIO_ELEGIDO="" FTP_TMP_DIR=""

    if [[ "$fuente" == "1" ]]; then
        case "$servicio" in
            Apache)
                echo ""
                echo "  Consultando versiones de Apache via DNF..."
                local versiones; versiones=$(dnf list --showduplicates httpd 2>/dev/null | grep "httpd\.x86_64" | awk '{print $2}' | sort -V | uniq)
                local v_latest="2.4.62" v_lts="2.4.51" v_oldest="2.4.37"
                [[ -n "$(echo "$versiones" | tail -n 1)" ]] && v_latest=$(echo "$versiones" | tail -n 1)
                [[ -n "$(echo "$versiones" | sed -n '2p')" ]] && v_lts=$(echo "$versiones" | sed -n '2p')
                [[ -n "$(echo "$versiones" | head -n 1)" ]] && v_oldest=$(echo "$versiones" | head -n 1)
                echo "  Versiones disponibles de Apache:"
                echo "    1) $v_latest  (Latest / Desarrollo)"
                echo "    2) $v_lts     (LTS / Estable)"
                echo "    3) $v_oldest  (Oldest)"
                read -p "  Seleccione version [1-3]: " sel
                case "$sel" in 1) version="$v_latest" ;; 2) version="$v_lts" ;; 3) version="$v_oldest" ;; *) version="$v_latest" ;; esac
                ;;
            Nginx)
                echo ""
                local base_url="https://nginx.org/packages/rhel/9/x86_64/RPMS"
                local v_latest="1.26.3" v_lts="1.24.0" v_oldest="1.20.2"
                local raw; raw=$(curl -s --max-time 10 "$base_url/" 2>/dev/null | grep -oP 'nginx-\K[0-9]+\.[0-9]+\.[0-9]+(?=-[0-9]+\.el9\.ngx\.x86_64\.rpm)' | sort -V | uniq)
                if [[ -n "$raw" ]]; then
                    v_latest=$(echo "$raw" | tail -n 1)
                    v_lts=$(echo "$raw" | grep "^1\.24" | tail -n 1)
                    [[ -z "$v_lts" ]] && v_lts=$(echo "$raw" | tail -n 2 | head -n 1)
                    v_oldest=$(echo "$raw" | head -n 1)
                fi
                echo "  Versiones disponibles de Nginx:"
                echo "    1) $v_latest  (Latest / Desarrollo)"
                echo "    2) $v_lts     (LTS / Estable)"
                echo "    3) $v_oldest  (Oldest)"
                read -p "  Seleccione version [1-3]: " sel
                case "$sel" in 1) version="$v_latest" ;; 2) version="$v_lts" ;; 3) version="$v_oldest" ;; *) version="$v_latest" ;; esac
                ;;
            Tomcat)
                echo ""
                echo "  Versiones disponibles de Tomcat:"
                echo "    1) 10.1.28  (Latest / Desarrollo)"
                echo "    2) 10.1.26  (LTS / Estable)"
                echo "    3) 9.0.91   (Oldest)"
                read -p "  Seleccione version [1-3]: " sel
                case "$sel" in 1) version="10.1.28" ;; 2) version="10.1.26" ;; 3) version="9.0.91" ;; *) version="10.1.28" ;; esac
                ;;
        esac
    else
        if ! navegar_y_descargar_ftp "$servicio"; then
            echo "  Instalacion cancelada."
            return 1
        fi
        archivo_tarball="$FTP_ARCHIVO_DESCARGADO"
        servicio_real="$FTP_SERVICIO_ELEGIDO"
        echo "  Servicio a instalar: $servicio_real"
    fi

    local puerto_sug
    case "$servicio_real" in
        Apache) puerto_sug=8080 ;;
        Nginx)  puerto_sug=8181 ;;
        Tomcat) puerto_sug=8009 ;;
        *)      puerto_sug=8080 ;;
    esac
    ss -tuln | grep -q ":$puerto_sug " && puerto_sug=$((puerto_sug + 1))

    echo ""
    read -p "  Puerto de escucha (sugerido: $puerto_sug, Enter = $puerto_sug): " puerto
    [[ -z "$puerto" ]] && puerto="$puerto_sug"

    case "$servicio_real" in
        Apache) instalar_apache_p7 "$version" "$puerto" "$archivo_tarball" ;;
        Nginx)  instalar_nginx_p7  "$version" "$puerto" "$archivo_tarball" ;;
        Tomcat) instalar_tomcat_p7 "$version" "$puerto" "$archivo_tarball" ;;
        *)      echo "  Servicio '$servicio_real' no reconocido." ;;
    esac

    [[ -n "$FTP_TMP_DIR" ]] && rm -rf "$FTP_TMP_DIR"
}

# ================================================================
# SECCION 6 - SSL/TLS
# ================================================================

pedir_dominio() {
    if [[ -n "$DOMINIO_SSL" ]]; then
        read -p "  Dominio actual: '$DOMINIO_SSL' ¿Cambiar? [S/N]: " cambiar
        [[ "$cambiar" =~ ^[Ss]$ ]] && read -p "  Nuevo dominio SSL: " DOMINIO_SSL
    else
        read -p "  Dominio para el certificado (Enter = $DOMINIO_DEFAULT): " DOMINIO_SSL
        [[ -z "$DOMINIO_SSL" ]] && DOMINIO_SSL="$DOMINIO_DEFAULT"
    fi
}

generar_certificado_ssl() {
    local dominio="$1" dir_ssl="$2"
    local cert="$dir_ssl/server.crt" key="$dir_ssl/server.key"
    mkdir -p "$dir_ssl"

    if [[ -f "$cert" && -f "$key" ]]; then
        local cn; cn=$(openssl x509 -subject -noout -in "$cert" 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' | head -1)
        if [[ "$cn" == "$dominio" ]]; then
            echo "  Certificado para '$dominio' ya existe y es valido."
            return 0
        fi
    fi

    echo "  Generando certificado autofirmado para '$dominio'..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key" -out "$cert" \
        -subj "/CN=$dominio/O=Practica7/OU=P7-SSL" 2>/dev/null

    if [[ -f "$cert" && -f "$key" ]]; then
        local expiry; expiry=$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)
        echo "  Certificado generado: CN=$dominio | Expira: $expiry"
        registrar_resumen "$dominio" "Cert-Generado" "OK" "CN=$dominio"
        return 0
    fi
    echo "  ERROR: No se pudo generar el certificado."
    return 1
}

activar_ssl_apache() {
    escribir_titulo "ACTIVAR SSL/TLS EN APACHE"
    rpm -q httpd &>/dev/null || { echo "  ERROR: Apache no instalado."; return 1; }

    pedir_dominio
    local dominio="$DOMINIO_SSL" ssl_dir="/etc/httpd/ssl"
    generar_certificado_ssl "$dominio" "$ssl_dir" || return 1

    local p_http; p_http=$(obtener_puerto_apache); [[ -z "$p_http" ]] && p_http=80

    cat > /etc/httpd/conf.d/ssl_p7.conf <<SSLEOF
Listen 443 https

SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache         shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout  300

<VirtualHost *:443>
    ServerName $dominio
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile    $ssl_dir/server.crt
    SSLCertificateKeyFile $ssl_dir/server.key
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite HIGH:!aNULL:!MD5
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</VirtualHost>

<VirtualHost *:$p_http>
    ServerName $dominio
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
SSLEOF

    abrir_firewall 443
    permitir_selinux_http 443
    restorecon -Rv "$ssl_dir" 2>/dev/null
    systemctl restart httpd

    local estado="OK"
    ss -tuln | grep -q ":443 " || estado="ADVERTENCIA"
    echo "  Apache HTTPS 443: $estado | Dominio: $dominio"
    registrar_resumen "Apache" "SSL-443" "$estado" "Dominio: $dominio"
}

activar_ssl_nginx() {
    escribir_titulo "ACTIVAR SSL/TLS EN NGINX"
    command -v nginx &>/dev/null || { echo "  ERROR: Nginx no instalado."; return 1; }

    pedir_dominio
    local dominio="$DOMINIO_SSL" ssl_dir="/etc/nginx/ssl"
    generar_certificado_ssl "$dominio" "$ssl_dir" || return 1

    local p_http; p_http=$(obtener_puerto_nginx); [[ -z "$p_http" ]] && p_http=80

    cat > /etc/nginx/conf.d/default.conf <<NGXEOF
server {
    listen $p_http;
    server_name $dominio;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $dominio;
    root /usr/share/nginx/html;
    ssl_certificate     $ssl_dir/server.crt;
    ssl_certificate_key $ssl_dir/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    location / {
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
NGXEOF

    abrir_firewall 443
    permitir_selinux_http 443
    restorecon -Rv "$ssl_dir" 2>/dev/null
    nginx -t 2>&1 | grep -q "successful" || { echo "  ERROR de sintaxis en Nginx."; return 1; }
    systemctl restart nginx

    local estado="OK"
    ss -tuln | grep -q ":443 " || estado="ADVERTENCIA"
    echo "  Nginx HTTPS 443: $estado | Dominio: $dominio"
    registrar_resumen "Nginx" "SSL-443" "$estado" "Dominio: $dominio"
}

activar_ssl_tomcat() {
    escribir_titulo "ACTIVAR SSL/TLS EN TOMCAT"
    [[ -f /opt/tomcat/bin/startup.sh ]] || { echo "  ERROR: Tomcat no instalado."; return 1; }

    pedir_dominio
    local dominio="$DOMINIO_SSL"
    local ssl_dir="/opt/tomcat/ssl"
    local keystore="$ssl_dir/keystore.p12"
    local keystore_pass="P7Tomcat2024"

    mkdir -p "$ssl_dir"
    echo "  Generando keystore para Tomcat..."
    keytool -genkeypair -alias tomcat -keyalg RSA -keysize 2048 -validity 365 \
        -keystore "$keystore" -storetype PKCS12 -storepass "$keystore_pass" \
        -dname "CN=$dominio, O=Practica7, OU=P7-SSL" 2>/dev/null

    [[ -f "$keystore" ]] || { echo "  ERROR: No se pudo generar el keystore."; return 1; }
    echo "  Keystore generado."

    local server_xml="/opt/tomcat/conf/server.xml"
    sed -i '/<Connector port="8443"/,/\/>/d' "$server_xml"
    sed -i "/<\/Service>/i\\
    <Connector port=\"8443\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\\
               SSLEnabled=\"true\" maxThreads=\"150\" scheme=\"https\" secure=\"true\"\\
               keystoreFile=\"$keystore\" keystorePass=\"$keystore_pass\"\\
               clientAuth=\"false\" sslProtocol=\"TLS\"/>" "$server_xml"

    abrir_firewall 8443
    permitir_selinux_http 8443
    chown -R tomcatsvc:tomcatsvc "$ssl_dir"
    pkill -f tomcat 2>/dev/null; sleep 2
    sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk CATALINA_HOME=/opt/tomcat \
        /opt/tomcat/bin/startup.sh 2>/dev/null

    echo "  Esperando que Tomcat inicie en puerto 8443..."
    for i in {1..20}; do
        ss -tuln | grep -q ":8443 " && break
        echo "  Intento $i/20..."; sleep 1
    done

    local estado="OK"
    ss -tuln | grep -q ":8443 " || estado="ADVERTENCIA"
    echo "  Tomcat HTTPS 8443: $estado | Dominio: $dominio"
    registrar_resumen "Tomcat" "SSL-8443" "$estado" "Dominio: $dominio"
}

activar_ftps_vsftpd() {
    escribir_titulo "ACTIVAR FTPS EN VSFTPD"
    rpm -q vsftpd &>/dev/null || { echo "  ERROR: vsftpd no instalado."; return 1; }

    pedir_dominio
    local dominio="$DOMINIO_SSL" ssl_dir="/etc/vsftpd/ssl"
    generar_certificado_ssl "$dominio" "$ssl_dir" || return 1

    local conf="$FTP_CONF"
    local cert="$ssl_dir/server.crt" key="$ssl_dir/server.key"

    for d in "ssl_enable=YES" "allow_anon_ssl=NO" "force_local_data_ssl=YES" \
              "force_local_logins_ssl=YES" "ssl_tlsv1=YES" "ssl_sslv2=NO" \
              "ssl_sslv3=NO" "require_ssl_reuse=NO" "ssl_ciphers=HIGH" \
              "rsa_cert_file=$cert" "rsa_private_key_file=$key"; do
        local param="${d%%=*}"
        if grep -q "^$param=" "$conf"; then
            sed -i "s|^$param=.*|$d|" "$conf"
        else
            echo "$d" >> "$conf"
        fi
    done

    restorecon -Rv "$ssl_dir" 2>/dev/null
    abrir_firewall 990
    systemctl restart vsftpd

    local estado="OK"
    systemctl is-active --quiet vsftpd || estado="ADVERTENCIA"
    echo "  FTPS vsftpd: $estado | Dominio: $dominio"
    echo "  Verificar: openssl s_client -connect $(hostname -I | awk '{print $1}'):21 -starttls ftp"
    registrar_resumen "vsftpd" "FTPS-SSL" "$estado" "Dominio: $dominio"
}

# ================================================================
# SECCION 7 - GESTION DE SERVICIOS
# ================================================================

gestionar_servicios_http() {
    escribir_titulo "GESTIONAR SERVICIOS HTTP"

    local httpd_est nginx_est tomcat_est ftp_est
    systemctl is-active --quiet httpd  && httpd_est="ACTIVO"  || httpd_est="DETENIDO"
    systemctl is-active --quiet nginx  && nginx_est="ACTIVO"  || nginx_est="DETENIDO"
    pgrep -f tomcat &>/dev/null        && tomcat_est="ACTIVO" || tomcat_est="DETENIDO"
    systemctl is-active --quiet vsftpd && ftp_est="ACTIVO"    || ftp_est="DETENIDO"
    rpm -q httpd  &>/dev/null || httpd_est="NO INSTALADO"
    command -v nginx &>/dev/null || nginx_est="NO INSTALADO"
    [[ -f /opt/tomcat/bin/startup.sh ]] || tomcat_est="NO INSTALADO"
    rpm -q vsftpd &>/dev/null || ftp_est="NO INSTALADO"

    echo "  Estado actual:"
    echo ""
    printf "    %-10s %s\n" "Apache"  "$httpd_est"
    printf "    %-10s %s\n" "Nginx"   "$nginx_est"
    printf "    %-10s %s\n" "Tomcat"  "$tomcat_est"
    printf "    %-10s %s\n" "vsftpd"  "$ftp_est"
    echo ""
    echo "  Acciones:"
    echo "    1) Detener Apache    2) Iniciar Apache"
    echo "    3) Detener Nginx     4) Iniciar Nginx"
    echo "    5) Detener Tomcat    6) Iniciar Tomcat"
    echo "    7) Detener vsftpd    8) Iniciar vsftpd"
    echo "    9) Detener TODOS     0) Volver"
    echo ""
    read -p "  Seleccione: " op

    case "$op" in
        1) systemctl stop httpd;   echo "  Apache detenido." ;;
        2) systemctl start httpd;  echo "  Apache iniciado." ;;
        3) systemctl stop nginx;   echo "  Nginx detenido." ;;
        4) systemctl start nginx;  echo "  Nginx iniciado." ;;
        5) pkill -f tomcat 2>/dev/null; echo "  Tomcat detenido." ;;
        6)
            if [[ -f /opt/tomcat/bin/startup.sh ]]; then
                sudo -u tomcatsvc env JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
                    CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh 2>/dev/null
                echo "  Tomcat iniciado."
            else
                echo "  ERROR: Tomcat no instalado."
            fi
            ;;
        7) systemctl stop vsftpd;  echo "  vsftpd detenido." ;;
        8) systemctl start vsftpd; echo "  vsftpd iniciado." ;;
        9)
            systemctl stop httpd nginx 2>/dev/null
            pkill -f tomcat 2>/dev/null
            echo "  Todos detenidos. Inicie el que desea demostrar."
            ;;
        0) return ;;
        *) echo "  Opcion no valida." ;;
    esac
}

# ================================================================
# SECCION 8 - ESTADO Y RESUMEN
# ================================================================

ver_estado_servicios() {
    escribir_titulo "ESTADO DE SERVICIOS"

    local p_apache p_nginx p_tomcat
    p_apache=$(obtener_puerto_apache); [[ -z "$p_apache" ]] && p_apache=8080
    p_nginx=$(obtener_puerto_nginx);   [[ -z "$p_nginx" ]]  && p_nginx=8181
    p_tomcat=$(obtener_puerto_tomcat); [[ -z "$p_tomcat" ]] && p_tomcat=8009

    printf "  %-16s %-8s %s\n" "Servicio" "Puerto" "Estado"
    printf "  %-16s %-8s %s\n" "--------" "------" "------"

    for check in "Apache HTTP:$p_apache" "Apache HTTPS:443" \
                 "Nginx HTTP:$p_nginx"   "Nginx HTTPS:443" \
                 "Tomcat HTTP:$p_tomcat" "Tomcat HTTPS:8443" \
                 "FTP:21"                "FTPS:990"; do
        local nombre="${check%%:*}" puerto="${check##*:}" estado
        ss -tuln 2>/dev/null | grep -q ":$puerto " && estado="ACTIVO" || estado="INACTIVO"
        printf "  %-16s %-8s %s\n" "$nombre" "$puerto" "$estado"
    done

    echo ""
    echo "  Certificados SSL instalados (P7):"
    for cert_file in /etc/httpd/ssl/server.crt /etc/nginx/ssl/server.crt /etc/vsftpd/ssl/server.crt; do
        if [[ -f "$cert_file" ]]; then
            local cn expiry
            cn=$(openssl x509 -subject -noout -in "$cert_file" 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,/]+' | head -1)
            expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
            printf "    %-45s Expira: %s\n" "Sujeto: CN=$cn" "$expiry"
        fi
    done
    [[ -f /opt/tomcat/ssl/keystore.p12 ]] && echo "    Keystore Tomcat: /opt/tomcat/ssl/keystore.p12"
}

mostrar_resumen_final() {
    escribir_titulo "RESUMEN FINAL - PRACTICA 7 LINUX"

    if [[ ! -f "$RESUMEN_FILE" || ! -s "$RESUMEN_FILE" ]]; then
        echo "  No hay acciones registradas aun."
        ver_estado_servicios
        return
    fi

    printf "  %-18s | %-14s | %-11s | %s\n" "Servicio" "Accion" "Estado" "Detalle"
    printf "  %-18s | %-14s | %-11s | %s\n" "------------------" "--------------" "-----------" "-------"
    while IFS='|' read -r srv acc est det; do
        printf "  %-18s | %-14s | %-11s | %s\n" "$srv" "$acc" "$est" "$det"
    done < "$RESUMEN_FILE"

    local ok adv err
    ok=$(grep -c "| OK |"          "$RESUMEN_FILE" 2>/dev/null || echo 0)
    adv=$(grep -c "| ADVERTENCIA |" "$RESUMEN_FILE" 2>/dev/null || echo 0)
    err=$(grep -c "| ERROR |"       "$RESUMEN_FILE" 2>/dev/null || echo 0)

    echo ""
    echo "  OK          : $ok"
    echo "  ADVERTENCIA : $adv"
    echo "  ERROR       : $err"

    ver_estado_servicios

    local ip; ip=$(hostname -I | awk '{print $1}')
    echo ""
    echo "  Comandos para verificar SSL (evidencias):"
    echo "    curl -k -I https://$ip"
    echo "    openssl s_client -connect $ip:443 -servername $DOMINIO_SSL"
    echo "    curl -k -I https://$ip:8443"
    echo "    openssl s_client -connect $ip:8443"
    echo "    openssl s_client -connect $ip:21 -starttls ftp"
}

# ================================================================
# SECCION 9 - ADMINISTRACION FTP LOCAL (P5 integrado)
# ================================================================

ftp_configurar_firewall() {
    systemctl is-active --quiet firewalld || return
    firewall-cmd --permanent --add-service=ftp 2>/dev/null
    firewall-cmd --permanent --add-port=40000-40100/tcp 2>/dev/null
    firewall-cmd --reload 2>/dev/null
    echo "  Firewall configurado para FTP."
}

ftp_configurar_selinux() {
    if command -v getenforce &>/dev/null && [[ "$(getenforce 2>/dev/null)" == "Enforcing" ]]; then
        setsebool -P ftpd_full_access 1
        echo "  SELinux configurado para FTP."
    fi
}

ftp_instalar() {
    escribir_titulo "INSTALAR SERVIDOR FTP (vsftpd)"
    if rpm -q vsftpd &>/dev/null; then
        echo "  vsftpd ya instalado."
        read -p "  ¿Reinstalar? [S/N]: " op
        [[ "$op" =~ ^[Ss]$ ]] && dnf reinstall -y vsftpd > /dev/null 2>&1
    else
        echo "  Instalando vsftpd..."
        dnf install -y vsftpd acl > /dev/null 2>&1
    fi
    systemctl enable vsftpd; systemctl start vsftpd
    ftp_configurar_firewall; ftp_configurar_selinux
    registrar_resumen "vsftpd" "Instalacion" "OK"
    echo "  vsftpd instalado y activo."
}

ftp_configurar() {
    escribir_titulo "CONFIGURAR VSFTPD"
    local conf="$FTP_CONF"
    cp -n "$conf" "${conf}.bak" 2>/dev/null

    for d in "anonymous_enable=YES" "local_enable=YES" "write_enable=YES" \
              "chroot_local_user=YES" "allow_writeable_chroot=YES" "pasv_enable=YES" \
              "pasv_min_port=40000" "pasv_max_port=40100" "anon_upload_enable=NO" \
              "anon_mkdir_write_enable=NO" "hide_ids=YES" "local_umask=002" \
              "anon_world_readable_only=YES" "anon_root=/ftp/public"; do
        local param="${d%%=*}"
        if grep -q "^$param=" "$conf"; then
            sed -i "s|^$param=.*|$d|" "$conf"
        else
            echo "$d" >> "$conf"
        fi
    done
    systemctl restart vsftpd
    echo "  vsftpd configurado correctamente."
}

ftp_crear_grupos() {
    escribir_titulo "CREAR GRUPOS FTP"
    for g in reprobados recursadores ftpusuarios; do
        getent group "$g" > /dev/null && echo "  Grupo '$g' ya existe." || { groupadd "$g"; echo "  Grupo '$g' creado."; }
    done
}

ftp_crear_estructura() {
    escribir_titulo "CREAR ESTRUCTURA DE CARPETAS FTP"
    mkdir -p /ftp/public/general
    mkdir -p /ftp/public/http/Linux/{Apache,Nginx,Tomcat}
    mkdir -p /ftp/users/{reprobados,recursadores}
    mkdir -p /ftp/general
    mountpoint -q /ftp/general || mount --bind /ftp/public/general /ftp/general
    ln -sfn /ftp/users/reprobados   /ftp/reprobados  2>/dev/null
    ln -sfn /ftp/users/recursadores /ftp/recursadores 2>/dev/null
    chmod 755 /ftp /ftp/public
    chmod 775 /ftp/public/general
    echo "  Estructura de carpetas creada."
}

ftp_asignar_permisos() {
    escribir_titulo "APLICAR PERMISOS FTP"
    chown root:root /ftp; chmod 755 /ftp /ftp/users
    chown root:reprobados  /ftp/users/reprobados;  chmod 2770 /ftp/users/reprobados
    chown root:recursadores /ftp/users/recursadores; chmod 2770 /ftp/users/recursadores
    chown root:ftpusuarios /ftp/public/general; chmod 775 /ftp/public/general
    setfacl -m g:ftpusuarios:rwx /ftp/public/general
    setfacl -m u:ftp:rx /ftp /ftp/public /ftp/public/general
    echo "  Permisos aplicados correctamente."
}

ftp_crear_usuarios() {
    escribir_titulo "CREAR USUARIOS FTP"
    read -p "  Numero de usuarios a crear: " num
    for (( i=1; i<=num; i++ )); do
        echo ""; echo "  --- Usuario $i de $num ---"
        read -p "  Nombre de usuario: " nombre
        if id "$nombre" &>/dev/null; then echo "  El usuario '$nombre' ya existe."; continue; fi
        read -s -p "  Contrasena: " password; echo ""
        read -p "  Grupo (reprobados/recursadores): " grupo
        [[ "$grupo" != "reprobados" && "$grupo" != "recursadores" ]] && { echo "  Grupo invalido."; continue; }

        useradd -m -d "/ftp/users/$nombre" -s /bin/bash -g "$grupo" -G ftpusuarios "$nombre"
        echo "$nombre:$password" | chpasswd
        mkdir -p "/ftp/users/$nombre/{general,$grupo,$nombre,http}"
        mountpoint -q "/ftp/users/$nombre/general" || mount --bind /ftp/public/general "/ftp/users/$nombre/general"
        mountpoint -q "/ftp/users/$nombre/$grupo"   || mount --bind "/ftp/users/$grupo" "/ftp/users/$nombre/$grupo"
        mountpoint -q "/ftp/users/$nombre/http"     || mount --bind /ftp/public/http "/ftp/users/$nombre/http"
        chown -R "$nombre:$grupo" "/ftp/users/$nombre/$nombre"; chmod 700 "/ftp/users/$nombre/$nombre"
        echo "  Usuario '$nombre' creado en grupo '$grupo'."
    done
    systemctl restart vsftpd
    echo ""; echo "  Usuarios creados correctamente."
}

ftp_cambiar_grupo() {
    escribir_titulo "CAMBIAR GRUPO DE USUARIO FTP"
    ftp_ver_usuarios
    read -p "  Nombre del usuario: " nombre
    id "$nombre" &>/dev/null || { echo "  El usuario '$nombre' no existe."; return; }
    read -p "  Nuevo grupo (reprobados/recursadores): " nuevo_grupo
    [[ "$nuevo_grupo" != "reprobados" && "$nuevo_grupo" != "recursadores" ]] && { echo "  Grupo invalido."; return; }
    local grupo_actual; grupo_actual=$(id -gn "$nombre")
    usermod -g "$nuevo_grupo" "$nombre"
    chown -R "$nombre:$nuevo_grupo" "/ftp/users/$nombre"
    if mountpoint -q "/ftp/users/$nombre/$grupo_actual"; then
        umount -l "/ftp/users/$nombre/$grupo_actual"; rm -rf "/ftp/users/$nombre/$grupo_actual"
    fi
    mkdir -p "/ftp/users/$nombre/$nuevo_grupo"
    mount --bind "/ftp/users/$nuevo_grupo" "/ftp/users/$nombre/$nuevo_grupo"
    chown ":$nuevo_grupo" "/ftp/users/$nombre/$nuevo_grupo"; chmod 775 "/ftp/users/$nombre/$nuevo_grupo"
    systemctl restart vsftpd
    echo "  Usuario '$nombre' movido al grupo '$nuevo_grupo'."
}

ftp_ver_usuarios() {
    echo ""; echo "  Usuarios FTP registrados:"; echo ""
    local miembros; miembros=$(getent group ftpusuarios 2>/dev/null | cut -d: -f4 | tr ',' '\n')
    if [[ -z "$miembros" ]]; then echo "  (No hay usuarios en ftpusuarios)"; return; fi
    while IFS= read -r u; do
        local grupo; grupo=$(id -gn "$u" 2>/dev/null)
        printf "    %-20s Grupo: %s\n" "$u" "$grupo"
    done <<< "$miembros"
    echo ""
}

ftp_ver_estado() {
    echo ""; echo "  Servicio vsftpd:"
    systemctl is-active --quiet vsftpd && echo "    Estado: ACTIVO" || echo "    Estado: INACTIVO"
    echo ""; echo "  Puerto 21:"
    ss -tuln | grep ":21 " || echo "    No hay nada escuchando en puerto 21."
}

menu_administrar_ftp() {
    while true; do
        escribir_titulo "ADMINISTRAR SERVIDOR FTP LOCAL"
        echo "  -- CONFIGURACION INICIAL --"
        echo "   1) Instalar vsftpd"
        echo "   2) Configurar vsftpd"
        echo "   3) Crear grupos (reprobados, recursadores, ftpusuarios)"
        echo "   4) Crear estructura de carpetas"
        echo "   5) Aplicar permisos"
        echo ""
        echo "  -- GESTION DE USUARIOS --"
        echo "   6) Crear usuario(s) FTP"
        echo "   7) Cambiar grupo de usuario"
        echo "   8) Ver usuarios FTP"
        echo ""
        echo "  -- UTILIDADES --"
        echo "   9) Ver estado del servidor FTP"
        echo "  10) Reiniciar vsftpd"
        echo "   0) Volver al menu principal"
        echo ""
        read -p "  Seleccione: " op
        case "$op" in
            1)  ftp_instalar ;;
            2)  ftp_configurar ;;
            3)  ftp_crear_grupos ;;
            4)  ftp_crear_estructura ;;
            5)  ftp_asignar_permisos ;;
            6)  ftp_crear_usuarios ;;
            7)  ftp_cambiar_grupo ;;
            8)  ftp_ver_usuarios ;;
            9)  ftp_ver_estado ;;
            10) systemctl restart vsftpd && echo "  vsftpd reiniciado." ;;
            0)  return ;;
            *)  echo "  Opcion no valida." ;;
        esac
    done
}
