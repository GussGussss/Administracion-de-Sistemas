#!/bin/bash
# Script de respaldo generado automaticamente
fecha=$(date +"%Y%m%d_%H%M%S")
docker exec db_postgres pg_dump -U admin_user practica_db > ./db/respaldo_$fecha.sql
echo "Respaldo creado: respaldo_$fecha.sql"
