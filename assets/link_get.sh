#!/bin/bash

# Функция для получения нового домена
get_cluster_codename() {
    local urls=(
        "https://redirector.gvt1.com/report_mapping?di=no"
        "https://redirector.xn--ngstr-lra8j.com/report_mapping?di=no"
    )
    
    local letters_list_a=('u' 'z' 'p' 'k' 'f' 'a' '5' '0' 'v' 'q' 'l' 'g' 'b' '6' '1' 'w' 'r' 'm' 'h' 'c' '7' '2' 'x' 's' 'n' 'i' 'd' '8' '3' 'y' 't' 'o' 'j' 'e' '9' '4' '-')
    local letters_list_b=('0' '1' '2' '3' '4' '5' '6' '7' '8' '9' 'a' 'b' 'c' 'd' 'e' 'f' 'g' 'h' 'i' 'j' 'k' 'l' 'm' 'n' 'o' 'p' 'q' 'r' 's' 't' 'u' 'v' 'w' 'x' 'y' 'z' '-')
    declare -A letters_map

    for i in "${!letters_list_a[@]}"; do
        letters_map["${letters_list_a[$i]}"]="${letters_list_b[$i]}"
    done

    for url in "${urls[@]}"; do
        response=$(curl -s --max-time 2 "$url")
        if [[ $? -eq 0 ]]; then
            cluster_codename=$(echo "$response" | grep -oP '=>\s*\K(\S+)(?=\s*(?:\(|:))' | tr -d '.: ')
            if [[ -n "$cluster_codename" ]]; then
                converted_name=""
                for (( i=0; i<${#cluster_codename}; i++ )); do
                    char="${cluster_codename:$i:1}"
                    converted_name+="${letters_map[$char]}"
                done
                domain="rr1---sn-${converted_name}.googlevideo.com"
                echo "$domain"
                return
            fi
        fi
    done

    echo ""
}

# Чтение предопределенного списка доменов из файла
predefined_domains=()
while IFS= read -r line; do
    predefined_domains+=("$line")
done < domains.txt

# Получаем новый домен
new_domain=$(get_cluster_codename)

# Если новый домен получен, добавляем его к списку
if [[ -n "$new_domain" && ! " ${predefined_domains[*]} " =~ " ${new_domain} " ]]; then
    predefined_domains+=("$new_domain")
fi

# Сохраняем все домены в файл
{
    for domain in "${predefined_domains[@]}"; do
        echo "$domain"
    done
} > links.txt

#echo "Сохранено доменов: ${#predefined_domains[@]}"
#echo "Новый домен: ${new_domain:-Не удалось получить}"
