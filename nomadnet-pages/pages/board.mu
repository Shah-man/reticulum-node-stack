#!/home/user/reticulum/venv/bin/python3
import time
import os
import RNS.vendor.umsgpack as msgpack
message_board_peer = 'c76898104199338222202073aa63375b'
userdir = os.path.expanduser("~")
if os.path.isdir("/etc/nomadmb") and os.path.isfile("/etc/nomadmb/config"):
    configdir = "/etc/nomadmb"
elif os.path.isdir(userdir+"/.config/nomadmb") and os.path.isfile(userdir+"/.config/nomadmb/config"):
    configdir = userdir+"/.config/nomadmb"
else:
    configdir = userdir+"/.nomadmb"
storagepath  = configdir+"/storage"
if not os.path.isdir(storagepath):
    os.makedirs(storagepath)
boardpath = configdir+"/storage/board"

# Counter (подсчёт без отображения)
_cdir = os.path.expanduser("~/.nomadnetwork/storage/counters")
os.makedirs(_cdir, exist_ok=True)
try:
    with open(_cdir+"/board.txt") as _f: _c = int(_f.read())
except: _c = 0
_c += 1
open(_cdir+"/board.txt", "w").write(str(_c))

print("`c`Ff80`bДоска объявлений города Сургут`b")
print("`c`Ffd0════════════════════════════")
print(" ")
print("`c`F5f0 `[>> Мост Meshtastic-Reticulum <<`:/page/guide.mu] `Ff33●`a")
print(" ")
print("`F5bfРазместить объявление:`F5f0`[lxmf@{}]".format(message_board_peer))
time_string = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time()))
print("`Fa8fUpdated: {}".format(time_string))
print("`a")
print("`F2af────────────────────────────")
print("`F5bf📌 `FdddДобро пожаловать в сеть Reticulum города Сургут! Это публичная доска объявлений.")
print("`F2af────────────────────────────")
print("`F5bf📌 `FdddВступить в SURGUT GROUP:`F5f0`[lxmf@868671a17736efbf68e99cacd1682026]")
print("`F2af────────────────────────────")
print("`a")
print("`F0df`bСообщения пользователей:`b`a")
print("`F2af────────────────────────────")
if os.path.isfile(boardpath):
    f = open(boardpath, "rb")
    board_contents = msgpack.unpack(f)
    board_contents.reverse()
    for content in board_contents:
        print("`Fddd{}".format(content.rstrip()))
        print("`F2af────────────────────────────")
    f.close()
else:
    print("`F888  No messages yet. Be the first!")
print("`a")
print("`c`Ffd0════════════════════════════")
print("`c`Ff80Доска объявлений города Сургут")
