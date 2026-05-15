#!/usr/bin/env python3
"""
ollama-bot -- Private AI assistant over Reticulum mesh network.
Built with LXMFy + Ollama. Part of the reticulum-pi-mesh project.
https://github.com/5hay196/reticulum-pi-mesh
"""
import os
import sys
sys.path.insert(0, '/home/user/ollama-bot')
from dotenv import load_dotenv
load_dotenv()
from cogs.ai import AICog
from cogs.admin import AdminCog
from cogs.groups import GroupsCog
from lxmfy import LXMFBot
load_dotenv()
bot = LXMFBot(
    name=os.getenv("BOT_NAME", "ITD5 AI Assistant"),
    announce=int(os.getenv("ANNOUNCE_INTERVAL", "900")),
    admins=[h.strip() for h in os.getenv("ADMIN_HASHES", "").split(",") if h.strip()],
    hot_reloading=True,
    rate_limit=int(os.getenv("RATE_LIMIT", "3")),
    cooldown=int(os.getenv("COOLDOWN", "60")),
    max_warnings=3,
    warning_timeout=300,
    storage_type="sqlite",
    storage_path="bot_data",
    propagation_node=os.getenv("PROPAGATION_NODE"),
    propagation_fallback_enabled=True,
)
bot.add_cog(AICog(bot))
bot.add_cog(AdminCog(bot))
bot.add_cog(GroupsCog(bot))
ai_cog = bot.cogs.get("AICog")
groups_cog = bot.cogs.get("GroupsCog")

@bot.on_message()
def handle_message(sender, message):
    content = message.content.decode('utf-8')
    if not content.startswith("/"):
        class Ctx:
            pass
        ctx = Ctx()
        ctx.sender = sender
        ctx.content = content
        ctx.args = content.split()
        ctx.reply = lambda text, **kwargs: bot.send(sender, text)
        ai_cog._ai_reply(ctx, content)

if __name__ == "__main__":
    bot.run()
