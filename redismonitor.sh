#!/bin/bash

# Funzione per gestire i semafori
# Questa funzione controlla se è possibile inviare ulteriori avvisi
# in base al numero massimo di avvisi e al tempo di blocco
# Se il tempo trascorso dall'ultimo avviso è maggiore del tempo di blocco,
# il contatore viene reimpostato e l'avviso viene inviato
# Se il numero di avvisi è inferiore al massimo, il contatore viene incrementato
# e l'avviso viene inviato
# Se il numero di avvisi ha raggiunto il massimo, l'avviso non viene inviato
# e il contatore non viene incrementato
# La funzione restituisce 0 se è possibile inviare ulteriori avvisi, altrimenti 1
check_semaphore() {
  local semaphore_file="$1"
  local max_alerts="$2"
  local block_minutes="$3"
  local current_time=$(date +%s)

  # Se il file del semaforo non esiste verrà creato
  if [ ! -f "$semaphore_file" ]; then
    echo "0 $current_time" > "$semaphore_file"
  fi

  local alert_count=$(awk '{print $1}' "$semaphore_file")
  local last_alert_time=$(awk '{print $2}' "$semaphore_file")

  # Calcola la differenza in minuti dall'ultimo avviso
  local time_diff=$(( (current_time - last_alert_time) / 60 ))

  # Se il tempo trascorso è maggiore del tempo di blocco, reimposta il contatore
  if [ "$time_diff" -ge "$block_minutes" ]; then
    echo "0 $current_time" > "$semaphore_file"
    alert_count=0
    time_diff=0
  fi

  # Se il numero di avvisi è inferiore al massimo, incremento il contatore e aggiorno il timestamp
  if [ "$alert_count" -lt "$max_alerts" ]; then
    echo "$((alert_count + 1)) $current_time" > "$semaphore_file"
    return 0
  fi

  # Se il numero di avvisi ha raggiunto il massimo, si da il segnale di bloccare l'invio di ulteriori avvisi
  return 1
}

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
echo
echo "
  _   _  _  ___  __         _       ___ ___ _   _
 |_) |_ | \  |  (_    |\/| / \ |\ |  |   | / \ |_)
 | \ |_ |_/ _|_ __)   |  | \_/ | \| _|_  | \_/ | |
"
echo
echo " di Lorenzo Padovani"
echo
echo


_now=$(date +%Y-%m-%d.%H.%M.%S)
yellow "starts at $_now"
echo

# Configurazione di default (verrà usata questa se non è presente un file di configurazione)
DATA=`/bin/date +"%a"`
REDIS_CONF="/etc/redis/redis.conf"
MAX_MEMORY_THRESHOLD_PERCENT=85 # Soglia di utilizzo della memoria in percentuale
EMAIL_RECIPIENTS="email1@example.com,email2@example.com"
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
LOG_RETENTION_DAYS=7 # Giorni di retention dei log
# semaphore
ALERT_BLOCK_MINUTES=30 # Minuti di blocco per gli avvisi dopo aver raggiunto il limite
MAX_ALERTS=5 # Numero massimo di avvisi prima di attivare il blocco
SEMAPHORE_EVICTION="/tmp/redismonitor_semaphore_eviction"
SEMAPHORE_PING="/tmp/redismonitor_semaphore_ping"
SEMAPHORE_MEMORY_SYS="/tmp/redismonitor_semaphore_memory_sys"
SEMAPHORE_MEMORY="/tmp/redismonitor_semaphore_memory"
SEMAPHORE_COMPRESSION="/tmp/redismonitor_semaphore_compression"
#redis check compression command
REDIS_ALERT_BLOCK_MINUTES=300 # Minuti di blocco per gli avvisi dopo aver raggiunto il limite
REDIS_CHECK_COMPRESSION_COMMAND="php -r 'phpinfo(INFO_MODULES);' | grep -A 10 -i redis | grep 'Available compression'"

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
echo


# Scrivo la configurazione finale che verrà usata a console
echo "Configurazione:"
echo "REDIS_CONF=$REDIS_CONF"
echo "MAX_MEMORY_THRESHOLD_PERCENT=$MAX_MEMORY_THRESHOLD_PERCENT"
echo "EMAIL_RECIPIENTS=$EMAIL_RECIPIENTS"
echo "DISCORD_WEBHOOK_URL=$DISCORD_WEBHOOK_URL"
echo "LOG_RETENTION_DAYS=$LOG_RETENTION_DAYS"
echo "ALERT_BLOCK_MINUTES=$ALERT_BLOCK_MINUTES"
echo "MAX_ALERTS=$MAX_ALERTS"
echo "REDIS_CHECK_COMPRESSION_COMMAND=$REDIS_CHECK_COMPRESSION_COMMAND"
echo

# Ottieni il nome della macchina vm
nome_macchina=$(hostname)
echo "Nome macchina: $nome_macchina"
echo

