#!/bin/bash

# Funzioni per colorare il testo
yellow() {
  echo -e "\033[33m$1\033[0m"
}

red() {
  echo -e "\033[31m$1\033[0m"
}

# Funzione per cancellare log più vecchi di X giorni
cleanup_logs() {
  local retention_days="$1"
  find . -name "redis_monitor-*.log" -type f -mtime "+$retention_days" -exec rm -f {} \;
}

# Funzione per inviare notifiche via email
send_email() {
  local subject="$1"
  local message="$2"
  if [ -z "$EMAIL_RECIPIENTS" ]; then
    return
  fi

  {
    echo "$message" | mail -s "$nomemacchina $subject" "$EMAIL_RECIPIENTS"
  } || {
    red "Errore durante l'invio dell'email: $subject"
  }
}

# Funzione per inviare notifiche a Discord
send_discord() {
  local message="$1"
  if [ -z "$DISCORD_WEBHOOK_URL" ]; then
    return
  fi

  {
    curl -H "Content-Type: application/json" -X POST -d "{\"content\": \"$message\"}" "$DISCORD_WEBHOOK_URL"
  } || {
    red "Errore durante l'invio della notifica a Discord: $message"
  }
}

# Stampa intestazione con ASCII art e nome
echo "
  _____  ______ _____ _____  _____   __  __  ____  _   _ _____ _______ ____  _____
 |  __ \|  ____|  __ \_   _|/ ____| |  \/  |/ __ \| \ | |_   _|__   __/ __ \|  __ \
 | |__) | |__  | |  | || | | (___   | \  / | |  | |  \| | | |    | | | |  | | |__) |
 |  _  /|  __| | |  | || |  \___ \  | |\/| | |  | | .   | | |    | | | |  | |  _  /
 | | \ \| |____| |__| || |_ ____) | | |  | | |__| | |\  |_| |_   | | | |__| | | \ \
 |_|  \_\______|_____/_____|_____/  |_|  |_|\____/|_| \_|_____|  |_|  \____/|_|  \_\
"
echo "di Lorenzo Padovani"
echo


_now=$(date +%Y-%m-%d.%H.%M.%S)
yellow "starts at $_now"

# Configurazione di default (verrà usata questa se non è presente un file di configurazione)
DATA=`/bin/date +"%a"`
REDIS_CONF="/etc/redis/redis.conf"
MAX_MEMORY_THRESHOLD_PERCENT=85 # Soglia di utilizzo della memoria in percentuale
EMAIL_RECIPIENTS="email1@example.com,email2@example.com"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
LOG_RETENTION_DAYS=7 # Giorni di retention dei log


#
# Load config file if exists
#
CONFIG_DIR=$( dirname "$(readlink -f "$0")" )
CONFIG_FILE="$CONFIG_DIR/redismonitor.config"

if [[ -f $CONFIG_FILE ]]; then
   echo "Loading settings from $CONFIG_FILE."
   source $CONFIG_FILE
else
   echo "Could not load settings from $CONFIG_FILE (file does not exist), script use default settings."
fi



# Scrivo la configurazione finale che verrà usata a console
echo "Configurazione:"
echo "REDIS_CONF=$REDIS_CONF"
echo "MAX_MEMORY_THRESHOLD_PERCENT=$MAX_MEMORY_THRESHOLD_PERCENT"
echo "EMAIL_RECIPIENTS=$EMAIL_RECIPIENTS"
echo "DISCORD_WEBHOOK_URL=$DISCORD_WEBHOOK_URL"
echo "LOG_RETENTION_DAYS=$LOG_RETENTION_DAYS"


# Controlla se la policy di evizione è attiva
if grep -q '^maxmemory-policy' "$REDIS_CONF"; then
  echo "Eviction policy attiva."
else
  red "Eviction policy non configurata in $REDIS_CONF"
  MESSAGE="Eviction policy non configurata in $REDIS_CONF"
  send_email "Redis Alert: Eviction Policy" "$MESSAGE"
  send_discord "$MESSAGE"
fi

