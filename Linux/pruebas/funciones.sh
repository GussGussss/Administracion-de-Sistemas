#!/bin/bash

#########################################
# Preparar repositorios
#########################################

preparar_repositorios() {

echo "Instalando utilidades necesarias (dnf-plugins-core, yum-utils, epel-release)..."
dnf install -y dnf-plugins-core yum-utils epel-release

echo "Limpiando cache de DNF..."
dnf clean all

echo "Actualizando cache de DNF..."
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

echo "Abriendo puerto $PUERTO en firewall..."
firewall-cmd --permanent --add-port=${PUERTO}/tcp
echo "Recargando firewall..."
firewall-cmd --reload

}

#########################################
# Permitir puerto HTTP en SELinux
#########################################

permitir_puerto_selinux() {

PUERTO=$1

if command -v semanage >/dev/null 2>&1; then
    echo "Verificando política SELinux para puerto $PUERTO..."
    if ! semanage port -l | grep -q "http_port_t.*\b$PUERTO\b"; then
        echo "Agregando puerto $PUERTO al tipo http_port_t en SELinux..."
        semanage port -a -t http_port_t -p tcp $PUERTO 2>/dev/null || \
        semanage port -m -t http_port_t -p tcp $PUERTO
    else
        echo "Puerto $PUERTO ya está permitido en SELinux."
    fi
fi

}

#########################################
# Detener servidores HTTP para evitar conflictos
#########################################

detener_servicios_http() {

echo "Deteniendo servicios HTTP existentes para evitar conflictos..."
systemctl stop httpd 2>/dev/null && echo "httpd detenido." || echo "httpd no estaba activo."
systemctl stop nginx 2>/dev/null && echo "nginx detenido." || echo "nginx no estaba activo."

}

#########################################
# Obtener versiones de Apache disponibles
#########################################

listar_versiones_apache() {

echo ""
echo "Consultando versiones disponibles de Apache en el repositorio DNF..."

VERSIONES=$(dnf list --showduplicates httpd \
| grep httpd.x86_64 \
| awk '{print $2}' \
| sort -V \
| uniq)

echo "Versiones encontradas:"
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
echo ""
echo "Instalando Apache versión $VERSION..."
dnf install -y httpd-$VERSION

activar_headers_apache

echo ""
echo "Configurando puerto $PUERTO..."

gestionar_puerto $PUERTO || return 1
permitir_puerto_selinux $PUERTO

echo "Modificando httpd.conf: Listen 80 -> Listen $PUERTO..."
sed -i "s/Listen 80/Listen $PUERTO/g" /etc/httpd/conf/httpd.conf

echo "Habilitando e iniciando servicio httpd..."
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

echo "Instalando módulo mod_headers para Apache..."
dnf install -y mod_headers

}

#########################################
# Seguridad Apache
#########################################

configurar_seguridad_apache() {

SECURITY_CONF="/etc/httpd/conf.d/security.conf"

echo "Aplicando configuración de seguridad Apache..."

touch $SECURITY_CONF

sed -i '/ServerTokens/d' $SECURITY_CONF
sed -i '/ServerSignature/d' $SECURITY_CONF

echo "ServerTokens Prod" >> $SECURITY_CONF
echo "ServerSignature Off" >> $SECURITY_CONF

cat <<SECEOF >> $SECURITY_CONF

<IfModule mod_headers.c>
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
</IfModule>

TraceEnable Off

SECEOF

echo "Reiniciando httpd para aplicar seguridad..."
systemctl restart httpd

}

#########################################
# Obtener versiones de Nginx disponibles
#########################################

listar_versiones_nginx() {

echo ""
echo "Preparando repositorios para Nginx..."
preparar_repositorios

echo ""
echo "Consultando versiones disponibles de Nginx en el repositorio DNF..."

VERSIONES=$(dnf repoquery --showduplicates nginx \
| awk '{print $1}' \
| awk -F'-' '{print $2}' \
| sort -V \
| uniq)

echo "Versiones encontradas:"
echo "$VERSIONES"
echo ""

COUNT=$(echo "$VERSIONES" | wc -l)

if [ "$COUNT" -lt 3 ]; then
    echo "Pocas versiones en repositorio, usando versiones predefinidas."
    LATEST="1.26.3"
    LTS="1.24.0"
    OLDEST="1.20.1"
else
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

echo "Creando usuario restringido nginxsvc..."
if ! id nginxsvc &>/dev/null; then
    useradd -r -s /sbin/nologin -d /var/www/nginx nginxsvc
    echo "Usuario nginxsvc creado."
else
    echo "Usuario nginxsvc ya existe."
fi

mkdir -p /var/www/nginx

echo "Aplicando permisos en /var/www/nginx..."
chown -R nginxsvc:nginxsvc /var/www/nginx
chmod -R 750 /var/www/nginx

}

#########################################
# Configurar puerto nginx (server block limpio)
#########################################

