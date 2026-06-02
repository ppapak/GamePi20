# GamePi20 Retropie single install script 

This is a provisioning script for the GamePi20 provisioning script on a Raspberry Pi Zero and Zero 2 executing Raspberry Pi OS (Debian Trixie Lite) paired with a RetroPie deployment. The script executes kernel-level configurations, compiles device tree structures, maps physical General Purpose Input/Output (GPIO) pins to specific input events, modifies boot parameters, and triggers downstream application compilation.

### Installation

Run the script as root to perform full dependency installation, driver compilation, and boot registration:

```bash
git clone https://github.com/ppapak/GamePi20
cd GamePi20
chmod +x install_pizero.sh
sudo ./install_pizero.sh
```

---

## Parameter Constraints and Environment Setup
The execution requires root privileges. It checks parameters to enforce specific architectural rules:
* Supported arguments: -zero, -zero2, -32, and -64.
* Mandatory definition: Both hardware target and architecture target must be specified via flags.
* Enforced failure condition: Selecting -zero and -64 aborts execution because the Broadcom BCM2835 inside the first-generation Pi Zero lacks 64-bit execution states.
* Environment isolation: Sets DEBIAN_FRONTEND=noninteractive to suppress interactive prompts during package configuration.

---

## Structural Decomposition of Execution Phases

### Phase 1: Package Synchronization and Core Dependencies

The script updates the package index and upgrades all packages to the Debian Trixie baseline. For the specified configuration (Raspberry Pi Zero 2 with 32-bit architecture), the system registers the armhf multiarch architecture and downloads cross-compilation binaries (gcc-arm-linux-gnueabihf). If 64-bit architecture is selected, it omits the cross-compilers and grabs standard native build tools alongside the Device Tree Compiler (device-tree-compiler).

### Phase 2: System Localization and Network Session Controls

Forces system localization to en_US.UTF-8. To preserve locale integrity during remote administration sessions, the script comments out AcceptEnv LANG LC_* within /etc/ssh/sshd_config. This prevents the client machine from pushing non-matching environment variables over SSH, ensuring deterministic text parsing across the console session.

### Phase 3: USB Subsystem Target State

The script checks for the presence of the rpi-usb-gadget utility. If found, it turns on USB gadget mode, allowing the Raspberry Pi Zero 2 to present itself as an Ethernet or serial peripheral over its micro-USB OTG port.

### Phase 4: Kernel Header Targeting

To support out-of-tree kernel modules, specific Linux headers must match the architecture:

* Target: Zero 2 / 32-bit: Installs linux-headers-rpi-v7l:armhf.
* Target: Zero 2 / 64-bit: Installs linux-headers-rpi-v8.

### Phase 5: Display Firmware Configuration and Register Initialization

The script configures an ultra-compact MIPI DBI SPI display panel by interacting with the panel-mipi-dbi platform driver framework. It does not use fbcp and is much faster.

### Phase 6: Gamepad Device Tree Compilation

The script builds a custom Device Tree Overlay (.dts) from scratch to expose the GamePi20 integrated buttons directly to the Linux kernel input subsystem via the gpio-keys driver.

### Phase 7: Input Event Redirection via Udev Subsystem

To ensure emulation frameworks recognize the compiled buttons as a joystick instead of a keyboard, the script deploys a hardware rules file. This forces system software such as SDL2 and RetroArch to treat incoming button events as gamepad inputs.

### Phase 8: Main Boot Parameter Appending via Hardware Filters

The script modifies /boot/firmware/config.txt. It adds parameters tailored to the GamePi20 expansion board:

```ini
[all]
dtoverlay=vc4-kms-v3d,nocma
max_framebuffers=2
display_auto_detect=1
auto_initramfs=1
disable_overscan=1
enable_uart=1
dtparam=spi=on
dtoverlay=mipi-dbi-spi,spi0-0,speed=32000000
dtparam=compatible=gamepi20\\0panel-mipi-dbi-spi
dtparam=width=320,height=240,width-mm=41,height-mm=31
dtparam=reset-gpio=27,dc-gpio=25,backlight-gpio=24
dtparam=write-only
dtoverlay=gamepi20-buttons
dtoverlay=audremap,pins_18_19
audio_pwm_mode=2
gpu_mem=32

```

### Phase 9: RetroPie Core Installation Protocol

The script clones the RetroPie setup tools into the home directory of the actual user executing the script. It forces the platform target variable to rpi3 for cross compilation. This is necessary because the Broadcom BCM2710A1 system-on-chip inside the Raspberry Pi Zero 2 uses the same quad-core ARM Cortex-A53 microarchitecture as the Raspberry Pi 3. It then executes the basic installation command to compile and install core packages (EmulationStation, RetroArch, and fundamental core dependencies) followed by local file sharing services (samba). This is useful as you can use even a Raspberry Pi 5, which is must faster to prepare the SD card.

---