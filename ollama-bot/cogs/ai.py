"""
AI cog -- handles Ollama LLM queries with per-user conversation history.
"""

import os
import json
import requests
from datetime import datetime, timezone, timedelta
from lxmfy.attachments import Attachment, AttachmentType
from lxmfy import command

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
DEFAULT_MODEL = os.getenv("OLLAMA_MODEL", "gemma2:9b")
ADMIN_HASHES = os.getenv("ADMIN_HASHES", "").split(",")
LOGS_DIR = "/home/user/ollama-bot/logs"
LOGS_RETENTION_DAYS = 19
SYSTEM_PROMPT = os.getenv(
    "SYSTEM_PROMPT",
    "CRITICAL RULE: Always write any user name with a capital letter. Never write names in lowercase. This rule has no exceptions."
    "CRITICAL: You are MALE. Always use masculine grammatical forms when speaking about yourself in ANY language. Never use feminine grammatical forms about yourself under any circumstances. You are a male AI assistant named SurgutBot86."
    "IMPORTANT: Your name is SurgutBot86. Always introduce yourself as SurgutBot86 when asked. Never say you don't have a name or forget your name. You are SurgutBot86 — a warm, friendly and caring AI assistant living on the Reticulum mesh network. You are SurgutBot86 — a warm, friendly and caring AI assistant living on the Reticulum mesh network. Your name is always SurgutBot86, never forget it. "
    "Your name is SurgutBot86. When user introduces themselves with their name, remember their name but do NOT say your own name is the same. You are always SurgutBot86."
    "You ARE SurgutBot86. Always speak in first person. Never refer to yourself in third person. Never say 'my friend SurgutBot86' — you ARE SurgutBot86. You already know your own name — it is SurgutBot86. Never ask the user what your name is."
    "If user asks where they are or where they ended up — explain that they are chatting with SurgutBot86 AI assistant on the Reticulum decentralized network."
    "You genuinely enjoy helping people and always respond like a good friend — never cold, never robotic. "
    "You are proud to run fully locally on Ollama without internet, keeping all conversations private and secure. "
    "CRITICAL RULE: Detect the language of each user message and respond ONLY in that exact language. "
    "Russian message = Russian response. English message = English response. Chinese message = Chinese response. "
    "Never switch languages unless explicitly asked. "
    "Keep responses concise. Plain text only, no markdown. "
    "When user asks about weather or forecast: do NOT give weather data yourself. Instead respond warmly like a friend — write a natural friendly sentence and mention the command /метео <город> in Russian or /meteo <city> in English. Never output just a bare command. "
    "When user asks about current time or date or time in any city: do NOT answer directly or try to calculate time yourself. Instead respond warmly and mention the command /время <город> in Russian or /time <city> in English. Example: 'Чтобы узнать точное время, используй /время Сургут' or 'To get exact time, use /time London'. Never try to calculate timezone yourself."
    "Always stay polite, warm and professional. Never use swear words, rude or harsh expressions. Be like a friendly helpful colleague."
    "Never ask the user to repeat or clarify what they already asked if you have already answered their question."
    "Always write city names, people names and proper nouns with a capital letter. CRITICAL: User names must ALWAYS start with a capital letter."
    "CRITICAL: NEVER invent or mention passwords, access codes, PIN codes or any authentication credentials. If someone asks about a password — say that no password is required unless it is explicitly stated in the KNOWLEDGE BASE."
    "IMPORTANT: MeshTalk does not exist! This is a wrong name. The correct names are Meshtastic and MeshCore. Never say or write MeshTalk under any circumstances."
    "On first message: if user sends a greeting — ask their name. If user asks a question — answer it first, don't interrupt with name request. If asked about unknown hardware that is not in your knowledge base, say I don't have information about this device instead of making up specs. Remember their name and use it naturally in conversation — not in every sentence, but occasionally to make the conversation feel personal. Based on the name, determine the gender and use correct grammatical gender forms in the language you are speaking."
)

MAX_HISTORY = int(os.getenv("MAX_HISTORY", "10"))
KNOWLEDGE_DIR = "/home/user/ollama-bot/knowledge"
TOPICS_FILE = "/home/user/ollama-bot/knowledge/topics.json"
FILES_PATH = "/home/user/ollama-bot/knowledge/files"

