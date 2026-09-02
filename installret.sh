#!/usr/bin/env bash
#
# ╔═══════════════════════════════════════════════════════════════╗
# ║              Reticulum Node Stack — Installer                 ║
# ╚═══════════════════════════════════════════════════════════════╝
#
# Sets up a full Reticulum node from scratch: RNS daemon, NomadNet
# propagation node, LXMF distribution group (with an anonymous
# broadcaster), message board, the rn/f2b management tools, and
# (optionally) a local LLM-powered bot.
#
# Repository:  https://github.com/Shah-man/reticulum-node-stack
# License:     MIT
# Version:     0.2.0
#
# ─── Usage ────────────────────────────────────────────────────────
#
#   sudo ./installret.sh              Interactive install
#   sudo ./installret.sh --dry-run    Show what would be done; no changes
#   sudo ./installret.sh --uninstall  Remove the stack
#   ./installret.sh --help            Show help and exit
#
# ─── Supported systems ────────────────────────────────────────────
#
#   • Debian 11/12 / Ubuntu 20.04+ (and derivatives: HiveOS, Kali)
#   • Alt Linux (p10, p11, Sisyphus) — best-effort
#   • Architecture: x86_64 or arm64/aarch64
#
# ─── Requirements ─────────────────────────────────────────────────
#
#   Minimum (without the bot):   1 CPU, 1 GB RAM, 10 GB free disk
#   Recommended (with the bot):  4 CPU, 16 GB RAM, 50 GB free disk,
#                                NVIDIA GPU with >= 8 GB VRAM
#
# ──────────────────────────────────────────────────────────────────

set -euo pipefail

# ─── Global variables ─────────────────────────────────────────────────────────

readonly SCRIPT_NAME="installret.sh"
readonly SCRIPT_VERSION="0.2.0"

readonly REPO_URL="https://github.com/Shah-man/reticulum-node-stack.git"
readonly REPO_DIR="/root/reticulum-node-stack"

# Filled in later by detect/ask functions
LANG_CHOICE="ru"            # ru | en — set by ask_language(), default ru
TARGET_USER=""
VENV_DIR=""                 # /home/<user>/reticulum
BOT_DIR=""                  # /home/<user>/ollama-bot
BACKUP_FILE=""              # путь к резервной копии identity (заполняется при uninstall)
NODE_NAME="Reticulum Node"
SYSTEM_NAME="reticulum_node"
INSTALL_BOT=false
DRY_RUN=false
UNINSTALL=false
TIMEZONE_WARNING=false
BACKUPS_CREATED=()
FAILED_SERVICES=()
WARN_NOTES=()               # collected best-effort warnings for the summary

# Broadcaster (service sender for the LXMF group)
readonly GROUP_CONFIG_DIR="/root/.config/lxmf_distribution_group_extended"

# f2b / fail2ban
readonly RN_PIN="/root/.rn_pin"         # shared PIN file used by both rn and f2b
readonly F2B_SSHD_BANTIME=3600        # 1 hour — must match scripts/f2b
readonly F2B_RECIDIVE_BANTIME=604800  # 1 week — must match scripts/f2b

readonly PIP_PACKAGES="rns nomadnet lxmf"

# ─── Colors ───────────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    readonly C_RED=$'\033[0;31m'
    readonly C_GRN=$'\033[0;32m'
    readonly C_YEL=$'\033[0;33m'
    readonly C_BLU=$'\033[0;34m'
    readonly C_RST=$'\033[0m'
else
    readonly C_RED="" C_GRN="" C_YEL="" C_BLU="" C_RST=""
fi

# ─── Bilingual string table ───────────────────────────────────────────────────
# Two dictionaries (ru/en) loaded into a single associative array L based on
# LANG_CHOICE. load_lang() is called right after the language is picked, so the
# entire installation — every log line and prompt — speaks the chosen language.

declare -A L

