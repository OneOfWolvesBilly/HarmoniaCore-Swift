# Specs → Impl Mapping

This document shows how specification files map to implementation notes.

## File Mapping

| Spec | Impl | Notes |
|------|------|-------|
| `specs/01_architecture.md` | (n/a) | Architecture is language-agnostic. |
| `specs/02_adapters.md` | `impl/02_01_apple.adapters_impl.md`<br>`impl/02_02_linux.adapters_impl.md` | Per-platform details. |
| `specs/02_01_apple.adapters.md` | `impl/02_01_apple.adapters_impl.md` | Swift adapter implementations. |
| `specs/02_02_linux.adapters.md` | `impl/02_02_linux.adapters_impl.md` | Linux adapter implementations. |
| `specs/03_ports.md` | `impl/03_ports_impl.md` | Concrete Swift / C++ shapes. |
| `specs/04_services.md` | `impl/04_services_impl.md` | Service wiring and examples. |
| `specs/05_models.md` | `impl/05_models_impl.md` | Swift/C++ model definitions. |

## How to Use

1. **Read the Spec first** - Understand the platform-neutral behavior requirements
2. **Then check the Impl** - See concrete code examples for your target platform
3. **Specs define "what"** - Impl shows "how"

## Document Structure

```
docs/
├── specs_to_impl_map.md    # This file (navigation guide)
├── specs/                  # Platform-neutral specifications
│   ├── 01_architecture.md
│   ├── 02_adapters.md
│   ├── 02_01_apple.adapters.md
│   ├── 02_02_linux.adapters.md
│   ├── 03_ports.md
│   ├── 04_services.md
│   └── 05_models.md
└── impl/                   # Platform-specific implementation notes
    ├── 02_01_apple.adapters_impl.md
    ├── 02_02_linux.adapters_impl.md
    ├── 03_ports_impl.md
    ├── 04_services_impl.md
    └── 05_models_impl.md
```