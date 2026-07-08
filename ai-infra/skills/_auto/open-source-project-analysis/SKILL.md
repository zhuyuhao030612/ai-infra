---
name: open-source-project-analysis
description: Analyze an open-source project architecture, identify gaps, and implement new features.
version: 0.1.0
auto_generated: true
generated_date: 2026-07-04
category: workflow
tags: [open-source, architecture, feature-implementation]
---

# open-source-project-analysis — Analyze an open-source project architecture, identify gaps, and implement new features.

## When to use

- When you need to understand the architecture of an open-source project.
- When you want to compare the project's architecture with existing solutions.
- When you need to implement new features based on a zero analysis of the project.

## Steps

### Step 1: Research Project Architecture
- **Tool**: WebSearch
- **Action**: Search for the GitHub repository of the open-source project (e.g., "GitHub Hermes open source project Nous Research").
- **Output**: Identify the relevant repository and note its popularity (e.g., 207k+ stars).

### Step 2: Confirm API Support
- **Tool**: WebSearch
- **Action**: Search for specific configurations related to API support in the project (e.g., "Hermes Agent DeepSeek API provider configuration").
- **Output**: Verify that the project supports the required API.

### Step 3: Get Architecture Details
- **Tool**: WebSearch
- **Action**: Search for detailed architecture information (e.g., "Hermes Agent architecture deep dive skill system memory system").
- **Output**: Retrieve the architecture details, including layers like memory and self-learning loops.

### Step 4: Confirm Deployment Options
- **Tool**: WebSearch
- **Action**: Search for deployment options (e.g., "Hermes Agent local deployment offline Ollama setup").
- **Output**: Verify that the project supports local deployment and offline setups.

### Step 5: Read Existing Files
- **Tool**: Read
- **Action**: Read multiple existing files (e.g., bounty-check.ps1, capabilities.json, AIRuntime.psm1) to understand the project's structure and format.
- **Output**: Familiarize yourself with the project's current state and file formats.

### Step 6: Create New Script
- **Tool**: Write
- **Action**: Create a new script for the new feature (e.g., ai-infra/scripts/nudge-review.ps1) based on the architecture details.
- **Output**: Generate the core script for the new feature.

### Step 7: Update PowerShell Commands
- **Tool**: Edit
- **Action**: Add the new command to ValidateSet and switch in the main PowerShell script (e.g., ai-infra/bin/ai.ps1).
- **Output**: Ensure the new command is accessible and functional within the project.

### Step 8: Register New Capability
- **Tool**: Edit
- **Action**: Register the new capability in the capabilities file (e.g., ai-infra/registry/capabilities.json).
- **Output**: Update the registry to include the new feature's capabilities.

### Step 9: Test Initial Implementation
- **Tool**: PowerShell
- **Action**: Perform a dry run and true run of the new feature script to identify bugs (e.g., JSON parsing bug).
- **Output**: Identify and report any issues found during testing.

### Step 10: Fix Bugs
- **Tool**: Edit
- **Action**: Address identified bugs in the script (e.g., replace -replace with [regex]::Match, fix $utf8NoBom scope).
- **Output**: Resolve all reported bugs and ensure the script runs correctly.

### Step 11: Verify Final Implementation
- **Tool**: PowerShell
- **Action**: Validate that the new feature works as expected after bug fixes.
- **Output**: Confirm that the new feature is functioning correctly in the project.

### Step 12: Update Documentation
- **Tool**: Edit
- **Action**: Update the documentation to reflect the new feature and its implementation (e.g., MEMORY.md).
- **Output**: Ensure all relevant documentation is up-to-date.

## Pitfalls

- Qwen outputs JSON with ```json wrapping, which needs to be removed using regex.
- PowerShell -replace operator [\\s\\S] syntax is not compatible; use [regex]::Match instead.
- $utf8NoBom variable scope bug—defined in a loop, causing external references to fail; move the definition to the file top.

## Verification

1. Check if the new feature script runs without errors.
2. Verify that the new capability is registered and accessible.
3. Test the functionality of the new feature in various scenarios.

## Anti-patterns

- Never use -replace with [\\s\\S] syntax for regex operations in PowerShell.
- Never define variables within loops if they need to be referenced outside the loop.