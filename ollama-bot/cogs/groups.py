"""
Groups cog -- real LXMF group creation/deletion via lxmf_distribution_group_extended.py
Each group runs as a separate systemd service with its own identity.
Only trusted users (whitelist) can create/delete groups.
Owner (ADMIN_HASHES) manages the whitelist.
"""

import os
import json
import time
import shutil
import subprocess
from datetime import datetime, timezone
from lxmfy import command

SCRIPT_PATH = "/home/user/reticulum/lxmf_distribution_group_extended.py"
PYTHON_PATH = "/home/user/reticulum/venv/bin/python3"
CONFIG_BASE = "/root/.config"
SERVICE_DIR = "/etc/systemd/system"

# Propagation node для всех групп (NomadNet Surgut)
PROPAGATION_NODE = "f89ede8428bb261e3e2a935dfe920f40"


class GroupsCog:
    def __init__(self, bot):
        self.bot = bot

    # ─── helpers ────────────────────────────────────────────────────────────

    def _is_owner(self, ctx) -> bool:
        return ctx.sender in self.bot.admins

    def _is_trusted(self, ctx) -> bool:
        if self._is_owner(ctx):
            return True
        return ctx.sender in self._get_trusted()

    def _get_trusted(self) -> list:
        raw = self.bot.storage.get("trusted_users", "[]")
        try:
            return json.loads(raw)
        except Exception:
            return []

    def _save_trusted(self, trusted: list):
        self.bot.storage.set("trusted_users", json.dumps(trusted))

    def _get_groups(self) -> dict:
        raw = self.bot.storage.get("groups", "{}")
        try:
            return json.loads(raw)
        except Exception:
            return {}

    def _save_groups(self, groups: dict):
        self.bot.storage.set("groups", json.dumps(groups))

    def _safe_name(self, name: str) -> str:
        """Convert group name to safe string for filesystem/systemd."""
        translit = {
            'а':'a','б':'b','в':'v','г':'g','д':'d','е':'e','ё':'yo',
            'ж':'zh','з':'z','и':'i','й':'j','к':'k','л':'l','м':'m',
            'н':'n','о':'o','п':'p','р':'r','с':'s','т':'t','у':'u',
            'ф':'f','х':'kh','ц':'ts','ч':'ch','ш':'sh','щ':'sch',
            'ъ':'','ы':'y','ь':'','э':'e','ю':'yu','я':'ya'
        }
        safe = name.lower().replace(" ", "_")
        result = ""
        for c in safe:
            result += translit.get(c, c)
        result = "".join(c for c in result if c.isalnum() or c == "_")
        return f"lxmf_group_{result}"

    def _get_group_hash(self, config_path: str) -> str:
        """Read LXMF address hash from group identity file."""
        identity_file = os.path.join(config_path, "identity")
        try:
            import RNS
            identity = RNS.Identity.from_file(identity_file)
            h = RNS.Destination.hash(identity, 'lxmf', 'delivery')
            return h.hex()
        except Exception as e:
            return None

    def _create_service(self, service_name: str, config_path: str, display_name: str):
        """Create and enable systemd service for a group."""
        service_content = f"""[Unit]
Description=LXMF Group: {display_name}
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/user/reticulum
ExecStart={PYTHON_PATH} {SCRIPT_PATH} -p {config_path}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"""
        service_file = os.path.join(SERVICE_DIR, f"{service_name}.service")
        with open(service_file, "w") as f:
            f.write(service_content)

        subprocess.run(["systemctl", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "enable", service_name], check=True)
        subprocess.run(["systemctl", "start", service_name], check=True)

    def _stop_and_remove_service(self, service_name: str):
        """Stop, disable and remove systemd service."""
        subprocess.run(["systemctl", "stop", service_name], check=False)
        subprocess.run(["systemctl", "disable", service_name], check=False)
        service_file = os.path.join(SERVICE_DIR, f"{service_name}.service")
        if os.path.exists(service_file):
            os.remove(service_file)
        subprocess.run(["systemctl", "daemon-reload"], check=False)

    def _add_russian_messages(self, config_path: str):
        """Add Russian translations to config.cfg after it's generated."""
        main_cfg = os.path.join(config_path, "config.cfg")
        if not os.path.exists(main_cfg):
            return
        
        with open(main_cfg, "r") as f:
            content = f.read()
        
        # Русские сообщения для добавления после немецких версий
        russian_messages = {
            "auto_add_wait-de": "auto_add_wait-ru = Заявка отправлена. Ожидайте подтверждения. Отмена: /leave",
            "auto_add_user-de": "auto_add_user-ru = Добро пожаловать в группу \"!display_name!\"! Для справки: /?",
            "auto_add_guest-de": "auto_add_guest-ru = Вы приняты в группу \"!display_name!\"! Только чтение. Выйти: /leave",
            "allow_user-de": "allow_user-ru = Вы приняты в группу \"!display_name!\"! Для справки: /?",
            "allow_guest-de": "allow_guest-ru = Вы приняты в группу \"!display_name!\"! Только чтение. Выйти: /leave",
            "deny_user-de": "deny_user-ru = Вам отказано во вступлении в группу.",
            "member_join-de": "member_join-ru = !source_name! вступил в группу.",
            "member_leave-de": "member_leave-ru = !source_name! покинул группу.",
        }
        
        lines = content.split('\n')
        new_lines = []
        for line in lines:
            new_lines.append(line)
            for de_key, ru_line in russian_messages.items():
                if line.startswith(de_key + " = ") or line.startswith(de_key + "="):
                    new_lines.append(ru_line)
                    break
        
        # Заменяем lng = en на lng = ru
        new_content = '\n'.join(new_lines)
        new_content = new_content.replace("lng = en", "lng = ru")
        
        with open(main_cfg, "w") as f:
            f.write(new_content)

    def _patch_private_group(self, config_path: str, service_name: str):
        """Patch config for private group: wait mode, 14-day announce, Russian."""
        main_cfg = os.path.join(config_path, "config.cfg")
        data_cfg = os.path.join(config_path, "data.cfg")
        
        # Patch config.cfg — анонс раз в 14 дней
        if os.path.exists(main_cfg):
            with open(main_cfg, "r") as f:
                cfg = f.read()
            cfg = cfg.replace("announce_startup = Yes", "announce_startup = No")
            cfg = cfg.replace("announce_periodic = Yes", "announce_periodic = Yes")
            cfg = cfg.replace("announce_periodic_interval = 120", "announce_periodic_interval = 20160")
            cfg = cfg.replace("lng = en", "lng = ru")
            with open(main_cfg, "w") as f:
                f.write(cfg)
        
        # Patch data.cfg — режим wait
        if os.path.exists(data_cfg):
            with open(data_cfg, "r") as f:
                data = f.read()
            data = data.replace("auto_add_user_type = user", "auto_add_user_type = wait")
            with open(data_cfg, "w") as f:
                f.write(data)

    # ─── whitelist commands ──────────────────────────────────────────────────


    @command(name="adminhelp")
    def adminhelp(self, ctx):
        """[Owner] Show admin commands."""
        if not self._is_owner(ctx):
            ctx.reply("Нет доступа.")
            return
        ctx.reply(
            "Админ команды бота:\n"
            "─────────────────────\n"
            "Whitelist:\n"
            "/trust <hash> - добавить доверенного\n"
            "/untrust <hash> - убрать доверенного\n"
            "/trusted - список доверенных\n"
            "─────────────────────\n"
            "Группы:\n"
            "/newgroup <название> - публичная\n"
            "/newgroup <название> private - приватная\n"
            "/delgroup <название> - удалить\n"
            "/setprivate <название> - сделать приватной\n"
            "/setpublic <название> - сделать публичной\n"
            "/groups - список групп\n"
            "/group <название> - инфо\n"
            "─────────────────────\n"
            "Команды В САМОЙ ГРУППЕ:\n"
            "/allow <hash> - одобрить заявку\n"
            "/deny <hash> - отклонить заявку\n"
            "/kick <hash> - выгнать\n"
            "/block <hash> - заблокировать\n"
            "/members - участники\n"
            "/wait - ожидающие\n"
            "/? - справка по группе\n"
            "─────────────────────\n"
            "Статистика:\n"
            "/stats - статистика бота\n"
            "/status - статус Ollama\n"
            "/models - список моделей\n"
            "/setmodel <модель> - сменить модель\n"
            "/clearall - очистить все истории"
        )

    @command(name="trust")
    def trust(self, ctx):
        """[Owner] Add user to trusted whitelist. /trust <hash>"""
        if not self._is_owner(ctx):
            ctx.reply("Нет доступа.")
            return
        if not ctx.args:
            ctx.reply("Укажи хэш: /trust <hash>")
            return
        user_hash = ctx.args[0].strip()
        trusted = self._get_trusted()
        if user_hash in trusted:
            ctx.reply(f"Уже в списке: {user_hash[:16]}...")
            return
        trusted.append(user_hash)
        self._save_trusted(trusted)
        ctx.reply(f"Добавлен в доверенные: {user_hash[:16]}...")

    @command(name="untrust")
    def untrust(self, ctx):
        """[Owner] Remove user from trusted whitelist. /untrust <hash>"""
        if not self._is_owner(ctx):
            ctx.reply("Нет доступа.")
            return
        if not ctx.args:
            ctx.reply("Укажи хэш: /untrust <hash>")
            return
        user_hash = ctx.args[0].strip()
        trusted = self._get_trusted()
        if user_hash not in trusted:
            ctx.reply(f"Не найден: {user_hash[:16]}...")
            return
        trusted.remove(user_hash)
        self._save_trusted(trusted)
        ctx.reply(f"Удалён из доверенных: {user_hash[:16]}...")

    @command(name="trusted")
    def trusted(self, ctx):
        """[Owner] List all trusted users."""
        if not self._is_owner(ctx):
            ctx.reply("Нет доступа.")
            return
        trusted = self._get_trusted()
        if not trusted:
            ctx.reply("Список доверенных пуст.")
            return
        lines = ["Доверенные пользователи:"]
        for i, h in enumerate(trusted, 1):
            lines.append(f"{i}. {h}")
        lines.append(f"\nВсего: {len(trusted)}")
        ctx.reply("\n".join(lines))

    # ─── stats command ───────────────────────────────────────────────────────

    @command(name="stats")
    def stats(self, ctx):
        """[Owner] Show bot usage statistics."""
        if not self._is_owner(ctx):
            ctx.reply("Нет доступа.")
            return
        total_users = self.bot.storage.get("stat_total_users", "0")
        total_messages = self.bot.storage.get("stat_total_messages", "0")
        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        dau_raw = self.bot.storage.get(f"stat_dau_{today}", [])
        try:
            dau = len(dau_raw) if isinstance(dau_raw, list) else len(json.loads(dau_raw))
        except Exception:
            dau = 0
        groups = self._get_groups()
        trusted = self._get_trusted()
        ctx.reply(
            f"Статистика SurgutBot86\n"
            f"{'─' * 30}\n"
            f"Всего пользователей: {total_users}\n"
            f"Всего сообщений: {total_messages}\n"
            f"Активны сегодня: {dau}\n"
            f"Групп зарегистрировано: {len(groups)}\n"
            f"Доверенных пользователей: {len(trusted)}"
        )

    # ─── group commands ──────────────────────────────────────────────────────

    @command(name="newgroup", threaded=True)
    def newgroup(self, ctx):
        """[Trusted] Create a new LXMF group. /newgroup <название> [private]"""
        if not self._is_trusted(ctx):
            ctx.reply("Нет доступа. Только доверенные пользователи могут создавать группы.")
            return
        if not ctx.args:
            ctx.reply(
                "Использование:\n"
                "/newgroup <название> — публичная группа\n"
                "/newgroup <название> private — приватная группа\n\n"
                "Приватная группа:\n"
                "• Новые участники ждут одобрения\n"
                "• Анонс раз в 14 дней\n"
                "• Русские сообщения"
            )
            return

        # Проверяем private в конце
        is_private = ctx.args[-1].lower() == "private" if ctx.args else False
        if is_private:
            group_name = " ".join(ctx.args[:-1]).strip()
        else:
            group_name = " ".join(ctx.args).strip()
        
        if not group_name:
            ctx.reply("Укажи название: /newgroup <название> [private]")
            return

        groups = self._get_groups()

        # check duplicate name
        if group_name.lower() in [k.lower() for k in groups]:
            ctx.reply(f"Группа '{group_name}' уже существует.")
            return

        safe = self._safe_name(group_name)
        config_path = os.path.join(CONFIG_BASE, safe)

        # check duplicate config path
        if os.path.exists(config_path):
            ctx.reply(f"Конфликт имени. Попробуй другое название.")
            return

        privacy_text = "приватную" if is_private else "публичную"
        ctx.reply(f"Создаю {privacy_text} группу '{group_name}'...\nЭто займёт несколько секунд.")

        try:
            # Create config directory and owr file
            os.makedirs(config_path, exist_ok=True)
            
            # Для приватных: анонс раз в 14 дней
            if is_private:
                auto_add = "False"
                announce_startup = "No"
                announce_periodic = "Yes"
                announce_interval = "20160"  # 14 дней в минутах
            else:
                auto_add = "True"
                announce_startup = "Yes"
                announce_periodic = "Yes"
                announce_interval = "120"

            owr_content = f"""[main]
lng = ru
[lxmf]
display_name = {group_name}
propagation_node = {PROPAGATION_NODE}
propagation_node_auto = True
description = 
auto_add_user_announce = {auto_add}
auto_add_user_message = {auto_add}
[telemetry]
location_enabled = False
location_lat = 0
location_lon = 0
owner_enabled = False
owner_data =
state_enabled = False
state_data = 0
[cluster]
enabled = False
name = grp
type = cluster
display_name = {group_name}
[router]
enabled = False
display_name = {group_name}
[high_availability]
enabled = False
role = master
peer =
[statistic]
enabled = True
[group]
announce_startup = {announce_startup}
announce_periodic = {announce_periodic}
announce_periodic_interval = {announce_interval}
[rights]
"""
            with open(os.path.join(config_path, "config.cfg.owr"), "w") as f:
                f.write(owr_content)

            # Create and start systemd service first
            service_name = safe
            self._create_service(service_name, config_path, group_name)

            # Wait for identity to be generated by the service
            identity_file = os.path.join(config_path, "identity")
            for _ in range(15):
                if os.path.exists(identity_file):
                    break
                time.sleep(1)

            # Read generated hash
            group_hash = self._get_group_hash(config_path)
            if not group_hash:
                self._stop_and_remove_service(service_name)
                shutil.rmtree(config_path, ignore_errors=True)
                ctx.reply("Ошибка: не удалось получить хэш группы.")
                return

            # Ждём пока сгенерируется config.cfg
            time.sleep(2)
            
            # Добавляем русские сообщения
            self._add_russian_messages(config_path)
            
            # Для приватных групп: режим wait
            if is_private:
                self._patch_private_group(config_path, service_name)
            
            # Перезапускаем чтобы применить изменения
            subprocess.run(["systemctl", "restart", service_name], check=False)

            # Save to bot storage
            now = datetime.now(timezone.utc).strftime("%d.%m.%Y %H:%M UTC")
            groups[group_name] = {
                "name": group_name,
                "hash": group_hash,
                "owner": ctx.sender,
                "created": now,
                "service": service_name,
                "config_path": config_path,
                "private": is_private,
            }
            self._save_groups(groups)

            privacy = "🔒 Приватная" if is_private else "🌐 Публичная"
            extra = ""
            if is_private:
                extra = "\n\nНовые участники ждут /allow в группе"
            ctx.reply(
                f"✅ Группа создана!\n"
                f"{'─' * 30}\n"
                f"Название: {group_name}\n"
                f"LXMF адрес: {group_hash}\n"
                f"Тип: {privacy}\n"
                f"Propagation: {PROPAGATION_NODE[:16]}...\n"
                f"Дата: {now}{extra}"
            )

        except Exception as e:
            shutil.rmtree(config_path, ignore_errors=True)
            ctx.reply(f"Ошибка создания группы: {str(e)}")

    @command(name="delgroup", threaded=True)
    def delgroup(self, ctx):
        """[Trusted] Delete a group. /delgroup <название>"""
        if not self._is_trusted(ctx):
            ctx.reply("Нет доступа.")
            return
        if not ctx.args:
            ctx.reply("Укажи название: /delgroup <название>")
            return

        group_name = " ".join(ctx.args).strip()
        groups = self._get_groups()

        found_key = None
        for k in groups:
            if k.lower() == group_name.lower():
                found_key = k
                break

        if not found_key:
            ctx.reply(f"Группа '{group_name}' не найдена.")
            return

        group = groups[found_key]

        if group["owner"] != ctx.sender and not self._is_owner(ctx):
            ctx.reply("Нельзя удалить чужую группу.")
            return

        ctx.reply(f"Удаляю группу '{found_key}'...")

        try:
            # Stop and remove systemd service
            service_name = group.get("service")
            if service_name:
                self._stop_and_remove_service(service_name)

            # Remove config directory
            config_path = group.get("config_path")
            if config_path and os.path.exists(config_path):
                shutil.rmtree(config_path)

            del groups[found_key]
            self._save_groups(groups)
            ctx.reply(f"✅ Группа '{found_key}' удалена.")

        except Exception as e:
            ctx.reply(f"Ошибка удаления группы: {str(e)}")



    def _set_group_privacy(self, ctx, private: bool):
        """Helper to set group privacy mode."""
        if not self._is_trusted(ctx):
            ctx.reply("Нет доступа.")
            return
        if not ctx.args:
            mode = "приватной" if private else "публичной"
            ctx.reply(f"Укажи название: /set{'private' if private else 'public'} <название>")
            return

        group_name = " ".join(ctx.args).strip()
        groups = self._get_groups()
        found_key = None
        for k in groups:
            if k.lower() == group_name.lower():
                found_key = k
                break

        if not found_key:
            ctx.reply(f"Группа '{group_name}' не найдена.")
            return

        group = groups[found_key]
        if group["owner"] != ctx.sender and not self._is_owner(ctx):
            ctx.reply("Нельзя изменить чужую группу.")
            return

        if group.get("private", False) == private:
            mode = "приватной" if private else "публичной"
            ctx.reply(f"Группа уже является {mode}.")
            return

        try:
            config_path = group.get("config_path")
            service_name = group.get("service")
            
            if private:
                # Делаем приватной: добавляем русские сообщения и wait режим
                self._add_russian_messages(config_path)
                self._patch_private_group(config_path, service_name)
            else:
                # Делаем публичной
                main_cfg = os.path.join(config_path, "config.cfg")
                data_cfg = os.path.join(config_path, "data.cfg")
                
                if os.path.exists(main_cfg):
                    with open(main_cfg, "r") as f:
                        cfg = f.read()
                    cfg = cfg.replace("announce_periodic_interval = 20160", "announce_periodic_interval = 120")
                    with open(main_cfg, "w") as f:
                        f.write(cfg)
                
                if os.path.exists(data_cfg):
                    with open(data_cfg, "r") as f:
                        data = f.read()
                    data = data.replace("auto_add_user_type = wait", "auto_add_user_type = user")
                    with open(data_cfg, "w") as f:
                        f.write(data)

            subprocess.run(["systemctl", "restart", service_name], check=True)

            group["private"] = private
            groups[found_key] = group
            self._save_groups(groups)

            mode = "🔒 приватной" if private else "🌐 публичной"
            ctx.reply(f"✅ Группа '{found_key}' теперь {mode}.")

        except Exception as e:
            ctx.reply(f"Ошибка: {str(e)}")

    @command(name="setprivate", threaded=True)
    def setprivate(self, ctx):
        """[Trusted] Make group private. /setprivate <название>"""
        self._set_group_privacy(ctx, True)

    @command(name="setpublic", threaded=True)
    def setpublic(self, ctx):
        """[Trusted] Make group public. /setpublic <название>"""
        self._set_group_privacy(ctx, False)

    @command(name="renamegroup", threaded=True)
    def renamegroup(self, ctx):
        """[Trusted] Rename a group display name. /renamegroup <старое> | <новое>"""
        if not self._is_trusted(ctx):
            ctx.reply("Нет доступа.")
            return
        if not ctx.args or "|" not in " ".join(ctx.args):
            ctx.reply("Использование: /renamegroup <старое название> | <новое название>\nПример: /renamegroup TestGroup | MyCoolGroup")
            return

        full = " ".join(ctx.args)
        parts = full.split("|", 1)
        old_name = parts[0].strip()
        new_name = parts[1].strip()

        if not old_name or not new_name:
            ctx.reply("Укажи оба названия: /renamegroup <старое> | <новое>")
            return

        groups = self._get_groups()
        found_key = None
        for k in groups:
            if k.lower() == old_name.lower():
                found_key = k
                break

        if not found_key:
            ctx.reply(f"Группа '{old_name}' не найдена.")
            return

        group = groups[found_key]

        if group["owner"] != ctx.sender and not self._is_owner(ctx):
            ctx.reply("Нельзя переименовать чужую группу.")
            return

        if new_name.lower() in [k.lower() for k in groups if k != found_key]:
            ctx.reply(f"Название '{new_name}' уже занято.")
            return

        ctx.reply(f"Переименовываю '{found_key}' → '{new_name}'...")

        try:
            config_path = group.get("config_path")
            owr_file = os.path.join(config_path, "config.cfg.owr")

            with open(owr_file, "r") as f:
                cfg = f.read()

            cfg = cfg.replace(
                f"display_name = {found_key}",
                f"display_name = {new_name}"
            )
            with open(owr_file, "w") as f:
                f.write(cfg)

            service_name = group.get("service")
            subprocess.run(["systemctl", "restart", service_name], check=True)

            group["name"] = new_name
            groups[new_name] = group
            del groups[found_key]
            self._save_groups(groups)

            lines = [
                "✅ Группа переименована!",
                "─" * 30,
                f"Было: {found_key}",
                f"Стало: {new_name}",
                f"LXMF адрес не изменился: {group['hash']}"
            ]
            ctx.reply("\n".join(lines))

        except Exception as e:
            ctx.reply(f"Ошибка переименования: {str(e)}")

    @command(name="groups")
    def groups_list(self, ctx):
        """List all registered groups."""
        groups = self._get_groups()
        if not groups:
            ctx.reply("Групп пока нет.")
            return
        is_trusted = self._is_trusted(ctx)
        visible = {k: g for k, g in groups.items() if not g.get("private", False) or is_trusted}
        if not visible:
            ctx.reply("Публичных групп пока нет.")
            return
        lines = ["Группы Reticulum:"]
        for i, (name, g) in enumerate(visible.items(), 1):
            lock = " 🔒" if g.get("private", False) else ""
            lines.append(f"{i}. {name}{lock} — {g['hash']}")
        lines.append(f"\nВсего: {len(visible)}")
        ctx.reply("\n".join(lines))

    @command(name="group")
    def group_info(self, ctx):
        """Group details. /group <название>"""
        if not ctx.args:
            ctx.reply("Укажи название: /group <название>")
            return
        group_name = " ".join(ctx.args).strip()
        groups = self._get_groups()
        found = None
        for k, g in groups.items():
            if k.lower() == group_name.lower():
                found = g
                break
        if not found:
            ctx.reply(f"Группа '{group_name}' не найдена.")
            return
        if found.get("private", False) and not self._is_trusted(ctx):
            ctx.reply(f"Группа '{group_name}' не найдена.")
            return
        privacy = "🔒 Приватная" if found.get("private", False) else "🌐 Публичная"
        ctx.reply(
            f"{found['name']}\n"
            f"{'─' * 30}\n"
            f"LXMF адрес: {found['hash']}\n"
            f"Тип: {privacy}\n"
            f"Дата: {found['created']}"
        )


def setup(bot):
    bot.add_cog(GroupsCog(bot))
