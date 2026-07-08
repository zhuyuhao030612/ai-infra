---
name: fix-split-diagnostic-logd-filenotfounderror
description: Fixed a FileNotFoundError in the TentOfTrials-bounty build.py script related to split_diagnostic_logd.
metadata:
  type: project
---

The error was caused by an incorrect path for the log file. Corrected the path and re-ran the build.