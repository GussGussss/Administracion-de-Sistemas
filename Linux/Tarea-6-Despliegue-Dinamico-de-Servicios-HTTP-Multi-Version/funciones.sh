#!/bin/bash
#########################################
# Preparar repositorios silenciosamente
#########################################

preparar_repositorios() {

# instalar utilidades necesarias
dnf install -y dnf-plugins-core yum-utils epel-release

# limpiar cache
dnf clean all
dnf makecache

}

#########################################
# Validar puerto
#########################################

validar_puerto() {

PUERTO=$1

if [[ ! $PUERTO =~ ^[0-9]+$ ]]; then
    echo "Puerto inválido"
    return 1
fi

if ((PUERTO < 1 || PUERTO > 65535)); then
    echo "Puerto fuera de rango"
    return 1
fi
if [[ $PUERTO == 22 || $PUERTO == 25 || $PUERTO == 53 ]]; then
    echo "Puerto reservado por el sistema"
    return 1
fi
if ss -tuln | grep -q ":$PUERTO "; then
    echo "El puerto ya está en uso"
    return 1
fi

return 0
}

#########################################
# Gestionar puerto general
#########################################

gestionar_puerto() {

PUERTO=$1

validar_puerto $PUERTO

if [ $? -ne 0 ]; then
    echo "Error: puerto inválido o en uso"
    return 1
fi

abrir_firewall $PUERTO

return 0

}


#########################################
# Abrir puerto en firewall
#########################################

abrir_firewall() {

PUERTO=$1

firewall-cmd --permanent --add-port=${PUERTO}/tcp
firewall-cmd --reload

}

#########################################
# Permitir puerto HTTP en SELinux
#########################################

permitir_puerto_selinux() {

PUERTO=$1

if command -v semanage >/dev/null 2>&1; then
    if ! semanage port -l | grep -q "http_port_t.*\\b$PUERTO\\b"; then
        semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
        semanage port -m -t http_port_t -p tcp $PUERTO
    fi
fi

}

#########################################
# Detener servidores HTTP para evitar conflictos
#########################################

detener_servicios_http() {

systemctl stop httpd 2>/dev/null
systemctl stop nginx 2>/dev/null

}

#########################################
# Obtener versiones de Apache disponibles
#########################################

listar_versiones_apache() {

echo "Buscando versiones disponibles de Apache en los repositorios..."
echo ""

echo "[dnf] Consultando: dnf list --showduplicates httpd"
VERSIONES=$(dnf list --showduplicates httpd \
| grep httpd.x86_64 \
| awk '{print $2}' \
| sort -V \
| uniq)

echo ""
echo "Versiones encontradas en el repositorio:"
echo "$VERSIONES"
echo ""

OLDEST=$(echo "$VERSIONES" | head -n 1)
LATEST=$(echo "$VERSIONES" | tail -n 1)
LTS=$(echo "$VERSIONES" | sed -n '2p')

echo "Versiones disponibles de Apache:"
echo ""
echo "1) $LATEST  (Latest / Desarrollo)"
echo "2) $LTS     (LTS / Estable)"
echo "3) $OLDEST  (Oldest)"

}

#########################################
# Instalar Apache
#########################################

