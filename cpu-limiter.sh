#!/bin/bash

STATE_FILE="/tmp/cpu_limit_state"
BACKUP_DIR="/tmp/cpu_limit_backup"
CPU_PATH="/sys/devices/system/cpu"

# Функция для сохранения текущих настроек (если еще не сохранены)
backup_params() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "== Сохранение текущих настроек процессора =="
        mkdir -p "$BACKUP_DIR"
        for cpu in $CPU_PATH/cpu[0-9]*; do
            cpu_name=$(basename "$cpu")
            if [ -d "$cpu/cpufreq" ]; then
                [ -f "$cpu/cpufreq/scaling_governor" ] && cat "$cpu/cpufreq/scaling_governor" > "$BACKUP_DIR/${cpu_name}_gov"
                [ -f "$cpu/cpufreq/scaling_max_freq" ] && cat "$cpu/cpufreq/scaling_max_freq" > "$BACKUP_DIR/${cpu_name}_max"
            fi
        done
        echo "enabled" > "$STATE_FILE"
    fi
}

# Список доступных частот
list_freqs() {
    if [ -f "$CPU_PATH/cpu0/cpufreq/scaling_available_frequencies" ]; then
        echo "Доступные частоты (kHz):"
        cat "$CPU_PATH/cpu0/cpufreq/scaling_available_frequencies"
    else
        echo "Доступный диапазон частот (kHz):"
        MIN=$(cat "$CPU_PATH/cpu0/cpufreq/cpuinfo_min_freq" 2>/dev/null)
        MAX=$(cat "$CPU_PATH/cpu0/cpufreq/cpuinfo_max_freq" 2>/dev/null)
        echo "Мин: $MIN | Макс: $MAX"
    fi
}

# Установка частоты
set_freq() {
    local freq=$1
    [ -z "$freq" ] && { echo "Ошибка: частота не указана"; list_freqs; return 1; }
    backup_params
    echo "== Установка макс. частоты: $freq kHz =="
    for cpu in $CPU_PATH/cpu[0-9]*; do
        [ -d "$cpu/cpufreq" ] || continue
        echo "$freq" | sudo tee "$cpu/cpufreq/scaling_max_freq" > /dev/null
        echo powersave | sudo tee "$cpu/cpufreq/scaling_governor" > /dev/null
    done
}

# Управление ядрами
set_cores() {
    local count=$1
    [ -z "$count" ] && { echo "Ошибка: количество ядер не указано"; return 1; }
    backup_params
    echo "== Активация ядер: $count =="
    
    # Ядро 0 всегда включено
    echo 1 | sudo tee "$CPU_PATH/cpu0/online" > /dev/null 2>&1
    
    local i=1
    while [ -d "$CPU_PATH/cpu$i" ]; do
        if [ $i -lt $count ]; then
            echo 1 | sudo tee "$CPU_PATH/cpu$i/online" > /dev/null
        else
            echo 0 | sudo tee "$CPU_PATH/cpu$i/online" > /dev/null
        fi
        i=$((i+1))
    done
}

enable_limit() {
    local freq=$1
    local cores=$2
    
    # Если параметры не заданы, берем минимум
    [ -z "$freq" ] && freq=$(cat "$CPU_PATH/cpu0/cpufreq/cpuinfo_min_freq")
    [ -z "$cores" ] && cores=1
    
    echo "== Включение лимитера (Частота: $freq, Ядер: $cores) =="
    set_freq "$freq"
    set_cores "$cores"

    # Отключение Turbo Boost
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
    fi
}

disable_limit() {
    echo "== Восстановление исходных настроек =="

    # Восстановление режима и частоты
    for file in "$BACKUP_DIR"/*_gov; do
        [ -f "$file" ] || continue
        cpu_name=$(basename "$file" _gov)
        cat "$file" | sudo tee "$CPU_PATH/$cpu_name/cpufreq/scaling_governor" > /dev/null
    done

    for file in "$BACKUP_DIR"/*_max; do
        [ -f "$file" ] || continue
        cpu_name=$(basename "$file" _max)
        cat "$file" | sudo tee "$CPU_PATH/$cpu_name/cpufreq/scaling_max_freq" > /dev/null
    done

    # Включение всех ядер
    local i=1
    while [ -d "$CPU_PATH/cpu$i" ]; do
        echo 1 | sudo tee "$CPU_PATH/cpu$i/online" > /dev/null
        i=$((i+1))
    done

    # Включение Turbo Boost
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        echo 0 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo > /dev/null
    fi

    rm -f "$STATE_FILE"
    rm -rf "$BACKUP_DIR"
    echo "== Настройки восстановлены =="
}

status() {
    if [ -f "$STATE_FILE" ]; then
        echo "Статус: ЛИМИТЕР АКТИВЕН"
    else
        echo "Статус: ЛИМИТЕР ВЫКЛЮЧЕН"
    fi
    
    local total_cores=$(ls -d $CPU_PATH/cpu[0-9]* | wc -l)
    local active_cores=0
    for ((i=0; i<total_cores; i++)); do
        if [ ! -f "$CPU_PATH/cpu$i/online" ] || [ "$(cat $CPU_PATH/cpu$i/online)" == "1" ]; then
            active_cores=$((active_cores+1))
        fi
    done

    echo "--- Текущее состояние ---"
    echo "Активных ядер: $active_cores из $total_cores"
    echo "Текущий режим (cpu0): $(cat $CPU_PATH/cpu0/cpufreq/scaling_governor 2>/dev/null)"
    echo "Макс. частота (cpu0): $(cat $CPU_PATH/cpu0/cpufreq/scaling_max_freq 2>/dev/null) kHz"
    
    if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
        [ "$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)" == "1" ] && echo "Turbo Boost: ВЫКЛЮЧЕН" || echo "Turbo Boost: ВКЛЮЧЕН"
    fi
}

case "$1" in
    on)
        enable_limit "$2" "$3"
        ;;
    off)
        disable_limit
        ;;
    status)
        status
        ;;
    freqs)
        list_freqs
        ;;
    set-freq)
        set_freq "$2"
        ;;
    set-cores)
        set_cores "$2"
        ;;
    *)
        echo "Использование: $0 {on [частота] [ядра]|off|status|freqs|set-freq <значение>|set-cores <кол-во>}"
        echo "Пример: $0 on 800000 2 (частота 800MHz, 2 ядра)"
        ;;
esac
