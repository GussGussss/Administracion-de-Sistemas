#!/bin/bash

# Variable global para el entorno de trabajo
DIR_BASE="/opt/practica11"

verificar_dependencias() {
    echo "Iniciando verificacion de dependencias..."

    # 1. Verificar Docker
    if command -v docker &> /dev/null; then
        echo "Docker ya esta instalado en el sistema."
        read -p "Desea forzar la reinstalacion de Docker? (s/n): " resp
        if [ "$resp" == "s" ]; then
            dnf remove -y docker-ce docker-ce-cli containerd.io
            dnf install -y docker-ce docker-ce-cli containerd.io
            systemctl enable --now docker
        fi
    else
        echo "Instalando Docker..."
        dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io
        systemctl enable --now docker
    fi

    # 2. Verificar Docker Compose (plugin o binario)
    if docker compose version &> /dev/null; then
        echo "Docker Compose ya esta instalado."
        read -p "Desea forzar la reinstalacion de Docker Compose? (s/n): " resp
        if [ "$resp" == "s" ]; then
            dnf install -y docker-compose-plugin
        fi
    else
        echo "Instalando Docker Compose..."
        dnf install -y docker-compose-plugin
    fi

    # 3. Crear directorio base de trabajo
    if [ ! -d "$DIR_BASE" ]; then
        echo "Creando directorio base en $DIR_BASE..."
        mkdir -p "$DIR_BASE"
    else
        echo "El directorio de trabajo $DIR_BASE ya existe."
    fi

    echo "Dependencias listas para operar."
}

configurar_infraestructura() {
    echo "Configurando entorno de infraestructura en $DIR_BASE..."

    # Verificar si ya existen los archivos para evitar sobreescritura accidental
    if [ -f "$DIR_BASE/docker-compose.yml" ]; then
        read -p "Los archivos de configuracion ya existen. Desea sobrescribirlos? (s/n): " resp
        if [ "$resp" != "s" ]; then
            echo "Operacion cancelada."
            return
        fi
    fi

    # 1. Creacion del archivo de variables de entorno (.env)
    # Aqui definimos las credenciales que seran inyectadas a los contenedores
    cat << 'EOF' > "$DIR_BASE/.env"
DB_USER=admin_db
DB_PASSWORD=password_seguro_123
DB_NAME=infra_db
PGADMIN_EMAIL=admin@sistema.local
PGADMIN_PASSWORD=admin_pass
EOF

    # 2. Creacion del archivo de orquestacion (docker-compose.yml)
    cat << 'EOF' > "$DIR_BASE/docker-compose.yml"
version: '3.8'

services:
  # Servicio 1: Balanceador de Carga (Punto de entrada unico)
  nginx_lb:
    image: nginx:alpine
    container_name: nginx_lb
    ports:
      - "80:80"
    networks:
      - red_publica
    restart: always
    # Configuracion minima para ocultar version y redirigir
    command: >
      /bin/sh -c "sed -i 's/server_tokens on;/server_tokens off;/g' /etc/nginx/nginx.conf && nginx -g 'daemon off;'"

  # Servicio 2: Servidor de Aplicaciones (Interno)
  app_interna:
    image: httpd:alpine
    container_name: app_interna
    networks:
      - red_publica
      - red_datos
    expose:
      - "80"
    restart: always

  # Servicio 3: Base de Datos (Persistente)
  postgres_db:
    image: postgres:15
    container_name: postgres_db
    env_file: .env
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - red_datos
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

  # Servicio 4: Panel Administrativo (Aislado)
  pgadmin_panel:
    image: dpage/pgadmin4
    container_name: pgadmin_panel
    env_file: .env
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
      PGADMIN_LISTEN_PORT: 80
    networks:
      - red_datos
    depends_on:
      postgres_db:
        condition: service_healthy
    restart: always

networks:
  red_publica:
    driver: bridge
  red_datos:
    internal: true  # Aislamiento total del exterior

volumes:
  db_data:
EOF

    echo "Archivos creados exitosamente en $DIR_BASE"
    chmod 600 "$DIR_BASE/.env"
}

desplegar_y_asegurar() {
    echo "Iniciando despliegue de la infraestructura..."

    # 1. Validar existencia de configuracion
    if [ ! -f "$DIR_BASE/docker-compose.yml" ]; then
        echo "Error: No se encuentra el archivo docker-compose.yml en $DIR_BASE. Ejecute la opcion 2 primero."
        return
    fi

    # 2. Levantar el stack de Docker Compose
    echo "Levantando contenedores en segundo plano (detached)..."
    cd "$DIR_BASE" && docker compose up -d

    if [ $? -eq 0 ]; then
        echo "Servicios desplegados exitosamente."
    else
        echo "Error al levantar los servicios."
        return
    fi

    # 3. Hardening del Firewall (Oracle Linux / RHEL Style)
    echo "Aplicando reglas de seguridad en el sistema anfitrion..."
    
    # Aseguramos que firewalld este corriendo
    systemctl enable --now firewalld &> /dev/null

    # Permitir solo HTTP (Puerto 80) y SSH (Puerto 22)
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=ssh

    # Bloquear explicitamente puertos que podrian intentar exponerse (5432, 8080, etc.)
    # Aunque Docker ignore algunas reglas, esto previene exposiciones accidentales del host
    firewall-cmd --permanent --remove-port=5432/tcp &> /dev/null
    firewall-cmd --permanent --remove-port=8080/tcp &> /dev/null
    firewall-cmd --permanent --remove-port=5050/tcp &> /dev/null

    # Aplicar cambios
    firewall-cmd --reload
    
    echo "Hardening completado: Solo los puertos 80 y 22 estan abiertos al publico."
    echo "Los servicios de Base de Datos y pgAdmin estan ahora aislados."
}
