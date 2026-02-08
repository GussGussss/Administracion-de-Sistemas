echo "*********** SCRIPT DE BIENVENIDA ***********"
nombre=$(hostname)
ip=$(hostname -I)
espacio=$(df -h /)
echo -e "\nNombre del equipo: $nombre"
echo -e "\IP del equipo: $ip"
echo -e "\nEspacio en el disco: \n$espacio\n"
