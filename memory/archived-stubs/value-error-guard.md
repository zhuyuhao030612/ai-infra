---
name: value-error-guard
description: Guard against ValueError when processing unknown instrument symbols in data_generator.
metadata:
  type: project
---

Why: To prevent runtime errors and ensure the robustness of the data generation process. How-to-apply: Implement a try-except block around the code that processes instrument symbols, catching ValueError and handling it appropriately.