load_lang() {
    # ── Russian ──────────────────────────────────────────────────────────
    if [[ "$LANG_CHOICE" == "ru" ]]; then
        L[banner]="Установщик Reticulum Node Stack"
        L[dry_mode]="РЕЖИМ DRY-RUN: изменения не вносятся"
        L[need_root]="Скрипт должен запускаться от root. Используйте: sudo ./$SCRIPT_NAME"

        # steps
        L[s_detect_os]="Определение ОС"
        L[s_detect_user]="Определение пользователя"
        L[s_preflight]="Предварительные проверки"
        L[s_confirm]="Подтверждение"
        L[s_nodename]="Имя узла"
        L[s_bot]="Бот SurgutBot86 (опционально)"
        L[s_prepare]="Подготовка системы (обновление, базовые пакеты)"
        L[s_clone]="Клонирование репозитория"
        L[s_rns]="Установка Reticulum (RNS, NomadNet, LXMF)"
        L[s_ollama]="Установка Ollama и SurgutBot86"
        L[s_configs]="Размещение конфигов"
        L[s_code]="Размещение кода сервисов"
        L[s_units]="Установка systemd-юнитов"
        L[s_scripts]="Установка управляющих скриптов"
        L[s_lang_init]="Инициализация языка интерфейса"
        L[s_firststart]="Первый запуск — включение и старт сервисов"
        L[s_broadcaster]="Настройка вещателя (broadcaster)"
        L[s_f2b]="Настройка защиты fail2ban (f2b)"
        L[s_health]="Проверка работоспособности"
        L[s_summary]="Итоги установки"
        L[s_uninstall]="Удаление Reticulum Node Stack"

        # generic
        L[detected]="Обнаружено:"
        L[using_apt]="семейство Debian — используется apt"
        L[using_aptget]="Alt Linux — используется apt-get"
        L[unsupported]="не поддерживается, продолжаем на ваш страх и риск"
        L[pkg_may_fail]="Установка пакетов может не сработать. Ctrl+C для отмены, либо ждите 5с."

        # users
        L[no_users]="Обычные пользователи не найдены"
        L[will_create_user]="Будет создан пользователь 'user' с домашним каталогом /home/user"
        L[user_created]="Пользователь 'user' создан"
        L[target_user_auto]="Целевой пользователь: %s (определён автоматически)"
        L[multi_users]="На этой машине несколько пользователей:"
        L[pick_user]="Выберите пользователя [1-%s]: "
        L[invalid_choice]="Неверный выбор, попробуйте снова"
        L[target_user]="Целевой пользователь: %s"

        # preflight
        L[no_systemd]="systemctl не найден — требуется система на базе systemd"
        L[systemd_ok]="systemd доступен"
        L[arch_ok]="Архитектура: %s (поддерживается)"
        L[arch_warn]="Архитектура: %s — бот может не работать, сам RNS должен работать"
        L[net_check]="Проверка доступа в интернет..."
        L[reachable]="%s доступен"
        L[no_github]="Не удаётся достучаться до github.com — нет интернета или сломан DNS"
        L[no_pypi]="Не удаётся достучаться до pypi.org — pip не сработает"
        L[disk_low_fail]="Свободно на /: %sG — нужно минимум 10G (без бота)"
        L[disk_low_bot]="Свободно на /: %sG — хватит без бота, но НЕ хватит для бота (нужно ~50G)"
        L[disk_ok]="Свободно на /: %sG"
        L[disk_unknown]="Не удалось определить свободное место"
        L[preflight_fail]="Предварительные проверки не пройдены. Исправьте проблемы выше и повторите."
        L[preflight_ok]="Все предварительные проверки пройдены"

        # consent
        L[consent_intro]="Скрипт развернёт Reticulum Node Stack на этой машине."
        L[consent_params]="Обнаруженные параметры:"
        L[consent_os]="ОС:"
        L[consent_user]="Пользователь:"
        L[consent_venv]="Путь venv:"
        L[consent_bot]="Путь бота:"
        L[consent_repo]="Путь репо:"
        L[consent_will]="Скрипт выполнит:"
        L[consent_l1]="Установит системные пакеты"
        L[consent_l2]="Создаст venv с RNS, NomadNet, LXMF"
        L[consent_l3]="Склонирует репозиторий reticulum-node-stack"
        L[consent_l4]="Разместит конфиги, код сервисов и systemd-юниты"
        L[consent_l5]="Настроит вещателя группы и fail2ban (f2b)"
        L[consent_l6]="Запустит все сервисы"
        L[consent_q]="Продолжить установку на этой машине? [y/N]: "
        L[confirmed]="Подтверждено, продолжаем"
        L[aborted]="Прервано пользователем"
        L[answer_yn]="Ответьте 'y' или 'n'"

        # node name
        L[nn_info1]="Имя узла отображается как display_name в NomadNet, на доске и в LXMF-группе."
        L[nn_info2]="Буквы, цифры, пробелы, дефисы, кириллица — всё можно."
        L[nn_info3]="Примеры: 'Northern propagation node', 'Node Alpha 42'"
        L[nn_prompt]="Имя узла [%s]: "
        L[nn_default]="Используется по умолчанию: %s"
        L[nn_sysname]="Системное имя: %s"
        L[nn_len]="Длина должна быть 2-64 символа (получено %s)"
        L[nn_badchars]="Эти символы запрещены: / \\ \" ' \$ \` перевод строки"
        L[nn_noascii]="Не удаётся сгенерировать безопасное ASCII-имя. Добавьте латиницу или цифры."
        L[nn_set]="Имя узла: %s"

        # bot
        L[bot_desc1]="SurgutBot86 — AI-бот для LXMF, отвечающий на сообщения через локальную LLM (Ollama)."
        L[bot_req]="Требования (рекомендуется):"
        L[bot_req_cpu]="4 CPU, 16 GB RAM, 50 GB свободного диска"
        L[bot_req_gpu]="NVIDIA GPU с >= 8 GB VRAM (для модели gemma2:9b)"
        L[bot_req_cpu_only]="Без GPU бот работает на CPU — медленно (30+ сек на ответ)."
        L[bot_skip_note]="Бота можно поставить позже, перезапустив этот скрипт."
        L[bot_q]="Установить SurgutBot86? [y/N]: "
        L[bot_yes]="Бот БУДЕТ установлен"
        L[bot_no]="Бот будет ПРОПУЩЕН"
        L[bot_gpu_warn]="GPU не обнаружен — бот будет работать на CPU (очень медленно). Продолжаем."

        # prepare
        L[apt_update]="Обновление списков пакетов..."
        L[apt_upgrade]="Обновление установленных пакетов (может занять несколько минут)..."
        L[unknown_skip_pkg]="Неизвестная ОС — пропускаем установку пакетов"
        L[install_manually]="Установите эти пакеты вручную:"
        L[installing]="Устанавливаю: %s"
        L[base_done]="Базовые пакеты установлены"
        L[time_check]="Проверка синхронизации времени..."
        L[no_timedatectl]="timedatectl недоступен — пропускаю проверку NTP"
        L[ntp_ok]="Время синхронизировано по NTP"
        L[ntp_enabling]="Время НЕ синхронизировано, включаю NTP..."
        L[ntp_enabled]="NTP-синхронизация включена"
        L[tz_default]="Часовой пояс: %s (по умолчанию). Задайте свой после установки:"
        L[tz_ok]="Часовой пояс: %s"

        # clone
        L[clone_src]="Источник: %s"
        L[clone_dst]="Назначение: %s"
        L[clone_exists]="Репозиторий уже есть, тяну изменения..."
        L[clone_updated]="Репозиторий обновлён"
        L[clone_notgit]="Путь %s существует, но это не git-репозиторий. Удалите/переименуйте вручную."
        L[clone_done]="Репозиторий склонирован"
        L[clone_verify_skip]="[dry-run] Пропускаю проверку структуры"
        L[clone_missing]="В репозитории нет ожидаемых каталогов: %s"
        L[clone_verified]="Структура репозитория проверена"

        # rns
        L[venv_reuse]="venv уже есть в %s — переиспользую"
        L[venv_bad]="%s существует, но это не корректный venv. Удалите вручную и повторите."
        L[venv_create]="Создаю venv в %s..."
        L[venv_created]="venv создан"
        L[pip_upgrade]="Обновляю pip внутри venv..."
        L[pip_install]="Устанавливаю %s (1-2 минуты)..."
        L[set_owner]="Назначаю владельца %s → %s..."
        L[verify_tools]="Проверяю установленные инструменты..."
        L[tool_missing]="%s не найден в venv"
        L[rns_incomplete]="Установка RNS неполная — некоторые инструменты отсутствуют."
        L[rns_done]="Стек RNS установлен"

        # ollama
        L[ollama_have]="Ollama уже установлена: %s"
        L[ollama_install]="Устанавливаю Ollama официальным установщиком..."
        L[ollama_alt_warn]="На Alt Linux официальный установщик обычно работает, при сбое — вручную."
        L[ollama_done]="Ollama установлена"
        L[gpu_check]="Проверка наличия NVIDIA GPU..."
        L[gpu_loaded]="Модуль ядра NVIDIA загружен — GPU доступен для CUDA/Ollama"
        L[gpu_details]="GPU: %s"
        L[gpu_bus_noload]="NVIDIA GPU на шине (%s), но модуль ядра не загружен"
        L[gpu_install_drv]="Установите проприетарный драйвер NVIDIA для ускорения. Без него — CPU."
        L[gpu_none]="NVIDIA GPU не обнаружен — Ollama будет на CPU (медленно)"
        L[model_pull]="Скачиваю модель: %s (~5.4 GB, может занять 10+ минут)..."
        L[model_ready]="Модель %s готова"
        L[bot_copy]="Копирую код бота в %s..."
        L[bot_copied]="Код бота скопирован"
        L[bot_env_kept]="Сохранён существующий .env"
        L[bot_venv_reuse]="venv бота уже есть — переиспользую"
        L[bot_venv_create]="Создаю venv бота..."
        L[bot_reqs]="Устанавливаю зависимости бота..."
        L[bot_installed]="SurgutBot86 установлен"

        # configs
        L[backup_saved]="Бэкап сохранён: %s"
        L[place_root]="Размещаю root-конфиг → %s"
        L[place_user]="Размещаю user-конфиг → %s"
        L[place_nomad]="Размещаю конфиг NomadNet → %s"
        L[nodename_set]="node_name установлен: %s"
        L[nodename_failwarn]="Подстановка могла не сработать — проверьте %s вручную"
        L[configs_done]="Все конфиги размещены"

        # code
        L[place_mb]="Размещаю messageboard.py → %s"
        L[place_grp]="Размещаю код LXMF-группы → %s"
        L[nomad_storage]="Создаю каталоги хранилища NomadNet в %s"
        L[copy_pages]="Копирую страницы NomadNet → %s"
        L[copy_files]="Копирую файлы NomadNet → %s"
        L[patch_shebang]="Правлю shebang в .mu → %s"
        L[code_incomplete]="Размещение кода сервисов неполное. Отсутствует: %s"
        L[code_done]="Весь код сервисов размещён"

        # units
        L[unit_installed]="Установлен: %s"
        L[unit_gen]="Генерирую %s → %s"
        L[bot_units_skip]="Бот пропущен → ollama.service и surgutbot86.service не ставятся"
        L[daemon_reload]="Перезагружаю демон systemd..."
        L[units_done]="Все systemd-юниты установлены"

        # scripts
        L[scripts_src_missing]="Источник не найден: %s — пропускаю"
        L[installing_script]="Устанавливаю %s → %s"
        L[scripts_done]="Управляющие скрипты установлены (rn, f2b, installret.sh, fetch-rnode-firmware.sh)"

        # lang init
        L[lang_writing]="Записываю язык интерфейса '%s' → %s"
        L[lang_done]="Язык интерфейса задан: %s"

        # firststart
        L[enabling]="Включаю автозапуск сервисов..."
        L[starting]="Запускаю сервисы (пауза %sс между каждым)..."
        L[restart_group]="Перезапускаю lxmf_group.service (конфиги созданы при первом старте)..."
        L[all_started]="Все сервисы запущены"

        # broadcaster
        L[bc_wait_cfg]="Жду генерацию config.cfg группы..."
        L[bc_cfg_missing]="Конфиг группы не появился (%s) — пропускаю настройку вещателя"
        L[bc_gen_id]="Генерирую identity вещателя..."
        L[bc_id_exists]="identity вещателя уже есть — переиспользую"
        L[bc_hash_fail]="Не удалось получить хеш вещателя — пропускаю"
        L[bc_hash]="Хеш вещателя: %s"
        L[bc_role_exists]="Роль broadcaster уже есть в config.cfg"
        L[bc_role_add]="Добавляю роль broadcaster в config.cfg..."
        L[bc_section_upd]="Прописываю секцию [broadcaster] в data.cfg..."
        L[bc_restart]="Перезапускаю группу для применения настроек вещателя..."
        L[bc_done]="Вещатель настроен — группа рассылает сообщения анонимно"

        # f2b
        L[f2b_no_fail2ban]="fail2ban не установлен — пропускаю настройку защиты"
        L[f2b_pin_gen]="Генерирую PIN для f2b → %s"
        L[f2b_pin_exists]="PIN-файл f2b уже есть — не трогаю"
        L[f2b_jail_write]="Пишу jail.local (sshd 1ч + recidive 1неделя)..."
        L[f2b_jail_exists]="jail.local уже есть — создаю jail.local бэкап, перезаписываю"
        L[f2b_enable]="Включаю и запускаю fail2ban..."
        L[f2b_done]="Защита fail2ban настроена"
        L[f2b_warn]="Не удалось полностью настроить fail2ban — проверьте 'f2b' вручную"

        # health
        L[warmup]="Жду %sс прогрева сервисов..."
        L[svc_active]="%s — активен"
        L[svc_state]="%s — %s"
        L[svc_journal]="Последние 10 строк журнала %s:"
        L[check_rns]="Проверяю интерфейсы RNS (rnstatus)..."
        L[rns_responded]="rnstatus ответил"
        L[rns_noresp]="rnstatus ответил не сразу (RNS может ещё инициализироваться)"
        L[check_ollama]="Проверяю Ollama (ollama ps)..."
        L[all_healthy]="Все сервисы работают"
        L[some_failed]="%s сервис(ов) не запустилось: %s"
        L[see_logs]="Смотрите логи: journalctl -u <сервис> -e"

        # summary
        L[inst_complete]="Установка завершена."
        L[inst_warn]="Установка завершена с предупреждениями."
        L[sum_node]="Имя узла:"
        L[sum_sys]="Системное имя:"
        L[sum_os]="ОС:"
        L[sum_user]="Пользователь:"
        L[sum_repo]="Репо:"
        L[sum_venv]="venv RNS:"
        L[sum_bot]="Бот:"
        L[sum_bot_no]="не установлен"
        L[sum_services]="Сервисы:"
        L[useful_cmds]="Полезные команды:"
        L[cmd_rn]="главное меню управления"
        L[cmd_rnhelp]="список всех команд rn"
        L[cmd_f2b]="статистика fail2ban"
        L[cmd_rnstatus]="статус интерфейсов RNS"
        L[cmd_journal]="логи сервиса"
        L[cmd_reinstall]="перезапуск установщика (обновление/добавить бота)"
        L[backups_made]="Создано бэкапов (%s):"
        L[restore_hint]="Восстановить бэкап:  mv <бэкап> <оригинал>"
        L[warn_notes_hdr]="Предупреждения:"
        L[tz_reminder]="Часовой пояс: система на UTC. Сменить:  timedatectl set-timezone <Зона>"
        L[gpu_reminder]="GPU: модуль NVIDIA не загружен — Ollama на CPU (медленно)."
        L[final_up]="Узел поднят. Запустите 'rn' для меню управления."
        L[final_failed]="Часть сервисов не запустилась. Логи: journalctl -u <сервис> -e"

        # uninstall
        L[un_confirm]="Это остановит и удалит Reticulum Node Stack. Продолжить? [y/N]: "
        L[un_stopping]="Останавливаю и отключаю сервисы..."
        L[un_units]="Удаляю systemd-юниты..."
        L[un_scripts]="Удаляю управляющие скрипты..."
        L[un_venv]="Удаляю venv и код стека..."
        L[un_bot]="Удаляю бота..."
        L[un_data]="Удаляю пользовательские данные..."
        L[un_backup]="Сохраняю резервную копию identity..."
        L[un_backup_title]="РЕЗЕРВНАЯ КОПИЯ IDENTITY"
        L[un_backup_saved]="Копия ключей сохранена (адреса узла/групп/бота):"
        L[un_backup_view]="Посмотреть, что внутри:"
        L[un_backup_restore_lbl]="Восстановить после новой установки:"
        L[un_backup_restart]="затем перезапустите узел:  rn → Перезапустить ВСЁ"
        L[un_backup_delete_lbl]="Удалить копию, если не нужна:"
        L[un_done]="Reticulum Node Stack удалён."
        L[un_aborted]="Удаление отменено."

    # ── English ──────────────────────────────────────────────────────────
    else
        L[banner]="Reticulum Node Stack installer"
        L[dry_mode]="DRY-RUN mode: no changes will be made"
        L[need_root]="This script must be run as root. Use: sudo ./$SCRIPT_NAME"

        L[s_detect_os]="Detecting OS"
        L[s_detect_user]="Detecting target user"
        L[s_preflight]="Preflight checks"
        L[s_confirm]="Confirmation"
        L[s_nodename]="Node name"
        L[s_bot]="SurgutBot86 bot (optional)"
        L[s_prepare]="Preparing system (updating, base packages)"
        L[s_clone]="Cloning repository"
        L[s_rns]="Installing Reticulum (RNS, NomadNet, LXMF)"
        L[s_ollama]="Installing Ollama and SurgutBot86"
        L[s_configs]="Placing configs"
        L[s_code]="Placing service code"
        L[s_units]="Installing systemd units"
        L[s_scripts]="Installing management scripts"
        L[s_lang_init]="Initializing interface language"
        L[s_firststart]="First startup — enabling and starting services"
        L[s_broadcaster]="Setting up the broadcaster"
        L[s_f2b]="Setting up fail2ban protection (f2b)"
        L[s_health]="Health check"
        L[s_summary]="Installation summary"
        L[s_uninstall]="Removing Reticulum Node Stack"

        L[detected]="Detected:"
        L[using_apt]="Debian family — using apt"
        L[using_aptget]="Alt Linux — using apt-get"
        L[unsupported]="unsupported, proceeding at your own risk"
        L[pkg_may_fail]="Package install may fail. Ctrl+C to abort, or wait 5s to continue."

        L[no_users]="No human users found on this system"
        L[will_create_user]="Will create user 'user' with home directory /home/user"
        L[user_created]="User 'user' created"
        L[target_user_auto]="Target user: %s (auto-detected)"
        L[multi_users]="Multiple users found on this system:"
        L[pick_user]="Pick a user [1-%s]: "
        L[invalid_choice]="Invalid choice, try again"
        L[target_user]="Target user: %s"

        L[no_systemd]="systemctl not found — this script requires a systemd-based system"
        L[systemd_ok]="systemd available"
        L[arch_ok]="Architecture: %s (supported)"
        L[arch_warn]="Architecture: %s — bot may not work, RNS itself should be fine"
        L[net_check]="Checking internet connectivity..."
        L[reachable]="%s reachable"
        L[no_github]="Cannot reach github.com — no internet or DNS broken"
        L[no_pypi]="Cannot reach pypi.org — pip will fail"
        L[disk_low_fail]="Free space on /: %sG — need at least 10G (without bot)"
        L[disk_low_bot]="Free space on /: %sG — enough without bot, NOT enough for bot (~50G)"
        L[disk_ok]="Free space on /: %sG"
        L[disk_unknown]="Could not determine free disk space"
        L[preflight_fail]="Preflight checks failed. Fix the issues above and retry."
        L[preflight_ok]="All preflight checks passed"

        L[consent_intro]="This script will deploy the Reticulum Node Stack on this machine."
        L[consent_params]="Detected parameters:"
        L[consent_os]="OS:"
        L[consent_user]="User:"
        L[consent_venv]="venv path:"
        L[consent_bot]="Bot path:"
        L[consent_repo]="Repo path:"
        L[consent_will]="The script will:"
        L[consent_l1]="Install system packages"
        L[consent_l2]="Create a venv with RNS, NomadNet, LXMF"
        L[consent_l3]="Clone the reticulum-node-stack repo"
        L[consent_l4]="Place configs, service code and systemd units"
        L[consent_l5]="Configure the group broadcaster and fail2ban (f2b)"
        L[consent_l6]="Start all services"
        L[consent_q]="Proceed with deployment on this machine? [y/N]: "
        L[confirmed]="Confirmed, proceeding"
        L[aborted]="Aborted by user"
        L[answer_yn]="Please answer 'y' or 'n'"

        L[nn_info1]="Node name appears as display_name in NomadNet, the board and the LXMF group."
        L[nn_info2]="Letters, digits, spaces, dashes, Cyrillic — all OK."
        L[nn_info3]="Examples: 'Northern propagation node', 'Node Alpha 42'"
        L[nn_prompt]="Node name [%s]: "
        L[nn_default]="Using default: %s"
        L[nn_sysname]="System name: %s"
        L[nn_len]="Length must be 2-64 chars (got %s)"
        L[nn_badchars]="These chars are not allowed: / \\ \" ' \$ \` newline"
        L[nn_noascii]="Cannot generate a safe ASCII system name. Include some Latin letters or digits."
        L[nn_set]="Node name: %s"

        L[bot_desc1]="SurgutBot86 is an AI LXMF bot that answers messages using a local LLM (Ollama)."
        L[bot_req]="Requirements (recommended):"
        L[bot_req_cpu]="4 CPU, 16 GB RAM, 50 GB free disk"
        L[bot_req_gpu]="NVIDIA GPU with >= 8 GB VRAM (for the gemma2:9b model)"
        L[bot_req_cpu_only]="Without a GPU the bot runs on CPU — slow (30+ sec per reply)."
        L[bot_skip_note]="You can install the bot later by re-running this script."
        L[bot_q]="Install SurgutBot86? [y/N]: "
        L[bot_yes]="Bot WILL be installed"
        L[bot_no]="Bot will be SKIPPED"
        L[bot_gpu_warn]="No GPU detected — the bot will run on CPU (very slow). Proceeding."

        L[apt_update]="Updating package lists..."
        L[apt_upgrade]="Upgrading installed packages (may take a few minutes)..."
        L[unknown_skip_pkg]="Unknown OS family — skipping package installation"
        L[install_manually]="Install these packages manually:"
        L[installing]="Installing: %s"
        L[base_done]="Base packages installed"
        L[time_check]="Checking time synchronization..."
        L[no_timedatectl]="timedatectl not available — skipping NTP check"
        L[ntp_ok]="Time is NTP-synchronized"
        L[ntp_enabling]="Time is NOT synchronized, enabling NTP..."
        L[ntp_enabled]="NTP synchronization enabled"
        L[tz_default]="Timezone: %s (default). Set your local timezone after install:"
        L[tz_ok]="Timezone: %s"

        L[clone_src]="Source: %s"
        L[clone_dst]="Target: %s"
        L[clone_exists]="Repository already exists, pulling latest changes..."
        L[clone_updated]="Repository updated"
        L[clone_notgit]="Path %s exists but is not a git repo. Remove or rename it manually."
        L[clone_done]="Repository cloned"
        L[clone_verify_skip]="[dry-run] Skipping structure verification"
        L[clone_missing]="Repository is missing expected directories: %s"
        L[clone_verified]="Repository structure verified"

        L[venv_reuse]="venv already exists at %s — reusing"
        L[venv_bad]="%s exists but is not a valid venv. Remove it manually and re-run."
        L[venv_create]="Creating venv at %s..."
        L[venv_created]="venv created"
        L[pip_upgrade]="Upgrading pip inside venv..."
        L[pip_install]="Installing %s (this may take 1-2 minutes)..."
        L[set_owner]="Setting ownership of %s to %s..."
        L[verify_tools]="Verifying installed tools..."
        L[tool_missing]="%s not found in venv"
        L[rns_incomplete]="RNS installation incomplete — some tools are missing."
        L[rns_done]="RNS stack installed"

        L[ollama_have]="Ollama is already installed: %s"
        L[ollama_install]="Installing Ollama via the official installer..."
        L[ollama_alt_warn]="On Alt Linux the official installer usually works; if it fails, install manually."
        L[ollama_done]="Ollama installed"
        L[gpu_check]="Checking for an NVIDIA GPU..."
        L[gpu_loaded]="NVIDIA kernel module loaded — GPU available for CUDA/Ollama"
        L[gpu_details]="GPU: %s"
        L[gpu_bus_noload]="NVIDIA GPU on the bus (%s), but kernel module not loaded"
        L[gpu_install_drv]="Install the proprietary NVIDIA driver for acceleration. Without it — CPU."
        L[gpu_none]="No NVIDIA GPU detected — Ollama will run on CPU (slow)"
        L[model_pull]="Pulling model: %s (~5.4 GB, may take 10+ minutes)..."
        L[model_ready]="Model %s ready"
        L[bot_copy]="Copying bot code to %s..."
        L[bot_copied]="Bot code copied"
        L[bot_env_kept]="Preserved existing .env"
        L[bot_venv_reuse]="Bot venv already exists — reusing"
        L[bot_venv_create]="Creating bot venv..."
        L[bot_reqs]="Installing bot requirements..."
        L[bot_installed]="SurgutBot86 installed"

        L[backup_saved]="Backup saved: %s"
        L[place_root]="Placing root config → %s"
        L[place_user]="Placing user config → %s"
        L[place_nomad]="Placing NomadNet config → %s"
        L[nodename_set]="node_name set to: %s"
        L[nodename_failwarn]="Substitution may have failed — check %s manually"
        L[configs_done]="All configs placed"

        L[place_mb]="Placing messageboard.py → %s"
        L[place_grp]="Placing LXMF group code → %s"
        L[nomad_storage]="Creating NomadNet storage dirs at %s"
        L[copy_pages]="Copying NomadNet pages → %s"
        L[copy_files]="Copying NomadNet files → %s"
        L[patch_shebang]="Patching .mu shebangs → %s"
        L[code_incomplete]="Service code placement incomplete. Missing: %s"
        L[code_done]="All service code placed"

        L[unit_installed]="Installed: %s"
        L[unit_gen]="Generating %s → %s"
        L[bot_units_skip]="Bot skipped → ollama.service and surgutbot86.service not installed"
        L[daemon_reload]="Reloading systemd daemon..."
        L[units_done]="All systemd units installed"

        L[scripts_src_missing]="Source not found: %s — skipping"
        L[installing_script]="Installing %s → %s"
        L[scripts_done]="Management scripts installed (rn, f2b, installret.sh, fetch-rnode-firmware.sh)"

        L[lang_writing]="Writing interface language '%s' → %s"
        L[lang_done]="Interface language set: %s"

        L[enabling]="Enabling services for autostart..."
        L[starting]="Starting services (%ss pause between each)..."
        L[restart_group]="Restarting lxmf_group.service (configs generated on first run)..."
        L[all_started]="All services started"

        L[bc_wait_cfg]="Waiting for the group's config.cfg to be generated..."
        L[bc_cfg_missing]="Group config did not appear (%s) — skipping broadcaster setup"
        L[bc_gen_id]="Generating broadcaster identity..."
        L[bc_id_exists]="Broadcaster identity already exists — reusing"
        L[bc_hash_fail]="Could not get broadcaster hash — skipping"
        L[bc_hash]="Broadcaster hash: %s"
        L[bc_role_exists]="broadcaster role already exists in config.cfg"
        L[bc_role_add]="Adding broadcaster role to config.cfg..."
        L[bc_section_upd]="Writing [broadcaster] section to data.cfg..."
        L[bc_restart]="Restarting the group to apply broadcaster settings..."
        L[bc_done]="Broadcaster configured — the group distributes messages anonymously"

        L[f2b_no_fail2ban]="fail2ban is not installed — skipping protection setup"
        L[f2b_pin_gen]="Generating f2b PIN → %s"
        L[f2b_pin_exists]="f2b PIN file already exists — leaving it"
        L[f2b_jail_write]="Writing jail.local (sshd 1h + recidive 1week)..."
        L[f2b_jail_exists]="jail.local already exists — backing it up, overwriting"
        L[f2b_enable]="Enabling and starting fail2ban..."
        L[f2b_done]="fail2ban protection configured"
        L[f2b_warn]="Could not fully configure fail2ban — check 'f2b' manually"

        L[warmup]="Waiting %ss for services to warm up..."
        L[svc_active]="%s — active"
        L[svc_state]="%s — %s"
        L[svc_journal]="Last 10 lines of journal for %s:"
        L[check_rns]="Checking RNS interfaces (rnstatus)..."
        L[rns_responded]="rnstatus responded"
        L[rns_noresp]="rnstatus did not respond cleanly (RNS may still be initializing)"
        L[check_ollama]="Checking Ollama (ollama ps)..."
        L[all_healthy]="All services healthy"
        L[some_failed]="%s service(s) failed: %s"
        L[see_logs]="See logs with: journalctl -u <service> -e"

        L[inst_complete]="Installation complete."
        L[inst_warn]="Installation finished with warnings."
        L[sum_node]="Node name:"
        L[sum_sys]="System name:"
        L[sum_os]="OS:"
        L[sum_user]="User:"
        L[sum_repo]="Repo:"
        L[sum_venv]="RNS venv:"
        L[sum_bot]="Bot:"
        L[sum_bot_no]="not installed"
        L[sum_services]="Services:"
        L[useful_cmds]="Useful commands:"
        L[cmd_rn]="main management menu"
        L[cmd_rnhelp]="list all rn commands"
        L[cmd_f2b]="fail2ban stats"
        L[cmd_rnstatus]="RNS interface status"
        L[cmd_journal]="service logs"
        L[cmd_reinstall]="re-run installer (update / add bot)"
        L[backups_made]="Backups created (%s):"
        L[restore_hint]="To restore a backup:  mv <backup> <original>"
        L[warn_notes_hdr]="Warnings:"
        L[tz_reminder]="Timezone: system is on UTC. To change:  timedatectl set-timezone <Zone>"
        L[gpu_reminder]="GPU: NVIDIA module not loaded — Ollama runs on CPU (slow)."
        L[final_up]="Node is up. Run 'rn' to open the management menu."
        L[final_failed]="Some services failed. Logs: journalctl -u <service> -e"

        L[un_confirm]="This will stop and remove the Reticulum Node Stack. Continue? [y/N]: "
        L[un_stopping]="Stopping and disabling services..."
        L[un_units]="Removing systemd units..."
        L[un_scripts]="Removing management scripts..."
        L[un_venv]="Removing venv and stack code..."
        L[un_bot]="Removing the bot..."
        L[un_data]="Removing user data..."
        L[un_backup]="Saving an identity backup..."
        L[un_backup_title]="IDENTITY BACKUP"
        L[un_backup_saved]="Keys saved (node/group/bot addresses):"
        L[un_backup_view]="See what's inside:"
        L[un_backup_restore_lbl]="Restore after a fresh install:"
        L[un_backup_restart]="then restart the node:  rn → Restart ALL"
        L[un_backup_delete_lbl]="Delete the backup if not needed:"
        L[un_done]="Reticulum Node Stack removed."
        L[un_aborted]="Uninstall aborted."
    fi
}

