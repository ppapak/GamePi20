#!/bin/bash
set -e

if [ $EUID -ne 0 ]; then
    exec sudo "$0" "$@"
fi

USAGE="Usage: $0 {-zero|-zero2} {-32|-64}"

TARGET_TARGET=""
TARGET_ARCH=""

while [ $# -gt 0 ]; do
    case "$1" in
        -zero)
            TARGET_TARGET="zero"
            ;;
        -zero2)
            TARGET_TARGET="zero2"
            ;;
        -32)
            TARGET_ARCH="32"
            ;;
        -64)
            TARGET_ARCH="64"
            ;;
        *)
            echo "$USAGE"
            exit 1
            ;;
    esac
    shift
done

if [ -z "$TARGET_TARGET" ] || [ -z "$TARGET_ARCH" ]; then
    echo "Error: Both target device and architecture flags must be specified."
    echo "$USAGE"
    exit 1
fi

if [ "$TARGET_TARGET" = "zero" ] && [ "$TARGET_ARCH" = "64" ]; then
    echo "Error: Raspberry Pi Zero W does not support 64 bit architecture."
    exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

export DEBIAN_FRONTEND=noninteractive

echo "Step 1: Executing system package updates and configuring multiarch architectures."
apt-get update && apt-get full-upgrade -y

if [ "$TARGET_ARCH" = "32" ]; then
    dpkg --add-architecture armhf
    apt-get update
    apt-get install -y locales-all git build-essential dkms wget python3 device-tree-compiler gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf
else
    apt-get install -y locales-all git build-essential dkms wget python3 device-tree-compiler
fi

echo "Step 2: Generating en_US.UTF-8 locale and modifying SSH environment configuration."
sed -i -e 's/^#\ *en_US.UTF-8\ UTF-8/en_US.UTF-8\ UTF-8/' /etc/locale.gen
locale-gen en_US.UTF-8

cat << LOCALE_CONF > /etc/default/locale
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LOCALE_CONF

sed -i 's/^AcceptEnv\ LANG\ LC_*/#\ AcceptEnv\ LANG\ LC_*/' /etc/ssh/sshd_config

echo "Step 3: Activating Raspberry Pi USB gadget mode."
if command -v rpi-usb-gadget >/dev/null 2>&1; then
    rpi-usb-gadget on
else
    echo "Utility rpi-usb-gadget missing. Skipping step."
fi

echo "Step 4: Installing target specific linux headers."
if [ "$TARGET_TARGET" = "zero" ]; then
    apt-get install -y linux-headers-rpi-v6:armhf
elif [ "$TARGET_TARGET" = "zero2" ] && [ "$TARGET_ARCH" = "32" ]; then
    apt-get install -y linux-headers-rpi-v7l:armhf
else
    apt-get install -y linux-headers-rpi-v8
fi

echo "Step 5: Display Firmware Configuration."
WORKSPACE=/tmp/gamepi20_setup
mkdir -p $WORKSPACE
cd $WORKSPACE

git clone https://github.com/notro/panel-mipi-dbi.git
cd panel-mipi-dbi

cat << EOF > gamepi20.txt
command 0x11
delay 120
command 0x36 0xB0
command 0x3a 0x05
command 0x21
command 0x29
delay 120
EOF

python3 mipi-dbi-cmd gamepi20.bin gamepi20.txt
cp gamepi20.bin /lib/firmware/
cd $WORKSPACE

echo "Step 6: Gamepad Device Tree Compilation."
cat << EOF > gamepi20-buttons.dts
/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2835";

    fragment@0 {
        target = <&gpio>;
        __overlay__ {
            gamepi20_pins: gamepi20_pins {
                brcm,pins = <4 5 6 12 13 16 17 20 21 22 23 26>;
                brcm,function = <0>;
                brcm,pull = <2>;
            };
        };
    };

    fragment@1 {
        target-path = "/";
        __overlay__ {
            gamepi20_buttons: gamepi20_buttons {
                compatible = "gpio-keys";
                pinctrl-names = "default";
                pinctrl-0 = <&gamepi20_pins>;
                status = "okay";

                button_up {
                    label = "UP";
                    linux,code = <544>;
                    gpios = <&gpio 12 1>;
                };
                button_down {
                    label = "DOWN";
                    linux,code = <545>;
                    gpios = <&gpio 20 1>;
                };
                button_left {
                    label = "LEFT";
                    linux,code = <546>;
                    gpios = <&gpio 21 1>;
                };
                button_right {
                    label = "RIGHT";
                    linux,code = <547>;
                    gpios = <&gpio 13 1>;
                };
                button_start {
                    label = "START";
                    linux,code = <315>;
                    gpios = <&gpio 26 1>;
                };
                button_select {
                    label = "SELECT";
                    linux,code = <314>;
                    gpios = <&gpio 16 1>;
                };
                button_a {
                    label = "A";
                    linux,code = <304>;
                    gpios = <&gpio 23 1>;
                };
                button_b {
                    label = "B";
                    linux,code = <305>;
                    gpios = <&gpio 4 1>;
                };
                button_tr {
                    label = "TR";
                    linux,code = <311>;
                    gpios = <&gpio 6 1>;
                };
                button_y {
                    label = "Y";
                    linux,code = <308>;
                    gpios = <&gpio 17 1>;
                };
                button_x {
                    label = "X";
                    linux,code = <307>;
                    gpios = <&gpio 22 1>;
                };
                button_tl {
                    label = "TL";
                    linux,code = <310>;
                    gpios = <&gpio 5 1>;
                };
            };
        };
    };
};
EOF

dtc -@ -I dts -O dtb -o gamepi20-buttons.dtbo gamepi20-buttons.dts

if [ -d /boot/firmware/overlays ]; then
    cp gamepi20-buttons.dtbo /boot/firmware/overlays/
fi
if [ -d /boot/overlays ]; then
    cp gamepi20-buttons.dtbo /boot/overlays/
fi

echo "Step 7: Udev Subsystem Rule Deployment."
cat << EOF > 99-gamepi.rules
SUBSYSTEM=="input", ATTRS{name}=="gamepi20_buttons", ENV{ID_INPUT_JOYSTICK}="1", ENV{ID_INPUT_KEYBOARD}="0"
EOF

cp 99-gamepi.rules /etc/udev/rules.d/

echo "Step 8: Main Boot Parameter Appending via Hardware Filters."
CONFIG_PATH="/boot/firmware/config.txt"
if [ ! -f "$CONFIG_PATH" ]; then
    CONFIG_PATH="/boot/config.txt"
fi

if [ -f "$CONFIG_PATH" ] && [ ! -f "${CONFIG_PATH}.bak" ]; then
    cp "$CONFIG_PATH" "${CONFIG_PATH}.bak"
fi

sed -i '/dtoverlay=vc4-kms-v3d/d' "$CONFIG_PATH"

cat << EOF >> "$CONFIG_PATH"
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
EOF

cd /
rm -rf $WORKSPACE

echo Step 9: Cloning RetroPie setup and initiating basic installation protocol.
if [ ! -d "$USER_HOME/RetroPie-Setup" ]; then
    sudo -u "$REAL_USER" git clone --depth=1 https://github.com/RetroPie/RetroPie-Setup.git "$USER_HOME/RetroPie-Setup"
fi
cd "$USER_HOME/RetroPie-Setup"
chmod +x retropie_packages.sh

export __platform=rpi3
./retropie_packages.sh setup basic_install
./retropie_packages.sh samba

echo "Setup execution complete. System requires a reboot to apply hardware configurations."
echo "Command to execute: sudo reboot"