instalar_apache() {

VERSION=$1
PUERTO=$2

detener_servicios_http

# Detectar si Apache ya está instalado
VERSION_INSTALADA=$(rpm -q httpd --qf "%{VERSION}-%{RELEASE}" 2>/dev/null)

if [ -n "$VERSION_INSTALADA" ]; then
    echo ""
    echo "Apache ya está instalado (versión $VERSION_INSTALADA)"
    echo "Se omite la instalación y se procede solo a cambiar el puerto a $PUERTO"
    echo ""

    gestionar_puerto $PUERTO || return 1
    permitir_puerto_selinux $PUERTO

    echo "Actualizando puerto en httpd.conf..."
    sed -i "s/^Listen .*/Listen $PUERTO/" /etc/httpd/conf/httpd.conf

    systemctl restart httpd

    crear_index "Apache" "$VERSION_INSTALADA" "$PUERTO" "/var/www/html"

    echo ""
    echo "====================================="
    echo " PUERTO ACTUALIZADO "
    echo "====================================="
    echo "Servidor: Apache"
    echo "Versión:  $VERSION_INSTALADA"
    echo "Puerto:   $PUERTO"
    echo "====================================="
    return 0
fi

echo "Instalando Apache versión $VERSION..."

dnf install -y httpd-$VERSION

activar_headers_apache

gestionar_puerto $PUERTO || return 1
permitir_puerto_selinux $PUERTO

echo "Configurando puerto $PUERTO..."

sed -i "s/Listen 80/Listen $PUERTO/g" /etc/httpd/conf/httpd.conf

systemctl enable httpd
systemctl restart httpd

crear_index "Apache" "$VERSION" "$PUERTO" "/var/www/html"

configurar_seguridad_apache

echo ""
echo "====================================="
echo " INSTALACIÓN COMPLETADA "
echo "====================================="
echo "Servidor: Apache"
echo "Versión: $VERSION"
echo "Puerto: $PUERTO"
echo "====================================="

}

#########################################
# Activar módulo headers
#########################################

activar_headers_apache() {

dnf install -y mod_headers

}

#########################################
# Seguridad Apache
#########################################

configurar_seguridad_apache() {

SECURITY_CONF="/etc/httpd/conf.d/security.conf"

echo "Aplicando seguridad Apache..."

# Crear archivo si no existe
touch $SECURITY_CONF

# Eliminar configuraciones previas
sed -i '/ServerTokens/d' $SECURITY_CONF
sed -i '/ServerSignature/d' $SECURITY_CONF

# Aplicar configuraciones seguras
echo "ServerTokens Prod" >> $SECURITY_CONF
echo "ServerSignature Off" >> $SECURITY_CONF

# Headers de seguridad
cat <<EOF >> $SECURITY_CONF

<IfModule mod_headers.c>
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
</IfModule>

TraceEnable Off

EOF

systemctl restart httpd

}

#########################################
# Obtener versiones de Nginx disponibles
#########################################

listar_versiones_nginx() {

echo "Buscando versiones disponibles de Nginx en los repositorios..."
echo ""

preparar_repositorios

echo ""
echo "[dnf] Consultando: dnf repoquery --showduplicates nginx"
VERSIONES=$(dnf repoquery --showduplicates nginx \
| awk '{print $1}' \
| awk -F'-' '{print $2}' \
| sort -V \
| uniq)

COUNT=$(echo "$VERSIONES" | wc -l)

if [ "$COUNT" -lt 3 ]; then

echo "Repositorio con pocas versiones disponibles ($COUNT encontradas)."
echo "Usando versiones conocidas como fallback:"
echo "  Latest: 1.26.3"
echo "  LTS:    1.24.0"
echo "  Oldest: 1.20.1"
echo ""

LATEST="1.26.3"
LTS="1.24.0"
OLDEST="1.20.1"

else

echo ""
echo "Versiones encontradas en el repositorio:"
echo "$VERSIONES"
echo ""

OLDEST=$(echo "$VERSIONES" | head -n 1)
LATEST=$(echo "$VERSIONES" | tail -n 1)
LTS=$(echo "$VERSIONES" | sed -n '2p')

fi

echo "Versiones disponibles de Nginx:"
echo ""
echo "1) $LATEST  (Latest / Desarrollo)"
echo "2) $LTS     (LTS / Estable)"
echo "3) $OLDEST  (Oldest)"

}

#########################################
# Crear usuario restringido nginx
#########################################

crear_usuario_nginx() {

if ! id nginxsvc &>/dev/null; then
    useradd -r -s /sbin/nologin -d /var/www/nginx nginxsvc
fi

mkdir -p /var/www/nginx

chown -R nginxsvc:nginxsvc /var/www/nginx
chmod -R 750 /var/www/nginx

}

#########################################
# Configurar puerto nginx (server block limpio)
#########################################

