# Mistake: Using Template Vault as Real Memory

## Mistake
The EC2 vault exists, but it was recreated from templates and may not contain the real Windows Obsidian context.

## Root Cause
Windows-to-EC2 sync was blocked, so Option B fallback created a usable but incomplete vault.

## Detection
Files contain generic starter content or lack detailed project history.

## Prevention
After fallback vault creation:
1. Populate current-system-state.md with verified operational facts.
2. Write daily logs immediately.
3. Record known risks in Mistakes.
4. Later sync or merge Windows source vault.