# ─── Logger ───────────────────────────────────────────────────────────────────

log_info()  { printf '%s[*]%s %s\n' "$C_BLU" "$C_RST" "$*"; }
log_ok()    { printf '%s[+]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
log_warn()  { printf '%s[!]%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
log_error() { printf '%s[X]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
log_step()  { printf '\n%s━━━ %s ━━━%s\n' "$C_BLU" "$*" "$C_RST"; }

die() { log_error "$*"; exit 1; }

# Run command, or just print it in dry-run mode
run() {
    if $DRY_RUN; then
        printf '%s[dry-run]%s %s\n' "$C_YEL" "$C_RST" "$*"
    else
        eval "$@"
    fi
}

# ─── Argument parsing / help ──────────────────────────────────────────────────

show_help() {
    cat <<EOF
${SCRIPT_NAME} ${SCRIPT_VERSION} — Reticulum Node Stack installer

Usage:
  sudo ./${SCRIPT_NAME}              Interactive install
  sudo ./${SCRIPT_NAME} --dry-run    Show actions without changing anything
  sudo ./${SCRIPT_NAME} --uninstall  Remove the stack
       ./${SCRIPT_NAME} --help       Show this help and exit
       ./${SCRIPT_NAME} --version    Show version and exit

The installer asks for the install language first; every subsequent log line
and prompt then speaks that language, and the choice is written to the
interface language file so rn/f2b start in the same language.

Requirements:
  Minimum (no bot):  1 CPU, 1 GB RAM, 10 GB free disk
  With the bot:      4 CPU, 16 GB RAM, 50 GB free disk, NVIDIA GPU >= 8 GB VRAM
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)   DRY_RUN=true ;;
            --uninstall) UNINSTALL=true ;;
            --help|-h)   show_help; exit 0 ;;
            --version|-v) echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"; exit 0 ;;
            *) echo "Unknown option: $1" >&2; echo "Try --help" >&2; exit 1 ;;
        esac
        shift
    done
}

