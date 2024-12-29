#!/bin/bash

# Cargar variables de entorno
source /opt/cwh/.env
set -e  # Detener el script en caso de error

# Variables de configuración
usuario_remoto="$REMOTE_USER"
servidor_remoto="$REMOTE_HOST"
directorio_local="/Your/origin/directory"
directorio_remoto="/your/destination/directory"
base_datos="$DB_NAME"
usuario_db="$DB_USER"
password_db="$DB_PASS"
log_file="/var/log/backup.log"
max_backups_diarios=7
max_backups_semanales=4
max_backups_mensuales=12
correo_notificacion="your@email.com"
nivel_compresion=9  # Nivel de compresión para tar
notificaciones_slack_webhook="https://hooks.slack.com/services/your/webhook/url"

# Obtener fecha y hora actual
fecha_actual=$(date +%Y%m%d)
hora_actual=$(date +%H%M%S)

# Función para registrar logs
function registrar_log() {
  local mensaje="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $mensaje" >> "$log_file"
}

# Función para enviar notificaciones
function enviar_notificacion() {
  local asunto="$1"
  local mensaje="$2"
  echo "$mensaje" | mail -s "$asunto" "$correo_notificacion"

  # Notificación opcional por Slack
  if [[ -n "$notificaciones_slack_webhook" ]]; then
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"$mensaje\"}" "$notificaciones_slack_webhook" &>/dev/null
  fi
}

# Validar las variables necesarias
function validar_configuracion() {
  for var in REMOTE_USER REMOTE_HOST DB_NAME DB_USER DB_PASS; do
    if [[ -z "${!var}" ]]; then
      registrar_log "Error: La variable $var no está definida"
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

# Función para realizar el backup de la base de datos
function backup_db() {
  local nombre_backup="wp_backup_db_${fecha_actual}_${hora_actual}.sql"
  local nombre_comprimido="$nombre_backup.gz"

  # Dump de la base de datos
  if mariadb-dump --single-transaction --quick --lock-tables=false -u "$usuario_db" -p"$password_db" "$base_datos" > "$nombre_backup"; then
    registrar_log "Backup de base de datos completado"

    # Comprimir el archivo de la base de datos
    if gzip -"$nivel_compresion" "$nombre_backup"; then
      registrar_log "Backup de base de datos comprimido correctamente"
    fi
  else
    enviar_notificacion "Error en Backup" "Fallo en el backup de la base de datos"
    exit 1
  fi

  # Transferir el archivo comprimido al servidor remoto
  if scp -o StrictHostKeyChecking=no "$nombre_comprimido" "$usuario_remoto@$servidor_remoto:$directorio_remoto/"; then
    registrar_log "Backup de la base de datos enviado al servidor remoto"
    rm -f "$nombre_comprimido"  # Limpiar archivo local
  else
    enviar_notificacion "Error en Backup" "Fallo al enviar el backup de la base de datos al servidor remoto"
    exit 1
  fi
}

# Función para realizar backup de archivos con exclusiones
function backup_archivos() {
  local tipo="$1"  # "diario", "semanal", "mensual"
  local nombre_backup="wp_backup_archivos_${tipo}_${fecha_actual}_${hora_actual}.tar.gz"

  # Excluir archivos innecesarios
  local exclusiones="--exclude='*.tmp' --exclude='*.log' --exclude='node_modules' --exclude='cache'"

  registrar_log "Iniciando backup de archivos ($tipo)"
  if tar -czf - $exclusiones -C "$directorio_local" . | ssh -o StrictHostKeyChecking=no "$usuario_remoto@$servidor_remoto" "cat > $directorio_remoto/$nombre_backup"; then
    registrar_log "Backup de archivos ($tipo) completado"
  else
    enviar_notificacion "Error en Backup" "Fallo en el backup de archivos ($tipo)"
    exit 1
  fi
}

# Función para limpiar backups antiguos con retención basada en tiempo
function limpiar_backups_antiguos() {
  local tipo="$1"
  local max_backups="$2"

  ssh "$usuario_remoto@$servidor_remoto" "
    ls -1t $directorio_remoto/*_${tipo}_*.tar.gz | tail -n +$((max_backups + 1)) | xargs -d '\n' rm -f
  "
  registrar_log "Backups antiguos ($tipo) eliminados si excedían $max_backups"
}

# Manejo de señales (para detener el script de manera segura)
trap 'enviar_notificacion "Backup Interrumpido" "El proceso de backup fue interrumpido"; exit 1' SIGINT SIGTERM

# Validar configuración y dependencias
validar_configuracion

# Inicio del backup
registrar_log "Inicio del proceso de backup"

# Selección de backup basado en el día
if [[ $(date +%u) -eq 1 ]]; then
  backup_db
  backup_archivos "semanal"
  limpiar_backups_antiguos "semanal" "$max_backups_semanales"
elif [[ $(date +%d) -eq 1 ]]; then
  backup_db
  backup_archivos "mensual"
  limpiar_backups_antiguos "mensual" "$max_backups_mensuales"
else
  backup_archivos "diario"
  limpiar_backups_antiguos "diario" "$max_backups_diarios"
fi

# Finalizar el proceso
registrar_log "Backup completado con éxito"
enviar_notificacion "Backup Completado" "El proceso de backup se realizó correctamente"
