#!/usr/bin/env python3
"""
Surgut Message Board - простая версия
"""

import RNS
import LXMF
import os
import time
import gc
import RNS.vendor.umsgpack as msgpack

# Конфигурация
DISPLAY_NAME = "MSG Board Surgut"
MAX_MESSAGES = 50
CHECK_INTERVAL = 10
COOLDOWN_SECONDS = 60
ANNOUNCE_INTERVAL = 7 * 24 * 60 * 60
ANNOUNCE_FILE = os.path.expanduser("~/.nomadmb/storage/last_announce")

# Пути
CONFIG_DIR = os.path.expanduser("~/.nomadmb")
STORAGE_DIR = os.path.join(CONFIG_DIR, "storage")
IDENTITY_PATH = os.path.join(STORAGE_DIR, "identity")
BOARD_PATH = os.path.join(STORAGE_DIR, "board")
BLOCKLIST_PATH = os.path.join(STORAGE_DIR, "blocklist")

os.makedirs(STORAGE_DIR, exist_ok=True)

class MessageBoard:
    def __init__(self):
        self.reticulum = RNS.Reticulum()
        self.last_message_time = {}
        self.last_announce = self.load_last_announce()
        
        if os.path.isfile(IDENTITY_PATH):
            self.identity = RNS.Identity.from_file(IDENTITY_PATH)
            RNS.log("Loaded identity from file", RNS.LOG_INFO)
        else:
            self.identity = RNS.Identity()
            self.identity.to_file(IDENTITY_PATH)
            RNS.log("Created new identity", RNS.LOG_INFO)
        
        self.router = LXMF.LXMRouter(identity=self.identity, storagepath=CONFIG_DIR)
        self.destination = self.router.register_delivery_identity(
            self.identity, 
            display_name=DISPLAY_NAME
        )
        self.router.register_delivery_callback(self.on_message)
        
        RNS.log(f"Message Board ready: {RNS.prettyhexrep(self.destination.hash)}", RNS.LOG_INFO)
    
    def load_last_announce(self):
        try:
            if os.path.isfile(ANNOUNCE_FILE):
                with open(ANNOUNCE_FILE, "r") as f:
                    return float(f.read().strip())
        except:
            pass
        return 0
    
    def save_last_announce(self):
        with open(ANNOUNCE_FILE, "w") as f:
            f.write(str(self.last_announce))
    
    def do_announce(self):
        self.destination.announce()
        self.last_announce = time.time()
        self.save_last_announce()
        RNS.log("Announce sent", RNS.LOG_INFO)
    
    def on_message(self, message):
        try:
            content = message.content.decode('utf-8')
            source_hash = RNS.hexrep(message.source_hash, delimit=False)

            # Проверка блок-листа
            if os.path.isfile(BLOCKLIST_PATH):
                with open(BLOCKLIST_PATH) as _bf:
                    if source_hash in [l.strip() for l in _bf.readlines()]:
                        RNS.log(f"Blocked message from {source_hash[:8]}", RNS.LOG_INFO)
                        self.send_reply(message.source_hash, "🚫 Вы заблокированы и не можете размещать объявления.")
                        return

            try:
                username = message.source_display_name or source_hash[:8]
            except:
                username = source_hash[:8]
            
            current_time = time.time()
            if source_hash in self.last_message_time:
                time_diff = current_time - self.last_message_time[source_hash]
                if time_diff < COOLDOWN_SECONDS:
                    wait_time = int(COOLDOWN_SECONDS - time_diff)
                    RNS.log(f"Spam protection: {username} must wait {wait_time}s", RNS.LOG_INFO)
                    self.send_reply(message.source_hash, f"⏳ Подождите {wait_time} сек. перед отправкой нового сообщения.")
                    return
            
            RNS.log(f"Message from {username}: {content[:50]}...", RNS.LOG_INFO)
            
            time_str = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(message.timestamp))
            new_message = f'`F888{time_str} `Fddd{content}\n`F888`[lxmf@{source_hash}]`Fd8fнаписать`f\n\n'
            
            self.save_message(new_message)
            self.last_message_time[source_hash] = current_time
            
            self.send_reply(message.source_hash, "✅ Ваше сообщение добавлено на доску объявлений!")
            
        except Exception as e:
            RNS.log(f"Error processing message: {e}", RNS.LOG_ERROR)
    
    def save_message(self, new_message):
        messages = []
        if os.path.isfile(BOARD_PATH):
            try:
                with open(BOARD_PATH, "rb") as f:
                    messages = msgpack.unpack(f)
            except:
                messages = []
        
        if new_message not in messages:
            messages.append(new_message)
        
        while len(messages) > MAX_MESSAGES:
            messages.pop(0)
        
        with open(BOARD_PATH, "wb") as f:
            msgpack.pack(messages, f)
    
    def send_reply(self, dest_hash, text):
        try:
            dest_identity = RNS.Identity.recall(dest_hash)
            if dest_identity:
                dest = RNS.Destination(
                    dest_identity,
                    RNS.Destination.OUT,
                    RNS.Destination.SINGLE,
                    "lxmf", "delivery"
                )
                lxm = LXMF.LXMessage(dest, self.destination, text, title="MSG Board Surgut")
                lxm.try_propagation_on_fail = True
                self.router.handle_outbound(lxm)
        except Exception as e:
            RNS.log(f"Error sending reply: {e}", RNS.LOG_ERROR)
    
    def run(self):
        RNS.log("Message Board running...", RNS.LOG_INFO)
        while True:
            time.sleep(CHECK_INTERVAL)
            
            if time.time() - self.last_announce > ANNOUNCE_INTERVAL:
                self.do_announce()
            
            gc.collect()


if __name__ == "__main__":
    board = MessageBoard()
    board.run()