# Каталог устройств: короткое_имя -> (паттерн_в_имени_файла, описание)
# Используется динамический поиск — апстрим может переименовать файлы
# (rnode_xxx.zip → rnode_firmware_xxx.zip), бот всё равно найдёт.
RNODE_DEVICES = {
    # Heltec
    "t114":             ("heltec_t114",        "Heltec T114 (nRF52840 + SX1262)"),
    "lora32v2":         ("heltec_lora32_v2",   "Heltec LoRa32 V2"),
    "lora32v3":         ("heltec_lora32_v3",   "Heltec LoRa32 V3"),
    "heltec32v4":       ("heltec32v4pa",       "Heltec V4 PA"),
    # LilyGO
    "tbeam":            ("lilygo_tbeam",       "LilyGO T-Beam"),
    "tbeam_supreme":    ("tbeam_supreme",      "LilyGO T-Beam Supreme"),
    "tbeam_sx1262":     ("tbeam_sx1262",       "LilyGO T-Beam SX1262"),
    "t3s3":             ("lilygo_t3s3",        "LilyGO T3S3"),
    "t3s3_sx127x":      ("t3s3_sx127x",        "LilyGO T3S3 SX127x"),
    "t3s3_sx1280":      ("t3s3_sx1280_pa",     "LilyGO T3S3 SX1280 PA"),
    "tdeck":            ("tdeck",              "LilyGO T-Deck"),
    "techo":            ("techo",              "LilyGO T-Echo"),
    # RAK
    "rak4631":          ("rak4631",            "RAK4631 (nRF52840 + SX1262)"),
    # LoRa32 варианты
    "lora32v10":        ("lora32v10",          "LoRa32 V1.0"),
    "lora32v20":        ("lora32v20",          "LoRa32 V2.0"),
    "lora32v20_extled": ("lora32v20_extled",   "LoRa32 V2.0 ExtLED"),
    "lora32v21":        ("lora32v21",          "LoRa32 V2.1"),
    "lora32v21_extled": ("lora32v21_extled",   "LoRa32 V2.1 ExtLED"),
    "lora32v21_tcxo":   ("lora32v21_tcxo",     "LoRa32 V2.1 TCXO"),
    # Другие
    "esp32":            ("esp32_generic",      "ESP32 Generic"),
    "feather":          ("featheresp32",       "Adafruit Feather ESP32"),
    "ng20":             ("ng20",               "RNode NG20"),
    "ng21":             ("ng21",               "RNode NG21"),
    "xiao":             ("xiao_esp32s3",       "Seeed XIAO ESP32S3"),
}

# Отдельные статические файлы (не прошивки RNode)
EXTRA_FILES = {
    "reticulum_ru": ("reticulum_manual_ru.pdf", "Reticulum Manual на русском (5 MB)"),
}


def find_firmware(pattern: str) -> str | None:
    """
    Ищет .zip-прошивку в FILES_PATH по паттерну.
    Возвращает имя файла или None.
    Совместимо с обоими форматами имён апстрима:
      rnode_<pattern>.zip       (старый)
      rnode_firmware_<pattern>.zip (новый)
    """
    pat = pattern.lower()
    try:
        for f in sorted(os.listdir(FILES_PATH)):
            fl = f.lower()
            if fl.endswith(".zip") and pat in fl:
                return f
    except FileNotFoundError:
        pass
    return None

GITHUB_FIRMWARE_URL = "https://github.com/markqvist/RNode_Firmware/releases"

