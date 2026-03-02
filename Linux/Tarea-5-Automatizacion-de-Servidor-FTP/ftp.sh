if [[ $EUID -ne 0 ]]; then
  echo "El script debe de ejecutarse como root :D"
  exit 1
fi

echo "****** Tarea 5: Automatizacion de Servidor FTP ********"

instalar_ftp(){
  echo ""
  echo "Verificando si el servicio vsftpd esta instalado....."
  echo ""

  if rpm -q vsftpd &>/dev/null; then
    echo "El servicio vsftpd ya esta instalado :D"
    while true; do
      read -p "Desea reinstalarlo (s/n)?: " opcion
      echo ""
      case $opcion in
        s|S)
          echo "Reinstalando el servicio vsftpd...."
          dnf reinstall -y vsftpd > /dev/null 2>&1
          echo ""
          echo "Reinstalacion completada :D"
          break ;;
        n|N)
          echo "No se realizara ninguna accion"
          break ;;
        *)
          echo "Opcion invalida... ingrese s o n" ;;
      esac
    done
  else
    echo "El servicio vsftpd no esta instalado"
    echo ""
    echo "Instalado....."
    dnf install -y vsftpd > /dev/null 2>&1
      if rpm -q vsftpd &>/dev/null; then
  			echo "Instalación completada :D"
  		else
  			echo "Hubo un error en la instalación."
  		fi
  fi

  if systemctl is-active --quiet vsftpd; then
    echo "El servicio ya esta activo"
  else
    echo "Iniciando servicio"
    systemctl start vsftpd
    systemctl enable vsftpd
  fi

  read -p "Presione ENTER para continuar..."
}

menu(){
  echo ""
  while true; do  
    echo "***** Menu FTP *****"
    echo "1) instalar servicio FTP"
    read -p "Seleccione una opcion: " opcion
    case $opcion in
      1)instalar_ftp ;;
      0)exit 0;;
      *) echo "opcion invalida"; sleep 1;;
    esac
  done
}

menu