configurar_puerto_nginx() {

PUERTO=$1
CONF="/etc/nginx/conf.d/default.conf"

cat > $CONF <<EOF
server {
    listen $PUERTO;
    server_name _;
    root /usr/share/nginx/html;

    location / {
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
EOF

}

#########################################
# Seguridad Nginx
#########################################

configurar_seguridad_nginx() {

CONF="/etc/nginx/nginx.conf"

sed -i '/server_tokens/d' $CONF
echo "server_tokens off;" >> $CONF

}

#########################################
# Instalar Nginx
#########################################

instalar_nginx() {

VERSION=$1
PUERTO=$2

detener_servicios_http

# Detectar si Nginx ya está instalado
if command -v nginx >/dev/null 2>&1; then
    VERSION_INSTALADA=$(nginx -v 2>&1 | cut -d'/' -f2)
    echo ""
    echo "Nginx ya está instalado (versión $VERSION_INSTALADA)"
    echo "Se omite la instalación y se procede solo a cambiar el puerto a $PUERTO"
    echo ""

    gestionar_puerto $PUERTO || return 1
    permitir_puerto_selinux $PUERTO

    echo "Actualizando puerto en configuración de Nginx..."
    configurar_puerto_nginx $PUERTO

    nginx -t || { echo "Error en configuración de Nginx"; return 1; }
    systemctl restart nginx

    crear_index "Nginx" "$VERSION_INSTALADA" "$PUERTO" "/usr/share/nginx/html"

    echo ""
    echo "====================================="
    echo " PUERTO ACTUALIZADO "
    echo "====================================="
    echo "Servidor: Nginx"
    echo "Versión:  $VERSION_INSTALADA"
    echo "Puerto:   $PUERTO"
    echo "====================================="
    return 0
fi

gestionar_puerto $PUERTO || return 1

echo "Instalando Nginx versión $VERSION..."

dnf install -y nginx

VERSION_REAL=$(nginx -v 2>&1 | cut -d'/' -f2)
VERSION=$VERSION_REAL

crear_usuario_nginx

permitir_puerto_selinux $PUERTO

configurar_puerto_nginx $PUERTO

nginx -t || { echo "Error en configuración de Nginx"; return 1; }

systemctl enable nginx
systemctl restart nginx

crear_index "Nginx" "$VERSION" "$PUERTO" "/usr/share/nginx/html"

configurar_seguridad_nginx

echo ""
echo "====================================="
echo " INSTALACIÓN COMPLETADA "
echo "====================================="
echo "Servidor: Nginx"
echo "Versión: $VERSION"
echo "Puerto: $PUERTO"
echo "====================================="

}

#########################################
# Configurar header Server en Tomcat
#########################################

configurar_header_tomcat() {

sed -i 's|protocol="org.apache.coyote.http11.Http11NioProtocol"|protocol="org.apache.coyote.http11.Http11NioProtocol" server="Apache-Tomcat"|' /opt/tomcat/conf/server.xml

}

#########################################
# Obtener versiones de Tomcat disponibles
#########################################

listar_versiones_tomcat() {

echo "Versiones disponibles de Tomcat:"
echo "(Tomcat no está en repositorios dnf, se descarga directo desde archive.apache.org)"
echo ""

echo "1) 10.1.28  (Latest / Desarrollo)"
echo "2) 10.1.26  (LTS / Estable)"
echo "3) 9.0.91   (Oldest)"

}

#########################################
# Crear usuario restringido tomcat
#########################################

crear_usuario_tomcat() {

if ! id tomcatsvc &>/dev/null; then
    useradd -r -s /sbin/nologin -d /opt/tomcat tomcatsvc
fi

}

#########################################
# Configurar puerto Tomcat
#########################################

configurar_puerto_tomcat() {

PUERTO=$1

# Reemplaza cualquier puerto que ya tenga el Connector, no solo 8080
sed -i "s/Connector port=\"[0-9]*\"/Connector port=\"$PUERTO\"/" /opt/tomcat/conf/server.xml

}

#########################################
# Instalar Tomcat
#########################################

instalar_tomcat() {

VERSION=$1
PUERTO=$2

detener_servicios_http

# Detectar si Tomcat ya está instalado
if [ -d "/opt/tomcat" ] && [ -f "/opt/tomcat/bin/version.sh" ]; then
    VERSION_INSTALADA=$(sudo -u tomcatsvc /opt/tomcat/bin/version.sh 2>/dev/null | grep "Server version" | cut -d'/' -f2)
    echo ""
    echo "Tomcat ya está instalado (versión $VERSION_INSTALADA)"
    echo "Se omite la instalación y se procede solo a cambiar el puerto a $PUERTO"
    echo ""

    gestionar_puerto $PUERTO || return 1
    permitir_puerto_selinux $PUERTO

    echo "Deteniendo Tomcat..."
    pkill -f tomcat 2>/dev/null
    sleep 2

    echo "Actualizando puerto en server.xml..."
    configurar_puerto_tomcat $PUERTO

    crear_index "Tomcat" "$VERSION_INSTALADA" "$PUERTO" "/opt/tomcat/webapps/ROOT"

    echo "Iniciando Tomcat en el nuevo puerto..."
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk
    sudo -u tomcatsvc env JAVA_HOME=$JAVA_HOME CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh

    echo "Esperando a que Tomcat inicie..."
    for i in {1..20}; do
        if ss -tuln | grep -q ":$PUERTO "; then
            echo "Tomcat iniciado correctamente"
            break
        fi
        sleep 1
    done

    echo ""
    echo "====================================="
    echo " PUERTO ACTUALIZADO "
    echo "====================================="
    echo "Servidor: Tomcat"
    echo "Versión:  $VERSION_INSTALADA"
    echo "Puerto:   $PUERTO"
    echo "====================================="
    return 0
fi

# instalar java
dnf install -y java-21-openjdk java-21-openjdk-devel

gestionar_puerto $PUERTO || return 1

echo "Instalando Tomcat versión $VERSION..."

cd /tmp

MAJOR=$(echo $VERSION | cut -d'.' -f1)

wget https://archive.apache.org/dist/tomcat/tomcat-$MAJOR/v$VERSION/bin/apache-tomcat-$VERSION.tar.gz

tar -xzf apache-tomcat-$VERSION.tar.gz

pkill -f tomcat 2>/dev/null
rm -rf /opt/tomcat
mv apache-tomcat-$VERSION /opt/tomcat

crear_usuario_tomcat

chown -R tomcatsvc:tomcatsvc /opt/tomcat

# configurar puerto antes de iniciar
configurar_puerto_tomcat $PUERTO

# agregar header Server
configurar_header_tomcat

permitir_puerto_selinux $PUERTO

crear_index "Tomcat" "$VERSION" "$PUERTO" "/opt/tomcat/webapps/ROOT"

# iniciar tomcat
JAVA_HOME=/usr/lib/jvm/java-21-openjdk

sudo -u tomcatsvc env JAVA_HOME=$JAVA_HOME CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh

echo "Esperando a que Tomcat inicie..."

for i in {1..20}; do
    if ss -tuln | grep -q ":$PUERTO "; then
        echo "Tomcat iniciado correctamente"
        break
    fi
    sleep 1
done

echo ""
echo "====================================="
echo " INSTALACIÓN COMPLETADA "
echo "====================================="
echo "Servidor: Tomcat"
echo "Versión: $VERSION"
echo "Puerto: $PUERTO"
echo "====================================="

}
#########################################
# Crear página personalizada
#########################################

crear_index() {

SERVICIO=$1
VERSION=$2
PUERTO=$3
DIRECTORIO=$4

mkdir -p $DIRECTORIO

cat <<EOF > $DIRECTORIO/index.html
<html>
<head>
<meta charset="UTF-8">
<title>Servidor HTTP</title>
</head>
<body>
<h1>Servidor: $SERVICIO</h1>
<h2>Versión: $VERSION</h2>
<h3>Puerto: $PUERTO</h3>
</body>
</html>
EOF

}
