---
name: deploy-sys-exit-propagation
description: Fixing sys.exit propagation in deployment scripts.
metadata:
  type: project
---

Why: To ensure proper termination of processes and clean up resources. How-to-apply: Review deployment scripts, identify where sys.exit is used, and propagate it appropriately.