#!/bin/bash
# funciones_p11.sh
# Lógica de soporte para la Práctica 11

DIRECTORIO_INFRA="/opt/practica11"

# Función crítica: Verifica si un paquete existe antes de intentar descargarlo
verificar_instalar_paquete() {
    local paquete=$1
    
    # Verificamos si el paquete ya está instalado
    if rpm -q "$paquete" &> /dev/null; then
        echo "[!] El paquete '$paquete' ya se encuentra instalado en el sistema."
        read -p "¿Desea forzar su descarga y reinstalación desde internet? (s/N): " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            echo "[+] Forzando reinstalación de $paquete..."
            dnf reinstall -y "$paquete"
        else
            echo "[-] Omitiendo instalación de $paquete para ahorrar datos."
        fi
    else
        echo "[+] El paquete '$paquete' no existe. Descargando e instalando..."
        dnf install -y "$paquete"
    fi
}

preparar_entorno() {
    echo "=== Preparación del Entorno ==="
    
    echo "[*] Verificando directorio de infraestructura externa..."
    if [ ! -d "$DIRECTORIO_INFRA" ]; then
        mkdir -p "$DIRECTORIO_INFRA"
        echo "[+] Directorio $DIRECTORIO_INFRA creado exitosamente."
    else
        echo "[-] El directorio $DIRECTORIO_INFRA ya existe. Omitiendo creación."
    fi

    echo "[*] Verificando herramientas de gestión de repositorios..."
    verificar_instalar_paquete "dnf-plugins-core"

    echo "[*] Configurando repositorio oficial de Docker CE..."
    if [ -f "/etc/yum.repos.d/docker-ce.repo" ]; then
        echo "[!] El repositorio Docker CE ya existe en el sistema."
        read -p "¿Desea forzar su descarga nuevamente? (s/N): " resp_repo
        if [[ "$resp_repo" =~ ^[sS]$ ]]; then
            echo "[+] Actualizando repositorio Docker CE..."
            dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
        else
            echo "[-] Omitiendo descarga del repositorio para ahorrar datos."
        fi
    else
        echo "[+] Añadiendo repositorio oficial de Docker CE..."
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    fi

    echo "[*] Verificando dependencias base (Motor Docker y Compose)..."
    verificar_instalar_paquete "docker-ce"
    verificar_instalar_paquete "docker-ce-cli"
    verificar_instalar_paquete "containerd.io"
    verificar_instalar_paquete "docker-compose-plugin"

    echo "[*] Asegurando que el demonio de Docker esté habilitado y en ejecución..."
    systemctl enable --now docker

    echo "[+] Preparación de entorno finalizada."
    read -p "Presione ENTER para continuar..."
}

submodo_pruebas() {
    echo "=== Protocolo de Pruebas Dinámicas ==="
    echo "1. Prueba 11.1: Validación de aislamiento de red"
    echo "2. Prueba 11.2: Validación de resolución interna DNS"
    echo "3. Prueba 11.3: Validación de túnel cifrado de gestión"
    echo "4. Prueba 11.4: Validación de persistencia y healthcheck"
    echo "0. Regresar al menú principal"
    echo "======================================"
    read -p "Seleccione una prueba a ejecutar: " opcion_prueba

    case $opcion_prueba in
        0) return ;;
        *) echo "[!] Prueba aún no implementada." ; read -p "Presione ENTER para continuar..." ;;
    esac
}

generar_archivos() {
    echo "=== Generación de Archivos de Orquestación ==="
    
    # Validación de existencia para no sobrescribir sin permiso
    if [ -f "$DIRECTORIO_INFRA/docker-compose.yml" ] || [ -f "$DIRECTORIO_INFRA/.env" ]; then
        echo "[!] Los archivos de configuración ya existen en $DIRECTORIO_INFRA."
        read -p "¿Desea sobrescribirlos y perder la configuración actual? (s/N): " resp_conf
        if [[ ! "$resp_conf" =~ ^[sS]$ ]]; then
            echo "[-] Omitiendo generación de archivos."
            read -p "Presione ENTER para continuar..."
            return
        fi
    fi

    echo "[*] Generando archivo de variables de entorno (.env)..."
    cat <<EOF > "$DIRECTORIO_INFRA/.env"
# Credenciales de Base de Datos PostgreSQL
POSTGRES_USER=admin_db
POSTGRES_PASSWORD=SuperSecretPassword2026
POSTGRES_DB=practica11_db

# Credenciales de Administrador pgAdmin
PGADMIN_DEFAULT_EMAIL=admin@practica11.local
PGADMIN_DEFAULT_PASSWORD=AdminPassword2026
EOF
    chmod 600 "$DIRECTORIO_INFRA/.env" # Seguridad: solo root puede leer este archivo

    echo "[*] Generando configuración de Nginx (Hardening)..."
    mkdir -p "$DIRECTORIO_INFRA/nginx"
    cat <<EOF > "$DIRECTORIO_INFRA/nginx/default.conf"
server {
    listen 80;
    server_tokens off; # Ocultar cabeceras de versión del servidor

    location / {
        proxy_pass http://app_interna:80;
    }
}
EOF

    echo "[*] Generando archivo de orquestación docker-compose.yml..."
    cat <<EOF > "$DIRECTORIO_INFRA/docker-compose.yml"
version: '3.8'

networks:
  red_publica:
    driver: bridge
  red_datos:
    driver: bridge
    internal: true # Aislamiento total: sin salida a internet

volumes:
  db_data:

services:
  frontend:
    image: nginx:alpine
    container_name: nginx_balancer
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - red_publica
      - red_datos

  app_server:
    image: httpd:alpine
    container_name: app_interna
    restart: always
    networks:
      - red_datos

  db:
    image: postgres:15-alpine
    container_name: postgres_db
    restart: always
    env_file: .env
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - red_datos
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \$\${POSTGRES_USER} -d \$\${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  pgadmin:
    image: dpage/pgadmin4
    container_name: servidor_pgadmin
    restart: always
    env_file: .env
    networks:
      - red_datos
    depends_on:
      db:
        condition: service_healthy
EOF

    echo "[+] Archivos generados correctamente en $DIRECTORIO_INFRA."
    read -p "Presione ENTER para continuar..."
}
