#!/bin/bash
# funciones_p11.sh
# Lógica de soporte para la Práctica 11 con Guía de Usuario Integrada

DIRECTORIO_INFRA="/opt/practica11"

# --- Funciones de Utilidad ---

verificar_instalar_paquete() {
    local paquete=$1
    if rpm -q "$paquete" &> /dev/null; then
        echo "[!] El paquete '$paquete' ya se encuentra instalado."
        read -p "¿Desea forzar su descarga y reinstalación? (s/N): " respuesta
        if [[ "$respuesta" =~ ^[sS]$ ]]; then
            dnf reinstall -y "$paquete"
        fi
    else
        echo "[+] Descargando e instalando '$paquete'..."
        dnf install -y "$paquete"
    fi
}

actualizar_resolucion_dns() {
    local target_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor_pgadmin 2>/dev/null | head -n 1)
    if [ -n "$target_ip" ]; then
        sed -i '/servidor_pgadmin/d' /etc/hosts
        tail -c1 /etc/hosts | read -r _ || echo >> /etc/hosts
        echo "$target_ip servidor_pgadmin" >> /etc/hosts
        restorecon -v /etc/hosts >/dev/null 2>&1 || true
    fi
}

# --- Funciones de Menú Principal ---

preparar_entorno() {
    
    echo "=== Opción 1: Preparación del Entorno ==="
    mkdir -p "$DIRECTORIO_INFRA"
    verificar_instalar_paquete "dnf-plugins-core"
    if [ ! -f "/etc/yum.repos.d/docker-ce.repo" ]; then
        dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    fi
    verificar_instalar_paquete "docker-ce"
    verificar_instalar_paquete "docker-ce-cli"
    verificar_instalar_paquete "containerd.io"
    verificar_instalar_paquete "docker-compose-plugin"
    systemctl enable --now docker
    echo "[+] Preparación finalizada."
    read -p "Presione ENTER para continuar..."
}

