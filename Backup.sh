#!/bin/bash

# Cargar variables de entorno
source /opt/cwh/.env  # Asegúrate de que este archivo contenga las credenciales

# Configuración
usuario_remoto="$REMOTE_USER"
servidor_remoto="$REMOTE_HOST"
directorio_local="/Your/origin/directory"
directorio_remoto="/your/destination/directori"
base_datos="$DB_NAME"
usuario_db="$DB_USER"
password_db="$DB_PASS"
log_file="/var/log/backup.log"
max_backups=10  # Máximo de backups a mantener
correo_notificacion="your@email.com"

# Función para enviar notificaciones
function enviar_notificacion() {
  local mensaje=$1
  echo "$mensaje" | mail -s "Notificación de Backup" "$correo_notificacion"
}

# Función para realizar el backup de la base de datos
function backup_db() {
  fecha=$(date +%Y%m%d)
  nombre_backup="wp_backup_db_$fecha.sql"

  if mariadb-dump --single-transaction --quick --lock-tables=false -u "$usuario_db" -p"$password_db" "$base_datos" > "$nombre_backup"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup de base de datos completado" >> "$log_file"
  else
    enviar_notificacion "Error: Fallo en el backup de la base de datos"
    exit 1
  fi
}

# Crear el directorio remoto si no existe
mkdir -p "$directorio_remoto"

# Función para enviar los backups al servidor remoto
function enviar_backup() {
  fecha=$(date +%Y%m%d)

  echo "Iniciando backup de archivos..."
  tar -czf - -C "$directorio_local" . | ssh -o StrictHostKeyChecking=no "$usuario_remoto@$servidor_remoto" "cat > $directorio_remoto/wp_backup_$fecha.tar.gz"
  echo "Backup de archivos finalizado."

  # Enviar el backup de la base de datos al servidor remoto
  local db_backup_file="wp_backup_db_$fecha.sql"
  if [[ -f "$db_backup_file" ]]; then
    scp -o StrictHostKeyChecking=no "$db_backup_file" "$usuario_remoto@$servidor_remoto:$directorio_remoto/"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup de base de datos enviado al servidor remoto" >> "$log_file"
  else
    enviar_notificacion "Error: Backup de la base de datos no encontrado"
  fi

  # Calcular y almacenar el hash del backup de archivos
  local backup_file="$directorio_remoto/wp_backup_$fecha.tar.gz"
  if ssh "$usuario_remoto@$servidor_remoto" "[ -f $backup_file ]"; then
    ssh "$usuario_remoto@$servidor_remoto" "sha256sum $backup_file > $backup_file.hash"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completo y hash calculado" >> "$log_file"
  else
    enviar_notificacion "Error: Backup de archivos no encontrado en $backup_file"
  fi
}

# Función para eliminar backups antiguos
function eliminar_backups_antiguos() {
  local count
  count=$(find "$directorio_remoto" -name "*.tar.gz" | wc -l)

  if [[ $count -gt $max_backups ]]; then
    find "$directorio_remoto" -name "*.tar.gz" -mtime +30 -exec rm {} \;
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backups antiguos eliminados" >> "$log_file"
  fi
  }

# Verificar si es lunes para realizar el backup completo
if [[ $(date +%u) -eq 1 ]]; then
  backup_db
  enviar_backup
else
  backup_db
  echo "Iniciando backup incremental..."
  # Aquí podrías agregar lógica para backups incrementales si es necesario
  echo "Backup incremental completado."
fi

# Limpiar backups antiguos
eliminar_backups_antiguos

# Log de ejecución
echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup completado" >> "$log_file"


