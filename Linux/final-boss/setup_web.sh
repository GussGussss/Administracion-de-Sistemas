#!/bin/bash

echo "======================================================"
echo "  🛠️ Iniciando el despliegue del Dashboard Web... "
echo "======================================================"

# 1. Instalar Apache y PHP
echo -e "\n[1/4] Instalando Apache (httpd) y PHP..."
sudo dnf install httpd php -y

# 2. Configurar servicios y firewall
echo -e "\n[2/4] Iniciando Apache y abriendo puertos en el Firewall..."
sudo systemctl enable --now httpd
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload

# 3. Crear el puente (Enlace Simbólico)
echo -e "\n[3/4] Creando el enlace simbólico hacia tu repositorio..."
# Usamos -f para borrar el enlace si ya existe, evitando errores al ejecutar el script múltiples veces
sudo rm -f /var/www/html/sistemas
sudo ln -s /home/srv-linux-sistemas/Administracion-de-Sistemas /var/www/html/sistemas

# 4. Permisos y SELinux (El "Final Boss")
echo -e "\n[4/4] Configurando Permisos y SELinux..."
sudo chmod o+rx /home/srv-linux-sistemas
sudo chmod -R o+rx /home/srv-linux-sistemas/Administracion-de-Sistemas

echo "Aplicando reglas de SELinux (esto puede tomar unos segundos, paciencia)..."
sudo setsebool -P httpd_enable_homedirs 1
sudo setsebool -P httpd_unified 1

# Asegurar que el script de diagnóstico tenga permisos de ejecución
sudo chmod +x /home/srv-linux-sistemas/Administracion-de-Sistemas/Linux/Tarea-1-Entorno-de-Virtualizacion-e-infraestructura-Base/tarea1_diagnostico.sh

echo "======================================================"
echo " ✅ ¡Despliegue Completado con Éxito! "
echo "======================================================"
echo "Tu servidor web ya está apuntando a tu repositorio y listo para probar."