configurar_puerto_nginx() {

PUERTO=$1
CONF="/etc/nginx/conf.d/default.conf"

echo "Escribiendo configuración de servidor Nginx en $CONF..."
cat > $CONF <<NGXEOF
server {
    listen $PUERTO;
    server_name _;
    root /usr/share/nginx/html;

    location / {
        index index.html;
        try_files \$uri \$uri/ =404;
    }
}
NGXEOF

}

#########################################
# Seguridad Nginx
#########################################

configurar_seguridad_nginx() {

CONF="/etc/nginx/nginx.conf"

echo "Aplicando server_tokens off en nginx.conf..."
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

gestionar_puerto $PUERTO || return 1

echo ""
echo "Instalando Nginx versión $VERSION..."
dnf install -y nginx

VERSION_REAL=$(nginx -v 2>&1 | cut -d'/' -f2)
VERSION=$VERSION_REAL
echo "Versión instalada: $VERSION"

crear_usuario_nginx

permitir_puerto_selinux $PUERTO

configurar_puerto_nginx $PUERTO

echo "Validando configuración de Nginx..."
nginx -t || { echo "Error en configuración de Nginx"; return 1; }

echo "Habilitando e iniciando servicio nginx..."
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

echo "Configurando header Server en Tomcat (server.xml)..."
sed -i 's|protocol="org.apache.coyote.http11.Http11NioProtocol"|protocol="org.apache.coyote.http11.Http11NioProtocol" server="Apache-Tomcat"|' /opt/tomcat/conf/server.xml

}

#########################################
# Obtener versiones de Tomcat disponibles
#########################################

listar_versiones_tomcat() {

echo ""
echo "Versiones disponibles de Tomcat:"
echo ""
echo "1) 10.1.28  (Latest / Desarrollo)"
echo "2) 10.1.26  (LTS / Estable)"
echo "3) 9.0.91   (Oldest)"

}

#########################################
# Crear usuario restringido tomcat
#########################################

crear_usuario_tomcat() {

echo "Creando usuario restringido tomcatsvc..."
if ! id tomcatsvc &>/dev/null; then
    useradd -r -s /sbin/nologin -d /opt/tomcat tomcatsvc
    echo "Usuario tomcatsvc creado."
else
    echo "Usuario tomcatsvc ya existe."
fi

}

#########################################
# Configurar puerto Tomcat
#########################################

configurar_puerto_tomcat() {

PUERTO=$1
echo "Configurando puerto $PUERTO en server.xml de Tomcat..."
sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/" /opt/tomcat/conf/server.xml

}

#########################################
# Instalar Tomcat
#########################################

instalar_tomcat() {

echo "Instalando Java 21 (requerido por Tomcat)..."
dnf install -y java-21-openjdk java-21-openjdk-devel

VERSION=$1
PUERTO=$2

detener_servicios_http

gestionar_puerto $PUERTO || return 1

echo ""
echo "Instalando Tomcat versión $VERSION..."

cd /tmp

MAJOR=$(echo $VERSION | cut -d'.' -f1)

echo "Descargando apache-tomcat-$VERSION.tar.gz desde archive.apache.org..."
wget https://archive.apache.org/dist/tomcat/tomcat-$MAJOR/v$VERSION/bin/apache-tomcat-$VERSION.tar.gz

echo "Extrayendo archivo..."
tar -xzf apache-tomcat-$VERSION.tar.gz

echo "Deteniendo instancia previa de Tomcat si existe..."
pkill -f tomcat 2>/dev/null && echo "Proceso Tomcat detenido." || echo "No había proceso Tomcat activo."

echo "Moviendo Tomcat a /opt/tomcat..."
rm -rf /opt/tomcat
mv apache-tomcat-$VERSION /opt/tomcat

crear_usuario_tomcat

echo "Aplicando permisos en /opt/tomcat..."
chown -R tomcatsvc:tomcatsvc /opt/tomcat

configurar_puerto_tomcat $PUERTO

configurar_header_tomcat

permitir_puerto_selinux $PUERTO

crear_index "Tomcat" "$VERSION" "$PUERTO" "/opt/tomcat/webapps/ROOT"

JAVA_HOME=/usr/lib/jvm/java-21-openjdk
echo "Iniciando Tomcat como usuario tomcatsvc..."
sudo -u tomcatsvc env JAVA_HOME=$JAVA_HOME CATALINA_HOME=/opt/tomcat /opt/tomcat/bin/startup.sh

echo "Esperando a que Tomcat inicie en puerto $PUERTO..."
for i in {1..20}; do
    if ss -tuln | grep -q ":$PUERTO "; then
        echo "Tomcat iniciado correctamente en puerto $PUERTO."
        break
    fi
    echo "  Intento $i/20..."
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

echo "Creando index.html en $DIRECTORIO..."
mkdir -p $DIRECTORIO

cat <<HTMLEOF > $DIRECTORIO/index.html
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
HTMLEOF

echo "index.html creado correctamente."

}
