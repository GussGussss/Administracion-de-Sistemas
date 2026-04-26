FROM alpine:latest

# Instalar Nginx sin cache para mantener imagen ligera
RUN apk update && apk add --no-cache nginx

# SEGURIDAD: Crear usuario no administrativo
RUN adduser -D -g 'www' www

# Crear directorios y asignar propiedad al usuario seguro
RUN mkdir -p /www /run/nginx && \
    chown -R www:www /var/lib/nginx /www /run/nginx /var/log/nginx

# Inyectar configuracion endurecida
COPY nginx.conf /etc/nginx/nginx.conf

# Exponer el puerto
EXPOSE 8080

# Forzar la ejecucion del contenedor con el usuario no-root
USER www

CMD ["nginx", "-g", "daemon off;"]
