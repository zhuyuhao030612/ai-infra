# PHS Tool Router Rules — which tool for which task

## Priority: Fastest tool that can do the job wins.

### File Operations
| Task | Tool | Fallback |
|---|---|---|
| Read file | Read | - |
| Edit file | Edit | Write |
| Search code | Grep | Bash grep |
| Find files | Glob | PowerShell Get-ChildItem |

### Desktop
| Task | Tool | Fallback |
|---|---|---|
| Launch app | desktop-action launch | Start-Process |
| Hotkey (ctrl+c etc) | desktop-action hotkey | pyautogui |
| Type text | desktop-action type | pyautogui |
| Click known position | desktop-action click | pyautogui |
| Find and click button | UIA (pywinauto) | OCR → Vision |
| Read screen text | RapidOCR (22ms) | Vision |
| Understand screen visually | Doubao Vision (2.4s) | AskUserQuestion |
| Dump window controls | UIA dump | - |

### Web
| Task | Tool | Fallback |
|---|---|---|
| Browser navigation | Playwright MCP | - |
| Click web element | Playwright | desktop-action click (last resort) |
| Read web text | Playwright snapshot | - |
| Screenshot web | Playwright screenshot | - |

### External Reasoning
| Task | Tool | Fallback |
|---|---|---|
| Code review | Local (self) | GPT-5.5 |
| Architecture design | Local + GPT-5.5 | - |
| Security audit | Local | GPT-5.5 |
| Simple decisions | Local | - |

### NEVER
- Don't use Vision for buttons/OCR/menus (UIA or OCR first)
- Don't use Playwright for desktop apps
- Don't use desktop click for web pages
- Don't wait for GPT-5.5 on critical path (async only)
- Don't screenshot if UIA can read it
