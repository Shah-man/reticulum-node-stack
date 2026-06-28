#!/bin/bash
# ============================================================
# fetch-rnode-firmware.sh
# Скачивает прошивки RNode из официального репозитория
# Mark Qvist: https://github.com/markqvist/RNode_Firmware
#
# Использование:
#   fetch-rnode-firmware.sh              # все прошивки (с бэкапом)
#   fetch-rnode-firmware.sh t114 tbeam   # только указанные устройства
#   fetch-rnode-firmware.sh --missing    # только отсутствующие
#   fetch-rnode-firmware.sh --list       # показать что есть на диске
#   fetch-rnode-firmware.sh --no-overwrite  # не трогать существующие
#   fetch-rnode-firmware.sh --help       # справка
#
# Бэкапы: хранится до 5 версий каждой прошивки в .old/ с timestamp
# ============================================================

set -e

REPO="markqvist/RNode_Firmware"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
TARGET_DIR="${SCRIPT_DIR}/../ollama-bot/knowledge/files"
BACKUP_DIR="${TARGET_DIR}/.old"
AI_PY="${SCRIPT_DIR}/../ollama-bot/cogs/ai.py"
VERSION_FILE="${TARGET_DIR}/.firmware_version"
KEEP_BACKUPS=5

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# ============================================================
# Язык интерфейса (синхронизирован с rn через тот же .rn_lang)
# Путь определяется так же, как в rn: /home/<user>/reticulum/.rn_lang
# ============================================================
_get_ret_user() {
    local u
    for u in /home/*; do
        if [[ -d "$u/reticulum/venv" ]]; then
            basename "$u"
            return
        fi
    done
    echo "user"  # fallback
}
RET_USER="$(_get_ret_user)"
LANG_FILE="/home/${RET_USER}/reticulum/.rn_lang"
LANG_RN="ru"
[ -f "$LANG_FILE" ] && LANG_RN="$(tr -d '[:space:]' < "$LANG_FILE" 2>/dev/null)"
[ "$LANG_RN" != "en" ] && LANG_RN="ru"

declare -A L
if [ "$LANG_RN" = "en" ]; then
    L[help_title]="RNode Firmware Fetcher"
    L[help_usage]="Usage:"
    L[help_options]="Options:"
    L[help_o_list]="Show the list of firmware on disk"
    L[help_o_missing]="Download only what's missing"
    L[help_o_noover]="Don't overwrite existing files"
    L[help_o_help]="This help"
    L[help_examples]="Examples:"
    L[help_e_all]="update all (with backup of old)"
    L[help_e_one]="only Heltec T114"
    L[help_e_three]="three devices"
    L[help_e_missing]="download missing"
    L[help_e_noover]="download T114 only if absent"
    L[help_backups]="Backups: up to %s versions of each firmware in .old/ with timestamp."
    L[help_devnames]="Device names — the same as in the bot's /files"
    L[unknown_opt]="Unknown option: %s"
    L[list_hdr]="=== Firmware on disk ==="
    L[list_dir]="Directory:"
    L[local_ver]="Local version:"
    L[ver_undef]="undefined"
    L[no_fw]="No firmware found"
    L[total]="Total:"
    L[fw_word]="firmware"
    L[backups_label]="Backups: %s files (%s) in %s"
    L[backups_keep]="Keeps up to %s versions per device"
    L[fetch_hdr]="=== RNode Firmware Fetcher ==="
    L[source]="Source: github.com/%s"
    L[target]="Target:   %s"
    L[filter]="Filter:   %s"
    L[mode_missing]="Mode:    --missing (only absent)"
    L[mode_noover]="Mode:    --no-overwrite (don't touch existing)"
    L[api_req]="→ Querying the GitHub API..."
    L[latest_ver]="Latest version:"
    L[published]="Published:    "
    L[local_ver2]="Local version:"
    L[no_zip]="✗ No zip files found in the latest release"
    L[nothing_filter]="✗ Nothing matched the filter: %s"
    L[avail_in_release]="Available names in the release:"
    L[all_on_disk]="✓ All needed firmware is already on disk"
    L[to_download]="→ To download: %s files"
    L[skipped_noover]="%s — skipped (--no-overwrite)"
    L[downloaded]="✓ Downloaded: %s firmware"
    L[skipped_n]="  Skipped: %s"
    L[backed_up]="  Backed up old versions: %s → %s"
    L[check_hdr]="=== Cross-check with RNODE_DEVICES in cogs/ai.py ==="
    L[aipy_notfound]="⚠ cogs/ai.py not found, cross-check skipped"
    L[all_devices_found]="✓ All devices from RNODE_DEVICES found on disk"
    L[missing_fw]="⚠ No firmware found for these devices:"
    L[maybe_renamed]="   Upstream may have renamed or removed these models."
else
    L[help_title]="RNode Firmware Fetcher"
    L[help_usage]="Использование:"
    L[help_options]="Опции:"
    L[help_o_list]="Показать список прошивок на диске"
    L[help_o_missing]="Скачать только те, которых ещё нет"
    L[help_o_noover]="Не перезаписывать существующие файлы"
    L[help_o_help]="Эта справка"
    L[help_examples]="Примеры:"
    L[help_e_all]="обновить все (с бэкапом старых)"
    L[help_e_one]="только Heltec T114"
    L[help_e_three]="три устройства"
    L[help_e_missing]="докачать недостающие"
    L[help_e_noover]="скачать T114, только если её нет"
    L[help_backups]="Бэкапы: до %s версий каждой прошивки в .old/ с timestamp."
    L[help_devnames]="Имена устройств — те же, что в /files у бота"
    L[unknown_opt]="Неизвестная опция: %s"
    L[list_hdr]="=== Прошивки на диске ==="
    L[list_dir]="Каталог:"
    L[local_ver]="Локальная версия:"
    L[ver_undef]="не определена"
    L[no_fw]="Прошивок не найдено"
    L[total]="Всего:"
    L[fw_word]="прошивок"
    L[backups_label]="Бэкапы: %s файлов (%s) в %s"
    L[backups_keep]="Хранится до %s версий на каждое устройство"
    L[fetch_hdr]="=== RNode Firmware Fetcher ==="
    L[source]="Источник: github.com/%s"
    L[target]="Цель:     %s"
    L[filter]="Фильтр:   %s"
    L[mode_missing]="Режим:    --missing (только отсутствующие)"
    L[mode_noover]="Режим:    --no-overwrite (не трогать существующие)"
    L[api_req]="→ Запрос к GitHub API..."
    L[latest_ver]="Последняя версия:"
    L[published]="Опубликована:    "
    L[local_ver2]="Локальная версия:"
    L[no_zip]="✗ В последнем релизе не найдено zip-файлов"
    L[nothing_filter]="✗ По фильтру ничего не найдено: %s"
    L[avail_in_release]="Доступные имена в релизе:"
    L[all_on_disk]="✓ Все нужные прошивки уже на диске"
    L[to_download]="→ К загрузке: %s файлов"
    L[skipped_noover]="%s — пропущено (--no-overwrite)"
    L[downloaded]="✓ Скачано: %s прошивок"
    L[skipped_n]="  Пропущено: %s"
    L[backed_up]="  Бэкап старых версий: %s → %s"
    L[check_hdr]="=== Сверка с RNODE_DEVICES в cogs/ai.py ==="
    L[aipy_notfound]="⚠ Файл cogs/ai.py не найден, сверка пропущена"
    L[all_devices_found]="✓ Все устройства из RNODE_DEVICES найдены на диске"
    L[missing_fw]="⚠ Для этих устройств не нашлось прошивок:"
    L[maybe_renamed]="   Возможно, апстрим переименовал или убрал эти модели."
fi

# Режимы
MODE_LIST=0
MODE_MISSING=0
MODE_NO_OVERWRITE=0
FILTERS=()

show_help() {
    cat <<HELP
${L[help_title]}

${L[help_usage]}
  $0 [options] [device ...]

${L[help_options]}
  --list           ${L[help_o_list]}
  --missing        ${L[help_o_missing]}
  --no-overwrite   ${L[help_o_noover]}
  --help, -h       ${L[help_o_help]}

${L[help_examples]}
  $0                          # ${L[help_e_all]}
  $0 t114                     # ${L[help_e_one]}
  $0 t114 tbeam techo         # ${L[help_e_three]}
  $0 --missing                # ${L[help_e_missing]}
  $0 --no-overwrite t114      # ${L[help_e_noover]}

$(printf "${L[help_backups]}" "${KEEP_BACKUPS}")
${L[help_devnames]}
(t114, lora32v2, lora32v3, heltec32v4, tbeam, techo, ...)
HELP
}

# Парсим аргументы
for arg in "$@"; do
    case "$arg" in
        --help|-h)      show_help; exit 0 ;;
        --list)         MODE_LIST=1 ;;
        --missing)      MODE_MISSING=1 ;;
        --no-overwrite) MODE_NO_OVERWRITE=1 ;;
        --*)            echo -e "${RED}$(printf "${L[unknown_opt]}" "$arg")${NC}"; show_help; exit 1 ;;
        *)              FILTERS+=("$arg") ;;
    esac
done

# ============================================================
# Режим --list — показать что на диске
# ============================================================
if [ "$MODE_LIST" -eq 1 ]; then
    echo -e "${CYAN}${L[list_hdr]}${NC}"
    echo "${L[list_dir]} ${TARGET_DIR}"
    echo
    if [ -f "${VERSION_FILE}" ]; then
        echo -e "${L[local_ver]} ${GREEN}$(cat "${VERSION_FILE}")${NC}"
    else
        echo -e "${L[local_ver]} ${YELLOW}${L[ver_undef]}${NC}"
    fi
    echo
    if ls "${TARGET_DIR}"/*.zip >/dev/null 2>&1; then
        ls -lh "${TARGET_DIR}"/*.zip | awk '{printf "  %-10s %s\n", $5, $NF}' | sed 's|/[^ ]*/||'
        echo
        COUNT=$(ls "${TARGET_DIR}"/*.zip | wc -l)
        echo -e "${L[total]} ${GREEN}${COUNT}${NC} ${L[fw_word]}"
    else
        echo -e "${YELLOW}${L[no_fw]}${NC}"
    fi
    if [ -d "${BACKUP_DIR}" ] && ls "${BACKUP_DIR}"/*.zip.* >/dev/null 2>&1; then
        BACKUP_COUNT=$(ls "${BACKUP_DIR}"/*.zip.* | wc -l)
        BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
        echo
        echo -e "${GRAY}$(printf "${L[backups_label]}" "${BACKUP_COUNT}" "${BACKUP_SIZE}" "${BACKUP_DIR}")${NC}"
        echo -e "${GRAY}$(printf "${L[backups_keep]}" "${KEEP_BACKUPS}")${NC}"
    fi
    exit 0
fi

# ============================================================
# Основной режим — скачивание
# ============================================================
echo -e "${CYAN}${L[fetch_hdr]}${NC}"
echo "$(printf "${L[source]}" "${REPO}")"
echo "$(printf "${L[target]}" "${TARGET_DIR}")"
if [ ${#FILTERS[@]} -gt 0 ]; then
    echo -e "$(printf "${L[filter]}" "${YELLOW}${FILTERS[*]}${NC}")"
fi
[ "$MODE_MISSING" -eq 1 ]      && echo -e "${YELLOW}${L[mode_missing]}${NC}"
[ "$MODE_NO_OVERWRITE" -eq 1 ] && echo -e "${YELLOW}${L[mode_noover]}${NC}"
echo

mkdir -p "${TARGET_DIR}"

# 1. Метаданные релиза
echo -e "${CYAN}${L[api_req]}${NC}"
ASSETS_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
LATEST_VERSION=$(echo "${ASSETS_JSON}" | grep -oE '"tag_name": "[^"]+"' | head -1 | cut -d'"' -f4)
PUBLISHED=$(echo "${ASSETS_JSON}" | grep -oE '"published_at": "[^"]+"' | head -1 | cut -d'"' -f4)
echo "  ${L[latest_ver]} ${LATEST_VERSION}"
echo "  ${L[published]} ${PUBLISHED}"

CURRENT_VERSION="none"
[ -f "${VERSION_FILE}" ] && CURRENT_VERSION=$(cat "${VERSION_FILE}")
echo "  ${L[local_ver2]} ${CURRENT_VERSION}"
echo

# 2. Все URL .zip
ALL_URLS=$(echo "${ASSETS_JSON}" | grep -oE '"browser_download_url": "[^"]+\.zip"' | cut -d'"' -f4)
if [ -z "${ALL_URLS}" ]; then
    echo -e "${RED}${L[no_zip]}${NC}"
    exit 1
fi

# 3. Фильтр по аргументам пользователя
if [ ${#FILTERS[@]} -gt 0 ]; then
    FILTERED=""
    for url in ${ALL_URLS}; do
        fname=$(basename "${url}" | tr '[:upper:]' '[:lower:]')
        for pat in "${FILTERS[@]}"; do
            if [[ "${fname}" == *"${pat,,}"* ]]; then
                FILTERED+="${url}"$'\n'
                break
            fi
        done
    done
    URLS=$(echo "${FILTERED}" | grep -v '^$' || true)
    if [ -z "${URLS}" ]; then
        echo -e "${RED}$(printf "${L[nothing_filter]}" "${FILTERS[*]}")${NC}"
        echo -e "${YELLOW}${L[avail_in_release]}${NC}"
        echo "${ALL_URLS}" | xargs -n1 basename | sed 's/^/  /'
        exit 1
    fi
else
    URLS="${ALL_URLS}"
fi

# 4. --missing: оставляем только то, чего нет на диске
if [ "$MODE_MISSING" -eq 1 ]; then
    NEEDED=""
    for url in ${URLS}; do
        fname=$(basename "${url}")
        if [ ! -f "${TARGET_DIR}/${fname}" ]; then
            NEEDED+="${url}"$'\n'
        fi
    done
    URLS=$(echo "${NEEDED}" | grep -v '^$' || true)
    if [ -z "${URLS}" ]; then
        echo -e "${GREEN}${L[all_on_disk]}${NC}"
        exit 0
    fi
fi

COUNT=$(echo "${URLS}" | wc -l)
echo -e "${CYAN}$(printf "${L[to_download]}" "${COUNT}")${NC}"
echo

# 5. Качаем (с бэкапом + ротацией)
mkdir -p "${BACKUP_DIR}"
i=0
SKIPPED=0
BACKED_UP=0
for url in ${URLS}; do
    i=$((i + 1))
    filename=$(basename "${url}")
    target="${TARGET_DIR}/${filename}"

    if [ -f "${target}" ]; then
        if [ "$MODE_NO_OVERWRITE" -eq 1 ]; then
            printf "${GRAY}[%2d/%d] $(printf "${L[skipped_noover]}" "%s")${NC}\n" "${i}" "${COUNT}" "${filename}"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi
        # Бэкап с timestamp
        TS=$(date +%Y%m%d-%H%M%S)
        cp "${target}" "${BACKUP_DIR}/${filename}.${TS}"
        BACKED_UP=$((BACKED_UP + 1))
        # Ротация: оставляем последние KEEP_BACKUPS бэкапов
        ls -1t "${BACKUP_DIR}/${filename}".* 2>/dev/null \
            | tail -n +$((KEEP_BACKUPS + 1)) \
            | xargs -r rm -f
    fi

    printf "[%2d/%d] %s\n" "${i}" "${COUNT}" "${filename}"
    curl -fsSL -o "${target}" "${url}"
done

# Обновляем version-файл только при полном обновлении
if [ ${#FILTERS[@]} -eq 0 ] && [ "$MODE_MISSING" -eq 0 ] && [ "$MODE_NO_OVERWRITE" -eq 0 ]; then
    echo "${LATEST_VERSION}" > "${VERSION_FILE}"
fi

echo
DOWNLOADED_COUNT=$((COUNT - SKIPPED))
echo -e "${GREEN}$(printf "${L[downloaded]}" "${DOWNLOADED_COUNT}")${NC}"
[ "$SKIPPED" -gt 0 ]   && echo -e "${GRAY}$(printf "${L[skipped_n]}" "${SKIPPED}")${NC}"
[ "$BACKED_UP" -gt 0 ] && echo -e "${GRAY}$(printf "${L[backed_up]}" "${BACKED_UP}" "${BACKUP_DIR}")${NC}"
echo

# 6. Сверка с RNODE_DEVICES в ai.py (только при полном обновлении)
if [ ${#FILTERS[@]} -eq 0 ] && [ "$MODE_MISSING" -eq 0 ]; then
    if [ ! -f "${AI_PY}" ]; then
        echo -e "${YELLOW}${L[aipy_notfound]}${NC}"
        exit 0
    fi

    echo -e "${CYAN}${L[check_hdr]}${NC}"

    PATTERNS=$(grep -oE '"[a-z][a-z0-9_]+":\s*\("[a-z0-9_]+"' "${AI_PY}" \
               | grep -oE '\("[a-z0-9_]+"' | tr -d '("')

    MISSING_PATTERNS=""
    for pat in ${PATTERNS}; do
        if ! ls "${TARGET_DIR}" | grep -iq "${pat}"; then
            MISSING_PATTERNS+="${pat} "
        fi
    done

    if [ -z "${MISSING_PATTERNS}" ]; then
        echo -e "${GREEN}${L[all_devices_found]}${NC}"
    else
        echo -e "${YELLOW}${L[missing_fw]}${NC}"
        for p in ${MISSING_PATTERNS}; do
            echo -e "  ${YELLOW}- ${p}${NC}"
        done
        echo -e "${GRAY}${L[maybe_renamed]}${NC}"
    fi
fi
