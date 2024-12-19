#!/bin/bash

# Глобальные константы
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="/tmp/${SCRIPT_NAME}.log"
readonly CONFIG_FILE="$HOME/.config/systemd/user/config.conf"
readonly BYEDPI_DIR="$HOME/ciadpi"
readonly TEMP_DIR=$(mktemp -d)
readonly setup_repo="https://github.com/fatyzzz/Byedpi-Setup/archive/refs/heads/dev.zip"
readonly branch="dev"

# Цвета для логирования
readonly COLOR_GREEN='\e[32m'
readonly COLOR_RED='\e[31m'
readonly COLOR_YELLOW='\e[33m'
readonly COLOR_RESET='\e[0m'

# Функция логирования с поддержкой цветов и файла
log() {
    local color=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    case $color in
        green) echo -e "${COLOR_GREEN}[INFO] $timestamp: $message${COLOR_RESET}" | tee -a "$LOG_FILE" ;;
        red)   echo -e "${COLOR_RED}[ERROR] $timestamp: $message${COLOR_RESET}" >&2 | tee -a "$LOG_FILE" ;;
        yellow)echo -e "${COLOR_YELLOW}[WARN] $timestamp: $message${COLOR_RESET}" | tee -a "$LOG_FILE" ;;
        *)     echo "[LOG] $timestamp: $message" | tee -a "$LOG_FILE" ;;
    esac
}


# Функция безопасного создания директории
safe_mkdir() {
    local dir_path=$1
    
    if [[ -d "$dir_path" ]]; then
        log yellow "Директория $dir_path уже существует. Очистка..."
        rm -rf "$dir_path"
    fi
    
    mkdir -p "$dir_path"
    log green "Создана директория: $dir_path"
}
safe_mkdir_no_rm() {
    local dir_path=$1
    
    if [[ -d "$dir_path" ]]; then
        log yellow "Директория $dir_path уже существует."
    else
        mkdir -p "$dir_path"
        log green "Создана директория: $dir_path"
    fi
}
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
    else
        log red "Не могу определить дистрибутив. Проверьте файл /etc/os-release."
        exit 1
    fi
}

# Установка пакетов для Arch Linux
install_arch() {
    local packages=("$@")
    log green "Обнаружен Arch Linux. Устанавливаю пакеты: ${packages[*]}"
    log yellow "Требуются права суперпользователя. Введите пароль root:"
    su -c "pacman -S --noconfirm ${packages[*]}"
}

# Установка пакетов для Debian
install_debian() {
    local packages=("$@")
    log green "Обнаружен Debian. Устанавливаю пакеты: ${packages[*]}"
    log yellow "Требуются права суперпользователя. Введите пароль root:"
    su -c "apt update && apt install -y ${packages[*]}" || {
        log red "Ошибка установки пакетов"
        exit 1
    }
    log green "Установка завершена."
}

# Установка пакетов для Ubuntu
install_ubuntu() {
    local packages=("$@")
    log green "Обнаружен Ubuntu. Устанавливаю пакеты: ${packages[*]}"
    su -c "apt update && apt install -y ${packages[*]}" || {
        log red "Ошибка установки пакетов"
        exit 1
    }
    log green "Установка завершена."
}

# Универсальная установка для других дистрибутивов
install_other() {
    local packages=("$@")
    log yellow "Ваш дистрибутив ($DISTRO) не поддерживается напрямую."
    
    if command -v zypper >/dev/null 2>&1; then
        su -c "zypper install -y ${packages[*]}"
    elif command -v dnf >/dev/null 2>&1; then
        su -c "dnf install -y ${packages[*]}"
    elif command -v yum >/dev/null 2>&1; then
        su -c "yum install -y ${packages[*]}"
    else
        log red "Не удалось найти менеджер пакетов. Установите вручную: ${packages[*]}"
        exit 1
    fi
}

# Проверка и установка зависимостей
check_dependencies() {
    detect_distro

    local dependencies=("gcc" "make" "unzip" "curl")
    local missing=()

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log yellow "Не найдены необходимые зависимости: ${missing[*]}"
        case "$DISTRO" in
            arch)
                install_arch "${missing[@]}"
                ;;
            debian)
                install_debian "${missing[@]}"
                ;;
            ubuntu)
                install_ubuntu "${missing[@]}"
                ;;
            *)
                install_other "${missing[@]}"
                ;;
        esac
    else
        log green "Все необходимые пакеты установлены."
    fi
}