generar_archivos() {
    
    echo "=== Opción 2: Generación de Archivos ==="
    cat <<EOF > "$DIRECTORIO_INFRA/.env"
POSTGRES_USER=admin_db
POSTGRES_PASSWORD=SuperSecretPassword2026
POSTGRES_DB=practica11_db
PGADMIN_DEFAULT_EMAIL=admin@practica11.com
PGADMIN_DEFAULT_PASSWORD=AdminPassword2026
EOF
    chmod 600 "$DIRECTORIO_INFRA/.env"
    mkdir -p "$DIRECTORIO_INFRA/nginx"
    cat <<EOF > "$DIRECTORIO_INFRA/nginx/default.conf"
server {
    listen 80;
    server_tokens off;
    location / { proxy_pass http://app_interna:80; }
}
EOF
    cat <<EOF > "$DIRECTORIO_INFRA/docker-compose.yml"
version: '3.8'
networks:
  red_publica:
    driver: bridge
  red_datos:
    driver: bridge
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
    echo "[+] Archivos generados en $DIRECTORIO_INFRA."
    read -p "Presione ENTER para continuar..."
}

desplegar_infraestructura() {
    
    echo "=== Opción 3: Despliegue de Infraestructura ==="
    cd "$DIRECTORIO_INFRA" || return
    docker compose up -d
    echo "[*] Esperando inicialización y healthchecks (10s)..."
    sleep 10
    actualizar_resolucion_dns
    echo "[+] Despliegue finalizado."
    read -p "Presione ENTER para continuar..."
}

# --- Funciones de Pruebas con Instrucciones de Usuario ---

ejecutar_prueba_11_1() {
    
    echo "--- Prueba 11.1: Validación de Aislamiento de Red ---"
    echo "INSTRUCCIONES:"
    echo "1. Diríjase a su computadora física (Windows/Ubuntu)."
    echo "2. Abra una terminal (PowerShell o CMD)."
    echo "3. Ejecute un comando curl hacia el puerto de la base de datos (5432)."
    echo ""
    DEFAULT_IP=$(ip -4 addr show enp0s3 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)
    read -p "Ingrese la IP de este servidor [Enter para '$DEFAULT_IP']: " ip_host
    ip_host=${ip_host:-$DEFAULT_IP}
    
    echo ""
    echo "[*] Ejecutando simulación de prueba desde el servidor para validar logs..."
    curl --connect-timeout 5 -v telnet://"$ip_host":5432
    echo ""
    echo "RESULTADO ESPERADO: En su máquina física, la conexión DEBE ser rechazada."
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_2() {
    
    echo "--- Prueba 11.2: Validación de Resolución Interna DNS ---"
    echo "INSTRUCCIONES:"
    echo "1. Esta prueba verifica que los contenedores se comunican por NOMBRE."
    echo "2. El script ejecutará un 'docker exec' dentro de Nginx."
    echo ""
    DEFAULT_SERVICE="db"
    read -p "Ingrese el nombre del servicio a testear [Enter para '$DEFAULT_SERVICE']: " target_dns
    target_dns=${target_dns:-$DEFAULT_SERVICE}
    
    echo ""
    echo "[*] Ejecutando: docker exec nginx_balancer ping -c 4 $target_dns"
    docker exec nginx_balancer ping -c 4 "$target_dns"
    echo ""
    echo "RESULTADO ESPERADO: El ping debe tener éxito, demostrando resolución DNS interna."
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_3() {
    
    echo "--- Prueba 11.3: Validación de Túnel Cifrado de Gestión ---"
    actualizar_resolucion_dns
    
    DEFAULT_USER=${SUDO_USER:-$USER}
    DEFAULT_IP=$(ip -4 addr show enp0s3 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n 1)

    echo "INSTRUCCIONES PARA EL ESTUDIANTE:"
    echo "1. Abra una terminal en su MÁQUINA FÍSICA (Windows/Ubuntu)."
    echo "2. Copie y pegue el siguiente comando SSH:"
    echo ""
    echo "   ssh -L 8080:servidor_pgadmin:80 $DEFAULT_USER@$DEFAULT_IP"
    echo ""
    echo "3. Una vez establecida la sesión, abra su navegador web y entre a:"
    echo "   http://localhost:8080"
    echo ""
    echo "4. Use las siguientes credenciales para pgAdmin:"
    echo "   Usuario: admin@practica11.com"
    echo "   Clave:   AdminPassword2026"
    echo "---------------------------------------------------"
    read -p "Presione ENTER cuando haya validado el acceso en su navegador..."
}

ejecutar_prueba_11_4() {
    
    echo "--- Prueba 11.4: Validación de Persistencia y Healthcheck ---"
    echo "INSTRUCCIONES:"
    echo "1. El script detendrá todo el stack (docker-compose down)."
    echo "2. Luego lo iniciará de nuevo."
    echo "3. Observe que pgAdmin no sube hasta que la DB reporte 'healthy'."
    echo ""
    read -p "Presione ENTER para iniciar la prueba de destrucción/reconstrucción..."
    
    cd "$DIRECTORIO_INFRA" || return
    echo "[*] Deteniendo infraestructura..."
    docker compose down
    echo "[+] Infraestructura eliminada. Iniciando recuperación..."
    docker compose up -d
    
    echo "[*] Monitoreando estados de salud de los servicios..."
    for i in {1..8}; do
        docker compose ps
        sleep 2
    done
    echo ""
    echo "RESULTADO ESPERADO: Los servicios deben estar 'Up' y los datos deben persistir."
    read -p "Presione ENTER para finalizar..."
}

submodo_pruebas() {
    while true; do
        
        echo "======================================"
        echo " Protocolo de Pruebas Dinámicas"
        echo "======================================"
        echo " 1. Prueba 11.1: Aislamiento (curl)"
        echo " 2. Prueba 11.2: DNS interna (ping)"
        echo " 3. Prueba 11.3: Túnel cifrado (Guía SSH)"
        echo " 4. Prueba 11.4: Persistencia (Ciclo de Vida)"
        echo " 0. Regresar al menú principal"
        echo "======================================"
        read -p "Seleccione una opción [0-4]: " opt
        case $opt in
            1) ejecutar_prueba_11_1 ;;
            2) ejecutar_prueba_11_2 ;;
            3) ejecutar_prueba_11_3 ;;
            4) ejecutar_prueba_11_4 ;;
            0) break ;;
            *) echo "Opción inválida."; sleep 1 ;;
        esac
    done
}
