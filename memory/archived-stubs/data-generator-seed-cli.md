---
name: data-generator-seed-cli
description: Add a seed CLI argument to the data_generator for reproducible tests.
metadata:
  type: project
---

Why: To ensure that data generation is consistent and repeatable. How-to-apply: Add a new CLI argument `--seed` to the data_generator script, which sets a random seed for all random number generators used in the data generation process.