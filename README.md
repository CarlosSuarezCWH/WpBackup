# Script de Backup

Este script automatiza el proceso de copia de seguridad de bases de datos y archivos hacia un servidor remoto.

## Requisitos

- Bash
- MariaDB
- SSH
- Herramienta de envío de correos (como `mail`)

## Configuración

1. **Variables de entorno**: Asegúrate de definir las siguientes variables en un archivo de configuración:

   - `REMOTE_USER`: Usuario para acceder al servidor remoto.
   - `REMOTE_HOST`: Dirección del servidor remoto.
   - `DB_NAME`: Nombre de la base de datos a respaldar.
   - `DB_USER`: Usuario de la base de datos.
   - `DB_PASS`: Contraseña de la base de datos.

2. **Configuración del script**: Ajusta las siguientes variables dentro del script:

   - `directorio_local`: Ruta del directorio local que deseas respaldar.
   - `directorio_remoto`: Ruta en el servidor remoto para almacenar los backups.
   - `log_file`: Ruta para el archivo de log.
   - `max_backups`: Número máximo de backups a mantener.
   - `correo_notificacion`: Correo electrónico para recibir notificaciones sobre el proceso.

## Funciones

- **enviar_notificacion**: Envía notificaciones por correo electrónico en caso de errores.
- **backup_db**: Realiza un respaldo de la base de datos y lo guarda localmente.
- **enviar_backup**: Comprime los archivos y los envía al servidor remoto, junto con el backup de la base de datos.
- **eliminar_backups_antiguos**: Elimina copias de seguridad antiguas según el límite establecido.

## Ejecución

El script ejecuta un backup completo los lunes y backups incrementales en otros días.

### Para ejecutar el script:

```bash
bash nombre_del_script.sh
