#!/bin/bash

# Cargar variables de entorno desde el archivo .env
ENV_FILE="/opt/cwh/.env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
else
  echo "Error: El archivo de configuración .env no existe en $ENV_FILE"
  exit 1
fi

set -e  # Detener el script en caso de error

# Variables adicionales
fecha_actual=$(date +%Y%m%d)
hora_actual=$(date +%H%M%S)
log_file="/var/log/backup.log"

# Función para registrar logs
function registrar_log() {
  local mensaje="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $mensaje" >> "$log_file"
}

# Función para enviar notificaciones
function enviar_notificacion() {
  local asunto="$1"
  local mensaje="$2"

  # Notificación por correo electrónico
  if [[ -n "$EMAIL_NOTIFICATION" ]]; then
    echo "$mensaje" | mail -s "$asunto" "$EMAIL_NOTIFICATION"
  fi

  # Notificación por Slack (opcional)
  if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$mensaje\"}" "$SLACK_WEBHOOK_URL" &>/dev/null
  fi
}

# Validar variables del archivo .env
function validar_configuracion() {
  for var in REMOTE_USER REMOTE_HOST DB_NAME DB_USER DB_PASS LOCAL_DIR REMOTE_DIR; do
    if [[ -z "${!var}" ]]; then
      registrar_log "Error: La variable $var no está definida en el archivo .env"
      exit 1
    fi
  done

  for cmd in mariadb-dump tar ssh scp mail rsync curl; do
    if ! command -v "$cmd" &>/dev/null; then
      registrar_log "Error: El comando $cmd no está instalado"
      exit 1
    fi
  done
}

# Backup de la base de datos
function backup_db() {
  local nombre_backup="wp_backup_db_${fecha_actual}_${hora_actual}.sql"
  local nombre_comprimido="$nombre_backup.gz"

  registrar_log "Iniciando backup de la base de datos"
  if mariadb-dump --single-transaction --quick --lock-tables=false -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$nombre_backup"; then
    gzip -"$COMPRESSION_LEVEL" "$nombre_backup"
    registrar_log "Backup de la base de datos comprimido correctamente"

    # Transferir al servidor remoto
    if scp -o StrictHostKeyChecking=no "$nombre_comprimido" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_DIR/"; then
      registrar_log "Backup de la base de datos enviado al servidor remoto"
      rm -f "$nombre_comprimido"
    else
      enviar_notificacion "Error en Backup" "Fallo al enviar el backup de la base de datos al servidor remoto"
      exit 1
    fi
  else
    enviar_notificacion "Error en Backup" "Fallo en el backup de la base de datos"
    exit 1
  fi
}

# Backup de archivos
function backup_archivos() {
  local tipo="$1"  # "diario", "semanal", "mensual"
  local nombre_backup="wp_backup_archivos_${tipo}_${fecha_actual}_${hora_actual}.tar.gz"
  local exclusiones=""

  # Incluir exclusiones si están definidas en el .env
  if [[ -n "$EXCLUDE_FILES" ]]; then
    for excl in $EXCLUDE_FILES; do
      exclusiones+="--exclude='$excl' "
    done
  fi

  registrar_log "Iniciando backup de archivos ($tipo)"
  if tar -czf - $exclusiones -C "$LOCAL_DIR" . | ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cat > $REMOTE_DIR/$nombre_backup"; then
    registrar_log "Backup de archivos ($tipo) completado"
  else
    enviar_notificacion "Error en Backup" "Fallo en el backup de archivos ($tipo)"
    exit 1
  fi
}

# Limpieza de backups antiguos
function limpiar_backups_antiguos() {
  local tipo="$1"
  local max_backups="$2"

  registrar_log "Eliminando backups antiguos ($tipo)"
  ssh "$REMOTE_USER@$REMOTE_HOST" "
    ls -1t $REMOTE_DIR/*_${tipo}_*.tar.gz | tail -n +$((max_backups + 1)) | xargs -d '\n' rm -f
  " && registrar_log "Backups antiguos ($tipo) eliminados"
}

# Manejo de señales
trap 'enviar_notificacion "Backup Interrumpido" "El proceso de backup fue interrumpido"; exit 1' SIGINT SIGTERM

# Validar configuración
validar_configuracion

# Inicio del proceso de backup
registrar_log "Inicio del proceso de backup"

# Realizar backups según el día
if [[ $(date +%u) -eq 1 ]]; then
  backup_db
  backup_archivos "semanal"
  limpiar_backups_antiguos "semanal" "$MAX_WEEKLY_BACKUPS"
elif [[ $(date +%d) -eq 1 ]]; then
  backup_db
  backup_archivos "mensual"
  limpiar_backups_antiguos "mensual" "$MAX_MONTHLY_BACKUPS"
else
  backup_archivos "diario"
  limpiar_backups_antiguos "diario" "$MAX_DAILY_BACKUPS"
fi

# Finalizar el proceso de backup
registrar_log "Backup completado con éxito"
enviar_notificacion "Backup Completado" "El proceso de backup se realizó correctamente"
