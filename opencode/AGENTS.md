# Engineering judgment

Before fixing the exact reported issue, step back and consider whether it's a
symptom of a broader problem or a questionable design assumption. A targeted fix
is often right, but choose it deliberately—not reflexively. Prefer addressing
the underlying class of problems when that makes the system simpler and more
robust.

# Computer control and Jev

For desktop/app tasks, load the `computer-control-jev` skill before acting.
Use the installed `open-computer-use` MCP to observe and operate apps; consult
the `jev` MCP for ambiguous bounded decisions and evidence checks. Prefer an
available app/browser-specific connector when it can do the job. Open Computer
Use can operate browsers too, but obey the current session's access restrictions.

Observe → choose (Jev when useful) → act → verify. Jev receives text, not pixels,
and never grants permission or proves completion without observed evidence.
Ask before sending, deleting, purchasing or other externally visible changes.
Do not bypass denied tool calls with the CLI, AppleScript or another route.

Jev uses OpenRouter through a launcher that reads macOS Keychain. Never print
keys, include them in tool arguments/chat/Git, or send them to Jev as evidence.
Setup and troubleshooting live in the skill's `references/setup.md`.