# Controlla se la policy di evizione è attiva
if grep -q '^maxmemory-policy' "$REDIS_CONF"; then
  echo "Eviction policy attiva."
else
  red "Eviction policy non configurata in $REDIS_CONF"
  MESSAGE="**$nome_macchina**: Eviction policy non configurata in $REDIS_CONF"
  if check_semaphore "$SEMAPHORE_EVICTION" "$MAX_ALERTS" "$ALERT_BLOCK_MINUTES"; then
    send_email "Redis Alert: Eviction Policy" "$MESSAGE"
    send_discord "$MESSAGE"
  else
    yellow "è stato raggiunto il limite di avvisi quindi non verrà inviato un ulteriore avviso"
  fi
fi
echo

# Controlla se Redis risponde al ping
if redis-cli ping | grep -q PONG; then
  echo "Redis risponde al ping."
else
  red "Redis non risponde al ping."
  MESSAGE="**$nome_macchina**: Redis non risponde al ping"
  if check_semaphore "$SEMAPHORE_PING" "$MAX_ALERTS" "$ALERT_BLOCK_MINUTES"; then
    send_email "Redis Alert: Ping Failed" "$MESSAGE"
    send_discord "$MESSAGE"
  else
    yellow "è stato raggiunto il limite di avvisi quindi non verrà inviato un ulteriore avviso"
  fi
  exit 1
fi
echo

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
echo

# Controlla se la memoria usata supera la soglia percentuale rispetto alla memoria totale del sistema
if [ "$USED_MEMORY_PERCENT_TOTAL" -gt "$MAX_MEMORY_THRESHOLD_PERCENT" ]; then
  red "Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_TOTAL%) rispetto alla memoria totale del sistema, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  MESSAGE="**$nome_macchina**: Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_TOTAL%) rispetto alla memoria totale del sistema, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  if check_semaphore "$SEMAPHORE_MEMORY_SYS" "$MAX_ALERTS" "$ALERT_BLOCK_MINUTES"; then
    send_email "Redis Alert: Memory Usage (Total System)" "$MESSAGE"
    send_discord "$MESSAGE"
  else
    yellow "è stato raggiunto il limite di avvisi quindi non verrà inviato un ulteriore avviso"
  fi
else
  echo "La memoria usata da Redis ($USED_MEMORY_MB MB, $USED_MEMORY_PERCENT_TOTAL%) non supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT% rispetto alla memoria totale del sistema"
fi
echo

# Controlla se la memoria usata supera la soglia percentuale rispetto alla memoria massima configurata in Redis
if [ "$USED_MEMORY_PERCENT_CONF" -gt "$MAX_MEMORY_THRESHOLD_PERCENT" ]; then
  red "Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_CONF%) rispetto alla memoria massima configurata, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  MESSAGE="**$nome_macchina**: Redis sta usando $USED_MEMORY_MB MB di memoria ($USED_MEMORY_PERCENT_CONF%) rispetto alla memoria massima configurata, che supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT%"
  if check_semaphore "$SEMAPHORE_MEMORY" "$MAX_ALERTS" "$ALERT_BLOCK_MINUTES"; then
    send_email "Redis Alert $nome_macchina: Memory Usage (Configured Max)" "$MESSAGE"
    send_discord "$MESSAGE"
  else
    yellow "è stato raggiunto il limite di avvisi quindi non verrà inviato un ulteriore avviso"
  fi
else
  echo "La memoria usata da Redis ($USED_MEMORY_MB MB, $USED_MEMORY_PERCENT_CONF%) non supera la soglia di $MAX_MEMORY_THRESHOLD_PERCENT% rispetto alla memoria massima configurata"
fi
echo

# Verifica se phpredis è installato con la compressione abilitata
# Controlla le informazioni dell'estensione redis
redis_info=$(REDIS_CHECK_COMPRESSION_COMMAND)
if echo "$redis_info"; then
    echo "La compressione è abilitata in phpredis."
else
    red "La compressione non è abilitata in phpredis."
    MESSAGE="**$nome_macchina**: La compressione non è abilitata in phpredis."
    if check_semaphore "$SEMAPHORE_MEMORY" "$MAX_ALERTS" "$REDIS_ALERT_BLOCK_MINUTES"; then
      send_email "Redis Alert $nome_macchina: Compressione Redis NON abilitata" "$MESSAGE"
      send_discord "$MESSAGE"
    else
      yellow "è stato raggiunto il limite di avvisi quindi non verrà inviato un ulteriore avviso"
    fi
fi
echo

# Pulizia log più vecchi di LOG_RETENTION_DAYS
echo "Pulizia log più vecchi di $LOG_RETENTION_DAYS giorni"
cleanup_logs "$LOG_RETENTION_DAYS"
echo

_now=$(date +%Y-%m-%d.%H.%M.%S)
yellow "Finish at $_now"
