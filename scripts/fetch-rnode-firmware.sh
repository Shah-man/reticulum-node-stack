#!/bin/bash
# ============================================================
# fetch-rnode-firmware.sh
# Качает последние прошивки RNode из официального репозитория
# Mark Qvist: https://github.com/markqvist/RNode_Firmware
#
# Особенности:
# - Проверяет версию релиза перед скачиванием
# - Сравнивает имена файлов со словарём RNODE_FIRMWARES в cogs/ai.py
# - Предупреждает если апстрим переименовал/добавил/удалил прошивки
# ============================================================

set -e

REPO="markqvist/RNode_Firmware"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
TARGET_DIR="${SCRIPT_DIR}/../ollama-bot/knowledge/files"
AI_PY="${SCRIPT_DIR}/../ollama-bot/cogs/ai.py"
VERSION_FILE="${TARGET_DIR}/.firmware_version"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== RNode Firmware Fetcher ===${NC}"
echo "Источник: github.com/${REPO}"
echo "Цель:     ${TARGET_DIR}"
echo

mkdir -p "${TARGET_DIR}"

# 1. Получаем метаданные последнего релиза
echo -e "${CYAN}→ Запрос к GitHub API...${NC}"
ASSETS_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")

LATEST_VERSION=$(echo "${ASSETS_JSON}" | grep -oE '"tag_name": "[^"]+"' | head -1 | cut -d'"' -f4)
PUBLISHED=$(echo "${ASSETS_JSON}" | grep -oE '"published_at": "[^"]+"' | head -1 | cut -d'"' -f4)

echo "  Последняя версия: ${LATEST_VERSION}"
echo "  Опубликована:     ${PUBLISHED}"

# 2. Проверяем локальную версию
CURRENT_VERSION="none"
if [ -f "${VERSION_FILE}" ]; then
    CURRENT_VERSION=$(cat "${VERSION_FILE}")
fi
echo "  Локальная версия: ${CURRENT_VERSION}"
echo

if [ "${CURRENT_VERSION}" = "${LATEST_VERSION}" ]; then
    echo -e "${GREEN}✓ Прошивки актуальной версии. Скачивание не требуется.${NC}"
    echo
    echo -e "${CYAN}Если хочешь принудительно перекачать — удали файл:${NC}"
    echo "  rm ${VERSION_FILE}"
    exit 0
fi

# 3. Извлекаем URL'ы всех .zip-файлов
URLS=$(echo "${ASSETS_JSON}" | grep -oE '"browser_download_url": "[^"]+\.zip"' | cut -d'"' -f4)

if [ -z "${URLS}" ]; then
    echo -e "${RED}✗ В последнем релизе не найдено zip-файлов. Прерываю.${NC}"
    exit 1
fi

COUNT=$(echo "${URLS}" | wc -l)
echo -e "${CYAN}→ Найдено файлов в релизе: ${COUNT}${NC}"
echo

# 4. Качаем
i=0
for url in ${URLS}; do
    i=$((i + 1))
    filename=$(basename "${url}")
    printf "[%2d/%d] %s\n" "${i}" "${COUNT}" "${filename}"
    curl -fsSL -o "${TARGET_DIR}/${filename}" "${url}"
done

echo "${LATEST_VERSION}" > "${VERSION_FILE}"
echo
echo -e "${GREEN}✓ Скачано: ${COUNT} прошивок${NC}"
echo

# 5. Сверка имён с RNODE_FIRMWARES в cogs/ai.py
if [ ! -f "${AI_PY}" ]; then
    echo -e "${YELLOW}⚠ Файл cogs/ai.py не найден, сверка имён пропущена${NC}"
    exit 0
fi

echo -e "${CYAN}=== Сверка с RNODE_FIRMWARES в cogs/ai.py ===${NC}"

# Имена прошивок, на которые ссылается бот
EXPECTED=$(grep -oE 'rnode_[a-z0-9_]+\.zip' "${AI_PY}" | sort -u)

# Имена прошивок, реально скачанные
DOWNLOADED=$(ls "${TARGET_DIR}"/rnode_*.zip 2>/dev/null | xargs -n1 basename | sort -u)

# Что бот ждёт, но в релизе нет (исчезли/переименованы)
MISSING=$(comm -23 <(echo "${EXPECTED}") <(echo "${DOWNLOADED}"))

# Что есть в релизе, но бот про них не знает (новые модели)
NEW=$(comm -13 <(echo "${EXPECTED}") <(echo "${DOWNLOADED}"))

if [ -z "${MISSING}" ] && [ -z "${NEW}" ]; then
    echo -e "${GREEN}✓ Все имена совпадают, словарь RNODE_FIRMWARES актуален${NC}"
else
    if [ -n "${MISSING}" ]; then
        echo -e "${RED}✗ Бот ссылается на прошивки, которых нет в релизе:${NC}"
        echo "${MISSING}" | sed 's/^/  - /'
        echo -e "${YELLOW}   → Возможно, апстрим переименовал или удалил эти модели${NC}"
        echo -e "${YELLOW}   → Проверь словарь RNODE_FIRMWARES в ${AI_PY}${NC}"
        echo
    fi
    if [ -n "${NEW}" ]; then
        echo -e "${YELLOW}+ В релизе появились новые прошивки, бот про них не знает:${NC}"
        echo "${NEW}" | sed 's/^/  + /'
        echo -e "${YELLOW}   → Можешь добавить их в словарь RNODE_FIRMWARES в ${AI_PY}${NC}"
        echo
    fi
    echo -e "${YELLOW}После правки словаря — перезапусти бота:${NC}"
    echo "  systemctl restart surgutbot86.service"
fi
