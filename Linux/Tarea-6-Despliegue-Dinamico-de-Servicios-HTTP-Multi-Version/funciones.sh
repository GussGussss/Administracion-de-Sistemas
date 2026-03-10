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

if ss -tuln | grep -q ":$PUERTO "; then
    echo "El puerto ya está en uso"
    return 1
fi

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

echo "Instalando Apache versión $VERSION..."

dnf install -y httpd-$VERSION > /dev/null 2>&1

activar_headers_apache

echo "Configurando puerto $PUERTO..."

sed -i "s/Listen 80/Listen $PUERTO/g" /etc/httpd/conf/httpd.conf

systemctl enable httpd > /dev/null 2>&1
systemctl restart httpd > /dev/null 2>&1

abrir_firewall $PUERTO

crear_index "Apache" "$VERSION" "$PUERTO"

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
# Crear página personalizada
#########################################

crear_index() {

SERVICIO=$1
VERSION=$2
PUERTO=$3

mkdir -p /var/www/html

cat <<EOF > /var/www/html/index.html
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