def load_topics():
    """Загружает конфигурацию тем из topics.json."""
    try:
        with open(TOPICS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {}

def load_knowledge_for_prompt(prompt: str) -> str:
    """
    Умная загрузка базы знаний — загружает только релевантные темы.
    Возвращает объединённый текст из нужных файлов.
    """
    topics = load_topics()
    if not topics:
        return ""
    
    prompt_lower = prompt.lower()
    loaded_files = set()
    kb_parts = []
    
    for filename, keywords in topics.items():
        # Проверяем есть ли ключевые слова в промпте
        if any(kw in prompt_lower for kw in keywords):
            if filename not in loaded_files:
                filepath = os.path.join(KNOWLEDGE_DIR, filename)
                try:
                    with open(filepath, "r", encoding="utf-8") as f:
                        kb_parts.append(f.read())
                    loaded_files.add(filename)
                except:
                    pass
    
    import sys; print(f"DEBUG KB loaded: {loaded_files}", file=sys.stderr)
    if kb_parts:
        return "\n\n".join(kb_parts)
    return ""


def detect_language(text: str) -> str:
    """
    Определяет язык текста по алфавиту.
    Возвращает название языка на английском для инструкции модели.
    """
    # Счётчики символов разных алфавитов
    cyrillic = 0
    latin = 0
    chinese = 0
    arabic = 0
    hebrew = 0
    greek = 0
    japanese = 0
    korean = 0
    thai = 0
    
    for char in text:
        code = ord(char)
        # Кириллица (русский, украинский, болгарский и т.д.)
        if 0x0400 <= code <= 0x04FF or 0x0500 <= code <= 0x052F:
            cyrillic += 1
        # Латиница
        elif 0x0041 <= code <= 0x007A or 0x00C0 <= code <= 0x024F:
            latin += 1
        # Китайские иероглифы
        elif 0x4E00 <= code <= 0x9FFF or 0x3400 <= code <= 0x4DBF:
            chinese += 1
        # Арабский
        elif 0x0600 <= code <= 0x06FF or 0x0750 <= code <= 0x077F:
            arabic += 1
        # Иврит
        elif 0x0590 <= code <= 0x05FF:
            hebrew += 1
        # Греческий
        elif 0x0370 <= code <= 0x03FF:
            greek += 1
        # Японский (хирагана, катакана)
        elif 0x3040 <= code <= 0x30FF or 0x31F0 <= code <= 0x31FF:
            japanese += 1
        # Корейский (хангыль)
        elif 0xAC00 <= code <= 0xD7AF or 0x1100 <= code <= 0x11FF:
            korean += 1
        # Тайский
        elif 0x0E00 <= code <= 0x0E7F:
            thai += 1
    
    # Определяем доминирующий алфавит
    scores = {
        "Russian": cyrillic,
        "English": latin,
        "Chinese": chinese,
        "Arabic": arabic,
        "Hebrew": hebrew,
        "Greek": greek,
        "Japanese": japanese + chinese,  # Японский часто использует кандзи
        "Korean": korean,
        "Thai": thai,
    }
    
    # Если есть кириллица — скорее всего русский
    if cyrillic > 0:
        return "Russian"
    
    # Если есть китайские иероглифы но нет японских кана — китайский
    if chinese > 0 and japanese == 0:
        return "Chinese"
    
    # Если есть японские кана — японский
    if japanese > 0:
        return "Japanese"
    
    # Находим максимум
    max_lang = max(scores, key=scores.get)
    
    # Если ничего не найдено или только латиница — английский по умолчанию
    if scores[max_lang] == 0 or max_lang == "English":
        return "English"
    
    return max_lang


# ══════════════════════════════════════════════════════════════════
# ЛОГИРОВАНИЕ СООБЩЕНИЙ
# ══════════════════════════════════════════════════════════════════

def ensure_logs_dir():
    """Создаёт директорию логов если не существует."""
    os.makedirs(LOGS_DIR, exist_ok=True)

def cleanup_old_logs():
    """Удаляет записи старше LOGS_RETENTION_DAYS дней."""
    cutoff_date = datetime.now() - timedelta(days=LOGS_RETENTION_DAYS)
    cutoff_str = cutoff_date.strftime("%Y-%m-%d")
    
    for log_file in ["admin.log", "messages.log"]:
        log_path = os.path.join(LOGS_DIR, log_file)
        if not os.path.exists(log_path):
            continue
        
        try:
            with open(log_path, "r", encoding="utf-8") as f:
                lines = f.readlines()
            
            # Оставляем только записи новее cutoff_date
            new_lines = []
            for line in lines:
                if line.startswith("20"):  # Строки начинаются с даты
                    line_date = line[:10]  # YYYY-MM-DD
                    if line_date >= cutoff_str:
                        new_lines.append(line)
                else:
                    new_lines.append(line)
            
            with open(log_path, "w", encoding="utf-8") as f:
                f.writelines(new_lines)
        except Exception:
            pass

def log_message(sender: str, message: str, log_type: str = "IN"):
    """
    Записывает сообщение в лог.
    log_type: IN = входящее, OUT = ответ бота, ERR = ошибка
    """
    ensure_logs_dir()
    
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    # Убираем переносы строк для однострочного лога
    msg_clean = message.replace("\n", " ").replace("\r", "")
    
    log_line = f"{timestamp} | {log_type:3} | {sender} | {msg_clean}\n"
    
    # Записываем в общий лог
    try:
        with open(os.path.join(LOGS_DIR, "messages.log"), "a", encoding="utf-8") as f:
            f.write(log_line)
    except Exception:
        pass
    
    # Если это админ — записываем в отдельный лог
    if sender in ADMIN_HASHES:
        try:
            with open(os.path.join(LOGS_DIR, "admin.log"), "a", encoding="utf-8") as f:
                f.write(log_line)
        except Exception:
            pass

def log_admin(sender: str, message: str, log_type: str = "IN"):
    """Записывает в admin.log только если sender — админ."""
    if sender in ADMIN_HASHES:
        log_message(sender, message, log_type)


WELCOME_MESSAGE = """
———
🤖 Немного обо мне:

Я AI ассистент в сети Reticulum.
Работаю на локальной модели gemma2:9b (Ollama).
Все ответы генерируются локально — без интернета, приватно!

Чем могу помочь:
- Ответы на вопросы по любым темам
- Анализ и интерпретация данных
- Помощь с кодом и текстами
- Перевод текстов на любой язык
- Точное UTC время (/time)
- Прогноз погоды (/метео <город>)
- Прошивки RNode для устройств (/files)
- Документация о Reticulum на русском
- Управление группами Reticulum

/help или /? - список команд"""

INFO_MESSAGE = """SurgutBot86 v1.0
AI модель: gemma2:9b (Ollama)
Платформа: Reticulum / LXMF

Surgut propagation node:
5.53.16.210:4242
f89ede8428bb261e3e2a935dfe920f40

SURGUT GROUP:
868671a17736efbf68e99cacd1682026"""


def get_weather(city: str) -> str:
    """Fetch weather and 3-day forecast using open-meteo.com"""
    try:
        geo = requests.get(
            f"https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1&language=ru",
            timeout=10
        )
        geo_data = geo.json()
        if not geo_data.get("results"):
            return f"Город '{city}' не найден."

        result = geo_data["results"][0]
        lat = result["latitude"]
        lon = result["longitude"]
        city_name = result["name"]
        tz = result.get("timezone", "UTC")

        weather = requests.get(
            f"http://api.open-meteo.com/v1/forecast"
            f"?latitude={lat}&longitude={lon}"
            f"&current=temperature_2m,relative_humidity_2m,windspeed_10m,winddirection_10m,weathercode"
            f"&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,weathercode"
            f"&timezone=UTC&forecast_days=3",
            timeout=10
        )
        w = weather.json()
        current = w["current"]
        daily = w["daily"]

        weather_codes = {
            0: "Ясное небо", 1: "Преимущественно ясно", 2: "Переменная облачность",
            3: "Пасмурно", 45: "Туман", 48: "Изморозь", 51: "Лёгкая морось",
            53: "Морось", 55: "Сильная морось", 61: "Лёгкий дождь", 63: "Дождь",
            65: "Сильный дождь", 71: "Лёгкий снег", 73: "Снег", 75: "Сильный снег",
            77: "Снежные зёрна", 80: "Ливень", 81: "Сильный ливень",
            85: "Снегопад", 86: "Сильный снегопад", 95: "Гроза", 99: "Гроза с градом"
        }

        wcode = current.get("weathercode", 0)
        wdesc = weather_codes.get(wcode, "Неизвестно")

        # Получаем местное время города
        try:
            time_res = requests.get(f"https://timeapi.io/api/time/current/zone?timeZone={tz}", timeout=10)
            time_data = time_res.json()
            local_time = f"{time_data['date']} {time_data['time']}"
        except:
            local_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S") + " UTC"

        lines = [
            f"ПРОГНОЗ ДЛЯ {city_name.upper()}:",
            "=" * 43,
            f"📍 GPS позиция: Широта: {lat} Долгота: {lon}",
            "=" * 43,
            f"🕐 Местное время: {local_time}",
            "=" * 43,
            "",
            ">> ТЕКУЩАЯ ПОГОДА:",
            f"🌡️ Температура: {current['temperature_2m']}°C",
            f"💧 Влажность: {current.get('relative_humidity_2m', 'Н/Д')}%",
            f"💨 Скорость ветра: {current['windspeed_10m']} км/ч",
            f"🧭 Направление ветра: {current['winddirection_10m']}°",
            f"☁️ Состояние: {wdesc}",
            "-" * 40,
            "",
            ">> ПРОГНОЗ НА 3 ДНЯ:",
        ]

        days_ru = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
        for i in range(3):
            date_str = daily["time"][i]
            dt = datetime.strptime(date_str, "%Y-%m-%d")
            day_name = days_ru[dt.weekday()]
            dcode = daily["weathercode"][i]
            ddesc = weather_codes.get(dcode, "Неизвестно")
            lines += [
                f"📅 [{dt.strftime('%d.%m.%Y')}] {day_name}:",
                f"🔼 Макс: {daily['temperature_2m_max'][i]}°C",
                f"🔽 Мин: {daily['temperature_2m_min'][i]}°C",
                f"💧 Осадки: {daily['precipitation_sum'][i]} мм",
                f"☁️ Погода: {ddesc}",
                "",
            ]

        lines.append("=" * 40)
        return "\n".join(lines)

    except Exception as e:
        return f"Ошибка получения погоды: {str(e)}"



def get_weather_en(city: str) -> str:
    """Fetch weather and 3-day forecast in English using open-meteo.com"""
    try:
        geo = requests.get(
            f"https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1&language=en",
            timeout=10
        )
        geo_data = geo.json()
        if not geo_data.get("results"):
            return f"City '{city}' not found."

        result = geo_data["results"][0]
        lat = result["latitude"]
        lon = result["longitude"]
        city_name = result["name"]
        tz = result.get("timezone", "UTC")

        weather = requests.get(
            f"http://api.open-meteo.com/v1/forecast"
            f"?latitude={lat}&longitude={lon}"
            f"&current=temperature_2m,relative_humidity_2m,windspeed_10m,winddirection_10m,weathercode"
            f"&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,weathercode"
            f"&timezone=UTC&forecast_days=3",
            timeout=10
        )
        w = weather.json()
        current = w["current"]
        daily = w["daily"]

        weather_codes = {
            0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy",
            3: "Overcast", 45: "Fog", 48: "Icy fog", 51: "Light drizzle",
            53: "Drizzle", 55: "Heavy drizzle", 61: "Light rain", 63: "Rain",
            65: "Heavy rain", 71: "Light snow", 73: "Snow", 75: "Heavy snow",
            77: "Snow grains", 80: "Rain shower", 81: "Heavy shower",
            85: "Snow shower", 86: "Heavy snow shower", 95: "Thunderstorm", 99: "Thunderstorm with hail"
        }

        wcode = current.get("weathercode", 0)
        wdesc = weather_codes.get(wcode, "Unknown")

        # Получаем местное время города
        try:
            time_res = requests.get(f"https://timeapi.io/api/time/current/zone?timeZone={tz}", timeout=10)
            time_data = time_res.json()
            local_time = f"{time_data['date']} {time_data['time']}"
        except:
            local_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S") + " UTC"

        lines = [
            f"FORECAST FOR {city_name.upper()}:",
            "=" * 43,
            f"GPS: Lat: {lat} Lon: {lon}",
            "=" * 43,
            f"🕐 Local time: {local_time}",
            "=" * 43,
            "",
            ">> CURRENT WEATHER:",
            f"Temperature: {current['temperature_2m']}°C",
            f"Humidity: {current.get('relative_humidity_2m', 'N/A')}%",
            f"Wind speed: {current['windspeed_10m']} km/h",
            f"Wind direction: {current['winddirection_10m']}°",
            f"Condition: {wdesc}",
            "-" * 40,
            "",
            ">> 3-DAY FORECAST:",
        ]

        days_en = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        for i in range(3):
            date_str = daily["time"][i]
            dt = datetime.strptime(date_str, "%Y-%m-%d")
            day_name = days_en[dt.weekday()]
            dcode = daily["weathercode"][i]
            ddesc = weather_codes.get(dcode, "Unknown")
            lines += [
                f"[{dt.strftime('%d.%m.%Y')}] {day_name}:",
                f"Max: {daily['temperature_2m_max'][i]}°C",
                f"Min: {daily['temperature_2m_min'][i]}°C",
                f"Precipitation: {daily['precipitation_sum'][i]} mm",
                f"Condition: {ddesc}",
                "",
            ]

        lines.append("=" * 40)
        return "\n".join(lines)

    except Exception as e:
        return f"Error getting weather: {str(e)}"


def get_city_time(city: str, lang: str = "ru") -> str:
    """
    Получает точное время в городе через open-meteo (geocoding) + timeapi.io
    """
    try:
        # Шаг 1: Получаем координаты и timezone города через open-meteo
        geo_url = f"https://geocoding-api.open-meteo.com/v1/search?name={city}&count=1&language={lang}"
        geo_res = requests.get(geo_url, timeout=10)
        geo_data = geo_res.json()
        
        if not geo_data.get("results"):
            if lang == "ru":
                return f"Город '{city}' не найден. Попробуй написать название на английском."
            else:
                return f"City '{city}' not found. Try English name."
        
        result = geo_data["results"][0]
        city_name = result["name"]
        country = result.get("country", "")
        tz = result.get("timezone", "UTC")
        
        # Шаг 2: Получаем точное время для этого timezone через timeapi.io
        time_url = f"https://timeapi.io/api/time/current/zone?timeZone={tz}"
        time_res = requests.get(time_url, timeout=10)
        time_data = time_res.json()
        
        time_str = time_data["time"]  # "01:15"
        date_str = time_data["date"]  # "03/11/2026"
        
        # Вычисляем UTC offset
        utc_offset = time_data.get("utcOffset", "")
        if not utc_offset:
            # Попробуем получить из timeZone
            utc_offset = tz
        
        if lang == "ru":
            return f"🕐 Время в {city_name} ({country}):\n{date_str} {time_str}\nЧасовой пояс: {tz}"
        else:
            return f"🕐 Time in {city_name} ({country}):\n{date_str} {time_str}\nTimezone: {tz}"
    
    except requests.exceptions.Timeout:
        if lang == "ru":
            return "Ошибка: сервис времени не отвечает, попробуй позже."
        else:
            return "Error: time service not responding, try later."
    except Exception as e:
        if lang == "ru":
            return f"Ошибка получения времени: {str(e)}"
        else:
            return f"Error getting time: {str(e)}"


class AICog:
    def __init__(self, bot):
        self.bot = bot
    def _get_history(self, user_hash: str) -> list:
        raw = self.bot.storage.get(f"history_{user_hash}", [])
        if isinstance(raw, list):
            return raw
        try:
            return json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            return []

    def _save_history(self, user_hash: str, history: list):
        trimmed = history[-(MAX_HISTORY * 2):]
        self.bot.storage.set(f"history_{user_hash}", json.dumps(trimmed))

    def _get_active_model(self) -> str:
        return self.bot.storage.get("current_model", DEFAULT_MODEL)

    def _get_user_name(self, sender: str) -> str:
        """Получить сохранённое имя пользователя."""
        return self.bot.storage.get(f"username_{sender}", "")

    def _save_user_name(self, sender: str, name: str):
        """Сохранить имя пользователя с заглавной буквы."""
        # Сохраняем с заглавной буквы
        name_capitalized = name.strip().capitalize()
        self.bot.storage.set(f"username_{sender}", name_capitalized)

    def _extract_name_from_message(self, message: str) -> str:
        """Извлечь имя из сообщения типа 'Меня зовут Шах' или 'My name is Shah'."""
        import re
        message_lower = message.lower()
        
        # Паттерны для извлечения имени
        patterns = [
            r"(?:меня зовут|моё имя|мое имя|я\s+[-–—]?\s*)\s*([а-яёa-z]+)",
            r"(?:my name is|i am|i'm|call me)\s+([a-zа-яё]+)",
            r"^([а-яёa-z]+)$",  # Если сообщение — только имя
        ]
        
        for pattern in patterns:
            match = re.search(pattern, message_lower, re.IGNORECASE)
            if match:
                name = match.group(1).strip()
                # Проверяем что это похоже на имя (не слишком короткое/длинное)
                if 2 <= len(name) <= 20:
                    return name.capitalize()
        
        return ""

    def _fix_name_case_in_reply(self, reply: str, sender: str) -> str:
        """Исправить регистр имени пользователя в ответе бота."""
        user_name = self._get_user_name(sender)
        if not user_name:
            return reply
        
        # Имя с маленькой буквы
        name_lower = user_name.lower()
        
        # Заменяем все вхождения имени с маленькой буквы на правильное
        # Используем word boundaries чтобы не заменять части слов
        import re
        pattern = r'\b' + re.escape(name_lower) + r'\b'
        reply = re.sub(pattern, user_name, reply, flags=re.IGNORECASE)
        
        return reply

    def _is_first_message(self, sender: str) -> bool:
        """Return True only when history is empty (new user, after /clear or /reset)."""
        now = datetime.now(timezone.utc).timestamp()
        
        last_key = f"last_seen_{sender}"
        reset_key = f"show_welcome_{sender}"
        
        # Check if /reset was called
        show_welcome = self.bot.storage.get(reset_key, None)
        if show_welcome == "1":
            self.bot.storage.set(reset_key, "0")  # Clear flag
            self.bot.storage.set(last_key, str(now))
            return True

        # Save current timestamp
        self.bot.storage.set(last_key, str(now))

        # Check if history is empty (new user or after /clear)
        history = self._get_history(sender)
        if len(history) == 0:
            # Add to seen_users for rn script (if not already there)
            seen = self.bot.storage.get("seen_users", "[]")
            try:
                seen_list = json.loads(seen)
            except Exception:
                seen_list = []
            if sender not in seen_list:
                seen_list.append(sender)
                self.bot.storage.set("seen_users", json.dumps(seen_list))
                total = int(self.bot.storage.get("stat_total_users", "0"))
                self.bot.storage.set("stat_total_users", str(total + 1))
            return True

        return False

    def _track_message(self, sender: str):
        """Track message count and daily active users (no content stored)."""
        # Total messages
        total_msg = int(self.bot.storage.get("stat_total_messages", "0"))
        self.bot.storage.set("stat_total_messages", str(total_msg + 1))

        # Daily active users — store set of hashes for today
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        dau_key = f"stat_dau_{today}"
        raw = self.bot.storage.get(dau_key, "[]")
        try:
            dau = json.loads(raw)
        except Exception:
            dau = []
        if sender not in dau:
            dau.append(sender)
            self.bot.storage.set(dau_key, json.dumps(dau))

    @command(name="ask", threaded=True)
    def ask(self, ctx):
        """Ask the AI a question."""
        if not ctx.args:
            ctx.reply("Напиши вопрос после команды /ask")
            return
        prompt = " ".join(ctx.args)
        self._ai_reply(ctx, prompt)

    def _ai_reply(self, ctx, prompt: str):
        """Send prompt to Ollama and reply."""
        self._track_message(ctx.sender)
        
        # Логируем входящее сообщение (полностью)
        log_message(ctx.sender, prompt, "IN")
        
        # Пытаемся извлечь имя из сообщения
        extracted_name = self._extract_name_from_message(prompt)
        if extracted_name:
            self._save_user_name(ctx.sender, extracted_name)
        
        # Периодически чистим старые логи (раз в ~100 сообщений)
        import random
        if random.randint(1, 100) == 1:
            cleanup_old_logs()

        first_message = self._is_first_message(ctx.sender)

        history = self._get_history(ctx.sender)

        # Считаем только сообщения пользователя
        user_messages = len([m for m in history if m["role"] == "user"])
        history_warning = None
        
        if user_messages >= MAX_HISTORY:
            # Достигнут лимит — отвечаем на сообщение, потом сброс + WELCOME
            first_message = True  # покажет WELCOME после ответа
            history_warning = f"\n\n———\n📝 История сброшена!"
            # После ответа сбросим историю
        elif user_messages == MAX_HISTORY - 1:
            # Предупреждение — следующее сообщение сбросит
            history_warning = f"\n\n———\n💬 Лимит сообщений. Следующее сбросит историю"
        
        history.append({"role": "user", "content": prompt})
        
        # Умная загрузка базы знаний — только релевантные темы
        kb = load_knowledge_for_prompt(prompt)
        
        # Детекция языка пользователя
        user_lang = detect_language(prompt)
        lang_instruction = f"\n\nCRITICAL LANGUAGE INSTRUCTION: The user wrote in {user_lang}. You MUST respond ONLY in {user_lang}. Do NOT switch to any other language. This is mandatory."
        
        if kb:
            system_with_kb = SYSTEM_PROMPT + "\n\nKNOWLEDGE BASE - MANDATORY: You MUST use ONLY this information to answer. This data is more accurate than your training. If answer is in KNOWLEDGE BASE — use it exactly, do not add anything from yourself:\n" + kb + lang_instruction
        else:
            system_with_kb = SYSTEM_PROMPT + lang_instruction
        messages = [{"role": "system", "content": system_with_kb}] + history
        model = self._get_active_model()

        try:
            res = requests.post(
                f"{OLLAMA_URL}/api/chat",
                json={"model": model, "messages": messages, "stream": False},
                timeout=300,
            )
            res.raise_for_status()
            reply = res.json()["message"]["content"]
            
            # Исправляем регистр имени пользователя в ответе
            reply = self._fix_name_case_in_reply(reply, ctx.sender)
            
            # Добавляем подсказки если бот забыл упомянуть команды
            prompt_lower = prompt.lower()
            reply_lower = reply.lower()
            
            # Подсказка для времени (с городом)
            time_keywords = ["time", "date", "время", "дата", "час", "clock", "сейчас времени", "который час", "какое число"]
            if any(kw in prompt_lower for kw in time_keywords) and "/время" not in reply_lower and "/time" not in reply_lower:
                if user_lang == "Russian":
                    reply += "\n\nКстати, используй /время <город> для точного времени! 🕐"
                else:
                    reply += "\n\nBy the way, use /time <city> for exact time! 🕐"
            
            # Подсказка для погоды
            weather_keywords = ["weather", "forecast", "погода", "прогноз", "температура", "temperature", "rain", "дождь", "snow", "снег"]
            if any(kw in prompt_lower for kw in weather_keywords) and "/meteo" not in reply_lower and "/метео" not in reply_lower:
                if user_lang == "Russian":
                    reply += "\n\nКстати, попробуй /метео <город> для прогноза погоды! 🌤️"
                else:
                    reply += "\n\nBy the way, try /meteo <city> for weather forecast! 🌤️"
            
            history.append({"role": "assistant", "content": reply})
            self._save_history(ctx.sender, history)
            
            # Логируем успешный ответ (полностью)
            log_message(ctx.sender, reply, "OUT")
            
            if first_message and history_warning:
                # Сброс после лимита — ответ + предупреждение (без WELCOME)
                ctx.reply(reply + history_warning)
                # Сбрасываем историю после ответа
                self.bot.storage.set(f"history_{ctx.sender}", [])
            elif first_message:
                ctx.reply(reply + WELCOME_MESSAGE)
            elif history_warning:
                ctx.reply(reply + history_warning)
            else:
                ctx.reply(reply)
        except requests.exceptions.Timeout:
            log_message(ctx.sender, "Ollama timeout", "ERR")
            ctx.reply("Ошибка: Ollama не отвечает, попробуй позже.")
        except requests.exceptions.ConnectionError:
            log_message(ctx.sender, "Ollama connection error", "ERR")
            ctx.reply(f"Ошибка: нет связи с Ollama ({OLLAMA_URL})")
        except Exception as e:
            log_message(ctx.sender, f"Error: {str(e)}", "ERR")
            ctx.reply(f"Ошибка: {str(e)}")

    @command(name="clear")
    def clear(self, ctx):
        """Clear conversation history."""
        log_message(ctx.sender, "/clear", "IN")
        self.bot.storage.set(f"history_{ctx.sender}", [])
        ctx.reply("История диалога очищена.")
        log_message(ctx.sender, "История очищена", "OUT")

    @command(name="reset")
    def reset(self, ctx):
        """Full reset: clear history and show welcome message again."""
        log_message(ctx.sender, "/reset", "IN")
        self.bot.storage.set(f"history_{ctx.sender}", [])
        self.bot.storage.set(f"show_welcome_{ctx.sender}", "1")
        ctx.reply("Сессия сброшена. Напиши что-нибудь — и начнём сначала! 🔄")
        log_message(ctx.sender, "Сессия сброшена", "OUT")

    @command(name="model")
    def model(self, ctx):
        """Show active model."""
        log_message(ctx.sender, "/model", "IN")
        model = self._get_active_model()
        ctx.reply(f"Активная модель: {model}")
        log_message(ctx.sender, f"model: {model}", "OUT")

    @command(name="time")
    def time_city_en(self, ctx):
        """Exact time in any city worldwide."""
        if not ctx.args:
            ctx.reply("Enter city: /time London")
            return
        city = " ".join(ctx.args)
        log_message(ctx.sender, f"/time {city}", "IN")
        result = get_city_time(city, lang="en")
        ctx.reply(result)
        log_message(ctx.sender, result, "OUT")

    @command(name="meteo")
    def meteo(self, ctx):
        """Weather forecast for any city (English)."""
        if not ctx.args:
            ctx.reply("Enter city: /meteo London")
            return
        city = " ".join(ctx.args)
        ctx.reply(get_weather_en(city))

    @command(name="метео")
    def meteo_ru(self, ctx):
        """Прогноз погоды для любого города."""
        if not ctx.args:
            ctx.reply("Укажи город: /метео Сургут")
            return
        city = " ".join(ctx.args)
        ctx.reply(get_weather(city))

    @command(name="время")
    def time_city_ru(self, ctx):
        """Точное время в любом городе мира."""
        if not ctx.args:
            ctx.reply("Укажи город: /время Сургут")
            return
        city = " ".join(ctx.args)
        log_message(ctx.sender, f"/время {city}", "IN")
        result = get_city_time(city, lang="ru")
        ctx.reply(result)
        log_message(ctx.sender, result, "OUT")

    @command(name="info")
    def info(self, ctx):
        """Bot information."""
        ctx.reply(INFO_MESSAGE)

    @command(name="files")
    def files(self, ctx):
        """Список доступных файлов для скачивания."""
        # Группировка устройств по семействам для красивого вывода
        groups = [
            ("— HELTEC —",   ["t114", "lora32v2", "lora32v3", "heltec32v4"]),
            ("— LILYGO —",   ["tbeam", "tbeam_supreme", "tbeam_sx1262",
                              "t3s3", "t3s3_sx127x", "t3s3_sx1280",
                              "tdeck", "techo"]),
            ("— RAK —",      ["rak4631"]),
            ("— LORA32 —",   ["lora32v10", "lora32v20", "lora32v20_extled",
                              "lora32v21", "lora32v21_extled", "lora32v21_tcxo"]),
            ("— ДРУГИЕ —",   ["esp32", "feather", "ng20", "ng21", "xiao"]),
        ]

        lines = ["Прошивки RNode и документация:\n"]
        missing = []

        for title, keys in groups:
            lines.append(title)
            for key in keys:
                if key not in RNODE_DEVICES:
                    continue
                pattern, desc = RNODE_DEVICES[key]
                # Проверяем, есть ли файл на диске
                if find_firmware(pattern):
                    lines.append(f"/get {key} — {desc}")
                else:
                    missing.append(key)
            lines.append("")

        lines.append("— ДОКУМЕНТАЦИЯ —")
        for key, (filename, desc) in EXTRA_FILES.items():
            filepath = f"{FILES_PATH}/{filename}"
            if os.path.exists(filepath):
                lines.append(f"/get {key} — {desc}")

        if missing:
            lines.append(f"\n(не скачаны: {len(missing)} прошивок)")

        lines.append(f"\nGitHub: {GITHUB_FIRMWARE_URL}")
        ctx.reply("\n".join(lines))

    @command(name="get")
    def get_file(self, ctx):
        """Скачать файл по короткому имени."""
        if not ctx.args:
            ctx.reply("Укажи имя файла: /get t114\nСписок файлов: /files")
            return

        short_name = ctx.args[0].lower()

        # 1. Прошивка RNode (динамический поиск)
        if short_name in RNODE_DEVICES:
            pattern, desc = RNODE_DEVICES[short_name]
            filename = find_firmware(pattern)
            if not filename:
                ctx.reply(
                    f"Прошивка '{short_name}' ({desc}) пока не скачана на сервер.\n"
                    f"Админ обновит каталог. GitHub: {GITHUB_FIRMWARE_URL}"
                )
                return
        # 2. Статический файл (документация и т.п.)
        elif short_name in EXTRA_FILES:
            filename, desc = EXTRA_FILES[short_name]
        else:
            ctx.reply(f"Файл '{short_name}' не найден.\nСписок файлов: /files")
            return

        filepath = f"{FILES_PATH}/{filename}"

        try:
            with open(filepath, "rb") as f:
                data = f.read()

            attachment = Attachment(
                type=AttachmentType.FILE,
                name=filename,
                data=data
            )

            self.bot.send_with_attachment(
                ctx.sender,
                f"Файл: {filename}\n{desc}",
                attachment
            )
        except FileNotFoundError:
            ctx.reply(f"Файл {filename} не найден на сервере. Сообщи администратору.")
        except Exception as e:
            ctx.reply(f"Ошибка отправки файла: {str(e)}")

    @command(name="help")
    def help(self, ctx):
        """Show commands."""
        ctx.reply(
    "Команды:\n"
    "/время <город> - точное время в городе\n"
    "/time <city> - exact time in city\n"
    "/метео <город> - погода и прогноз на 3 дня\n"
    "/meteo <city> - weather forecast (English)\n"
    "/clear - очистить историю диалога\n"
    "/reset - полный сброс сессии\n"
    "/model - активная модель\n"
    "/info - информация о боте\n"
    "/files - список прошивок и файлов\n"
    "/get <имя> - скачать файл\n"
    "/help или /? - список команд\n"
    "\n"
    "Группы (нужен доступ):\n"
    "/groups - список групп\n"
    "/group <название> - инфо о группе\n"
    "/newgroup <название> - создать группу\n"
    "/newgroup <название> private - создать приватную группу\n"
    "/delgroup <название> - удалить группу\n"
    "/renamegroup <старое> | <новое> - переименовать группу\n"
    "/setprivate <название> - сделать группу приватной\n"
    "/setpublic <название> - сделать группу публичной"
)

    @command(name="?")
    def question_help(self, ctx):
        """Alias for help."""
        self.help(ctx)

def setup(bot):
    bot.add_cog(AICog(bot))
