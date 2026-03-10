#!/bin/bash

#########################################
# Validar puerto
#########################################

validar_puerto() {

PUERTO=$1

if [[ ! $PUERTO =~ ^[0-9]+$ ]]; then
    echo "Puerto inválido"
    return 1
fi

if ((PUERTO < 1024 || PUERTO > 65535)); then
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

firewall-cmd --permanent --add-port=${PUERTO}/tcp > /dev/null 2>&1
firewall-cmd --reload > /dev/null 2>&1

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

echo "Versiones disponibles de Apache:"

dnf list --showduplicates httpd \
| grep httpd.x86_64 \
| awk '{print $2}' \
| nl

}

#########################################
# Instalar Apache
#########################################

instalar_apache() {

VERSION=$1
PUERTO=$2
detener_servicios_http
echo "Instalando Apache versión $VERSION..."

dnf install -y httpd-$VERSION > /dev/null 2>&1

activar_headers_apache

echo "Configurando puerto $PUERTO..."

gestionar_puerto $PUERTO || return 1

echo "Configurando puerto $PUERTO..."

sed -i "s/Listen 80/Listen $PUERTO/g" /etc/httpd/conf/httpd.conf

systemctl enable httpd > /dev/null 2>&1
systemctl restart httpd > /dev/null 2>&1

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

dnf install -y mod_headers > /dev/null 2>&1

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

systemctl restart httpd > /dev/null 2>&1

}

#########################################
# Obtener versiones de Nginx disponibles
#########################################

listar_versiones_nginx() {

echo "Versiones disponibles de Nginx:"

dnf list --showduplicates nginx \
| grep nginx.x86_64 \
| awk '{print $2}' \
| nl

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
# Configurar puerto nginx
#########################################

configurar_puerto_nginx() {

PUERTO=$1

CONF1="/etc/nginx/conf.d/default.conf"
CONF2="/etc/nginx/nginx.conf"

if [ -f "$CONF1" ]; then
    sed -i "s/listen.*80.*/listen $PUERTO;/" $CONF1
else
    sed -i "s/listen.*80.*/listen $PUERTO;/" $CONF2
fi

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
gestionar_puerto $PUERTO || return 1

echo "Instalando Nginx versión $VERSION..."

dnf install -y nginx-$VERSION > /dev/null 2>&1

crear_usuario_nginx

configurar_puerto_nginx $PUERTO

nginx -t > /dev/null 2>&1

systemctl enable nginx > /dev/null 2>&1
systemctl restart nginx > /dev/null 2>&1

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