# ─── Language selection ───────────────────────────────────────────────────────
# Asked before anything else so the whole run speaks the chosen language.
# Skipped in dry-run only if stdin is not a TTY (defaults to ru).

ask_language() {
    # Non-interactive (piped) → default ru, no prompt
    if [[ ! -t 0 ]]; then
        LANG_CHOICE="ru"
        load_lang
        return
    fi

    echo
    echo "  ┌─────────────────────────────────────────┐"
    echo "  │   Reticulum Node Stack — Installer       │"
    echo "  ├─────────────────────────────────────────┤"
    echo "  │   Выберите язык установки / Choose lang  │"
    echo "  │                                          │"
    echo "  │     [1] Русский                          │"
    echo "  │     [2] English                          │"
    echo "  └─────────────────────────────────────────┘"
    echo
    local choice
    while true; do
        read -rp "  [1/2]: " choice
        case "$choice" in
            1|"") LANG_CHOICE="ru"; break ;;
            2)    LANG_CHOICE="en"; break ;;
            *)    echo "  1 или / or 2" ;;
        esac
    done
    load_lang
}

# ─── Confirm helper (y/N) ─────────────────────────────────────────────────────

confirm() {
    # $1 = prompt key in L ; returns 0 for yes, 1 for no
    local ans
    while true; do
        read -rp "${L[$1]}" ans
        case "${ans,,}" in
            y|yes|д|да) return 0 ;;
            n|no|н|нет|"") return 1 ;;
            *) log_warn "${L[answer_yn]}" ;;
        esac
    done
}

# ─── Root check ───────────────────────────────────────────────────────────────

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        # L not loaded yet if this runs very early; print bilingual
        echo "This script must be run as root. Use: sudo ./${SCRIPT_NAME}" >&2
        echo "Скрипт нужно запускать от root. Используйте: sudo ./${SCRIPT_NAME}" >&2
        exit 1
    fi
}

# ─── OS detection ─────────────────────────────────────────────────────────────
# Sets OS_FAMILY (debian|alt|unknown) and PKG (apt|apt-get) and OS_PRETTY.

OS_FAMILY="unknown"
OS_PRETTY="unknown"

detect_os() {
    log_step "${L[s_detect_os]}"

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_PRETTY="${PRETTY_NAME:-${NAME:-unknown}}"
        local id="${ID:-}" idlike="${ID_LIKE:-}"

        if [[ "$id" =~ (debian|ubuntu|kali|hiveos) ]] || [[ "$idlike" =~ (debian|ubuntu) ]]; then
            OS_FAMILY="debian"
        elif [[ "$id" =~ (altlinux|alt) ]] || [[ "$idlike" =~ alt ]]; then
            OS_FAMILY="alt"
        fi
    fi

    log_info "${L[detected]} ${OS_PRETTY}"
    case "$OS_FAMILY" in
        debian) log_ok "${L[using_apt]}" ;;
        alt)    log_ok "${L[using_aptget]}" ;;
        *)      log_warn "${OS_PRETTY} — ${L[unsupported]}" ;;
    esac
}

# ─── Target user detection ────────────────────────────────────────────────────
# Picks the human user whose home will host the reticulum venv.
# Sets TARGET_USER, VENV_DIR, BOT_DIR.