# Controlla se Redis risponde al ping
if redis-cli ping | grep -q PONG; then
  red "Redis risponde al ping."
else
  echo "Redis non risponde al ping."
  MESSAGE="Redis non risponde al ping"
  send_email "Redis Alert: Ping Failed" "$MESSAGE"
  send_discord "$MESSAGE"
  exit 1
fi

nome_macchina=$(hostname)

# Ottieni la maxmemory configurata in Redis
MAX_MEMORY_CONF=$(redis-cli config get maxmemory | grep -v maxmemory)
MAX_MEMORY_CONF_MB=$((MAX_MEMORY_CONF / 1024 / 1024))

# Ottieni la memoria totale del sistema in MB
TOTAL_MEMORY=$(free -m | awk '/^Mem:/{print $2}')

# Ottieni la memoria totale usata da Redis in MB
# USED_MEMORY=$(redis-cli info memory | grep used_memory: | awk -F':' '{print $2}')
USED_MEMORY=$(redis-cli info memory | grep used_memory: | awk -F':' '{print $2}' | tr -d '[:space:]')
divisore=$((1024 * 1024))
#echo $USED_MEMORY

USED_MEMORY_MB=$(expr $USED_MEMORY / $divisore)

# Calcola la percentuale di memoria usata da Redis rispetto alla memoria totale del sistema
USED_MEMORY_PERCENT_TOTAL=$((100 * USED_MEMORY_MB / TOTAL_MEMORY))

# Calcola la percentuale di memoria usata da Redis rispetto alla memoria massima configurata in Redis
USED_MEMORY_PERCENT_CONF=$((100 * USED_MEMORY_MB / MAX_MEMORY_CONF_MB))

# Stampa i valori di USED_MEMORY_MB, USED_MEMORY_PERCENT_TOTAL e USED_MEMORY_PERCENT_CONF
echo "Memoria usata da Redis: $USED_MEMORY_MB MB"
echo "Percentuale di memoria usata da Redis rispetto alla memoria totale del sistema: $USED_MEMORY_PERCENT_TOTAL%"
echo "Percentuale di memoria usata da Redis rispetto alla memoria massima configurata: $USED_MEMORY_PERCENT_CONF%"

# Controlla se la memoria usata supera la soglia percentuale rispetto alla memoria totale del sistema
if [ "$USED_MEMORY_PERCENT_TOTAL" -gt "$MAX_MEMORY_THRESHOLD_PERCENT" ]; then
  red "Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_TOTAL%) rispetto alla memoria totale del sistema, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  MESSAGE="Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_TOTAL%) rispetto alla memoria totale del sistema, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  send_email "Redis Alert: Memory Usage (Total System)" "$MESSAGE"
  send_discord "$MESSAGE"
else
  echo "La memoria usata da Redis ($USED_MEMORY_MB MB, $USED_MEMORY_PERCENT_TOTAL%) non supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT% rispetto alla memoria totale del sistema"
fi

# Controlla se la memoria usata supera la soglia percentuale rispetto alla memoria massima configurata in Redis
if [ "$USED_MEMORY_PERCENT_CONF" -gt "$MAX_MEMORY_THRESHOLD_PERCENT" ]; then
  red "Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_CONF%) rispetto alla memoria massima configurata, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  MESSAGE="**$nome_macchina**: Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_CONF%) rispetto alla memoria massima configurata, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  send_email "Redis Alert $nome_macchina: Memory Usage (Configured Max)" "$MESSAGE"
  send_discord "$MESSAGE"
else
  echo "La memoria usata da Redis ($USED_MEMORY_MB MB, $USED_MEMORY_PERCENT_CONF%) non supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT% rispetto alla memoria massima configurata"
fi

# Pulizia log più vecchi di LOG_RETENTION_DAYS
echo "Pulizia log più vecchi di $LOG_RETENTION_DAYS giorni"
cleanup_logs "$LOG_RETENTION_DAYS"

_now=$(date +%Y-%m-%d.%H.%M.%S)
yellow "Finish at $_now"
