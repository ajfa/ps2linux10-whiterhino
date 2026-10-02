#!/bin/sh
# Boots PS2 Linux 1.0 from the hard disk image in the patched WhiteRhino, in a window.
#
# Environment (paths; the defaults are relative to this directory):
#   PCSX2      the patched pcsx2-qt binary           (default ../whiterhino/build/bin/pcsx2-qt)
#   BIOS_DIR   directory with the PS2 BIOS           (default ../bios)
#   BIOS_FILE  BIOS file name in BIOS_DIR            (default "PS2 Bios 30004R V6 Pal.bin")
#   DISC1_BOOT DISC 1 made by make-disc1-boot.py     (default ../media/DISC1-boot.iso)
#   DISC2      DISC 2 ISO                            (default ../media/DISC2.iso)
#   HDD        disk image made by build-hdd.sh       (default ../ps2linux-hdd.raw)
#
# In the blue Runtime Environment menu press Right once (it lands on "Rescue", which in
# this setup boots the installed system) and then Enter.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
PCSX2=${PCSX2:-$HERE/../whiterhino/build/bin/pcsx2-qt}
BIOS_DIR=${BIOS_DIR:-$HERE/../bios}
BIOS_FILE=${BIOS_FILE:-PS2 Bios 30004R V6 Pal.bin}
DISC1_BOOT=${DISC1_BOOT:-$HERE/../media/DISC1-boot.iso}
DISC2=${DISC2:-$HERE/../media/DISC2.iso}
HDD=${HDD:-$HERE/../ps2linux-hdd.raw}
CFG=${XDG_CONFIG_HOME:-$HERE/../config}

mkdir -p "$CFG/PCSX2/inis"
cat > "$CFG/PCSX2/inis/PCSX2.ini" <<INI
[UI]
SettingsVersion = 1
SetupWizardIncomplete = false
ConfirmShutdown = false
StartFullscreen = false
[Folders]
Bios = $BIOS_DIR
[Filenames]
BIOS = $BIOS_FILE
[EmuCore/CPU]
ExtraMemory = false
[EmuCore/CPU/Recompiler]
EnableEE = false
[EmuCore/GS]
Renderer = 13
[SPU2/Output]
Backend = Null
[DEV9/Hdd]
HddEnable = true
HddFile = $HDD
[DEV9/Eth]
EthEnable = true
EthApi = Sockets
EthDevice = Auto
InterceptDHCP = true
AutoMask = true
AutoGateway = true
[USB1]
Type = hidkbd
[USB2]
Type = hidmouse
hidmouse_Pointer = Pointer-0
hidmouse_LeftButton = Pointer-0/LeftButton
hidmouse_RightButton = Pointer-0/RightButton
hidmouse_MiddleButton = Pointer-0/MiddleButton
[AutoUpdater]
CheckAtStartup = false
INI

export XDG_CONFIG_HOME="$CFG"
# Guest kernel entry point (Sony's Linux 2.2.1, from System.map).
export WHITERHINO_GUEST_ENTRY=0x800103a0
# The emulator swaps DISC 2 / DISC 1 when the Runtime Environment asks for them.
export WHITERHINO_DISC_HOOK_PC=0x010067a4
export WHITERHINO_DISC_A="$DISC1_BOOT"
export WHITERHINO_DISC_B="$DISC2"
# USB mouse without grabbing the host pointer, scaled to the 800x600 guest screen.
export WHITERHINO_MOUSE_ABSOLUTE=1
export WHITERHINO_MOUSE_GUEST_W=800
export LIBGL_ALWAYS_SOFTWARE=1
[ -n "$DISPLAY" ] && export QT_QPA_PLATFORM=xcb
exec "$PCSX2" -nogui -logfile "$CFG/emulator.log" -- "$DISC1_BOOT"
