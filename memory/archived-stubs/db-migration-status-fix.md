---
name: db-migration-status-fix
description: Fixed the issue with applying migration status in the database.
metadata:
  type: project
---

Why: The system was not correctly updating the migration status, causing delays in deployment. How-to-apply: Run the `db_migration apply_status` command to fix the issue.