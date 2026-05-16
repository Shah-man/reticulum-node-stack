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

# Режимы
MODE_LIST=0
MODE_MISSING=0
MODE_NO_OVERWRITE=0
FILTERS=()

show_help() {
    cat <<HELP
RNode Firmware Fetcher

Использование:
  $0 [опции] [устройство ...]

Опции:
  --list           Показать список прошивок на диске
  --missing        Скачать только те, которых ещё нет
  --no-overwrite   Не перезаписывать существующие файлы
  --help, -h       Эта справка

Примеры:
  $0                          # обновить все (с бэкапом старых)
  $0 t114                     # только Heltec T114
  $0 t114 tbeam techo         # три устройства
  $0 --missing                # докачать недостающие
  $0 --no-overwrite t114      # скачать T114, только если её нет

Бэкапы: до ${KEEP_BACKUPS} версий каждой прошивки в .old/ с timestamp.
Доступные имена устройств — те же, что в /files у бота
(t114, lora32v2, lora32v3, heltec32v4, tbeam, techo, и т.д.)
HELP
}

# Парсим аргументы
for arg in "$@"; do
    case "$arg" in
        --help|-h)      show_help; exit 0 ;;
        --list)         MODE_LIST=1 ;;
        --missing)      MODE_MISSING=1 ;;
        --no-overwrite) MODE_NO_OVERWRITE=1 ;;
        --*)            echo -e "${RED}Неизвестная опция: $arg${NC}"; show_help; exit 1 ;;
        *)              FILTERS+=("$arg") ;;
    esac
done

