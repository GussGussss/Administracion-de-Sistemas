#!/bin/bash

# Funcion auxiliar para preguntar al usuario (S/N)
# No usa emojis por requerimiento
preguntar_confirmacion() {
    local mensaje=$1
    read -p "$mensaje (s/n): " respuesta
    case "$respuesta" in
        [sS]|[sS][iI]|[yY]|[eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Nueva Funcion: Descargar Utilidades (Docker Images)
descargar_utilidades() {
    echo "Iniciando descarga de imagenes y utilidades necesarias..."
    
    # Lista de imagenes necesarias para la practica
    local imagenes=("alpine:latest" "postgres:latest" "delfer/alpine-ftp-server")
    
    for img in "${imagenes[@]}"; do
        # Verificar si la imagen ya existe localmente
        if docker images -q "$img" > /dev/null 2>&1; then
            echo "La imagen $img ya se encuentra descargada."
            if preguntar_confirmacion "Desea descargarla nuevamente para actualizar?"; then
                docker pull "$img"
            fi
        else
            echo "Descargando imagen: $img"
            docker pull "$img"
        fi
    done
    echo "Proceso de descarga finalizado."
}

# Funcion: Instalar Dependencias (Docker Engine)
instalar_docker() {
    echo "Verificando instalacion de Docker Engine..."
    
    if command -v docker &> /dev/null; then
        echo "Docker ya esta instalado en el sistema."
        if preguntar_confirmacion "Desea intentar reinstalar o actualizar Docker?"; then
            dnf install -y dnf-utils
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        fi
    else
        echo "Instalando Docker Engine por primera vez..."
        dnf install -y dnf-utils
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
        systemctl start docker
        systemctl enable docker
    fi
}

# Funcion: Preparar el Terreno
preparar_entorno() {
    echo "Configurando red y volumenes..."
    
    mkdir -p web db ftp
    
    # Validacion de Red
    if docker network inspect infra_red >/dev/null 2>&1; then
        echo "La red infra_red ya existe."
        if preguntar_confirmacion "Desea recrear la red? (Esto podria desconectar contenedores activos)"; then
            docker network rm infra_red
            docker network create --subnet=172.20.0.0/16 infra_red
        fi
    else
        docker network create --subnet=172.20.0.0/16 infra_red
    fi
    
    # Validacion de Volumenes
    local volumenes=("db_data" "web_content")
    for vol in "${volumenes[@]}"; do
        if docker volume inspect "$vol" >/dev/null 2>&1; then
            echo "El volumen $vol ya existe."
        else
            docker volume create "$vol"
        fi
    done
    
    echo "Configuracion de infraestructura base lista."
}

# Funcion: Limpiar todo
limpiar_todo() {
    echo "Deteniendo y eliminando contenedores de la practica..."
    docker rm -f web_server db_postgres ftp_server 2>/dev/null
    echo "Limpieza completada."
}

# Funcion: Desplegar Servidor Web Seguro
desplegar_web() {
    echo "Preparando despliegue del Servidor Web (Nginx + Hardening)..."
    
    # 1. Generacion Automatica de Archivos de Configuracion
    if [ ! -f "web/Dockerfile" ]; then
        echo "Generando Dockerfile y nginx.conf automaticamente..."
        
        # Escribir nginx.conf
        cat << 'EOF' > web/nginx.conf
worker_processes 1;
events { worker_connections 1024; }
http {
    include mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    
    # SEGURIDAD: Ocultar la version exacta de Nginx (Server Tokens)
    server_tokens off;

    server {
        # Puerto > 1024 para permitir ejecucion sin usuario root
        listen 8080;
        server_name localhost;
        
        # Directorio que se enlazara al volumen web_content
        root /www;
        index index.html;

        location / {
            try_files $uri $uri/ =404;
        }
    }
}
EOF

        # Escribir Dockerfile
        cat << 'EOF' > web/Dockerfile
FROM alpine:latest

# Instalar Nginx sin cache para mantener imagen ligera
RUN apk update && apk add --no-cache nginx

# SEGURIDAD: Crear usuario no administrativo
RUN adduser -D -g 'www' www

# Crear directorios y asignar propiedad al usuario seguro
RUN mkdir -p /www /run/nginx && \
    chown -R www:www /var/lib/nginx /www /run/nginx /var/log/nginx

# Inyectar configuracion endurecida
COPY nginx.conf /etc/nginx/nginx.conf

# Exponer el puerto
EXPOSE 8080

# Forzar la ejecucion del contenedor con el usuario no-root
USER www

CMD ["nginx", "-g", "daemon off;"]
EOF

        # Crear un index de prueba
        cat << 'EOF' > web/index.html
<!DOCTYPE html>
<html>
<head><title>Practica 10 - Web</title></head>
<body><h2>Servidor Nginx Seguro Funcionando</h2><p>Esperando archivos del FTP...</p></body>
</html>
EOF
    fi

    # 2. Construccion de la Imagen (Build)
    if docker images -q nginx_seguro:local > /dev/null 2>&1; then
        echo "La imagen nginx_seguro:local ya existe."
        if preguntar_confirmacion "Desea reconstruir la imagen web?"; then
            docker build -t nginx_seguro:local ./web
        fi
    else
        echo "Construyendo imagen personalizada basada en Alpine..."
        docker build -t nginx_seguro:local ./web
    fi

    # 3. Despliegue del Contenedor (Run)
    if docker ps -a --format '{{.Names}}' | grep -Eq "^web_server\$"; then
        echo "El contenedor web_server ya esta desplegado."
        if preguntar_confirmacion "Desea destruirlo y recrearlo?"; then
            docker rm -f web_server
            lanzar_contenedor_web
        fi
    else
        lanzar_contenedor_web
    fi
}

# Funcion auxiliar para el comando run de la web
lanzar_contenedor_web() {
    echo "Iniciando contenedor web con limites de recursos..."
    docker run -d \
        --name web_server \
        --network infra_red \
        -p 80:8080 \
        -v web_content:/www \
        --cpus="0.5" \
        --memory="512m" \
        nginx_seguro:local
        
    # Copiar el index de prueba al volumen
    docker cp web/index.html web_server:/www/index.html
    echo "Servidor Web en linea y expuesto en el puerto 80 del host."
}