# Функция безопасной загрузки с кэшированием
safe_download() {
    local url=$1
    local output=$2
    local cache_dir="/tmp/cache/byedpi"

    safe_mkdir "$cache_dir"

    local cache_file="$cache_dir/$(basename "$output")"

    if [[ -f "$cache_file" ]]; then
        log yellow "Используем кэшированную версию: $cache_file"
        cp "$cache_file" "$output"
    else
        log green "Загрузка: $url"
        if ! curl -L -o "$output" "$url"; then
            log red "Не удалось загрузить $url"
            return 1
        fi
        cp "$output" "$cache_file"
    fi
}

# Компиляция и установка ByeDPI
install_byedpi() {
    local repo_url="https://github.com/hufrea/byedpi/archive/refs/heads/main.zip"
    local zip_file="$TEMP_DIR/byedpi-main.zip"

    safe_download "$repo_url" "$zip_file"
    
    unzip -q "$zip_file" -d "$TEMP_DIR"
    cd "$TEMP_DIR/byedpi-main" || exit 1

    log yellow "Компиляция ByeDPI..."
    if make; then
        safe_mkdir "$BYEDPI_DIR"
        mv ciadpi "$BYEDPI_DIR/ciadpi-core"
        log green "ByeDPI успешно установлен в $BYEDPI_DIR"
    else
        log red "Ошибка компиляции ByeDPI"
        exit 1
    fi
}

# Загрузка и обработка списков
fetch_configuration_lists() {
    local setup_zip="$TEMP_DIR/Byedpi-Setup-$branch.zip"

    safe_download "$setup_repo" "$setup_zip"
    unzip -q "$setup_zip" -d "$TEMP_DIR"

    cd "$TEMP_DIR/Byedpi-Setup-$branch/assets" || exit 1

    bash link_get.sh

    # Отладка содержимого файлов
    log yellow "Проверка файла settings.txt:"
    if [[ -f settings.txt ]]; then
        log green "Файл settings.txt существует"
        log green "Количество настроек: $(wc -l < settings.txt)"
    else
        log red "Файл settings.txt не найден"
    fi

    log yellow "Проверка файла links.txt:"
    if [[ -f links.txt ]]; then
        log green "Файл links.txt существует"
        log green "Количество доменов: $(wc -l < links.txt)"
    else
        log red "Файл links.txt не найден"
    fi

    if [[ ! -f links.txt || ! -f settings.txt ]]; then
        log red "Не удалось создать конфигурационные файлы"
        exit 1
    fi
}

# Интерактивный выбор порта
select_port() {
    local port
    read -p "Введите порт для Byedpi (по умолчанию 14228): " port
    port=${port:-14228}

    if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1024 || "$port" -gt 65535 ]]; then
        log red "Некорректный порт. Используется порт по умолчанию: 14228"
        port=14228
    fi

    echo "$port"
}

select_port_test() {
    local port_test
    read -p "Введите порт для ТЕСТA! Byedpi (по умолчанию 10200): " port_test
    port_test=${port_test:-10200}  # Здесь заменили "port" на "port_test"

    if [[ ! "$port_test" =~ ^[0-9]+$ || "$port_test" -lt 1024 || "$port_test" -gt 65535 ]]; then
        log red "Некорректный порт. Используется порт по умолчанию: 10200"
        port_test=10200
    fi

    echo "$port_test"
}


# Обновление конфигурации systemd и службы
update_service() {
    local port=$1
    local setting=$2

    # Проверка параметров
    if [[ -z "$port" ]] || [[ -z "$setting" ]]; then
        log red "Ошибка: не указан порт или настройки"
        return 1
    fi

    # Создаем конфигурационный файл
    safe_mkdir_no_rm "$(dirname "$CONFIG_FILE")"
    echo "$setting" > "$CONFIG_FILE"
    # Создаем службу systemd
    cat > "$HOME/.config/byedpi.conf" <<EOF
SEL_PORT="$port"
SEL_SETTINGS="$setting"
EOF

    cat > "$HOME/.config/systemd/user/ciadpi.service" <<EOF
[Unit]
Description=ByeDPI Proxy Service
Documentation=https://github.com/fatyzzz/Byedpi-Setup
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
EnvironmentFile=-%h/.config/byedpi.conf
ExecStart=%h/ciadpi/ciadpi-core --ip 127.0.0.1 --port \$SEL_PORT \$SEL_SETTINGS
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOF

    # Перезагружаем конфигурацию systemd
    systemctl --user daemon-reload

    # Перезапускаем службу
    systemctl --user restart ciadpi || {
        log red "Ошибка запуска службы"
        return 1
    }
    systemctl --user enable ciadpi 2>/dev/null
    user_name=$(whoami)
    loginctl enable-linger $user_name
    log green "Служба добавлена в автозапуск"
    return 0
}