# ============================================================
# Режим --list — показать что на диске
# ============================================================
if [ "$MODE_LIST" -eq 1 ]; then
    echo -e "${CYAN}=== Прошивки на диске ===${NC}"
    echo "Каталог: ${TARGET_DIR}"
    echo
    if [ -f "${VERSION_FILE}" ]; then
        echo -e "Локальная версия: ${GREEN}$(cat "${VERSION_FILE}")${NC}"
    else
        echo -e "Локальная версия: ${YELLOW}не определена${NC}"
    fi
    echo
    if ls "${TARGET_DIR}"/*.zip >/dev/null 2>&1; then
        ls -lh "${TARGET_DIR}"/*.zip | awk '{printf "  %-10s %s\n", $5, $NF}' | sed 's|/[^ ]*/||'
        echo
        COUNT=$(ls "${TARGET_DIR}"/*.zip | wc -l)
        echo -e "Всего: ${GREEN}${COUNT}${NC} прошивок"
    else
        echo -e "${YELLOW}Прошивок не найдено${NC}"
    fi
    if [ -d "${BACKUP_DIR}" ] && ls "${BACKUP_DIR}"/*.zip.* >/dev/null 2>&1; then
        BACKUP_COUNT=$(ls "${BACKUP_DIR}"/*.zip.* | wc -l)
        BACKUP_SIZE=$(du -sh "${BACKUP_DIR}" | cut -f1)
        echo
        echo -e "${GRAY}Бэкапы: ${BACKUP_COUNT} файлов (${BACKUP_SIZE}) в ${BACKUP_DIR}${NC}"
        echo -e "${GRAY}Хранится до ${KEEP_BACKUPS} версий на каждое устройство${NC}"
    fi
    exit 0
fi

# ============================================================
# Основной режим — скачивание
# ============================================================
echo -e "${CYAN}=== RNode Firmware Fetcher ===${NC}"
echo "Источник: github.com/${REPO}"
echo "Цель:     ${TARGET_DIR}"
if [ ${#FILTERS[@]} -gt 0 ]; then
    echo -e "Фильтр:   ${YELLOW}${FILTERS[*]}${NC}"
fi
[ "$MODE_MISSING" -eq 1 ]      && echo -e "Режим:    ${YELLOW}--missing (только отсутствующие)${NC}"
[ "$MODE_NO_OVERWRITE" -eq 1 ] && echo -e "Режим:    ${YELLOW}--no-overwrite (не трогать существующие)${NC}"
echo

mkdir -p "${TARGET_DIR}"

# 1. Метаданные релиза
echo -e "${CYAN}→ Запрос к GitHub API...${NC}"
ASSETS_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
LATEST_VERSION=$(echo "${ASSETS_JSON}" | grep -oE '"tag_name": "[^"]+"' | head -1 | cut -d'"' -f4)
PUBLISHED=$(echo "${ASSETS_JSON}" | grep -oE '"published_at": "[^"]+"' | head -1 | cut -d'"' -f4)
echo "  Последняя версия: ${LATEST_VERSION}"
echo "  Опубликована:     ${PUBLISHED}"

CURRENT_VERSION="none"
[ -f "${VERSION_FILE}" ] && CURRENT_VERSION=$(cat "${VERSION_FILE}")
echo "  Локальная версия: ${CURRENT_VERSION}"
echo

# 2. Все URL .zip
ALL_URLS=$(echo "${ASSETS_JSON}" | grep -oE '"browser_download_url": "[^"]+\.zip"' | cut -d'"' -f4)
if [ -z "${ALL_URLS}" ]; then
    echo -e "${RED}✗ В последнем релизе не найдено zip-файлов${NC}"
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
        echo -e "${RED}✗ По фильтру ничего не найдено: ${FILTERS[*]}${NC}"
        echo -e "${YELLOW}Доступные имена в релизе:${NC}"
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
        echo -e "${GREEN}✓ Все нужные прошивки уже на диске${NC}"
        exit 0
    fi
fi

COUNT=$(echo "${URLS}" | wc -l)
echo -e "${CYAN}→ К загрузке: ${COUNT} файлов${NC}"
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
            printf "${GRAY}[%2d/%d] %s — пропущено (--no-overwrite)${NC}\n" "${i}" "${COUNT}" "${filename}"
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
echo -e "${GREEN}✓ Скачано: ${DOWNLOADED_COUNT} прошивок${NC}"
[ "$SKIPPED" -gt 0 ]   && echo -e "${GRAY}  Пропущено: ${SKIPPED}${NC}"
[ "$BACKED_UP" -gt 0 ] && echo -e "${GRAY}  Бэкап старых версий: ${BACKED_UP} → ${BACKUP_DIR}${NC}"
echo

# 6. Сверка с RNODE_DEVICES в ai.py (только при полном обновлении)
if [ ${#FILTERS[@]} -eq 0 ] && [ "$MODE_MISSING" -eq 0 ]; then
    if [ ! -f "${AI_PY}" ]; then
        echo -e "${YELLOW}⚠ Файл cogs/ai.py не найден, сверка пропущена${NC}"
        exit 0
    fi

    echo -e "${CYAN}=== Сверка с RNODE_DEVICES в cogs/ai.py ===${NC}"

    PATTERNS=$(grep -oE '"[a-z][a-z0-9_]+":\s*\("[a-z0-9_]+"' "${AI_PY}" \
               | grep -oE '\("[a-z0-9_]+"' | tr -d '("')

    MISSING_PATTERNS=""
    for pat in ${PATTERNS}; do
        if ! ls "${TARGET_DIR}" | grep -iq "${pat}"; then
            MISSING_PATTERNS+="${pat} "
        fi
    done

    if [ -z "${MISSING_PATTERNS}" ]; then
        echo -e "${GREEN}✓ Все устройства из RNODE_DEVICES найдены на диске${NC}"
    else
        echo -e "${YELLOW}⚠ Для этих устройств не нашлось прошивок:${NC}"
        for p in ${MISSING_PATTERNS}; do
            echo -e "  ${YELLOW}- ${p}${NC}"
        done
        echo -e "${GRAY}   Возможно, апстрим переименовал или убрал эти модели.${NC}"
    fi
fi