detect_target_user() {
    log_step "${L[s_detect_user]}"

    # Collect candidate users: UID >= 1000, has /home/<name>, not 'nobody'
    local candidates=()
    local name uid home
    while IFS=: read -r name _ uid _ _ home _; do
        [[ "$uid" -ge 1000 && "$uid" -lt 65534 ]] || continue
        [[ "$home" == /home/* ]] || continue
        [[ -d "$home" ]] || continue
        candidates+=("$name")
    done < /etc/passwd

    if [[ ${#candidates[@]} -eq 0 ]]; then
        log_warn "${L[no_users]}"
        log_info "${L[will_create_user]}"
        if ! $DRY_RUN; then
            useradd -m -s /bin/bash user
            log_ok "${L[user_created]}"
        fi
        TARGET_USER="user"
    elif [[ ${#candidates[@]} -eq 1 ]]; then
        TARGET_USER="${candidates[0]}"
        printf -v _m "${L[target_user_auto]}" "$TARGET_USER"; log_ok "$_m"
    else
        log_info "${L[multi_users]}"
        local i=1
        for name in "${candidates[@]}"; do
            printf "    [%d] %s\n" "$i" "$name"; ((i++))
        done
        local choice
        while true; do
            printf -v _p "${L[pick_user]}" "${#candidates[@]}"
            read -rp "$_p" choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
                TARGET_USER="${candidates[$((choice-1))]}"
                break
            fi
            log_warn "${L[invalid_choice]}"
        done
        printf -v _m "${L[target_user]}" "$TARGET_USER"; log_ok "$_m"
    fi

    VENV_DIR="/home/${TARGET_USER}/reticulum"
    BOT_DIR="/home/${TARGET_USER}/ollama-bot"
}

# ─── Preflight checks ─────────────────────────────────────────────────────────

preflight() {
    log_step "${L[s_preflight]}"
    local ok=true

    # systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        log_error "${L[no_systemd]}"; ok=false
    else
        log_ok "${L[systemd_ok]}"
    fi

    # architecture
    local arch; arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64|aarch64|arm64)
            printf -v _m "${L[arch_ok]}" "$arch"; log_ok "$_m" ;;
        *)
            printf -v _m "${L[arch_warn]}" "$arch"; log_warn "$_m" ;;
    esac

    # connectivity
    log_info "${L[net_check]}"
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 10 https://github.com >/dev/null 2>&1; then
            printf -v _m "${L[reachable]}" "github.com"; log_ok "$_m"
        else
            log_error "${L[no_github]}"; ok=false
        fi
        if curl -fsS --max-time 10 https://pypi.org >/dev/null 2>&1; then
            printf -v _m "${L[reachable]}" "pypi.org"; log_ok "$_m"
        else
            log_error "${L[no_pypi]}"; ok=false
        fi
    fi

    # disk space on /
    local free_g=""
    if free_g="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -dc '0-9')"; then
        if [[ -n "$free_g" ]]; then
            if (( free_g < 10 )); then
                printf -v _m "${L[disk_low_fail]}" "$free_g"; log_error "$_m"; ok=false
            elif (( free_g < 50 )) && $INSTALL_BOT; then
                printf -v _m "${L[disk_low_bot]}" "$free_g"; log_warn "$_m"
            else
                printf -v _m "${L[disk_ok]}" "$free_g"; log_ok "$_m"
            fi
        else
            log_warn "${L[disk_unknown]}"
        fi
    else
        log_warn "${L[disk_unknown]}"
    fi

    if ! $ok; then
        die "${L[preflight_fail]}"
    fi
    log_ok "${L[preflight_ok]}"
}

# ─── Consent ──────────────────────────────────────────────────────────────────

ask_consent() {
    log_step "${L[s_confirm]}"
    echo
    log_info "${L[consent_intro]}"
    echo
    echo "  ${L[consent_params]}"
    echo "    ${L[consent_os]}    ${OS_PRETTY}"
    echo "    ${L[consent_user]}  ${TARGET_USER}"
    echo "    ${L[consent_venv]}  ${VENV_DIR}/venv"
    $INSTALL_BOT && echo "    ${L[consent_bot]}   ${BOT_DIR}"
    echo "    ${L[consent_repo]}  ${REPO_DIR}"
    echo
    echo "  ${L[consent_will]}"
    echo "    • ${L[consent_l1]}"
    echo "    • ${L[consent_l2]}"
    echo "    • ${L[consent_l3]}"
    echo "    • ${L[consent_l4]}"
    echo "    • ${L[consent_l5]}"
    echo "    • ${L[consent_l6]}"
    echo

    if $DRY_RUN; then
        log_info "${L[dry_mode]}"
        return 0
    fi
    if confirm consent_q; then
        log_ok "${L[confirmed]}"
    else
        die "${L[aborted]}"
    fi
}

# ─── Node name ────────────────────────────────────────────────────────────────
# Sets NODE_NAME (display) and SYSTEM_NAME (ASCII slug for internal use).

ask_node_name() {
    log_step "${L[s_nodename]}"
    echo
    log_info "${L[nn_info1]}"
    log_info "${L[nn_info2]}"
    log_info "${L[nn_info3]}"
    echo

    local default_name="Reticulum Node"
    local input

    if [[ ! -t 0 ]]; then
        NODE_NAME="$default_name"
        printf -v _m "${L[nn_default]}" "$NODE_NAME"; log_info "$_m"
    else
        while true; do
            printf -v _p "${L[nn_prompt]}" "$default_name"
            read -rp "$_p" input
            input="${input:-$default_name}"

            # length 2-64
            local len="${#input}"
            if (( len < 2 || len > 64 )); then
                printf -v _m "${L[nn_len]}" "$len"; log_warn "$_m"; continue
            fi
            # forbidden chars: / \ " ' $ ` and newline
            if [[ "$input" == *[/\\\"\'\$\`]* ]] || [[ "$input" == *$'\n'* ]]; then
                log_warn "${L[nn_badchars]}"; continue
            fi
            NODE_NAME="$input"
            break
        done
    fi

    # system name: ASCII slug, lowercase, spaces→_, strip non [a-z0-9_-]
    local slug
    slug="$(echo "$NODE_NAME" \
        | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | tr ' ' '_' \
        | tr -cd 'a-z0-9_-')"
    slug="${slug##_}"; slug="${slug%%_}"
    if [[ -z "$slug" ]]; then
        # Cyrillic-only name → fall back to a generic slug
        slug="reticulum_node"
    fi
    SYSTEM_NAME="$slug"

    printf -v _m "${L[nn_set]}" "$NODE_NAME"; log_ok "$_m"
    printf -v _m "${L[nn_sysname]}" "$SYSTEM_NAME"; log_info "$_m"
}

# ─── Bot question ─────────────────────────────────────────────────────────────

ask_bot() {
    log_step "${L[s_bot]}"
    echo
    log_info "${L[bot_desc1]}"
    echo
    echo "  ${L[bot_req]}"
    echo "    • ${L[bot_req_cpu]}"
    echo "    • ${L[bot_req_gpu]}"
    echo "    • ${L[bot_req_cpu_only]}"
    echo
    log_info "${L[bot_skip_note]}"
    echo

    if [[ ! -t 0 ]]; then
        INSTALL_BOT=false
        log_info "${L[bot_no]}"
        return
    fi

    if confirm bot_q; then
        INSTALL_BOT=true
        log_ok "${L[bot_yes]}"
    else
        INSTALL_BOT=false
        log_info "${L[bot_no]}"
    fi
}

# ─── System preparation ───────────────────────────────────────────────────────

prepare_system() {
    log_step "${L[s_prepare]}"

    local base_pkgs_debian="git python3 python3-venv python3-pip curl wget \
dialog iconv fail2ban build-essential libffi-dev"
    local base_pkgs_alt="git python3 python3-module-venv python3-module-pip curl wget \
dialog fail2ban gcc"

    case "$OS_FAMILY" in
        debian)
            log_info "${L[apt_update]}"
            run "DEBIAN_FRONTEND=noninteractive apt update -y"
            log_info "${L[apt_upgrade]}"
            run "DEBIAN_FRONTEND=noninteractive apt upgrade -y"
            printf -v _m "${L[installing]}" "$base_pkgs_debian"; log_info "$_m"
            # libffi-dev/build-essential needed by some wheels; iconv is in coreutils on debian (skip pkg)
            run "DEBIAN_FRONTEND=noninteractive apt install -y git python3 python3-venv python3-pip curl wget dialog fail2ban build-essential libffi-dev"
            ;;
        alt)
            log_info "${L[apt_update]}"
            run "apt-get update -y"
            printf -v _m "${L[installing]}" "$base_pkgs_alt"; log_info "$_m"
            run "apt-get install -y git python3 python3-module-venv python3-module-pip curl wget dialog fail2ban gcc"
            ;;
        *)
            log_warn "${L[unknown_skip_pkg]}"
            log_info "${L[install_manually]}"
            echo "    git python3 python3-venv python3-pip curl wget dialog fail2ban"
            ;;
    esac
    log_ok "${L[base_done]}"

    # time sync (best-effort)
    log_info "${L[time_check]}"
    if command -v timedatectl >/dev/null 2>&1; then
        if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
            log_ok "${L[ntp_ok]}"
        else
            log_warn "${L[ntp_enabling]}"
            run "timedatectl set-ntp true" || true
            log_ok "${L[ntp_enabled]}"
        fi
        # timezone note
        local tz; tz="$(timedatectl show -p Timezone --value 2>/dev/null || echo UTC)"
        if [[ "$tz" == "UTC" || "$tz" == "Etc/UTC" ]]; then
            TIMEZONE_WARNING=true
            printf -v _m "${L[tz_default]}" "$tz"; log_warn "$_m"
            echo "    timedatectl set-timezone <Region/City>"
        else
            printf -v _m "${L[tz_ok]}" "$tz"; log_ok "$_m"
        fi
    else
        log_warn "${L[no_timedatectl]}"
    fi
}

# ─── Clone repository ─────────────────────────────────────────────────────────

clone_repo() {
    log_step "${L[s_clone]}"
    printf -v _m "${L[clone_src]}" "$REPO_URL"; log_info "$_m"
    printf -v _m "${L[clone_dst]}" "$REPO_DIR"; log_info "$_m"

    if [[ -d "$REPO_DIR/.git" ]]; then
        log_info "${L[clone_exists]}"
        run "git -C '$REPO_DIR' pull --ff-only" || true
        log_ok "${L[clone_updated]}"
    elif [[ -e "$REPO_DIR" ]]; then
        printf -v _m "${L[clone_notgit]}" "$REPO_DIR"; die "$_m"
    else
        run "git clone --depth 1 '$REPO_URL' '$REPO_DIR'"
        log_ok "${L[clone_done]}"
    fi

    # verify expected structure
    if $DRY_RUN; then
        log_info "${L[clone_verify_skip]}"; return
    fi
    local missing=()
    local d
    for d in scripts configs systemd; do
        [[ -d "$REPO_DIR/$d" ]] || missing+=("$d")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf -v _m "${L[clone_missing]}" "${missing[*]}"; die "$_m"
    fi
    log_ok "${L[clone_verified]}"
}

# ─── Install Reticulum stack (venv) ───────────────────────────────────────────

install_rns() {
    log_step "${L[s_rns]}"
    local venv="${VENV_DIR}/venv"

    if [[ -d "$venv" ]]; then
        if [[ -x "$venv/bin/python" ]]; then
            printf -v _m "${L[venv_reuse]}" "$venv"; log_info "$_m"
        else
            printf -v _m "${L[venv_bad]}" "$venv"; die "$_m"
        fi
    else
        printf -v _m "${L[venv_create]}" "$venv"; log_info "$_m"
        run "mkdir -p '$VENV_DIR'"
        run "python3 -m venv '$venv'"
        log_ok "${L[venv_created]}"
    fi

    log_info "${L[pip_upgrade]}"
    run "'$venv/bin/pip' install --upgrade pip wheel setuptools"

    printf -v _m "${L[pip_install]}" "$PIP_PACKAGES"; log_info "$_m"
    run "'$venv/bin/pip' install --upgrade $PIP_PACKAGES"

    printf -v _m "${L[set_owner]}" "$VENV_DIR" "$TARGET_USER"; log_info "$_m"
    run "chown -R '${TARGET_USER}:${TARGET_USER}' '$VENV_DIR'"

    # verify tools
    if ! $DRY_RUN; then
        log_info "${L[verify_tools]}"
        local t ok=true
        for t in rnsd rnstatus nomadnet lxmd rnid; do
            if [[ ! -x "$venv/bin/$t" ]]; then
                printf -v _m "${L[tool_missing]}" "$t"; log_warn "$_m"; ok=false
            fi
        done
        $ok || die "${L[rns_incomplete]}"
    fi
    log_ok "${L[rns_done]}"
}

# ─── GPU detection helper ─────────────────────────────────────────────────────
# Echoes "loaded" | "bus" | "none". Sets GPU_INFO for messages.

GPU_INFO=""
detect_gpu() {
    # kernel module loaded == driver active
    if lsmod 2>/dev/null | grep -q '^nvidia'; then
        if command -v nvidia-smi >/dev/null 2>&1; then
            GPU_INFO="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
        fi
        echo "loaded"; return
    fi
    # present on PCI bus but no driver
    if command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -qi 'NVIDIA'; then
        GPU_INFO="$(lspci 2>/dev/null | grep -i 'NVIDIA' | head -1)"
        echo "bus"; return
    fi
    echo "none"
}

# ─── Install Ollama + bot ─────────────────────────────────────────────────────

install_ollama_and_bot() {
    $INSTALL_BOT || return 0
    log_step "${L[s_ollama]}"

    # Ollama
    if command -v ollama >/dev/null 2>&1; then
        printf -v _m "${L[ollama_have]}" "$(ollama --version 2>/dev/null | head -1)"; log_info "$_m"
    else
        log_info "${L[ollama_install]}"
        [[ "$OS_FAMILY" == "alt" ]] && log_warn "${L[ollama_alt_warn]}"
        run "curl -fsSL https://ollama.com/install.sh | sh"
        log_ok "${L[ollama_done]}"
    fi

    # GPU
    log_info "${L[gpu_check]}"
    local gpu; gpu="$(detect_gpu)"
    case "$gpu" in
        loaded)
            log_ok "${L[gpu_loaded]}"
            [[ -n "$GPU_INFO" ]] && { printf -v _m "${L[gpu_details]}" "$GPU_INFO"; log_info "$_m"; }
            ;;
        bus)
            printf -v _m "${L[gpu_bus_noload]}" "$GPU_INFO"; log_warn "$_m"
            log_warn "${L[gpu_install_drv]}"
            log_warn "${L[bot_gpu_warn]}"
            ;;
        none)
            log_warn "${L[gpu_none]}"
            log_warn "${L[bot_gpu_warn]}"
            ;;
    esac

    # Pull model
    local model="gemma2:9b"
    printf -v _m "${L[model_pull]}" "$model"; log_info "$_m"
    run "ollama pull $model"
    printf -v _m "${L[model_ready]}" "$model"; log_ok "$_m"

    # Bot code
    local bot_src="$REPO_DIR/ollama-bot"
    if [[ -d "$bot_src" ]]; then
        printf -v _m "${L[bot_copy]}" "$BOT_DIR"; log_info "$_m"
        run "mkdir -p '$BOT_DIR'"
        # preserve existing .env
        if [[ -f "$BOT_DIR/.env" ]]; then
            run "cp -a '$BOT_DIR/.env' '/tmp/.botenv.keep'"
        fi
        run "cp -a '$bot_src/.' '$BOT_DIR/'"
        if [[ -f "/tmp/.botenv.keep" ]]; then
            run "mv '/tmp/.botenv.keep' '$BOT_DIR/.env'"
            log_info "${L[bot_env_kept]}"
        fi

        # bot venv
        local bvenv="$BOT_DIR/venv"
        if [[ -x "$bvenv/bin/python" ]]; then
            log_info "${L[bot_venv_reuse]}"
        else
            log_info "${L[bot_venv_create]}"
            run "python3 -m venv '$bvenv'"
        fi
        if [[ -f "$bot_src/requirements.txt" ]]; then
            log_info "${L[bot_reqs]}"
            run "'$bvenv/bin/pip' install --upgrade pip"
            run "'$bvenv/bin/pip' install -r '$BOT_DIR/requirements.txt'"
        fi
        run "chown -R '${TARGET_USER}:${TARGET_USER}' '$BOT_DIR'"
        log_ok "${L[bot_installed]}"
    fi
}

# ─── Backup helper ────────────────────────────────────────────────────────────

backup_file() {
    # $1 = path to back up if it exists
    local f="$1"
    [[ -e "$f" ]] || return 0
    local bak
    bak="${f}.bak-$(date +%Y%m%d-%H%M%S)"
    run "cp -a '$f' '$bak'"
    BACKUPS_CREATED+=("$bak")
    printf -v _m "${L[backup_saved]}" "$bak"; log_info "$_m"
}

# ─── Place configs ────────────────────────────────────────────────────────────
# root RNS config → /root/.reticulum/config (the services run as root)
# user RNS config → /home/<user>/reticulum/config? (kept for the venv user CLI)
# nomadnet config → /root/.nomadnetwork/config
# node_name is substituted into the nomadnet config.

place_configs() {
    log_step "${L[s_configs]}"

    local root_rns_dir="/root/.reticulum"
    local nomad_dir="/root/.nomadnetwork"
    local user_rns_dir="/home/${TARGET_USER}/.reticulum"

    run "mkdir -p '$root_rns_dir' '$nomad_dir' '$user_rns_dir'"

    # root reticulum config (anonymize interface name)
    printf -v _m "${L[place_root]}" "$root_rns_dir/config"; log_info "$_m"
    backup_file "$root_rns_dir/config"
    if ! $DRY_RUN; then
        sed -e 's/\[\[RNode LoRa Surgut\]\]/[[RNode LoRa]]/' \
            "$REPO_DIR/configs/reticulum-root/config" > "$root_rns_dir/config"
    fi

    # user reticulum config (for the venv user running rnstatus etc.)
    printf -v _m "${L[place_user]}" "$user_rns_dir/config"; log_info "$_m"
    backup_file "$user_rns_dir/config"
    run "cp -a '$REPO_DIR/configs/reticulum-user/config' '$user_rns_dir/config'"
    run "chown -R '${TARGET_USER}:${TARGET_USER}' '$user_rns_dir'"

    # nomadnet config with node_name substitution
    printf -v _m "${L[place_nomad]}" "$nomad_dir/config"; log_info "$_m"
    backup_file "$nomad_dir/config"
    if ! $DRY_RUN; then
        # escape replacement for sed (only & and / matter here; node name is sanitized)
        local esc_name="${NODE_NAME//\//\\/}"; esc_name="${esc_name//&/\\&}"
        sed -e "s/^node_name = .*/node_name = ${esc_name}/" \
            -e 's/Propagation Node SURGUT/Propagation Node/' \
            "$REPO_DIR/configs/nomadnet/config" > "$nomad_dir/config"
        if grep -q "^node_name = ${NODE_NAME}$" "$nomad_dir/config" 2>/dev/null; then
            printf -v _m "${L[nodename_set]}" "$NODE_NAME"; log_ok "$_m"
        else
            printf -v _m "${L[nodename_failwarn]}" "$nomad_dir/config"; log_warn "$_m"
        fi
    fi

    log_ok "${L[configs_done]}"
}

# ─── Place service code ───────────────────────────────────────────────────────
# messageboard.py        → $VENV_DIR/messageboard.py
# lxmf group script      → $VENV_DIR/lxmf_distribution_group_extended.py
# nomadnet pages/files   → /root/.nomadnetwork/storage/{pages,files}
# .mu shebangs rewritten to the target user's venv python.

place_code() {
    log_step "${L[s_code]}"
    local missing=()

    # messageboard
    if [[ -f "$REPO_DIR/messageboard/messageboard.py" ]]; then
        printf -v _m "${L[place_mb]}" "$VENV_DIR/messageboard.py"; log_info "$_m"
        run "cp -a '$REPO_DIR/messageboard/messageboard.py' '$VENV_DIR/messageboard.py'"
    else
        missing+=("messageboard.py")
    fi

    # lxmf group
    if [[ -f "$REPO_DIR/lxmf-group/lxmf_distribution_group_extended.py" ]]; then
        printf -v _m "${L[place_grp]}" "$VENV_DIR/lxmf_distribution_group_extended.py"; log_info "$_m"
        run "cp -a '$REPO_DIR/lxmf-group/lxmf_distribution_group_extended.py' '$VENV_DIR/lxmf_distribution_group_extended.py'"
    else
        missing+=("lxmf_distribution_group_extended.py")
    fi

    # nomadnet pages & files
    local nomad_storage="/root/.nomadnetwork/storage"
    local pages_dst="$nomad_storage/pages"
    local files_dst="$nomad_storage/files"
    printf -v _m "${L[nomad_storage]}" "$nomad_storage"; log_info "$_m"
    run "mkdir -p '$pages_dst' '$files_dst'"

    if [[ -d "$REPO_DIR/nomadnet-pages/pages" ]]; then
        printf -v _m "${L[copy_pages]}" "$pages_dst"; log_info "$_m"
        run "cp -a '$REPO_DIR/nomadnet-pages/pages/.' '$pages_dst/'"
        # rewrite .mu shebangs to target user's venv python
        if ! $DRY_RUN; then
            printf -v _m "${L[patch_shebang]}" "$pages_dst"; log_info "$_m"
            local mu
            while IFS= read -r -d '' mu; do
                sed -i "1s|^#!.*python3.*|#!${VENV_DIR}/venv/bin/python3|" "$mu"
            done < <(find "$pages_dst" -name '*.mu' -print0)
            run "chmod +x '$pages_dst'/*.mu" || true
        fi
    else
        missing+=("nomadnet-pages")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        printf -v _m "${L[code_incomplete]}" "${missing[*]}"
        $DRY_RUN && log_warn "$_m" || die "$_m"
    fi
    log_ok "${L[code_done]}"
}

# ─── systemd unit generation ──────────────────────────────────────────────────
# Repo units hardcode /home/user/ — substitute the real target user.
# Also generate reticulum.service and lxmf_group.service which are NOT in repo.

install_units() {
    log_step "${L[s_units]}"
    local sysd="/etc/systemd/system"
    local venv="${VENV_DIR}/venv"

    # 1) reticulum.service (rnsd daemon) — not in repo, generate it
    printf -v _m "${L[unit_gen]}" "reticulum.service" "$sysd/reticulum.service"; log_info "$_m"
    if ! $DRY_RUN; then
        cat > "$sysd/reticulum.service" <<UNIT
[Unit]
Description=Reticulum Network Stack Daemon
After=network.target

[Service]
Type=simple
User=root
ExecStart=${venv}/bin/rnsd
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT
    fi

    # 2) lxmf_group.service — not in repo, generate it
    printf -v _m "${L[unit_gen]}" "lxmf_group.service" "$sysd/lxmf_group.service"; log_info "$_m"
    if ! $DRY_RUN; then
        cat > "$sysd/lxmf_group.service" <<UNIT
[Unit]
Description=LXMF Distribution Group
After=network.target reticulum.service
Requires=reticulum.service

[Service]
Type=simple
User=root
WorkingDirectory=${VENV_DIR}
ExecStart=${venv}/bin/python3 ${VENV_DIR}/lxmf_distribution_group_extended.py
Restart=always
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
UNIT
    fi

    # 3) repo units: substitute /home/user/ → /home/<target>/ and anonymize descriptions
    local unit
    for unit in messageboard nomadnet; do
        local src="$REPO_DIR/systemd/${unit}.service"
        [[ -f "$src" ]] || continue
        printf -v _m "${L[unit_installed]}" "${unit}.service"; log_info "$_m"
        if ! $DRY_RUN; then
            sed -e "s#/home/user/#/home/${TARGET_USER}/#g" \
                -e 's/Surgut Message Board/Message Board/' \
                -e 's/Propagation Node SURGUT/Propagation Node/' \
                "$src" > "$sysd/${unit}.service"
        fi
    done

    # 4) bot units only if installing bot
    if $INSTALL_BOT; then
        for unit in ollama surgutbot86; do
            local src="$REPO_DIR/systemd/${unit}.service"
            [[ -f "$src" ]] || continue
            printf -v _m "${L[unit_installed]}" "${unit}.service"; log_info "$_m"
            if ! $DRY_RUN; then
                sed -e "s#/home/user/#/home/${TARGET_USER}/#g" \
                    "$src" > "$sysd/${unit}.service"
            fi
        done
    else
        log_info "${L[bot_units_skip]}"
    fi

    log_info "${L[daemon_reload]}"
    run "systemctl daemon-reload"
    log_ok "${L[units_done]}"
}

# ─── Install management scripts ───────────────────────────────────────────────

install_scripts() {
    log_step "${L[s_scripts]}"
    local dst="/usr/local/bin"
    local s src
    for s in rn f2b fetch-rnode-firmware.sh; do
        src="$REPO_DIR/scripts/$s"
        if [[ ! -f "$src" ]]; then
            printf -v _m "${L[scripts_src_missing]}" "$src"; log_warn "$_m"; continue
        fi
        printf -v _m "${L[installing_script]}" "$s" "$dst/$s"; log_info "$_m"
        run "install -m 0755 '$src' '$dst/$s'"
    done
    # install self as installret.sh for re-runs / --uninstall
    printf -v _m "${L[installing_script]}" "installret.sh" "$dst/installret.sh"; log_info "$_m"
    run "install -m 0755 '$0' '$dst/installret.sh'" || true

    log_ok "${L[scripts_done]}"
}

# ─── Initialize interface language file ───────────────────────────────────────

init_language_file() {
    log_step "${L[s_lang_init]}"
    local lang_file="${VENV_DIR}/.rn_lang"
    printf -v _m "${L[lang_writing]}" "$LANG_CHOICE" "$lang_file"; log_info "$_m"
    if ! $DRY_RUN; then
        run "mkdir -p '$VENV_DIR'"
        echo "$LANG_CHOICE" > "$lang_file"
        run "chown '${TARGET_USER}:${TARGET_USER}' '$lang_file'" || true
    fi
    printf -v _m "${L[lang_done]}" "$LANG_CHOICE"; log_ok "$_m"
}

# ─── First startup ────────────────────────────────────────────────────────────
# Enable + start all services. The LXMF group generates its config.cfg/data.cfg
# on first launch, so we start it, wait, then (later) configure the broadcaster.

ACTIVE_SERVICES=()

first_startup() {
    log_step "${L[s_firststart]}"

    local services=(reticulum.service nomadnet.service messageboard.service lxmf_group.service)
    $INSTALL_BOT && services+=(ollama.service surgutbot86.service)
    ACTIVE_SERVICES=("${services[@]}")

    log_info "${L[enabling]}"
    local svc
    for svc in "${services[@]}"; do
        run "systemctl enable '$svc'" || true
    done

    printf -v _m "${L[starting]}" "3"; log_info "$_m"
    for svc in "${services[@]}"; do
        run "systemctl start '$svc'" || true
        $DRY_RUN || sleep 3
    done

    log_ok "${L[all_started]}"
}

# ─── Broadcaster setup ────────────────────────────────────────────────────────
# Runs AFTER first_startup so the group's config.cfg/data.cfg already exist.
# Generates a fresh broadcaster identity (no hardcoded hashes), then writes the
# broadcaster role into config.cfg and the [broadcaster] section into data.cfg —
# using the exact same logic as scripts/rn.

readonly BC_BROADCASTER_NAME="rn-broadcaster"

get_broadcaster_hash() {
    local id="$1"
    "${VENV_DIR}/venv/bin/rnid" -i "$id" -H lxmf.delivery 2>/dev/null \
        | grep -oiE "is <[0-9a-f]{32}>" | grep -oiE "[0-9a-f]{32}" | head -1
}

setup_broadcaster() {
    log_step "${L[s_broadcaster]}"

    local config_file="${GROUP_CONFIG_DIR}/config.cfg"
    local data_file="${GROUP_CONFIG_DIR}/data.cfg"
    local bc_dir="${VENV_DIR}/rn_broadcaster"
    local bc_id="${bc_dir}/identity"

    if $DRY_RUN; then
        log_info "[dry-run] rnid -g ${bc_id}; add broadcaster role; write [broadcaster] section"
        log_ok "${L[bc_done]}"
        return
    fi

    # Wait for the group to generate its config (up to ~30s)
    log_info "${L[bc_wait_cfg]}"
    local i
    for i in $(seq 1 15); do
        [[ -f "$config_file" && -f "$data_file" ]] && break
        sleep 2
    done
    if [[ ! -f "$config_file" || ! -f "$data_file" ]]; then
        printf -v _m "${L[bc_cfg_missing]}" "$GROUP_CONFIG_DIR"; log_warn "$_m"
        WARN_NOTES+=("broadcaster: group config not generated, configure later via rn [9]")
        return
    fi

    # Generate identity (rnid -g won't overwrite — only create if absent)
    mkdir -p "$bc_dir"
    if [[ -f "$bc_id" ]]; then
        log_info "${L[bc_id_exists]}"
    else
        log_info "${L[bc_gen_id]}"
        if ! "${VENV_DIR}/venv/bin/rnid" -g "$bc_id" >/dev/null 2>&1; then
            log_warn "${L[bc_hash_fail]}"
            WARN_NOTES+=("broadcaster: identity generation failed")
            return
        fi
    fi
    chown -R "${TARGET_USER}:${TARGET_USER}" "$bc_dir" 2>/dev/null || true

    # Resolve hash
    local b_hash; b_hash="$(get_broadcaster_hash "$bc_id")"
    if [[ -z "$b_hash" ]]; then
        log_warn "${L[bc_hash_fail]}"
        WARN_NOTES+=("broadcaster: could not resolve LXMF hash")
        return
    fi
    printf -v _m "${L[bc_hash]}" "$b_hash"; log_info "$_m"

    # Role in config.cfg (same approach as rn)
    if grep -qE "^broadcaster\s*=" "$config_file"; then
        log_info "${L[bc_role_exists]}"
    else
        log_info "${L[bc_role_add]}"
        local admin_line
        admin_line="$(grep -nE "^admin\s*=\s*interface" "$config_file" | head -1 | cut -d: -f1)"
        if [[ -n "$admin_line" ]]; then
            sed -i "${admin_line}a broadcaster = send_local,anonymous" "$config_file"
        else
            sed -i "/^\[rights\]/a broadcaster = send_local,anonymous" "$config_file"
        fi
    fi

    # [broadcaster] section in data.cfg (same Python as rn)
    log_info "${L[bc_section_upd]}"
    python3 - "$data_file" "$b_hash" "$BC_BROADCASTER_NAME" << 'PYEOF'
import sys, re
data_file, new_hash, name = sys.argv[1], sys.argv[2], sys.argv[3]
with open(data_file, "r", encoding="utf-8") as f:
    text = f.read()
new_section = "[broadcaster]\n{} = {}\n\n".format(new_hash, name)
pattern = re.compile(r"\[broadcaster\]\s*\n(?:(?!\[).*\n?)*", re.MULTILINE)
if pattern.search(text):
    text = pattern.sub(new_section, text, count=1)
else:
    m = re.search(r"\[admin\]\s*\n(?:(?!\[).*\n?)*", text)
    if m:
        insert_at = m.end()
        text = text[:insert_at] + "\n" + new_section + text[insert_at:]
    else:
        if not text.endswith("\n"):
            text += "\n"
        text += "\n" + new_section
text = re.sub(r"\n{3,}", "\n\n", text)
with open(data_file, "w", encoding="utf-8") as f:
    f.write(text)
PYEOF

    # Restart the group to apply
    log_info "${L[bc_restart]}"
    systemctl restart lxmf_group.service 2>/dev/null || true
    log_ok "${L[bc_done]}"
}

# ─── fail2ban / f2b setup ─────────────────────────────────────────────────────
# Full automation: generate a PIN for f2b, write jail.local with an sshd jail
# (1h ban) and a recidive jail (1week ban) — bantimes must match scripts/f2b.

setup_f2b() {
    log_step "${L[s_f2b]}"

    # Note: the f2b PIN is intentionally NOT created here — the user sets their
    # own PIN on first run of rn. The installer only prepares fail2ban itself.

    if ! command -v fail2ban-client >/dev/null 2>&1 && [[ ! -d /etc/fail2ban ]]; then
        log_warn "${L[f2b_no_fail2ban]}"
        WARN_NOTES+=("f2b: fail2ban not installed; configure it manually if you want protection")
        return 0
    fi

    if $DRY_RUN; then
        log_info "[dry-run] write /etc/fail2ban/jail.local (sshd + recidive); enable+start fail2ban"
        log_ok "${L[f2b_done]}"
        return 0
    fi

    # Run the whole setup in a guarded subshell so an unexpected failure inside
    # never aborts the installer (set -e safe). We report success/failure after.
    local jail="/etc/fail2ban/jail.local"
    if [[ -f "$jail" ]]; then
        log_info "${L[f2b_jail_exists]}"
        backup_file "$jail"
    else
        log_info "${L[f2b_jail_write]}"
    fi

    # Detect a sane SSH log backend: Kali/modern Debian use systemd journal.
    local ssh_backend="systemd"
    if [[ -f /var/log/auth.log ]]; then
        ssh_backend="auto"
    fi

    if cat > "$jail" <<JAIL
# Managed by installret.sh — Reticulum Node Stack
[DEFAULT]
backend  = ${ssh_backend}
bantime  = ${F2B_SSHD_BANTIME}
findtime = 600
maxretry = 5
# Keep ban history long enough for f2b "total bans" statistics
dbpurgeage = 2592000

[sshd]
enabled  = true
port     = ssh
bantime  = ${F2B_SSHD_BANTIME}
maxretry = 5

[recidive]
enabled  = true
bantime  = ${F2B_RECIDIVE_BANTIME}
findtime = 86400
maxretry = 2
JAIL
    then
        log_info "${L[f2b_enable]}"
        if systemctl enable fail2ban >/dev/null 2>&1 && systemctl restart fail2ban >/dev/null 2>&1; then
            # Verify it actually came up
            sleep 1
            if systemctl is-active fail2ban >/dev/null 2>&1; then
                log_ok "${L[f2b_done]}"
            else
                log_warn "${L[f2b_warn]}"
                WARN_NOTES+=("f2b: fail2ban did not stay active — check: systemctl status fail2ban")
            fi
        else
            log_warn "${L[f2b_warn]}"
            WARN_NOTES+=("f2b: fail2ban failed to (re)start — check: systemctl status fail2ban")
        fi
    else
        log_warn "${L[f2b_warn]}"
        WARN_NOTES+=("f2b: could not write ${jail}")
    fi
    return 0
}

# ─── Health check ─────────────────────────────────────────────────────────────

health_check() {
    log_step "${L[s_health]}"
    if $DRY_RUN; then return; fi

    printf -v _m "${L[warmup]}" "8"; log_info "$_m"
    sleep 8

    local svc state
    for svc in "${ACTIVE_SERVICES[@]}"; do
        state="$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
        if [[ "$state" == "active" ]]; then
            printf -v _m "${L[svc_active]}" "$svc"; log_ok "$_m"
        else
            printf -v _m "${L[svc_state]}" "$svc" "$state"; log_warn "$_m"
            FAILED_SERVICES+=("$svc")
            printf -v _m "${L[svc_journal]}" "$svc"; log_info "$_m"
            journalctl -u "$svc" -n 10 --no-pager 2>/dev/null | sed 's/^/      /' || true
        fi
    done

    # RNS responsiveness
    log_info "${L[check_rns]}"
    if "${VENV_DIR}/venv/bin/rnstatus" >/dev/null 2>&1; then
        log_ok "${L[rns_responded]}"
    else
        log_warn "${L[rns_noresp]}"
    fi

    if $INSTALL_BOT; then
        log_info "${L[check_ollama]}"
        ollama ps >/dev/null 2>&1 || true
    fi

    if [[ ${#FAILED_SERVICES[@]} -eq 0 ]]; then
        log_ok "${L[all_healthy]}"
    else
        printf -v _m "${L[some_failed]}" "${#FAILED_SERVICES[@]}" "${FAILED_SERVICES[*]}"; log_warn "$_m"
        log_info "${L[see_logs]}"
    fi
}

# ─── Summary ──────────────────────────────────────────────────────────────────

print_summary() {
    log_step "${L[s_summary]}"
    echo

    if [[ ${#FAILED_SERVICES[@]} -eq 0 ]]; then
        log_ok "${L[inst_complete]}"
    else
        log_warn "${L[inst_warn]}"
    fi
    echo

    echo "  ${L[sum_node]}  ${NODE_NAME}"
    echo "  ${L[sum_sys]}   ${SYSTEM_NAME}"
    echo "  ${L[sum_os]}    ${OS_PRETTY}"
    echo "  ${L[sum_user]}  ${TARGET_USER}"
    echo "  ${L[sum_repo]}  ${REPO_DIR}"
    echo "  ${L[sum_venv]}  ${VENV_DIR}/venv"
    if $INSTALL_BOT; then
        echo "  ${L[sum_bot]}   SurgutBot86 (${BOT_DIR})"
    else
        echo "  ${L[sum_bot]}   ${L[sum_bot_no]}"
    fi
    echo

    echo "  ${L[sum_services]}"
    local svc state mark
    for svc in "${ACTIVE_SERVICES[@]}"; do
        state="$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
        if [[ "$state" == "active" ]]; then mark="${C_GRN}●${C_RST}"; else mark="${C_RED}●${C_RST}"; fi
        printf "    %b %-26s %s\n" "$mark" "$svc" "$state"
    done
    echo

    echo "  ${L[useful_cmds]}"
    echo "    rn                 — ${L[cmd_rn]}"
    echo "    rn help            — ${L[cmd_rnhelp]}"
    echo "    f2b                — ${L[cmd_f2b]}"
    echo "    ${VENV_DIR}/venv/bin/rnstatus  — ${L[cmd_rnstatus]}"
    echo "    journalctl -u <svc> -e         — ${L[cmd_journal]}"
    echo "    installret.sh                  — ${L[cmd_reinstall]}"
    echo

    if [[ ${#BACKUPS_CREATED[@]} -gt 0 ]]; then
        printf -v _m "${L[backups_made]}" "${#BACKUPS_CREATED[@]}"; echo "  $_m"
        local b
        for b in "${BACKUPS_CREATED[@]}"; do echo "    $b"; done
        echo "  ${L[restore_hint]}"
        echo
    fi

    # Warnings collected through the run
    local notes=("${WARN_NOTES[@]}")
    $TIMEZONE_WARNING && notes+=("${L[tz_reminder]}")
    if $INSTALL_BOT; then
        local gpu; gpu="$(detect_gpu)"
        [[ "$gpu" != "loaded" ]] && notes+=("${L[gpu_reminder]}")
    fi
    if [[ ${#notes[@]} -gt 0 ]]; then
        echo "  ${L[warn_notes_hdr]}"
        local n
        for n in "${notes[@]}"; do echo "    • $n"; done
        echo
    fi

    if [[ ${#FAILED_SERVICES[@]} -eq 0 ]]; then
        log_ok "${L[final_up]}"
    else
        log_warn "${L[final_failed]}"
    fi
}

# ─── Uninstall ────────────────────────────────────────────────────────────────

# Собрать резервную копию всех identity/ключей ПЕРЕД безвозвратным удалением
# данных. Identity нельзя восстановить — потеря = потеря адреса узла/групп/бота
# в сети навсегда. Архивируем всё ценное в /root/reticulum-backup-<дата>.tar.gz.
backup_identities() {
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    BACKUP_FILE="/root/reticulum-backup-${ts}.tar.gz"   # global: used in summary

    # Только identity-файлы (невосстановимые ключи — потеря = потеря адреса
    # узла/групп/бота в сети навсегда). Конфиги, доску, базу не трогаем — они
    # пересоздаются. Берём каждый identity точечно.
    local candidates=(
        "/root/.reticulum/storage/transport_identity"   # транспортный identity узла Reticulum
        "/root/.nomadnetwork/storage/identity"          # NomadNet
        "${GROUP_CONFIG_DIR}/identity"                   # SURGUT GROUP
        "${VENV_DIR}/rn_broadcaster/identity"            # вещатель / broadcaster
    )
    # доп. identity узла Reticulum, если хранятся в storage/identities/
    local f
    for f in /root/.reticulum/storage/identities/*; do
        [ -f "$f" ] && candidates+=("$f")
    done
    # динамические группы, созданные через бота
    local d
    for d in /root/.config/lxmf_group_*/identity; do
        [ -f "$d" ] && candidates+=("$d")
    done
    # identity бота, если бот установлен
    [ -n "$BOT_DIR" ] && [ -f "${BOT_DIR}/config/identity" ] && \
        candidates+=("${BOT_DIR}/config/identity")

    # оставляем только реально существующие файлы
    local existing=()
    local p
    for p in "${candidates[@]}"; do
        [ -f "$p" ] && existing+=("$p")
    done

    if [ "${#existing[@]}" -eq 0 ]; then
        BACKUP_FILE=""      # нечего бэкапить — очищаем флаг
        return 0
    fi

    log_info "${L[un_backup]}"
    # относительные пути (без ведущего '/'), tar от корня — чтобы восстановление
    # ложилось точно в исходные места одной командой tar ... -C /
    local rels=()
    for p in "${existing[@]}"; do
        rels+=("${p#/}")
    done
    if tar -czf "$BACKUP_FILE" -C / "${rels[@]}" 2>/dev/null; then
        chmod 600 "$BACKUP_FILE" 2>/dev/null
    else
        BACKUP_FILE=""      # не удалось — не показываем ложный путь
    fi
}

do_uninstall() {
    log_step "${L[s_uninstall]}"

    if ! $DRY_RUN; then
        if ! confirm un_confirm; then
            log_info "${L[un_aborted]}"; exit 0
        fi
    fi

    # Need target user to know paths
    [[ -z "$TARGET_USER" ]] && detect_target_user

    # Резервная копия identity — ВСЕГДА и без вопросов (ключи невосстановимы).
    # Делается до остановки/удаления, чтобы файлы точно были на месте.
    if ! $DRY_RUN; then
        backup_identities
    fi

    local services=(surgutbot86.service ollama.service lxmf_group.service \
                    messageboard.service nomadnet.service reticulum.service)

    log_info "${L[un_stopping]}"
    local svc
    for svc in "${services[@]}"; do
        run "systemctl stop '$svc' 2>/dev/null" || true
        run "systemctl disable '$svc' 2>/dev/null" || true
    done

    log_info "${L[un_units]}"
    local sysd="/etc/systemd/system"
    for svc in "${services[@]}"; do
        run "rm -f '$sysd/$svc'"
    done
    run "systemctl daemon-reload"

    log_info "${L[un_scripts]}"
    run "rm -f /usr/local/bin/rn /usr/local/bin/f2b /usr/local/bin/fetch-rnode-firmware.sh /usr/local/bin/installret.sh"

    log_info "${L[un_venv]}"
    run "rm -rf '${VENV_DIR}/venv' '${VENV_DIR}/messageboard.py' '${VENV_DIR}/lxmf_distribution_group_extended.py'"

    if $INSTALL_BOT || [[ -d "$BOT_DIR" ]]; then
        log_info "${L[un_bot]}"
        run "rm -rf '$BOT_DIR'"
    fi

    # The PIN and the fail2ban jail config are protection settings, not node
    # data — always remove them so a fresh install truly starts clean (rn will
    # offer to set a new PIN on first run). rn and f2b now share /root/.rn_pin.
    run "rm -f /etc/fail2ban/jail.local '$RN_PIN'"

    # Данные удаляются всегда — снос значит снос. Ценные ключи (identity)
    # уже сохранены в резервную копию выше, остальное (конфиги, доска, база)
    # пересоздаётся при новой установке.
    log_info "${L[un_data]}"
    run "rm -rf '${VENV_DIR}/rn_broadcaster' '${VENV_DIR}/.rn_lang' '${VENV_DIR}/logs'"
    run "rm -rf /root/.reticulum /root/.nomadnetwork '${GROUP_CONFIG_DIR}'"
    # Динамические группы, созданные через бота
    run "rm -rf /root/.config/lxmf_group_*"
    run "rm -rf '$REPO_DIR'"
    # remove the now-empty reticulum dir if nothing else is left in it
    run "rmdir '${VENV_DIR}' 2>/dev/null || true"

    log_ok "${L[un_done]}"

    # Инструкция по резервной копии identity (если она была создана).
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        echo ""
        echo -e "${C_BLU}── ${L[un_backup_title]} ──${C_RST}"
        echo -e "${L[un_backup_saved]}"
        echo -e "  ${C_GRN}${BACKUP_FILE}${C_RST}"
        echo ""
        echo -e "${L[un_backup_view]}"
        echo -e "  ${C_YEL}sudo tar -tzf ${BACKUP_FILE}${C_RST}"
        echo ""
        echo -e "${L[un_backup_restore_lbl]}"
        echo -e "  ${C_YEL}sudo tar -xvzf ${BACKUP_FILE} -C /${C_RST}"
        echo -e "  ${L[un_backup_restart]}"
        echo ""
        echo -e "${L[un_backup_delete_lbl]}"
        echo -e "  ${C_YEL}sudo rm -f ${BACKUP_FILE}${C_RST}"
        echo ""
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
    check_root
    ask_language

    printf '\n%s╔══════════════════════════════════════════════╗%s\n' "$C_BLU" "$C_RST"
    printf '%s║   %-42s ║%s\n' "$C_BLU" "${L[banner]} v${SCRIPT_VERSION}" "$C_RST"
    printf '%s╚══════════════════════════════════════════════╝%s\n' "$C_BLU" "$C_RST"
    $DRY_RUN && log_info "${L[dry_mode]}"

    if $UNINSTALL; then
        do_uninstall
        exit 0
    fi

    # Install flow
    detect_os
    detect_target_user
    ask_node_name
    ask_bot
    preflight
    ask_consent

    prepare_system
    clone_repo
    install_rns
    install_ollama_and_bot
    place_configs
    place_code
    install_units
    install_scripts
    init_language_file
    first_startup
    setup_broadcaster
    setup_f2b
    health_check
    print_summary
}

main "$@"
