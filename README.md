# CPU Limit Tool

Simple Linux CPU limiter script for reducing heat and power usage on old laptops (tested on low-power CPUs like Intel Atom series).

## Features

- Switch CPU to `powersave` governor
- Limit max CPU frequency to minimum available
- Disable Intel Turbo Boost (if available)
- Optional core disabling (keeps system cooler)
- Full restore mode (returns original settings)
- Temporary state (resets after reboot if not restored)

---

## ⚙️ Usage

### Make executable
```bash
chmod +x cpu-limit.sh
