<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Final Boss - Admin de Sistemas</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; display: flex; height: 100vh; background-color: #f4f4f9; }
        nav { width: 250px; background-color: #2c3e50; color: white; padding: 20px; }
        nav h2 { font-size: 1.2rem; border-bottom: 1px solid #455a64; padding-bottom: 10px; }
        nav a { display: block; color: #ecf0f1; text-decoration: none; padding: 10px; margin-bottom: 5px; border-radius: 4px; }
        nav a:hover { background-color: #34495e; }
        main { flex-grow: 1; padding: 30px; overflow-y: auto; }
        .consola { background-color: #1e1e1e; color: #00ff00; padding: 20px; border-radius: 5px; font-family: monospace; white-space: pre-wrap; margin-top: 20px; box-shadow: 0 4px 8px rgba(0,0,0,0.2); }
        .botones { margin-top: 15px; }
        .btn { padding: 10px 15px; background-color: #3498db; color: white; text-decoration: none; border-radius: 4px; margin-right: 10px; border: none; cursor: pointer; }
        .btn:hover { background-color: #2980b9; }
    </style>
</head>
<body>

    <nav>
        <h2>Admin Linux</h2>
        <a href="index.php?practica=1">Práctica 1: Diagnóstico</a>
        <a href="index.php?practica=2">Práctica 2: Servidor DHCP</a>
    </nav>

    <main>
        <h1>Panel Centralizado de Servidores</h1>
        
        <?php
        // --- PRÁCTICA 1 ---
        if (isset($_GET['practica']) && $_GET['practica'] == '1') {
            echo "<h3>Ejecutando Tarea 1...</h3>";
            $comando = "/home/srv-linux-sistemas/Administracion-de-Sistemas/Linux/Tarea-1-Entorno-de-Virtualizacion-e-infraestructura-Base/check_status.sh 2>&1";
            $salida = shell_exec($comando);
            echo "<div class='consola'>" . ($salida ?? "Error fatal") . "</div>";
        } 
        // --- PRÁCTICA 2 ---
        elseif (isset($_GET['practica']) && $_GET['practica'] == '2') {
            echo "<h3>Gestión del Servidor DHCP (KEA)</h3>";
            
            // Botones de acción para la web
            echo "<div class='botones'>
                    <a href='index.php?practica=2&accion=instalar' class='btn'>Instalar KEA</a>
                    <a href='index.php?practica=2&accion=estado' class='btn'>Ver Estado</a>
                    <a href='index.php?practica=2&accion=leases' class='btn'>Ver Concesiones</a>
                  </div>";

            // Si se presionó algún botón, ejecutamos el comando con sudo
            if (isset($_GET['accion'])) {
                $accion = escapeshellcmd($_GET['accion']); // Seguridad
                $ruta_script = "/home/srv-linux-sistemas/Administracion-de-Sistemas/Linux/Tarea-2-Automatizacion-y-gestion-del-servidor-DHCP/srv_dhcp.sh";
                
                // Nota el "sudo" al principio y el "$accion" al final
                $comando = "sudo $ruta_script $accion 2>&1";
                $salida = shell_exec($comando);
                
                echo "<div class='consola'>$salida</div>";
            }
        } 
        else {
            echo "<p>Selecciona una práctica del menú.</p>";
        }
        ?>
    </main>

</body>
</html>
