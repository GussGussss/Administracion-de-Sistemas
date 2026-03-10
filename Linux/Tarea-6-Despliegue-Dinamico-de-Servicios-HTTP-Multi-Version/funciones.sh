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
