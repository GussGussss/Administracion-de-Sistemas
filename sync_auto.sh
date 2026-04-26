#!/bin/bash

cd ~/Administracion-de-Sistemas

git pull origin main
git add .
fecha=$(date +"%Y-%m-%d %H:%M:%S")

git commit -m "Auto-sync Linux: $fecha"
git push origin main
