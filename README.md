# lumide_java

[![pub package](https://img.shields.io/pub/v/lumide_java.svg)](https://pub.dev/packages/lumide_java) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) [![Powered by SoFluffy](https://img.shields.io/badge/Powered%20by-SoFluffy-orange)](https://sofluffy.io)

The official Java extension for [Lumide IDE](https://lumide.dev).

`lumide_java` provides advanced Java developmental features powered by the Eclipse JDT Language Server. It supports side-by-side installations of JDTLS to maintain compatibility across different JDK versions.

## Features

### 🛠 Comprehensive Java Support
- **Multi-Version JDTLS**: Automatically selects the correct JDTLS version (e.g., v1.38.0 for Java 17, latest for Java 21+).
- **IntelliSense**: High-fidelity code completions, signatures, and documentation.
- **Diagnostics**: Real-time error reporting and semantic analysis.
- **Navigation**: Go-to-definition, find references, and hierarchical symbol search.
- **Refactoring**: Industrial-grade code refactoring tools.

### ⚡ Integrated Experience
- **Auto-Installer**: Downloads and isolates JDTLS versions automatically based on your JDK.
- **Project Detection**: Supports Maven (`pom.xml`) and Gradle (`build.gradle`, `.kts`) projects natively.

## Commands

Access these via the Command Palette (`Cmd+Shift+P` / `Ctrl+Shift+P`):

| Command ID | Title | Description |
|---|---|---|
| `lumide_java.restartLsp` | **Java: Restart Language Server** | Restart the active JDTLS process |
| `lumide_java.reinstallJdtls` | **Java: Reinstall Language Server** | Re-download the active JDTLS |
| `lumide_java.upgradeJdtls` | **Java: Upgrade Language Server** | Upgrade to the latest JDTLS (Java 21+) |

## Requirements

- **JDK 17+**: A Java Development Kit must be installed.
    - Recommended: [Eclipse Temurin](https://adoptium.net)
- **Private Storage**: JDTLS installs in Lumide’s private storage for this plugin.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

Built with ❤️ by [SoFluffy](https://sofluffy.io).

## Happy Coding 🦊
