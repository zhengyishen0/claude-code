#!/bin/bash
# Test script for Stop/SubagentStop hooks

echo "[$(date '+%Y-%m-%d %H:%M:%S')] stop-test.sh executed" >> /tmp/stop-hook-test.log
echo "Hook input:" >> /tmp/stop-hook-test.log
cat >> /tmp/stop-hook-test.log

exit 0
