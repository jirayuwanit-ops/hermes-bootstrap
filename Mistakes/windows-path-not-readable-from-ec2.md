# Mistake: Assuming EC2 Can Read Windows Paths

## Mistake
Tried to use or reference C:\Users\Benz\OneDrive\Desktop\AGENT_CORE_MEMORY from Linux EC2.

## Root Cause
EC2 is a separate Linux machine and has no direct mount for Benz's Windows filesystem. /mnt/c does not exist.

## Detection
Any Linux command referencing C:\ paths or /mnt/c fails or returns missing path.

## Prevention
Use one of these transfer/sync methods:
1. OneDrive share/download link
2. rclone OneDrive sync
3. SCP from Windows to EC2
4. Upload zip file through an available tool
5. Recreate minimal vault on EC2 as temporary fallback
