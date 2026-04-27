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


desplegar_contenedores() {
    echo "----------------------------------------"
    echo " Desplegando Infraestructura con Compose"
    echo "----------------------------------------"

    echo "Generando archivo docker-compose.yml en $DIR_BASE..."
    
    cat << EOF > "$DIR_BASE/docker-compose.yml"
version: '3.8'

services:
  db:
    image: postgres:15-alpine
    container_name: base_datos_p10
    restart: unless-stopped
    environment:
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: admin_password
      POSTGRES_DB: base_practica
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - infra_red
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

  ftp:
    image: delfer/alpine-ftp-server
    container_name: servidor_ftp_p10
    restart: unless-stopped
    environment:
      USERS: "adminftp|passwordftp"
    ports:
      - "21:21"
      - "21000-21010:21000-21010"
    volumes:
      - web_content:/ftp/adminftp
    networks:
      - infra_red
    deploy:
      resources:
        limits:
          cpus: '0.2'
          memory: 256M

  web:
    build:
      context: ./web
      dockerfile: Dockerfile
    container_name: servidor_web_p10
    restart: unless-stopped
    ports:
      - "80:8080"
    volumes:
      - web_content:/usr/share/nginx/html
    networks:
      - infra_red
    depends_on:
      - db
      - ftp
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

volumes:
  db_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DIR_BASE/db
  web_content:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $DIR_BASE/ftp

networks:
  infra_red:
    external: true
EOF

    echo "  - Archivo Compose generado."
    
    echo "Iniciando descarga de imagenes y construccion de contenedores..."
    # Nos movemos a la carpeta de infraestructura para ejecutar compose
    cd "$DIR_BASE" || exit
    
    # El parametro -d levanta los contenedores en segundo plano (detached)
    # El parametro --build fuerza a leer tu nuevo Dockerfile
    docker compose up -d --build

    if [ $? -eq 0 ]; then
        echo "----------------------------------------"
        echo " DESPLIEGUE EXITOSO."
        echo " Los 3 servicios estan corriendo con limites de recursos."
        echo " Puedes comprobarlo saliendo del script y usando 'docker ps'"
        echo "----------------------------------------"
    else
        echo "----------------------------------------"
        echo " ERROR: Hubo un fallo al intentar levantar los contenedores."
        echo "----------------------------------------"
    fi
    
    # Regresamos al directorio original donde esta el script
    cd - > /dev/null
    read -p "Presiona Enter para continuar..."
}

menu_pruebas() {
    while true; do
        clear
        echo "=========================================================="
        echo " Protocolo de Pruebas Dinamico (Validación Práctica 10)"
        echo "=========================================================="
        echo "1. Prueba 10.1 (Persistencia con datos personalizados)"
        echo "2. Prueba 10.2 (Ping de red con paquetes configurables)"
        echo "3. Prueba 10.3 (Subida FTP de archivo personalizado)"
        echo "4. Prueba 10.4 (Límites de Recursos en tiempo real)"
        echo ""
        echo "0. Volver al menú principal"
        echo "=========================================================="
        read -p "Selecciona la prueba a ejecutar: " op_prueba

        case $op_prueba in
            1)
                echo "----------------------------------------"
                echo " Ejecutando Prueba 10.1: Persistencia Real"
                echo "----------------------------------------"
                # Le pedimos al usuario que cree su propia base de datos
                read -p "Ingresa el nombre de la BASE DE DATOS a crear: " nombre_db
                if [ -z "$nombre_db" ]; then nombre_db="db_prueba_$(date +%s)"; fi

                echo "1. Creando Base de Datos '$nombre_db' dentro de Postgres..."
                # Usamos la BD por defecto 'postgres' para poder crear una nueva
                docker exec base_datos_p10 psql -U admin -d postgres -c "CREATE DATABASE $nombre_db;"
                
                echo "2. Creando una tabla y registro dentro de '$nombre_db'..."
                docker exec base_datos_p10 psql -U admin -d $nombre_db -c "CREATE TABLE persistencia (id serial, nota text); INSERT INTO persistencia (nota) VALUES ('Datos guardados en $nombre_db');"
                
                echo "3. Simulando desastre: Eliminando contenedor 'base_datos_p10'..."
                docker rm -f base_datos_p10
                
                echo "4. Levantando un contenedor NUEVO con el mismo volumen..."
                cd "$DIR_BASE" && docker compose up -d db
                
                echo "Esperando arranque del motor..."
                for i in {1..15}; do
                    if docker exec base_datos_p10 pg_isready -U admin >/dev/null 2>&1; then
                        break
                    fi
                    sleep 2
                done
                
                echo "5. Verificando si la base de datos '$nombre_db' sobrevivio..."
                # Listamos las bases de datos para ver si existe la que creamos
                docker exec base_datos_p10 psql -U admin -d postgres -l | grep "$nombre_db"
                
                echo -e "\n6. Consultando datos dentro de '$nombre_db'..."
                docker exec base_datos_p10 psql -U admin -d $nombre_db -c "SELECT * FROM persistencia;"
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                echo "----------------------------------------"
                echo " Ejecutando Prueba 10.2: Red y DNS"
                echo "----------------------------------------"
                read -p "Cuantos paquetes PING deseas enviar? (Ej. 4): " num_paquetes
                
                # Validacion: Si no metes un numero, asigna 3 por defecto
                if ! [[ "$num_paquetes" =~ ^[0-9]+$ ]]; then num_paquetes=3; fi

                echo "Haciendo ping ($num_paquetes paquetes) desde servidor_web_p10 hacia base_datos_p10..."
                docker exec servidor_web_p10 ping -c $num_paquetes base_datos_p10
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                echo "----------------------------------------"
                echo " Ejecutando Prueba 10.3: FTP hacia Nginx"
                echo "----------------------------------------"
                read -p "Ingresa el nombre del archivo a crear (ej. saludo.html): " nombre_archivo
                if [ -z "$nombre_archivo" ]; then nombre_archivo="dinamico.html"; fi
                
                read -p "Ingresa una frase para el contenido web: " frase_web
                if [ -z "$frase_web" ]; then frase_web="Contenido autogenerado"; fi

                echo "1. Creando archivo local /tmp/$nombre_archivo..."
                echo "<h1>$frase_web</h1><p>Archivo: $nombre_archivo</p>" > "/tmp/$nombre_archivo"
                
                echo "2. Subiendo $nombre_archivo por FTP..."
                curl -T "/tmp/$nombre_archivo" ftp://adminftp:passwordftp@localhost/
                
                echo -e "\n3. Consultando el archivo servido por Nginx (puerto 80)..."
                curl "http://localhost/$nombre_archivo"
                echo -e "\n----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                echo "----------------------------------------"
                echo " Ejecutando Prueba 10.4: Limites de Recursos"
                echo "----------------------------------------"
                echo "Leyendo estadisticas directamente del daemon de Docker en tiempo real..."
                docker stats --no-stream
                echo "----------------------------------------"
                read -p "Presiona Enter para continuar..."
                ;;
            0)
                break
                ;;
            *)
                echo "Opcion no valida."
                sleep 2
                ;;
        esac
    done
}
