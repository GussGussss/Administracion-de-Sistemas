if [[ $EUID -ne 0 ]]; then
  echo "El script debe de ejecutarse como root"
  exit 1
fi

echo "****** Tarea 5: Automatizacion de Servidor FTP ********"
instalar_vsftpd(){
  echo ""
  echo "Verificando si el servicio vsftpd esta instalado....."
  echo ""

  if rpm -q vsftpd &>/dev/null; then
    echo "El servicio vsftpd ya esta instalado :D"
  else
    echo "El servicio vsftpd no esta instalado"
    echo ""
    echo "Instalado....."
    dnf install -y vsftpd /dev/null 2>&1
    echo "Instalacion completada :D"
    echo ""
  fi

  if systemctl is-active --quiet vsftpd; then
    echo "El servicio ya esta activo"
  else
    echo "Iniciando servicio"
    systemctl start vsftpd
  fi
}
