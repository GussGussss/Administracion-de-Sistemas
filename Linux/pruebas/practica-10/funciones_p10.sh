#!/bin/bash
# Archivo: funciones_p10.sh

# Definición de la ruta raíz de infraestructura fuera del repositorio
DIR_BASE="/opt/practica10"

instalar_dependencias() {
    echo "----------------------------------------"
    echo " Preparando Dependencias del Sistema"
    echo "----------------------------------------"

    if command -v docker &> /dev/null; then
        echo "Se ha detectado que Docker ya está instalado."
        read -p "¿Deseas forzar la reinstalación/actualización? (s/n): " reinstalar_docker
        if [[ "$reinstalar_docker" == "s" || "$reinstalar_docker" == "S" ]]; then
            echo "Reinstalando Docker..."
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io
        else
            echo "Omitiendo la descarga de Docker."
        fi
    else
        echo "Docker no está instalado. Procediendo a descargar e instalar..."
        dnf -y install dnf-plugins-core
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io
    fi

    systemctl enable docker
    systemctl start docker

    if docker compose version &> /dev/null || command -v docker-compose &> /dev/null; then
        echo "Se ha detectado que Docker Compose ya está instalado."
    else
        echo "Docker Compose no está instalado. Instalando..."
        dnf install -y docker-compose-plugin
    fi

    echo "----------------------------------------"
    echo " Dependencias listas y servicios activos."
    echo "----------------------------------------"
    
    read -p "Presiona Enter para continuar..."
}

preparar_entorno_docker() {
    echo "----------------------------------------"
    echo " Preparando Estructura y Red de Docker"
    echo "----------------------------------------"

    # 1. Creación de la estructura en el directorio del sistema
    echo "Creando directorios en $DIR_BASE..."
    mkdir -p "$DIR_BASE/web" "$DIR_BASE/db" "$DIR_BASE/ftp"
    # Aseguramos permisos para que el usuario pueda manipularlos si es necesario
    chmod -R 755 "$DIR_BASE"
    echo "  - Directorios en el sistema listos."

    # 2. Creación de la red personalizada
    echo "Validando red de Docker (infra_red - 172.20.0.0/16)..."
    
    if docker network ls | grep -q "infra_red"; then
        echo "  - La red 'infra_red' ya existe en Docker. Omitiendo creación."
    else
        echo "  - La red no existe. Creando 'infra_red'..."
        docker network create --subnet=172.20.0.0/16 infra_red
        if [ $? -eq 0 ]; then
            echo "  - Red 'infra_red' creada exitosamente."
        else
            echo "  - ERROR al intentar crear la red."
        fi
    fi

    echo "----------------------------------------"
    echo " Entorno de carpetas y red preparado."
    echo "----------------------------------------"
    
    read -p "Presiona Enter para continuar..."
}

generar_archivos_configuracion() {
    echo "----------------------------------------"
    echo " Generando Archivos de Configuracion Web"
    echo "----------------------------------------"

    if [ -f "$DIR_BASE/web/Dockerfile" ]; then
        read -p "El Dockerfile y archivos web ya existen en $DIR_BASE/web. ¿Deseas sobrescribirlos? (s/n): " sobrescribir_web
        if [[ "$sobrescribir_web" != "s" && "$sobrescribir_web" != "S" ]]; then
            echo "Omitiendo creacion de archivos web."
            generar_web="no"
        else
            generar_web="si"
        fi
    else
        generar_web="si"
    fi

    if [ "$generar_web" == "si" ]; then
        echo "Creando nginx.conf en $DIR_BASE/web/..."
        cat << 'EOF' > "$DIR_BASE/web/nginx.conf"
worker_processes 1;
events { worker_connections 1024; }
http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    server_tokens off;
    
    server {
        listen 8080;
        server_name localhost;
        
        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }
    }
}
EOF

        echo "Creando index.html..."
        cat << 'EOF' > "$DIR_BASE/web/index.html"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Practica 10 - Web Segura</title>
    <style>
        body { font-family: Arial, sans-serif; background-color: #2c3e50; color: #ecf0f1; text-align: center; padding: 50px; }
        h1 { color: #3498db; }
    </style>
</head>
<body>
    <h1>Servidor Web Seguro (Docker)</h1>
    <p>Nginx en Alpine Linux | Usuario No Administrativo | Server Tokens Off</p>
</body>
</html>
EOF

        echo "Creando Dockerfile personalizado..."
        cat << 'EOF' > "$DIR_BASE/web/Dockerfile"
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/index.html
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid
USER nginx
EXPOSE 8080
EOF
        echo "  - Archivos creados exitosamente en $DIR_BASE/web"
    fi

    echo "----------------------------------------"
    echo " Proceso de configuracion finalizado."
    echo "----------------------------------------"
    
    read -p "Presiona Enter para continuar..."
}
