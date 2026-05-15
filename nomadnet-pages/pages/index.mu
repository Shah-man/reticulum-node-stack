#!/home/user/reticulum/venv/bin/python3
import os

counter_dir = os.path.expanduser("~/.nomadnetwork/storage/counters")
os.makedirs(counter_dir, exist_ok=True)
counter_file = counter_dir + "/index.txt"
backup_file = counter_dir + "/index.bak"

# Читаем счётчик с бэкапом
try:
    with open(counter_file) as f:
        count = int(f.read().strip())
except:
    # Пробуем бэкап
    try:
        with open(backup_file) as f:
            count = int(f.read().strip())
    except:
        count = 10000  # Дефолт если всё пропало

count += 1

# Сохраняем с бэкапом
open(backup_file, "w").write(str(count))
open(counter_file, "w").write(str(count))

def ru_decline(n):
    if 11 <= n % 100 <= 19:
        return f"{n} просмотров"
    r = n % 10
    if r == 1:
        return f"{n} просмотр"
    elif 2 <= r <= 4:
        return f"{n} просмотра"
    else:
        return f"{n} просмотров"

print("`c`F2af`bСургутский узел Reticulum`b")
print("`c`F555═══════════════════════════════════")
print("`c`F0df Добро пожаловать!")
print(f"`c`F888{ru_decline(count)}")
print("`a")
print("`F5f0 `[>> Доска объявлений <<`:/page/board.mu] `Ff33●`a")
print(" ")
print("`b`F5bf Об узле:`b")
print(" ")
print("`FaaaЭто узел ретрансляции Reticulum, расположенный в `F5f0городе Сургут,")
print("`F5f0ХМАО-Югра, Россия.`a")
print("`FaaaУзел хранит и пересылает сообщения для локальной сети.")
print(" ")
print("`b`F5bf Сервисы:`b")
print(" ")
print("`Fddd- SURGUT GROUP:`F5f0`[lxmf@868671a17736efbf68e99cacd1682026]")
print("`Fddd- Узел ретрансляции - хранение и пересылка сообщений")
print("`Fddd- Доступен 24/7")
print("`Fddd- AI ассистент:")
print("`Fddd  SurgutBot86:`F5f0`[lxmf@1133a876c8b6419d6882248e129fb950]")
print(" ")
print("`b`F5bf Подключение:`b")
print(" ")
print("`FdddРадио: 868.7625 MHz, SF7, BW125, CR7, 22dBm")
print("`FdddTCP:   5.53.16.210:4242")
print(" ")
print("`b`F5bf Узел ретрансляции:`b")
print(" ")
print("`FaaaЧтобы получать сообщения когда вы офлайн,")
print("`Faaaдобавьте этот адрес как узел ретрансляции")
print("`Faaaв настройках вашего LXMF клиента:")
print("`F5f0f89ede8428bb261e3e2a935dfe920f40")
print(" ")
print("`b`F5bf Конфигурация Reticulum:`b")
print(" ")
print("`F888[[Surgut86 TCP]]")
print("`F888  type = TCPClientInterface")
print("`F888  enabled = yes")
print("`F888  target_host = 5.53.16.210")
print("`F888  target_port = 4242")
print(" ")
print("`b`Ff55 Правила:`b")
print(" ")
print("`Fddd1. Уважайте других участников")
print("`Fddd2. Не рассылайте спам")
print("`Fddd3. Помогайте новичкам")
print(" ")
print("`c`F888 --- Powered by Reticulum ---")
