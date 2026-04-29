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
    </style>
</head>
<body>

    <nav>
        <h2>Admin Linux</h2>
        <a href="index.php?practica=1">Práctica 1: Diagnóstico</a>
    </nav>

    <main>
        <h1>Panel Centralizado de Servidores</h1>
        
        <?php
        if (isset($_GET['practica']) && $_GET['practica'] == '1') {
            echo "<h3>Ejecutando Tarea 1...</h3>";
            
            // Ruta exacta al script. El " 2>&1" al final es MAGIA: captura los errores para mostrarlos en pantalla
            $comando = "/home/srv-linux-sistemas/Administracion-de-Sistemas/Linux/Tarea-1-Entorno-de-Virtualizacion-e-infraestructura-Base/check_status.sh";
            
            // Ejecutamos el comando
            $salida = shell_exec($comando);
            
            // Verificamos si PHP no pudo ejecutar nada en absoluto
            if ($salida === null) {
                $salida = "Error fatal de PHP: No se pudo invocar el script. Revisa la ruta.";
            }

            echo "<div class='consola'>$salida</div>";
        } else {
            echo "<p>Selecciona una práctica del menú.</p>";
        }
        ?>
    </main>

</body>
</html>
