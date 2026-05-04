# Mistake: Treating SSH Login as File Upload Success

## Mistake
SSH connections appeared in EC2 logs, but AGENT_CORE_MEMORY.zip was not present on EC2.

## Root Cause
SSH connection only proves login worked. It does not prove scp completed or wrote to the expected remote path.

## Detection
Check exact target path:
- ls -lh /home/ubuntu/AGENT_CORE_MEMORY.zip
- find /home/ubuntu -name "*.zip" -mmin -180

## Prevention
Every upload must verify:
1. scp exit success
2. exact remote file exists
3. remote file size is non-zero
4. zip integrity is valid
5. expected files appear after extraction
