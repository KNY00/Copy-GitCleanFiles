# Copy-GitCleanFiles

A lightweight PowerShell utility designed to create a clean, stripped-down mirror of your project repository in seconds.

## Motivation & Utility

Modern development setups clutter repositories with hundreds of megabytes—or gigabytes—of transient dependencies, build artifacts, compiled binaries, cache trees, and environment secrets (`node_modules/`, `vendor/`, `target/`, `.venv/`, `.env`, `.pyc`, logs, etc.).

When working with LLM web interfaces (e.g., Claude Projects, ChatGPT Canvas, Gemini, or custom web consoles):

- Context windows get eaten up by machine-generated dependencies.
- Confidential environment files (`.env`) can be leaked by mistake.
- Manually cherry-picking or pruning directories before zipping and uploading is slow and error-prone.

`Copy-GitCleanFiles.ps1` automates this process by querying your repository's native Git engine via `git ls-files --cached --others --exclude-standard`. It extracts **only** genuine project and source code files, replicating your exact directory hierarchy into an isolated destination directory ready for immediate archive generation or LLM ingestion.

## Quickstart

Run the script from your terminal using shorthand flags:

```
.\Copy-GitCleanFiles.ps1 -s . -d ..\clean-project-export
```

Zip or upload the resulting `..\clean-project-export` directory directly to your LLM web interface.

## Prerequisites

- **PowerShell:** Version 5.1 or PowerShell Core 7+.
- **Git:** Installed and available in your system `$PATH`.
- The source directory must be an initialized Git repository containing or tracking your project files.

## Parameters & Flags

The script adheres to idiomatic PowerShell parameter standards (PascalCase single-dash syntax) with built-in shorthand aliases and positional bindings.

### \-Source (Aliases: -s, -Src)

- **Type:** `[string]`
- **Required:** Yes
- **Position:** `0`
- **Description:** The root path of the Git project you want to extract. Can be:
	- An absolute path: `-Source "C:\Development\MyProject"`
		- A relative path: `-s .` or `-Source ..\sibling-app` *(Relative paths are resolved strictly against the terminal directory where you run the command, not the script's installation directory).*

### \-Destination (Aliases: -d, -Dest)

- **Type:** `[string]`
- **Required:** Yes
- **Position:** `1`
- **Description:** The target folder where the clean files will be copied.
	- Automatically created recursively if it does not already exist.
		- If it exists, the script prevents accidental overwrites and requires typing `confirm destruction` before wiping and repopulating.

## Usage Examples

### 1\. Positional Parameters (Fastest)

```
.\Copy-GitCleanFiles.ps1 ./my-repo ../llm-upload
```

### 2\. Relative Path Execution from Project Root

Export the current working project into a sibling directory:

```
.\Copy-GitCleanFiles.ps1 -s . -d ..\my-project-llm
```

### 3\. Absolute Cross-Drive Export (Windows)

```
.\Copy-GitCleanFiles.ps1 -Source "D:\Projects\BackendEngine" -Destination "C:\Temp\LLMContext"
```

## Safety Features

- **Circular Duplication Guard:** Evaluates paths using OS-aware, segment-by-segment canonicalization. The script will reject any attempt to target the source repository itself (`-Source . -Destination .`).
- **Destructive Overwrite Prompt:** If the target destination already exists, you must explicitly confirm directory destruction:
	```
	WARNING: Destination folder already exists: 'C:\Temp\LLMContext'
	Type 'confirm destruction' to destroy it and continue:
	```
- **File Collision Check:** Throws a terminating error if the destination path points to an existing file rather than a directory.
- **Literal Path Handling:** Resolves square brackets and special globbing characters without PowerShell wildcards corrupting source paths.
- **Unicode Filename Preservation:** Runs Git operations using `core.quotepath=false` under UTF-8 console streams to preserve non-ASCII characters without octal escaping.
