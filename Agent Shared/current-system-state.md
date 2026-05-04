# Current System State

## HERMES / EC2
- HERMES runs on AWS EC2 Linux.
- EC2 user: ubuntu.
- Target Obsidian memory path: /home/ubuntu/AGENT_CORE_MEMORY.
- Symlink path: /home/ubuntu/agent_vault.

## Current Priority
Complete Central Intelligence / Obsidian memory setup before starting new production changes.

## Known Constraint
Original vault exists on Windows OneDrive Desktop, but EC2 cannot access Windows C:\ paths directly.

## HERMES Obsidian Production Memory Loop — Final Status
- Date: 2026-05-04
- Final phase: Phase 8E
- Verdict: PASS
- Auto-read: enabled via memory.provider obsidian-vault
- Auto-log: enabled via session:end hook
- Authoritative Daily Log writer: ~/.hermes/hooks/obsidian-session-end/handler.py
- Provider on_session_end path: intentionally no-op after Phase 8D dedup guard
- Warm /reset dedup test: passed
- Duplicate provider entry: false
- Service: hermes-official-gateway.service active
- Last verified PID: 737159
- Current model/provider: openrouter/owl-alpha
- Do not change model/provider unless Benz approves
