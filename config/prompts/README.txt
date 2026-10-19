# System prompt templates live here (one `.md` per command, direct children).
#
# They are loaded by Pi through `settings.json`:
#   "prompts": ["/etc/pi/agent/prompts"]
# The filename becomes the command name (e.g. `operator-review.md` -> /operator-review).
#
# Template format:
#   ---
#   description: Shown in command completion
#   argument-hint: "[focus]"
#   ---
#   Body with ${1}, $@, ${1:-default} substitutions.
