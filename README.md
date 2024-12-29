# Descripción
Este script está diseñado para realizar respaldos automáticos de un sitio web WordPress, incluyendo sus archivos y base de datos. Utiliza un archivo .env para manejar las configuraciones, lo que facilita su personalización y seguridad. También incluye soporte para notificaciones por correo electrónico y Slack, y gestiona la retención de backups antiguos (diarios, semanales y mensuales).

## Características
- Backup de Archivos: Respaldos completos o incrementales de los archivos del sitio.
- Backup de Base de Datos: Dumps de la base de datos comprimidos y transferidos al servidor remoto.
- Configuración mediante .env: Todas las variables sensibles y configuraciones se definen en un archivo externo.
- Notificaciones: Envía notificaciones por correo electrónico y Slack (opcional).
- Gestión de Retención: Elimina automáticamente los backups antiguos según la configuración.
- Seguridad: Soporte para exclusión de archivos innecesarios y cifrado del backup de la base de datos.

## Requisitos
### Comandos Necesarios:
- mariadb-dump
- tar
- ssh
- scp
- rsync
- mail
- curl
- Acceso SSH: El servidor remoto debe ser accesible mediante SSH.
- Archivo .env: Configuración de variables de entorno.

