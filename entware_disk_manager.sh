#!/opt/bin/bash

# =====================================================
# ENTWARE MANAGER 
# Универсальный менеджер разделов и Entware!
# =====================================================


# ==========================
# Проверка и установка пакетов
# ==========================
install_if_missing() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Утилита $1 не найдена. Устанавливаем..."
        opkg update
        opkg install "$1"
    fi
}

install_if_missing parted
install_if_missing tune2fs


# ==========================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ==========================
pause() {
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

select_disk() {
    clear
    echo "=== СПИСОК ПОДКЛЮЧЕННЫХ ДИСКОВ ==="
    echo ""
        USB_FOUND=0
    for d in /dev/sd?; do
        if [ -b "$d" ]; then
            parted -s "$d" print
            echo ""
            USB_FOUND=1
        fi
    done

    if [ "$USB_FOUND" -eq 0 ]; then
        echo "USB-диски не найдены."
        pause
        return 1
    fi
    echo ""
	echo "Найдите название своего накопителя из списка выше"
    echo "Найдите строку вида (например Disk /dev/sda: 61.9GB где *sda* имя):"
    read -p "Введите имя диска (пример: sda или sdb): " disk

    if [ ! -b "/dev/$disk" ]; then
        echo "Ошибка: диск /dev/$disk не найден."
        pause
        return 1
    fi
    return 0
}

unmount_if_mounted() {
    if mount | grep -q "$1 "; then
        echo "Раздел $1 сейчас смонтирован. Выполняем размонтирование..."
        umount -l "$1"
        sleep 1
    fi
}
# ==========================
# ПРОВЕРКА АКТИВНОГО ENTWARE
# ==========================
get_entware_uuid() {
    # Получаем устройство, смонтированное в /opt
    ENTWARE_DEV=$(mount | awk '$3=="/opt" {print $1}')
    # Получаем UUID
    [ -n "$ENTWARE_DEV" ] && \
    ENTWARE_UUID=$(blkid "$ENTWARE_DEV" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
}

is_entware_partition() {
    # $1 = /dev/sdX или /dev/sdXn
    get_entware_uuid
    TARGET_UUID=$(blkid "$1" | sed -n 's/.*UUID="\([^"]*\)".*/\1/p')
    # Сравниваем UUID активного Entware с проверяемым разделом
    [ -n "$ENTWARE_UUID" ] && [ "$TARGET_UUID" = "$ENTWARE_UUID" ]
}

# ==========================
# СОЗДАНИЕ БЕКАПА ENTWARE
# ==========================
create_backup() {
    clear
    echo "=== СОЗДАНИЕ БЕКАПА ENTWARE ==="
    echo ""
    echo "Будет создан архив текущей Entware (тот, что смонтирован в /opt)"
    echo ""
    echo "Скрипт предложит выбрать раздел для сохранения архива"
    echo ""
    echo "Полное название будет выглядеть так: Entware_backup_ИМЯ_ДАТА.tar.gz"
    echo ""
	
	# --- Подтверждение продолжения ---
    read -p "Продолжить создание бекапа? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Операция отменена."
        pause
        return
    fi
	
    read -p "Введите короткое имя для бекапа (пример: My): " label

    echo ""
    echo "Выберите раздел для сохранения бекапа:"
    echo ""

    i=1
    # Перебираем все точки монтирования в /tmp/mnt/
    for mnt in /tmp/mnt/*; do
        if [ -d "$mnt" ] && mount | grep -q " on $mnt "; then
            # Находим устройство, примонтированное в эту точку
            dev=$(mount | grep " on $mnt " | awk '{print $1}')
            
            if [ -n "$dev" ] && [ -b "$dev" ]; then
                # Получаем LABEL и UUID через blkid
                blkid_output=$(blkid "$dev" 2>/dev/null)
                lbl=$(echo "$blkid_output" | grep -o 'LABEL="[^"]*"' | sed 's/LABEL="//;s/"$//')
                [ -z "$lbl" ] && lbl="(без метки)"
                uuid=$(echo "$blkid_output" | grep -o 'UUID="[^"]*"' | sed 's/UUID="//;s/"$//')
                
                # Выводим в едином стиле: Метка (UUID)
                echo "$i) $mnt | Метка: $lbl ($uuid)"
                eval MNT_$i="$mnt"
                i=$((i+1))
            fi
        fi
    done

    # Если не найдено ни одной точки монтирования
    if [ $i -eq 1 ]; then
        echo "Не найдено подключённых разделов в /tmp/mnt/"
        echo "Бекап будет сохранён в /opt (по умолчанию)"
        backup_path="/opt"
    else
        echo ""
        read -p "Введите номер раздела (1,2,3...) (Enter= /opt): " sel

        if [ -z "$sel" ]; then
            backup_path="/opt"
        else
            backup_path=$(eval echo \$MNT_"$sel")
            if [ -z "$backup_path" ]; then
                echo "Неверный выбор."
                pause
                return
            fi
        fi
    fi

    backup="${backup_path}/Entware_backup_${label}_$(date +%Y-%m-%d).tar.gz"

    echo ""
    echo "Создаём архив /opt → $backup"
    
    # Создаём архив с проверкой результата
    if tar cvzf "$backup" -C /opt .; then
        echo ""
        echo "✓ Бекап успешно создан:"
        echo "  $backup"
        
        # Показываем размер файла
        if [ -f "$backup" ]; then
            size=$(ls -lh "$backup" | awk '{print $5}')
            echo "  Размер: $size"
        fi
    else
        echo ""
        echo "✗ ОШИБКА: Не удалось создать архив!"
        echo "Возможно, недостаточно места или нет прав на запись."
    fi

    pause
}

# ==========================
# ФОРМАТИРОВАНИЕ РАЗДЕЛА
# ==========================
format_device() {
    clear
    echo "=== СПИСОК ДОСТУПНЫХ РАЗДЕЛОВ ==="
	echo ""
    echo "Выберите раздел, который хотите полностью отформатировать."
    echo "ВНИМАНИЕ: Все данные на нём будут удалены!"
    echo "Загрузка разделов, ждите..."
	echo ""
	echo "Доступные разделы:"

	i=1
	for dev in /dev/sd[a-z][0-9]*; do
		if [ -b "$dev" ]; then
			blkid_output=$(blkid "$dev" 2>/dev/null)
			label=$(echo "$blkid_output" | grep -o 'LABEL="[^"]*"' | sed 's/LABEL="//;s/"$//')
			[ -z "$label" ] && label="(без метки)"
			uuid=$(echo "$blkid_output" | grep -o 'UUID="[^"]*"' | sed 's/UUID="//;s/"$//')
			
			echo "$i) $dev | Метка: $label ($uuid)"
			eval PART_$i="$dev"
			i=$((i+1))
		fi
	done

	echo ""
	read -p "Введите номер раздела (1,2,3...): " choice
	device=$(eval echo \$PART_"$choice")

	if [ -z "$device" ]; then
		echo "Неверный выбор."
		pause
		return
	fi

	device=${device#/dev/}
	
	# Проверка на пустой ввод
    if [ -z "$device" ]; then
        echo "Операция отменена."
        pause
        return
    fi

    # Проверка что это именно sdX-раздел
    case "$device" in
        sd[a-z][0-9]*)
            ;;
        *)
            echo "Ошибка: разрешены только разделы вида sda1, sdb2 и т.д."
            pause
            return
            ;;
    esac

    if [ ! -b /dev/$device ]; then
        echo "Ошибка: устройство /dev/$device не найдено."
        pause
        return
    fi
	
	    # Проверка на активный Entware
    if is_entware_partition "/dev/$device"; then
        echo ""
        echo "ОШИБКА: Этот раздел используется активным Entware!"
        echo "Сначала переключите Entware в интерфейсе Keenetic."
        pause
        return
    fi
	
    read -p "Введите новую метку раздела (пример: OPKG-Entware): " label
    
	# Проверка метки
    if [ -z "$label" ]; then
        echo "Метка не указана. Операция отменена."
        pause
        return
    fi
	
    unmount_if_mounted "/dev/$device"

    echo ""
    echo "Форматируем /dev/$device в ext4..."

    if mkfs.ext4 -F -O^metadata_csum,^64bit,^orphan_file -b 4096 -m0 -L "$label" /dev/$device; then
        echo "Форматирование завершено УСПЕШНО."
    else
        echo "ОШИБКА: Не удалось отформатировать раздел!"
        echo "Возможно, раздел поврежден или занят системой."
        pause
        return
    fi
	
    echo ""
    read -p "Перезагрузить роутер для обновления разделов? (y/n): " r
    [ "$r" = "y" ] && reboot
}

# ==========================================
# СОЗДАНИЕ РАЗДЕЛОВ ИЗ НЕРАЗМЕЧЕННОГО ПРОСТРАНСТВА
# ==========================================
create_from_unallocated() {

    clear
    echo "=== СОЗДАНИЕ РАЗДЕЛА ИЗ НЕРАЗМЕЧЕННОГО ПРОСТРАНСТВА ==="
    echo ""
    echo "Выберите диск, на котором хотите создать раздел."
    echo ""

    # --- Список ВСЕХ дисков ---
    echo "Доступные диски:"
    i=1
    for disk_dev in /dev/sd[a-z]; do
        if [ -b "$disk_dev" ]; then
            # Получаем размер диска через blockdev или fdisk
            disk_size=$(blockdev --getsize64 "$disk_dev" 2>/dev/null)
            if [ -n "$disk_size" ]; then
                # Конвертируем байты в МБ
                disk_size_mb=$((disk_size / 1024 / 1024))
            else
                # Фоллбэк: пробуем через fdisk
                disk_size_mb=$(fdisk -l "$disk_dev" 2>/dev/null | grep "Disk $disk_dev" | awk '{print $5}' | sed 's/[^0-9]//g')
                disk_size_mb=$((disk_size_mb / 1024 / 1024))
            fi
            
            # Получаем модель диска (если есть)
            model=$(cat /sys/block/${disk_dev#/dev/}/device/model 2>/dev/null | tr -d ' ')
            [ -z "$model" ] && model="(неизвестно)"
            
            echo "$i) $disk_dev | Размер: ${disk_size_mb} MB | Модель: $model"
            eval DISK_$i="$disk_dev"
            eval SIZE_$i="$disk_size_mb"
            i=$((i+1))
        fi
    done

    # Если дисков не найдено
    if [ $i -eq 1 ]; then
        echo "В системе не найдено ни одного диска /dev/sdX."
        pause
        return
    fi

    echo ""
    read -p "Введите номер диска (1,2,3...): " choice
    disk_dev=$(eval echo \$DISK_"$choice")
    disk_size_mb=$(eval echo \$SIZE_"$choice")

    if [ -z "$disk_dev" ]; then
        echo "Неверный выбор."
        pause
        return
    fi

    # Извлекаем имя диска без /dev/ (sda)
    disk=${disk_dev#/dev/}

    echo ""
    echo "Работаем с диском: $disk_dev (${disk_size_mb} MB)"
    echo "Проверка наличия неразмеченного пространства..."
    echo ""

    # Получаем конец последнего раздела
    last_end=$(parted /dev/$disk unit MB print 2>/dev/null | awk '/^ [0-9]+/ {end=$3} END{print end}' | sed 's/MB//')
    
    # Если разделов нет — начинаем с 1MB
    [ -z "$last_end" ] && last_end=1

    # Получаем общий размер диска (уже есть disk_size_mb)
    
    # Подсчёт свободного места
    last_end_int=${last_end%.*}
    free_space=$((disk_size_mb - last_end_int))

    echo "Общий размер диска: ${disk_size_mb} MB"
    echo "Использовано: ~${last_end_int} MB"
    echo "Свободно: ${free_space} MB"
    echo ""

    if [ "$free_space" -le 0 ]; then
        echo "На диске нет неразмеченного пространства для создания нового раздела."
        echo ""
        read -p "Нажмите Enter для возврата..." dummy
        return
    fi

    echo "Доступно для создания раздела: ${free_space} MB"
    echo "Свободное пространство начинается с ${last_end_int} MB"

    # Цикл создания разделов
    while true; do
        echo ""
        read -p "Создать новый раздел из неразмеченного пространства? (y/n): " create_more
        [ "$create_more" != "y" ] && break

        echo ""
        read -p "Расширить раздел до 100% диска (y/n): " expand_last

        if [ "$expand_last" = "y" ]; then
            end="100%"
        else
            read -p "Введите размер раздела в MB (пример: 1000): " size
            end=$(( last_end_int + size ))

            # Проверка выхода за пределы диска
            if [ "$end" -gt "$disk_size_mb" ]; then
                echo "Ошибка: размер выходит за пределы диска."
                continue
            fi
        fi

        read -p "Введите метку раздела (пример: OPKG): " label
        [ -z "$label" ] && label="NONAME"

        echo ""
        echo "Создаём раздел с ${last_end_int}MB по ${end}MB..."
        
        # Создаём раздел
        if parted --align optimal /dev/$disk mkpart primary ext4 ${last_end_int}MB ${end}MB; then
            sleep 2
            
            # Определяем номер нового раздела (исправленная логика)
            # Ищем раздел, который начинается ближе всего к last_end, но не раньше
            part_num=$(parted /dev/$disk unit MB print 2>/dev/null | awk -v start="$last_end" '
                /^ [0-9]+/ { 
                    pnum=$1; pstart=$2+0; 
                    if (pstart >= start && (min_start == "" || pstart < min_start)) { 
                        min_start=pstart; found=pnum 
                    } 
                } 
                END { print found }
            ')
            
            # Фоллбэк: если не нашли, берём последний номер
            [ -z "$part_num" ] && part_num=$(parted /dev/$disk print 2>/dev/null | awk '/^ [0-9]+/ {num=$1} END{print num}')
            
            new_part="/dev/${disk}${part_num}"
            
            # Принудительно размонтируем, если система успела авто-смонтировать
            umount -l "$new_part" 2>/dev/null
            sleep 1
            
            echo "Форматируем $new_part в ext4..."
            if mkfs.ext4 -F -O^metadata_csum,^64bit,^orphan_file -b 4096 -m0 -L "$label" "$new_part"; then
                echo "✓ Раздел $new_part создан и отформатирован."
            else
                echo "⚠ Раздел создан, но форматирование не удалось."
            fi
        else
            echo "ОШИБКА: Не удалось создать раздел."
            echo "Возможные причины:"
            echo "  • Таблица разделов повреждена или диск защищён"
            echo "  • Превышено максимальное количество разделов (4 для MBR)"
            echo "  • Недостаточно свободного места"
            pause
            return
        fi

        # Если расширили до 100% — дальше создавать нельзя
        if [ "$end" = "100%" ]; then
            echo "Раздел расширен до конца диска."
            break
        fi

        last_end_int=$end
    done

    echo ""
    echo "Операция завершена!"
    echo ""
    read -p "Перезагрузить роутер для обновления разделов? (y/n): " r
    [ "$r" = "y" ] && reboot
}

# ==========================
# УДАЛЕНИЕ РАЗДЕЛА
# ==========================
delete_partition() {

    clear
    echo "=== ТЕКУЩИЕ РАЗДЕЛЫ НА ДИСКЕ ==="
    echo ""
    echo "Выберите раздел, который хотите удалить."
    echo "ВНИМАНИЕ: Все данные на нём будут безвозвратно удалены!"
    echo ""

    # --- Список ВСЕХ разделов на ВСЕХ дисках ---
    echo "Доступные разделы:"
    i=1
    for dev in /dev/sd[a-z][0-9]*; do
        if [ -b "$dev" ]; then
            blkid_output=$(blkid "$dev" 2>/dev/null)
            label=$(echo "$blkid_output" | grep -o 'LABEL="[^"]*"' | sed 's/LABEL="//;s/"$//')
            [ -z "$label" ] && label="(без метки)"
            uuid=$(echo "$blkid_output" | grep -o 'UUID="[^"]*"' | sed 's/UUID="//;s/"$//')
            
            echo "$i) $dev | Метка: $label ($uuid)"
            eval PART_$i="$dev"
            i=$((i+1))
        fi
    done

    # Если разделов вообще не найдено
    if [ $i -eq 1 ]; then
        echo "В системе не найдено ни одного раздела /dev/sdX."
        pause
        return
    fi

    echo ""
    read -p "Введите номер раздела для удаления: " choice
    target=$(eval echo \$PART_"$choice")

    if [ -z "$target" ]; then
        echo "Неверный выбор."
        pause
        return
    fi

    # Проверка существования устройства
    if [ ! -b "$target" ]; then
        echo "Ошибка: устройство $target не найдено."
        pause
        return
    fi

    # Проверка на активный Entware
    if is_entware_partition "$target"; then
        echo ""
        echo "ОШИБКА: Нельзя удалить раздел с активным Entware!"
        echo "Сначала переключите Entware в интерфейсе Keenetic."
        pause
        return
    fi

    # Размонтирование
    unmount_if_mounted "$target"

    # Извлекаем имя диска (sda) и номер раздела (1) из /dev/sda1
    # Удаляем /dev/ -> sda1
    tmp=${target#/dev/}
    # Извлекаем диск: убираем последнюю цифру (работает для sda1, sdb12 и т.д.)
    disk=$(echo "$tmp" | sed 's/[0-9]*$//')
    # Извлекаем номер: убираем буквы в начале
    part_num=$(echo "$tmp" | sed 's/^[a-z]*//')

    echo ""
    echo "Удаляем раздел $part_num на диске $disk..."
    
    # Удаляем раздел через parted
    if parted /dev/$disk rm $part_num; then
        echo "Раздел удалён."
    else
        echo "ОШИБКА: Не удалось удалить раздел."
        echo "Возможно, диск защищён от записи, имеет таблицу разделов GPT или занят системой."
        pause
        return
    fi

    echo ""
    read -p "Перезагрузить роутер для обновления таблицы разделов? (y/n): " r
    [ "$r" = "y" ] && reboot
}
# ==========================
# ПОЛНАЯ ОЧИСТКА ДИСКА
# ==========================
wipe_disk() {
    clear
    echo "=== ПОЛНАЯ ОЧИСТКА ДИСКА ==="
    echo ""
    echo "ВНИМАНИЕ: Это удалит ВСЕ разделы и данные на диске!"
    echo ""

    # --- Список ВСЕХ дисков с размером и моделью ---
    echo "Доступные диски:"
    i=1
    for disk_dev in /dev/sd[a-z]; do
        if [ -b "$disk_dev" ]; then
            # Получаем размер диска
            size=$(blockdev --getsize64 "$disk_dev" 2>/dev/null)
            if [ -n "$size" ]; then
                size_mb=$((size / 1024 / 1024))
            else
                size_mb="?"
            fi
            
            # Получаем модель диска
            model=$(cat /sys/block/${disk_dev#/dev/}/device/model 2>/dev/null | tr -d ' ')
            [ -z "$model" ] && model="(неизвестно)"
            
            echo "$i) $disk_dev | Размер: ${size_mb} MB | Модель: $model"
            eval DISK_$i="$disk_dev"
            i=$((i+1))
        fi
    done

    # Если дисков не найдено
    if [ $i -eq 1 ]; then
        echo "В системе не найдено ни одного диска /dev/sdX."
        pause
        return
    fi

    echo ""
    read -p "Введите номер диска для ПОЛНОЙ ОЧИСТКИ (1,2,3...): " choice
    disk_dev=$(eval echo \$DISK_"$choice")
    
    if [ -z "$disk_dev" ]; then
        echo "Неверный выбор."
        pause
        return
    fi

    # Извлекаем имя диска без /dev/ (sda из /dev/sda)
    disk=${disk_dev#/dev/}

    echo ""
    echo "Работаем с диском: $disk_dev"
    echo ""

    # Проверка на активный Entware
    get_entware_uuid
    if [ -n "$ENTWARE_UUID" ]; then
        for part in /dev/${disk}?*; do
            if is_entware_partition "$part"; then
                echo ""
                echo "ОШИБКА: На этом диске находится активный Entware!"
                echo "Сначала отключите Entware в интерфейсе Keenetic."
                pause
                return
            fi
        done
    fi

    echo "ВНИМАНИЕ!"
    echo "Эта операция полностью удалит ВСЕ разделы и данные на диске $disk_dev"
    echo ""
    read -p "Для подтверждения введите большими буквами (YES): " confirm

    [ "$confirm" != "YES" ] && echo "Операция отменена." && pause && return

    echo "Размонтируем все разделы диска..."
    for part in /dev/${disk}?*; do
        umount -l "$part" 2>/dev/null
    done

    echo "Удаляем таблицу разделов..."
    dd if=/dev/zero of=/dev/$disk bs=1M count=10
    parted /dev/$disk mklabel msdos

    echo "Диск полностью очищен."

    read -p "Создать новые разделы сейчас? (y/n): " create_now
    if [ "$create_now" = "y" ]; then
        create_partitions
    else
        read -p "Перезагрузить роутер? (y/n): " r
        [ "$r" = "y" ] && reboot
    fi
}

# ==========================
# СОЗДАНИЕ НЕСКОЛЬКИХ РАЗДЕЛОВ
# ==========================
create_partitions() {
    clear
    echo "=== СОЗДАНИЕ НЕСКОЛЬКИХ РАЗДЕЛОВ ==="
    echo ""
    echo "Выберите диск, на котором хотите создать разделы."
    echo ""

    # --- Список ВСЕХ дисков ---
    echo "Доступные диски:"
    i=1
    for disk_dev in /dev/sd[a-z]; do
        if [ -b "$disk_dev" ]; then
            # Получаем размер диска
            size=$(blockdev --getsize64 "$disk_dev" 2>/dev/null)
            if [ -n "$size" ]; then
                size_mb=$((size / 1024 / 1024))
            else
                # Фоллбэк через /sys/block/
                sectors=$(cat /sys/block/${disk_dev#/dev/}/size 2>/dev/null)
                [ -n "$sectors" ] && size_mb=$((sectors * 512 / 1024 / 1024)) || size_mb="?"
            fi
            
            # Получаем модель диска
            model=$(cat /sys/block/${disk_dev#/dev/}/device/model 2>/dev/null | tr -d ' ')
            [ -z "$model" ] && model="(неизвестно)"
            
            echo "$i) $disk_dev | Размер: ${size_mb} MB | Модель: $model"
            eval DISK_$i="$disk_dev"
            eval SIZE_$i="$size_mb"
            i=$((i+1))
        fi
    done

    # Если дисков не найдено
    if [ $i -eq 1 ]; then
        echo "В системе не найдено ни одного диска /dev/sdX."
        pause
        return
    fi

    echo ""
    read -p "Введите номер диска (1,2,3...): " choice
    disk_dev=$(eval echo \$DISK_"$choice")
    disk_size_mb=$(eval echo \$SIZE_"$choice")

    if [ -z "$disk_dev" ]; then
        echo "Неверный выбор."
        pause
        return
    fi

    # Извлекаем имя диска без /dev/ (sda)
    disk=${disk_dev#/dev/}

    echo ""
    echo "Работаем с диском: $disk_dev (${disk_size_mb} MB)"
    echo ""

    # Получаем конец последнего раздела
    last_end=$(parted /dev/$disk unit MB print 2>/dev/null | awk '/^ [0-9]+/ {end=$3} END{print end}' | sed 's/MB//')
    [ -z "$last_end" ] && last_end=1

    echo "Новые разделы будут создаваться начиная с ${last_end}MB"
    read -p "Сколько разделов создать подряд? (1-4): " count

    # Проверка ввода
    case "$count" in
        [1-4]) ;;
        *) echo "Неверное количество. Операция отменена."; pause; return ;;
    esac

    i=1
    while [ $i -le $count ]; do
        echo ""
        echo "=== НАСТРОЙКА РАЗДЕЛА $i ИЗ $count ==="

        # --- ЕСЛИ ЭТО ПОСЛЕДНИЙ РАЗДЕЛ ---
        if [ $i -eq $count ]; then
            read -p "Расширить последний раздел до 100% диска? (y/n): " expand_last

            if [ "$expand_last" = "y" ]; then
                end="100%"
            else
                read -p "Введите размер раздела в MB (пример: 1000): " size
                end=$(( last_end + size ))
            fi
        else
            read -p "Введите размер раздела в MB (пример: 1000): " size
            end=$(( last_end + size ))
        fi

        read -p "Введите метку раздела (пример: OPKG-Entware): " label
        [ -z "$label" ] && label="NONAME"

        echo ""
        echo "Создаём раздел с ${last_end}MB по ${end}MB..."
        
        # Создаём раздел с ПРОВЕРКОЙ успеха
        if parted --align optimal /dev/$disk mkpart primary ext4 ${last_end}MB ${end}MB; then
            sleep 2
            
            # Определяем номер нового раздела (исправленная логика)
            part_num=$(parted /dev/$disk unit MB print 2>/dev/null | awk -v start="$last_end" '
                /^ [0-9]+/ { 
                    pnum=$1; pstart=$2+0; 
                    if (pstart >= start && (min_start == "" || pstart < min_start)) { 
                        min_start=pstart; found=pnum 
                    } 
                } 
                END { print found }
            ')
            
            # Фоллбэк: если не нашли, берём последний номер
            [ -z "$part_num" ] && part_num=$(parted /dev/$disk print 2>/dev/null | awk '/^ [0-9]+/ {num=$1} END{print num}')
            
            new_part="/dev/${disk}${part_num}"

            # Принудительно размонтируем перед форматированием
            umount -l "$new_part" 2>/dev/null
            sleep 1

            echo "Форматируем $new_part в ext4..."
            if mkfs.ext4 -F -O^metadata_csum,^64bit,^orphan_file -b 4096 -m0 -L "$label" "$new_part"; then
                echo "✓ Раздел $new_part создан и отформатирован."
            else
                echo "⚠ Раздел создан, но форматирование не удалось!"
            fi
        else
            echo "ОШИБКА: Не удалось создать раздел $i."
            echo "Возможные причины:"
            echo "  • Таблица разделов повреждена или диск защищён"
            echo "  • Превышено максимальное количество разделов (4 для MBR)"
            echo "  • Недостаточно свободного места"
            pause
            return
        fi

        # Обновляем last_end только если это не 100%
        if [ "$end" != "100%" ]; then
            last_end=$end
        fi

        i=$((i+1))
    done

    echo ""
    echo "Все разделы успешно созданы и отформатированы."

    read -p "Перезагрузить роутер для обновления разделов? (y/n): " r
    [ "$r" = "y" ] && reboot
}

# ==========================
# МЕНЮ РАЗДЕЛОВ
# ==========================
disk_tools() {
while true
do
clear
echo "============== УПРАВЛЕНИЕ РАЗДЕЛАМИ ДИСКА =============="
echo ""
echo "1) Создать новые разделы из неразмеченного пространства"
echo "2) Удалить существующий раздел"
echo "3) Отформатировать раздел"
echo "4) Полностью очистить диск"
echo ""
echo "5) Показать информацию о дисках"
echo "6) Показать список разделов системы"
echo "7) Показать UUID и метки разделов"
echo "8) Показать таблицу разделов выбранного диска"
echo ""
echo "0) Вернуться в главное меню"
echo ""

read -p "Выберите пункт меню: " c

case $c in
1) create_from_unallocated ;;
2) delete_partition ;;
3) format_device ;;
4) wipe_disk ;;
5) clear; parted -l; pause ;;
6) clear; cat /proc/partitions; pause ;;
7) clear; echo "Ждите, идёт получение информации о разделах..."; echo ""; blkid; pause ;;
8) select_disk && parted /dev/$disk print; pause ;;
0) break ;;
*) echo "Неверный выбор."; sleep 1 ;;
esac

done
}


# ==========================
# ГЛАВНОЕ МЕНЮ
# ==========================
while true
do
clear
echo "========== ENTWARE MANAGER =========="
echo ""
echo "1) Работа с разделами диска"
echo "2) Создать бекап смонтированного Entware"
echo "0) Выход"
echo ""

read -p "Выберите пункт меню: " main

case $main in
1) disk_tools ;;
2) create_backup ;;
0) exit 0 ;;
*) echo "Неверный выбор."; sleep 1 ;;
esac

done