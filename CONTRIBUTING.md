# Contributing to PSWimToolkit

First off, thank you for considering contributing to PSWimToolkit! 🎉

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Coding Guidelines](#coding-guidelines)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)

## Code of Conduct

This project adheres to a [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## Getting Started

1. **Fork** the repository on GitHub
2. **Clone** your fork locally:
   ```powershell
   git clone https://github.com/YOUR-USERNAME/PSWimToolkit.git
   cd PSWimToolkit
   ```
3. **Add upstream** remote:
   ```powershell
   git remote add upstream https://github.com/mchave3/PSWimToolkit.git
   ```

## Development Setup

### Prerequisites

- Windows OS (required for DISM/WIM operations)
- PowerShell 7.4 or higher
- Git

### Building the Module

```powershell
# Restore dependencies and build
./build.ps1 -AutoRestore -Tasks build

# Import the built module for testing
Import-Module ./output/module/PSWimToolkit -Force
```

### Running Tests

```powershell
# Run all tests
./build.ps1 -Tasks test

# Run tests with verbose output
./build.ps1 -Tasks test -Verbose
```

## Making Changes

1. **Create a branch** from `main`:
   ```powershell
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```

2. **Make your changes** following our [coding guidelines](#coding-guidelines)

3. **Test your changes** locally

4. **Commit** with a clear message:
   ```powershell
   git commit -m "feat: add new feature description"
   # or
   git commit -m "fix: resolve issue with..."
   ```

### Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

| Type | Description |
|------|-------------|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `docs:` | Documentation changes |
| `style:` | Code style changes (formatting, etc.) |
| `refactor:` | Code refactoring |
| `test:` | Adding or updating tests |
| `chore:` | Maintenance tasks |

## Coding Guidelines

### PowerShell Style

- Use **PascalCase** for function names with approved verbs: `Get-Something`, `Set-Something`
- Use **PascalCase** for parameters: `-ParameterName`
- Use **camelCase** for local variables: `$myVariable`
- Include **comment-based help** for all public functions
- Follow [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) rules

### File Organization

| Folder | Purpose |
|--------|---------|
| `source/Public/` | Exported functions (one function per file) |
| `source/Private/` | Internal functions (not exported) |
| `source/Classes/` | PowerShell classes |
| `source/GUI/` | WPF XAML and GUI-related code |
| `tests/Unit/` | Unit tests |

### Example Function Template

```powershell
function Get-Example {
    <#
    .SYNOPSIS
        Brief description of the function.

    .DESCRIPTION
        Detailed description of what the function does.

    .PARAMETER Name
        Description of the parameter.

    .EXAMPLE
        Get-Example -Name "Test"

        Description of what this example does.

    .OUTPUTS
        System.String

    .NOTES
        Author: Your Name
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    begin {
        Write-Verbose "Starting Get-Example"
    }

    process {
        # Your code here
    }

    end {
        Write-Verbose "Completed Get-Example"
    }
}
```

## Testing

### Writing Tests

- Place tests in `tests/Unit/` mirroring the source structure
- Name test files: `FunctionName.tests.ps1`
- Use Pester 5.x syntax

### Test Example

```powershell
BeforeAll {
    $script:moduleName = 'PSWimToolkit'
    Import-Module -Name $script:moduleName -Force
}

AfterAll {
    Get-Module -Name $script:moduleName -All | Remove-Module -Force
}

Describe 'Get-Example' {
    Context 'When called with valid parameters' {
        It 'Should return expected result' {
            $result = Get-Example -Name 'Test'
            $result | Should -Not -BeNullOrEmpty
        }
    }
}
```

## Submitting Changes

1. **Push** your branch to your fork:
   ```powershell
   git push origin feature/your-feature-name
   ```

2. **Open a Pull Request** on GitHub:
   - Target the `main` branch
   - Fill out the PR template
   - Link any related issues

3. **Wait for review**:
   - CI checks must pass (lint, tests)
   - Address any feedback from reviewers

4. **Merge**: Once approved, your PR will be merged! 🎉

## Questions?

- 💬 Open a [Discussion](https://github.com/mchave3/PSWimToolkit/discussions)
- 🐛 Report a [Bug](https://github.com/mchave3/PSWimToolkit/issues/new?template=bug_report.yml)

---

Thank you for contributing! 🙏
