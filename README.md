# PSWimToolkit

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/PSWimToolkit?style=flat-square&logo=powershell&logoColor=white)](https://www.powershellgallery.com/packages/PSWimToolkit)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/PSWimToolkit?style=flat-square)](https://www.powershellgallery.com/packages/PSWimToolkit)
[![License](https://img.shields.io/github/license/mchave3/PSWimToolkit?style=flat-square)](LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/mchave3/PSWimToolkit/lint.yml?style=flat-square&label=lint)](https://github.com/mchave3/PSWimToolkit/actions)

A modern PowerShell toolkit for provisioning Windows images (WIM) with Microsoft Update Catalog integration and automation helpers.

## ✨ Features

- 🖥️ **Modern GUI** - WPF-based graphical interface for easy WIM management
- 📦 **WIM Management** - Mount, unmount, and service Windows images
- 🔄 **Update Integration** - Search and download updates from Microsoft Update Catalog
- 🛠️ **DISM Integration** - Leverage Windows DISM for image servicing
- 📋 **Automation Ready** - PowerShell functions for scripting and automation

## 📋 Requirements

- **Windows** - This module requires Windows OS (DISM, WIM support)
- **PowerShell 7.4+** - PowerShell Core is required
- **Administrator privileges** - Required for mounting/servicing WIM images

## 🚀 Installation

### From PowerShell Gallery (Recommended)

```powershell
Install-Module -Name PSWimToolkit -Scope CurrentUser
```

### From Source

```powershell
# Clone the repository
git clone https://github.com/mchave3/PSWimToolkit.git
cd PSWimToolkit

# Build the module
./build.ps1 -AutoRestore -Tasks build

# Import the built module
Import-Module ./output/module/PSWimToolkit -Force
```

## 📖 Usage

### Launch the GUI

```powershell
# Import the module
Import-Module PSWimToolkit

# Start the graphical interface
Start-PSWimToolkit
```

### GUI Features

The graphical interface allows you to:
- Browse and select WIM/ISO files
- View image information and metadata
- Search Microsoft Update Catalog for updates
- Download and integrate updates into images
- Export modified images

## 🏗️ Project Structure

```
PSWimToolkit/
├── source/
│   ├── Classes/        # PowerShell classes
│   ├── Private/        # Internal functions
│   ├── Public/         # Exported functions
│   ├── GUI/            # WPF XAML and GUI logic
│   └── Types/          # .NET assemblies
├── tests/              # Pester tests
└── docs/               # Documentation
```

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) before submitting a Pull Request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built with [Sampler](https://github.com/gaelcolas/Sampler) module template
- Uses [HtmlAgilityPack](https://html-agility-pack.net/) for HTML parsing

## 📬 Support

- 🐛 [Report a bug](https://github.com/mchave3/PSWimToolkit/issues/new?template=bug_report.yml)
- ✨ [Request a feature](https://github.com/mchave3/PSWimToolkit/issues/new?template=feature_request.yml)
- 💬 [Ask a question](https://github.com/mchave3/PSWimToolkit/discussions)

---

**Author:** Mickael CHAVE

**Project:** [https://github.com/mchave3/PSWimToolkit](https://github.com/mchave3/PSWimToolkit)

