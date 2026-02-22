echo ""
echo ""
echo "****** Tarea 4: SSH **********"
ipActual=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
echo "Hostname: $(hostname)"
echo "IP: $ipActual"
echo ""

instalar_ssh(){
  echo ""
  echo "Checando que el servicio SSH ya este instalado....."

  if rpm -q openssh-server &>/dev/null; then
    echo "El servicio SSH si esta instalado :D"
      while true; do
        read -p "¿Quiere reinstalar el servicio? (s/n): " opcion
          case $opcion in
            s|S)
              echo "Reinstalando SSH..."
              sudo dnf reinstall -y openssh-server > /dev/null 2>&1
              echo "Reintalacion completa :D"
              break
              ;;
            n|N)
              echo "No se hara ninguna accion"
              break
              ;;
            *)
              echo "Opcion incorrecta... Ingrese s o n"
              ;;
          esac
      done
  else
      echo "El servicio SSH no esta instalado."
      echo "Instalando servicio SSH...."
      sudo dnf install -y openssh-server > /dev/null 2>&1
      if rpm -q openssh-server &>/dev/null; then
        echo "Instalaacion completada :D"
      else
        echo "Ocurrio un error al instalar el servicio SSH :c"
      fi
  fi
  sudo systemctl start sshd
  sudo systemctl enable sshd
  if ! sudo firewall-cmd --list-services | grep -qw ssh; then  
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --reload
  fi
  read -p "Presione ENTER para continuar..."
}

estado_ssh(){
  echo ""
  echo "****** Estado del servicio DNS ******"
  echo ""
  if systemctl is-active --quiet sshd; then
    echo "Estado: Servicio SSH activo"
    echo ""
    read -p "¿Quiere ver el estado detallado del servicio? (s/n): " opcion
      case $opcion in
        s|S)
          echo "**** Estado detallado del Servicio DNS ****"
          echo ""
          sudo systemctl status sshd --no-pager
          return
          ;;
        n|N)
          return
          ;;
        *)
          echo "opcion invalida... ingrese n o s"
          ;;
      esac
  else
    echo "Estado: Servicio SHH inactivo"
  fi
}

menu_ssh(){
while true; do
  echo ""
  echo ""
  echo "***** Menu SSH ****"
  echo "1) Instalar servicio SSH"
  echo "2) Estaod del servicio DNS"
  read -p "Selecciona un opcion " opcion
  case $opcion in
    1)instalar_ssh ;;
    2)estado_ssh ;;
    *) echo "opcion invalida"; sleep 1;;
  esac
done
}

menu_ssh
