---
name: terraform-import-unmanaged-resources
description: Fixes issues with Terraform importing unmanaged resources.
metadata:
  type: project
---

Why: When you try to import an existing resource into Terraform that is not managed by Terraform, it can lead to conflicts and errors. How-to-apply: Use the `terraform import` command followed by the resource type and ID.