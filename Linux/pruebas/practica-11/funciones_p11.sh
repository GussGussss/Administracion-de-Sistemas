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

desplegar_infraestructura() {
    echo "=== Despliegue de Infraestructura ==="
    
    if [ ! -f "$DIRECTORIO_INFRA/docker-compose.yml" ]; then
        echo "[!] No se encontró el archivo de orquestación. Ejecute la Opción 2 primero."
        read -p "Presione ENTER para continuar..."
        return
    fi

    cd "$DIRECTORIO_INFRA" || return

    echo "[*] Verificando estado de las imágenes locales..."
    # Lógica de Ahorro de Datos: Preguntar antes de descargar/actualizar
    read -p "¿Desea forzar la búsqueda y descarga de actualizaciones de imágenes desde internet? (s/N): " resp_pull
    if [[ "$resp_pull" =~ ^[sS]$ ]]; then
        echo "[+] Conectando a los repositorios para actualizar imágenes..."
        docker compose pull
    else
        echo "[-] Omitiendo actualización de imágenes. Se utilizará la caché local para ahorrar datos."
    fi

    echo "[*] Levantando los servicios en segundo plano..."
    docker compose up -d

    echo "[*] Esperando la inicialización y Healthchecks (10 segundos)..."
    sleep 10

    echo "[*] Configurando resolución DNS a nivel de Sistema Operativo para el túnel SSH..."
    # Extraer la IP dinámica del contenedor pgadmin usando inspección de Docker
    IP_PGADMIN=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor_pgadmin 2>/dev/null | head -n 1)
    
    if [ -n "$IP_PGADMIN" ]; then
        # Limpiar cualquier entrada previa para evitar conflictos
        sed -i '/servidor_pgadmin/d' /etc/hosts
        
        # Inyectar la nueva IP para que el demonio SSH pueda resolver el nombre
        echo "$IP_PGADMIN servidor_pgadmin" >> /etc/hosts
        echo "[+] Resolución SSH configurada: 'servidor_pgadmin' apunta a la IP interna $IP_PGADMIN."
    else
        echo "[-] Advertencia: No se pudo obtener la IP de servidor_pgadmin. Es posible que el contenedor aún no esté listo."
    fi

    echo "[+] Despliegue finalizado."
    echo "Servicios activos en este momento:"
    docker compose ps
    echo "======================================"
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_1() {
    clear
    echo "--- Prueba 11.1: Validación de Aislamiento de Red ---"
    echo "Vamos a simular un ataque externo intentando acceder a la base de datos."
    read -p "Ingrese la IP de este servidor Oracle Linux (o 'localhost' si prueba localmente): " ip_host
    echo "[*] Ejecutando: curl --connect-timeout 5 -v telnet://$ip_host:5432"
    echo "[!] Resultado esperado: Connection timed out o Connection refused."
    echo "---------------------------------------------------"
    curl --connect-timeout 5 -v telnet://"$ip_host":5432
    echo "---------------------------------------------------"
    echo "Si la conexion fallo, el aislamiento es EXITOSO. Nadie puede ver su BD."
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_2() {
    clear
    echo "--- Prueba 11.2: Validación de Resolución Interna DNS ---"
    echo "Demostraremos que Nginx puede encontrar a los otros contenedores por nombre."
    read -p "Ingrese el nombre del servicio a buscar (ej. db, app_server, pgadmin): " target_dns
    echo "[*] Ejecutando ping desde el contenedor nginx_balancer hacia '$target_dns'..."
    echo "---------------------------------------------------"
    docker exec nginx_balancer ping -c 4 "$target_dns"
    echo "---------------------------------------------------"
    echo "Si hubo respuesta (0% packet loss), el DNS de Docker es EXITOSO."
    read -p "Presione ENTER para continuar..."
}

ejecutar_prueba_11_3() {
    clear
    echo "--- Prueba 11.3: Validación de Túnel Cifrado de Gestión ---"
    echo "Para esta prueba, usted debe actuar desde su computadora FISICA (Windows 10 / Ubuntu)."
    read -p "Ingrese su nombre de usuario en Oracle Linux (ej. root, alumno): " usr_ssh
    read -p "Ingrese la IP de este servidor Oracle Linux: " ip_ssh
    echo "---------------------------------------------------"
    echo "PASO 1: Abra la terminal o CMD en su maquina fisica."
    echo "PASO 2: Ejecute exactamente el siguiente comando:"
    echo ""
    echo "    ssh -L 8080:servidor_pgadmin:80 $usr_ssh@$ip_ssh"
    echo ""
    echo "PASO 3: Inicie sesion con su contrasena."
    echo "PASO 4: Abra su navegador en Windows y entre a: http://localhost:8080"
    echo "---------------------------------------------------"
    echo "Debera ver la pantalla de inicio de sesion de pgAdmin."
    echo "Credenciales definidas en su .env: admin@practica11.local / AdminPassword2026"
    read -p "Presione ENTER una vez que haya validado el acceso en su navegador..."
}

ejecutar_prueba_11_4() {
    echo "--- Prueba 11.4: Validación de Persistencia y Healthcheck ---"
    cd "$DIRECTORIO_INFRA" || return
    echo "[*] Simulando caida del sistema. Destruyendo contenedores actuales..."
    docker compose down
    echo "[*] Sistema abajo. Comprobando estado:"
    docker compose ps
    echo "---------------------------------------------------"
    read -p "Presione ENTER para iniciar la recuperacion del sistema..."
    
    echo "[*] Levantando infraestructura nuevamente..."
    docker compose up -d
    echo "[*] Observando el orden de arranque (verifique que pgadmin espere a que db sea 'healthy')..."
    
    # Bucle de observación de 15 segundos para ver el cambio de estado
    for i in {1..15}; do
        clear
        echo "Monitoreando estado (Intento $i/15). Observe la columna STATUS:"
        docker compose ps
        sleep 2
    done
    
    echo "---------------------------------------------------"
    echo "Recuperacion finalizada. Si pgadmin esta 'Up', el Healthcheck funciono."
    echo "Los datos de su base de datos siguen intactos gracias al volumen persistente."
    read -p "Presione ENTER para continuar..."
}

submodo_pruebas() {
    while true; do
        echo "======================================"
        echo " Protocolo de Pruebas Dinámicas"
        echo "======================================"
        echo " 1. Prueba 11.1: Aislamiento de red (curl)"
        echo " 2. Prueba 11.2: Resolución DNS interna (ping)"
        echo " 3. Prueba 11.3: Túnel cifrado de gestión (ssh -L)"
        echo " 4. Prueba 11.4: Persistencia y Healthcheck (down/up)"
        echo " 0. Regresar al menú principal"
        echo "======================================"
        read -p "Seleccione una prueba a ejecutar [0-4]: " opcion_prueba

        case $opcion_prueba in
            1) ejecutar_prueba_11_1 ;;
            2) ejecutar_prueba_11_2 ;;
            3) ejecutar_prueba_11_3 ;;
            4) ejecutar_prueba_11_4 ;;
            0) break ;;
            *) echo "[-] Opción inválida." ; sleep 2 ;;
        esac
    done
}