test_configurations() {
    local port_test=$1
    log green "=== Начало тестирования ==="
    log green "Используемый порт: $port_test"

    # Читаем настройки и домены в массивы сразу
    mapfile -t settings < <(grep -v '^[[:space:]]*$' settings.txt)
    mapfile -t links < <(grep -v '^[[:space:]]*$' links.txt)

    log yellow "Загружено настроек: ${#settings[@]}"
    log yellow "Загружено доменов: ${#links[@]}"

    # Останавливаем службу
    systemctl --user stop ciadpitest 2>/dev/null || true

    local -a results=()
    local max_parallel=${#links[@]}  # Увеличиваем количество параллельных проверок
    safe_mkdir_no_rm "$HOME/.config/systemd/user/"
    # Перебираем настройки
    local setting_number=1
    for setting in "${settings[@]}"; do
        [[ -z "$setting" ]] && continue
        
        log yellow "================================================"
        log yellow "Тестирование настройки [$setting_number/${#settings[@]}]"
        log green "Настройка: $setting"
        # Создаем службу
        cat > "$HOME/.config/byedpitest.conf" <<EOF
SEL_PORT="$port_test"
SEL_SETTINGS="$setting"
EOF
        cat > "$HOME/.config/systemd/user/ciadpitest.service" <<EOF
[Unit]
Description=ByeDPI Proxy Service
Documentation=https://github.com/fatyzzz/Byedpi-Setup
Wants=network-online.target
After=network-online.target nss-lookup.target

[Service]
EnvironmentFile=%h/.config/byedpitest.conf
ExecStart=%h/ciadpi/ciadpi-core --ip 127.0.0.1 --port \$SEL_PORT \$SEL_SETTINGS
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=default.target
EOF
        log green "Запускаем службу..."
        { systemctl --user daemon-reload && systemctl --user restart ciadpitest; } || {
            log red "Ошибка запуска службы для настройки $setting, пропускаем..."
            continue
        }
        

        log yellow "Ожидание запуска службы..."
        for i in {1..10}; do
            if systemctl --user is-active --quiet ciadpitest; then
            log green "Служба успешно запущена"
            break
            fi
            sleep 1
        done

        if ! systemctl --user is-active --quiet ciadpitest; then
            log red "Служба не запустилась для настройки $setting, пропускаем..."
            continue
        fi

        local success_count=0
        local total_count=0
        local failed_links=()
        local temp_dir=$(mktemp -d)
        local -a pids=()
        local -A domain_status=()  # Хэш для хранения статусов проверок
        sleep 3
        log green "Начинаем параллельную проверку доменов..."
        
        # Запускаем проверку каждого домена в фоновом режиме
        local domain_number=1
        for link in "${links[@]}"; do
            [[ -z "$link" ]] && continue
            local https_link="https://$link"

            (
                local http_code
                http_code=$(curl -x socks5h://127.0.0.1:"$port_test" \
                            -o /dev/null -s -w "%{http_code}" "$https_link" \
                            --connect-timeout 2 --max-time 3) || http_code="000"

                if [[ "$http_code" == "200" || "$http_code" == "404" || "$http_code" == "400" || "$http_code" == "405" || "$http_code" == "403" || "$http_code" == "302" || "$http_code" == "301" ]]; then
                    log green "  ✓ OK ($https_link: $http_code)"
                    echo "success" > "$temp_dir/result_$domain_number"
                else
                    log red "  ✗ FAILED ($https_link: $http_code)"
                    echo "failure#$https_link#$http_code" > "$temp_dir/result_$domain_number"
                fi
            ) &
            pids+=($!)

            ((domain_number++))
            
            # Ограничиваем количество параллельных проверок
            if ((${#pids[@]} >= max_parallel)); then
                wait "${pids[0]}" 2>/dev/null || true
                pids=("${pids[@]:1}")
            fi
        done

        # Ожидаем завершения всех проверок
        wait "${pids[@]}" 2>/dev/null || true

        # Подсчитываем результаты через один проход по файлам
        local result success_status link code
        while IFS=: read -r result domain_num link code; do
            ((total_count++))
            if [[ "$result" == "success" ]]; then
                ((success_count++))
            else
                failed_links+=("$link (код: $code)")
            fi
        done < <(cat "$temp_dir"/result_* 2>/dev/null)

        # Очищаем временные файлы
        rm -rf "$temp_dir"

        log yellow "Останавливаем службу..."
        systemctl --user stop ciadpitest 2>/dev/null || true

        local success_rate=0
        if [[ $total_count -gt 0 ]]; then
            success_rate=$((success_count * 100 / total_count))
        fi
        
        log yellow "Удаляем тестовую функцию"
        rm $HOME/.config/systemd/user/ciadpitest.service
        rm $HOME/.config/byedpitest.conf

        results+=("$setting#$success_rate#$success_count#$total_count#${#failed_links[@]}")

        log green "Результаты для настройки [$setting_number/${#settings[@]}]:"
        log green "- Успешно: $success_count из $total_count ($success_rate%)"
        log yellow "- Неудачно: ${#failed_links[@]}"
        
        log yellow "================================================"
        echo
        ((setting_number++))
    done

    # Быстрый вывод результатов
    printf "RESULTS_START\n%s\nRESULTS_END\n" "$(printf '%s\n' "${results[@]}")"
}

# Основная функция
main() {
    echo -e "\e[32m"
    cat << "EOF"
⠀⣀⣀⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣀⣀⠀⠀
⢾⣿⣿⣿⣿⣶⣤⡀⠀⠀⠀⠀⠀⠀⠀⠀⠄⠀⣀⣴⣶⣿⣿⣿⣿⡇⠀
⠈⢿⣿⣿⣿⡛⠛⠈⠳⣄⠂⠀⠀⠀⠀⠀⣠⠞⠉⠛⢻⣿⣿⣿⡟⠀⠀
⠀⠸⣿⣿⣿⠥⠀⠀⠀⠈⢢⠀⠀⠀⠀⡜⠁⠀⠀⠀⢸⣿⣿⣿⠁⠀⠀
⠀⠀⣿⣿⣯⠭⠤⠀⠀⠀⠀⠃⣰⡄⠌⠀⠀⠀⠀⠨⢭⣿⣿⣿⠀⠀⠀
⠀⠀⠹⢿⣿⣈⣀⣀⠀⠀⠠⢴⣿⣿⡦⠀⠀⠀⣀⣈⣱⣿⠿⠃⠀⠀⠀
⠀⠀⠀⢠⣾⣿⡟⠁⠀⠀⠀⠀⣿⣏⠀⠀⠀⠀⠘⣻⣿⣶⠀⠀⠀⠀⠀
⠀⠀⠀⢸⣿⣿⢂⠀⠀⠀⠀⠘⢸⡇⠆⠀⠀⠀⢀⠰⣿⣿⠀⠀⠀⠀⠀
⠀⠀⠀⠈⣿⣷⣿⣆⡀⠀⠀⠁⠈⠀⠠⠀⠀⢀⣶⣿⣿⠏⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠘⣿⣿⣿⣷⣴⡜⠀⠀⠀⠀⣦⣤⣾⣿⣿⡏⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⢀⡿⠛⠿⠿⠿⠛⠁⠀⠀⠀⠀⠘⠿⠿⠿⠿⢧⠀⠀⠀⠀⠀
⠀⠀⠀⠀⣾⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⣧⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⠀⠀⠀⠀⠀
EOF
    # Добавление текста
    echo -e "\e[36m"
    echo "Byedpi-Setup"
    echo "github.com/fatyzzz/Byedpi-Setup"
    echo -e "\e[0m"
    sleep 2
    check_dependencies
    
    trap ' 
    log red "Скрипт прерван"; 
    read -p "Вы хотите отключить службу ciadpi? (y/n): " choice
    if [[ $choice =~ ^[Yy]$ ]]; then
        log yellow "Отключение службы ciadpi..."
        systemctl --user stop ciadpi 2>/dev/null || log red "Не удалось остановить службу."
    else
        log green "Служба оставлена включенной."
    fi
    exit 1
    ' SIGINT SIGTERM ERR

    local port
    local selector
    local port_test

    echo
    log green "Выберите действие:"
    echo
    log yellow "1 - Установка ByeDPI"
    log yellow "2 - Только тестирование конфигурации"
    log yellow "3 - Поменять порт у службы: "
    read selector

    case "$selector" in
        "1")
            if [[ -f $HOME/.config/systemd/user/ciadpi.service ]]; then
                log yellow "Служба ciadpi уже запущена."
                port_test=$(select_port_test)
                port=$(grep -oP '(?<=SEL_PORT=")\d+(?=")' "$HOME/.config/byedpi.conf")
            else
                port=$(select_port)
                port_test=$port
            fi
            ;;
        "2")
            port_test=$(select_port_test)
            ;;
        "3")
            # Проверяем существование службы
            if [[ ! -f $HOME/.config/systemd/user/ciadpi.service ]]; then
                log red "Служба ciadpi не найдена. Пожалуйста, выберите другое действие."
                exit 1
            fi

            stop_service() {
                systemctl --user stop ciadpi 2>/dev/null || true
            }

            update_service_port() {
                local new_port=$1

                # Выключаем службу
                stop_service

                # Обновляем порты в файле службы
                sed -i "s/--port [0-9]*/--port $new_port/" "$HOME/.config/systemd/user/ciadpi.service"

                # Включаем службу с обновленными настройками
                systemctl --user start ciadpi
            }

            # Запросить новый порт от пользователя
            new_port=$(select_port) # Здесь используем функцию выбора порта из предыдущего шага

            # Обновляем порт в службе
            update_service_port "$new_port"

            log green "Служба ciadpi успешно обновлена с новым портом: $new_port"
            exit 0
            ;;
        *)
            log red "Некорректный выбор действия"
            exit 1
            ;;
    esac
    log green "Начало установки ByeDPI"
    safe_mkdir "$TEMP_DIR"
    install_byedpi
    fetch_configuration_lists
    
    # Создаем временный файл для результатов
    local results_file=$(mktemp)
    
    # Запускаем тестирование и записываем результаты во временный файл,
    # при этом отображая все логи в реальном времени
    test_configurations "$port_test" | tee "$results_file"
    
    local -a test_results
    local capture=0
    while IFS= read -r line; do
        if [[ "$line" == "RESULTS_START" ]]; then
            capture=1
            continue
        elif [[ "$line" == "RESULTS_END" ]]; then
            break
        elif [[ $capture -eq 1 ]]; then
            test_results+=("$line")
        fi
    done < "$results_file"

    # Удаляем временный файл
    rm -f "$results_file"

    if [[ ${#test_results[@]} -eq 0 ]]; then
        log red "Не найдено рабочих конфигураций"
        exit 1
    fi

    # Сортируем результаты по проценту успеха и длине настройки
    log yellow "Топ 10 конфигураций:"
    local -a sorted_results=()
    for result in "${test_results[@]}"; do
        IFS='#' read -r setting success_rate success_count total_count failed_count <<< "$result"
        # Добавляем длину настройки как дополнительный критерий сортировки
        sorted_results+=("$success_rate:${#setting}:$result")
    done

    # Сортируем по проценту успеха (по убыванию) и длине настройки (по возрастанию)
    local -a filtered_results=()
    while IFS=: read -r _ _ setting success_rate success_count total_count failed_count; do
        filtered_results+=("$setting#$success_rate#$success_count#$total_count#$failed_count")
    done < <(printf '%s\n' "${sorted_results[@]}" | sort -t: -k1,1nr -k2,2n | head -n 10)

    # Выводим отсортированные результаты
    for i in "${!filtered_results[@]}"; do
        IFS='#' read -r setting success_rate success_count total_count failed_count <<< "${filtered_results[i]}"
        
        # Определяем цвет в зависимости от процента успеха
        if ((success_rate >= 80)); then
            color="${COLOR_GREEN}"
        elif ((success_rate >= 50)); then
            color="${COLOR_YELLOW}"
        else
            color="${COLOR_RED}"
        fi
        
        echo -e "$i) ${color}$setting (Успех: $success_rate%, $success_count/$total_count, Неуспешно: $failed_count)${COLOR_RESET}"
    done

    if [[ "$selector" == "1" ]]; then
        read -p "Выберите номер конфигурации: " selected_index
        if [[ ! "$selected_index" =~ ^[0-9]+$ || "$selected_index" -ge "${#filtered_results[@]}" ]]; then
            log red "Некорректный выбор"
            exit 1
        fi

        IFS='#' read -r selected_setting _ _ _ _ <<< "${filtered_results[selected_index]}"    
        update_service "$port" "$selected_setting"
        log green "Установка ByeDPI завершена. Служба ciadpi запущена от пользователя с настройкой: $selected_setting "
        log yellow "Информация для подключения Socks5 прокси"
        log yellow "Айпи: 127.0.0.1"
        log yellow "Порт: $port"
    else
        log green "t.me/fatyzzz"
    fi

    # Очистка временных файлов
    rm -rf "$TEMP_DIR"
}

# Запуск основной функции
main
