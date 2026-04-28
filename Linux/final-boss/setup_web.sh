#!/bin/bash

echo "======================================================"
echo "  🛠️ Iniciando el despliegue del Dashboard Web... "
echo "======================================================"

# 1. Instalar Apache y PHP
echo -e "\n[1/5] Instalando Apache (httpd) y PHP..."
sudo dnf install httpd php -y

# 2. Configurar servicios y firewall
echo -e "\n[2/5] Iniciando Apache y abriendo puertos en el Firewall..."
sudo systemctl enable --now httpd
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --reload

# 3. Crear el puente (Enlace Simbólico)
echo -e "\n[3/5] Creando el enlace simbólico hacia tu repositorio..."
# Usamos -f para borrar el enlace si ya existe, evitando errores al ejecutar el script múltiples veces
sudo rm -f /var/www/html/sistemas
sudo ln -s /home/srv-linux-sistemas/Administracion-de-Sistemas /var/www/html/sistemas

# 4. Permisos de Sistema y Configuración de Apache
echo -e "\n[4/5] Configurando permisos de Apache y reglas de directorio..."
# Aseguramos que Apache pueda cruzar hasta tu carpeta
sudo chmod +x /home
sudo chmod +x /home/srv-linux-sistemas
sudo chmod -R 755 /home/srv-linux-sistemas/Administracion-de-Sistemas

# Creamos la regla para que Apache confíe en tu carpeta y permita el enlace simbólico
echo '<Directory "/home/srv-linux-sistemas/Administracion-de-Sistemas">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>' | sudo tee /etc/httpd/conf.d/sistemas.conf > /dev/null

# 5. SELinux (El "Final Boss")
echo -e "\n[5/5] Configurando políticas de SELinux (esto puede tomar unos segundos)..."
sudo setsebool -P httpd_enable_homedirs 1
sudo setsebool -P httpd_unified 1
# Etiquetamos tu carpeta como contenido web legítimo
sudo chcon -R -t httpd_sys_content_t /home/srv-linux-sistemas/Administracion-de-Sistemas

# Asegurar que el script de diagnóstico tenga permisos de ejecución nativos
sudo chmod +x /home/srv-linux-sistemas/Administracion-de-Sistemas/Linux/Tarea-1-Entorno-de-Virtualizacion-e-infraestructura-Base/tarea1_diagnostico.sh

# Aplicar los cambios reiniciando el servicio web
echo "Reiniciando el servicio web para aplicar las configuraciones..."
sudo systemctl restart httpd

echo -e "\n======================================================"
echo " ✅ ¡Despliegue Completado con Éxito! "
echo "======================================================"
echo "Tu servidor web ya está apuntando a tu repositorio y libre del error 403."
