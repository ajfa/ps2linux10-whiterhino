#!/bin/bash
# Builds a PS2 Linux 1.0 hard disk image from DISC 2, outside the PS2: the 375 packages of
# "WindowMaker Workstation" unpacked into hda1, owners and modes from the RPM headers,
# configuration as the Sony installer writes it, and a first-boot script that runs the
# RPM %pre/%post scriptlets and registers the packages inside the PS2.
#
# Usage (as root):  DISC2=path/to/DISC2.iso HDD=ps2linux-hdd.raw ./build-hdd.sh
# Optional: TZ_NAME (default UTC), ROOT_PASSWORD and USER_PASSWORD (default ps2linux).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
CONF=$HERE/../config
: "${DISC2:?set DISC2 to the DISC 2 ISO}"
: "${HDD:?set HDD to the disk image to create}"
TZ_NAME=${TZ_NAME:-UTC}
ROOT_PASSWORD=${ROOT_PASSWORD:-ps2linux}
USER_PASSWORD=${USER_PASSWORD:-ps2linux}
WORK=$(mktemp -d)
D2=$WORK/disc2
R=$WORK/root
mkdir -p "$D2" "$R"
mount -o loop,ro "$DISC2" "$D2"
RPMS=$D2/SCEI/RPMS
LOOP=
cleanup() {
	umount "$R" 2>/dev/null || true
	[ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null || true
	umount "$D2" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT

# DOS partition table as the Sony installer leaves it: hda1 ext2 (/), hda5 swap.
rm -f "$HDD"
truncate -s $(( (3800126 + 262144) * 512 )) "$HDD"
sfdisk -q "$HDD" <<'TABLE'
label: dos
unit: sectors
start=63, size=3800000, type=83, bootable
start=3800063, size=262207, type=5
start=3800126, size=262144, type=82
TABLE
SWAP=$(losetup -f --show -o $((3800126 * 512)) --sizelimit $((262144 * 512)) "$HDD")
mkswap "$SWAP" >/dev/null; losetup -d "$SWAP"
LOOP=$(losetup -f --show -o $((63 * 512)) --sizelimit $((3800000 * 512)) "$HDD")
# ext2 revision 0 with no newer features: what Sony's Linux 2.2.1 kernel reads.
mke2fs -q -t ext2 -r 0 -b 4096 "$LOOP"
mount -t ext2 "$LOOP" "$R"

echo "Unpacking $(wc -l < "$CONF/packages.txt") packages..."
while read -r f; do
	rpm2cpio "$RPMS/$f" | (cd "$R" && cpio -idmu --quiet --no-preserve-owner 2>/dev/null) || echo "warning: cpio $f"
done < "$CONF/packages.txt"

# Owner, group and mode of every packaged file, from the RPM headers (what
# "rpm --setugids --setperms" does, which takes hours inside the emulated PS2).
for f in $(cat "$CONF/packages.txt"); do
	rpm -qp --nosignature --qf '[%{FILEUSERNAME} %{FILEGROUPNAME} %{FILEMODES:octal} %{FILENAMES}\n]' "$RPMS/$f" 2>/dev/null
done > "$WORK/owners.txt"
python3 - "$R" "$WORK/owners.txt" <<'PY'
import os, stat, sys
root, listing = sys.argv[1], sys.argv[2]
uid = {l.split(":")[0]: int(l.split(":")[2]) for l in open(root + "/etc/passwd") if l.count(":") >= 3}
gid = {l.split(":")[0]: int(l.split(":")[2]) for l in open(root + "/etc/group") if l.count(":") >= 3}
for line in open(listing, errors="replace"):
    p = line.rstrip("\n").split(" ", 3)
    if len(p) < 4 or not os.path.lexists(root + p[3]):
        continue
    os.lchown(root + p[3], uid.get(p[0], 0), gid.get(p[1], 0))
    if not os.path.islink(root + p[3]):
        os.chmod(root + p[3], stat.S_IMODE(int(p[2], 8)))
PY

# Soname links, which ldconfig would create inside the PS2.
printf '/usr/X11R6/lib\n/usr/lib\n' > "$R/etc/ld.so.conf"
for d in /lib /usr/lib /usr/X11R6/lib; do
	for f in "$R$d"/*.so.*; do
		[ -f "$f" ] && [ ! -L "$f" ] || continue
		so=$(readelf -d "$f" 2>/dev/null | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p')
		[ -n "$so" ] && [ "$so" != "$(basename "$f")" ] && [ ! -e "$R$d/$so" ] && ln -s "$(basename "$f")" "$R$d/$so"
	done
done

# Configuration written by the Sony installer (todo.py) after the copy.
F="%-23s %-23s %-7s %-15s %d %d\n"
{
	printf "$F" /dev/hda1 / ext2 check=none 1 1
	printf "$F" /dev/cdrom /mnt/cdrom iso9660 noauto,owner,ro,check=r 0 0
	printf "$F" /dev/hda5 swap swap defaults 0 0
	printf "$F" /dev/ps2mc00 /mnt/mc00 ps2mcfs noauto,owner 0 0
	printf "$F" /dev/ps2mc10 /mnt/mc10 ps2mcfs noauto,owner 0 0
	printf "$F" none /proc/bus/usb usbdevfs defaults 0 0
	printf "$F" none /proc proc defaults 0 0
	printf "$F" none /dev/pts devpts gid=5,mode=620 0 0
} > "$R/etc/fstab"
: > "$R/etc/mtab"
mkdir -p "$R/mnt/cdrom" "$R/mnt/mc00" "$R/mnt/mc10"
ln -sf ps2cdvd "$R/dev/cdrom"
ln -sf usbmouse "$R/dev/mouse"
printf 'LANG="en_US"\n' > "$R/etc/sysconfig/i18n"
printf 'KEYTABLE="us"\n' > "$R/etc/sysconfig/keyboard"
printf 'MOUSETYPE="ps/2"\nXMOUSETYPE="PS/2"\nFULLNAME="Generic - 2 Button Mouse (PS/2)"\nXEMU3="yes"\n' > "$R/etc/sysconfig/mouse"
printf 'NETWORKING=yes\nFORWARD_IPV4=false\nHOSTNAME=ps2linux\nGATEWAY=\n' > "$R/etc/sysconfig/network"
printf 'DEVICE=eth0\nBOOTPROTO=dhcp\nONBOOT=yes\n' > "$R/etc/sysconfig/network-scripts/ifcfg-eth0"
printf '127.0.0.1\t\tps2linux localhost.localdomain localhost\n' > "$R/etc/hosts"
cp "$R/usr/share/zoneinfo/$TZ_NAME" "$R/etc/localtime"
printf 'ZONE="%s"\nUTC=true\nARC=false\n' "$TZ_NAME" > "$R/etc/sysconfig/clock"
printf 'WindowMaker' > "$R/etc/sysconfig/desktop"
sed -i 's/^id:[0-9]:/id:5:/' "$R/etc/inittab"
# X: the GS server, VESA 800x600 at 24 bits (Sony's default), no pointer acceleration
# so the guest pointer follows the host mouse one to one.
ln -sf ../../usr/X11R6/bin/Xgsx "$R/etc/X11/X"
cp "$CONF/XGSConfig" "$R/etc/X11/XGSConfig"
printf '\n# no pointer acceleration: the guest pointer follows the host mouse\n/usr/X11R6/bin/xset m 1 1\n' >> "$R/etc/X11/wdm/Xsetup_0"

# RPM %pre/%post scriptlets, run in order inside the PS2 on the first boot.
mkdir -p "$R/root/rpm-scriptlets"
n=0
for f in $(cat "$CONF/packages.txt"); do
	n=$((n + 1))
	for t in PRE:a POST:b; do
		prog=$(rpm -qp --nosignature --qf "%{${t%:*}INPROG}" "$RPMS/$f" 2>/dev/null)
		body=$(rpm -qp --nosignature --qf "%{${t%:*}IN}" "$RPMS/$f" 2>/dev/null)
		[ "$prog" = "(none)" ] && prog=""; [ "$body" = "(none)" ] && body=""
		[ -z "$prog$body" ] && continue
		{ echo "${prog:-/bin/sh}"; echo "$body"; } > "$(printf '%s/root/rpm-scriptlets/%03d%s-%s' "$R" $n "${t#*:}" "${f%.rpm}")"
	done
done
cp "$CONF/packages.txt" "$R/root/packages.txt"
# The RPMs themselves, so the first boot can register them without a disc in the drive.
mkdir -p "$R/var/tmp/first-boot-rpms"
while read -r f; do cp "$RPMS/$f" "$R/var/tmp/first-boot-rpms/"; done < "$CONF/packages.txt"
cat > "$R/root/first-boot.sh" <<EOF
#!/bin/sh
# Runs once from rc.local: what rpm and the Sony installer do inside the PS2.
exec > /root/first-boot.log 2>&1
set -x
/sbin/ldconfig
for s in /root/rpm-scriptlets/*; do
	prog=\`head -1 \$s\`
	[ "\$prog" = /sbin/ldconfig ] && continue
	tail +2 \$s > /tmp/rpm-script
	echo "== \$s"
	\$prog /tmp/rpm-script 1
done
rm -f /tmp/rpm-script
/sbin/ldconfig
/usr/sbin/authconfig --kickstart --nostart --useshadow --enablemd5
echo $ROOT_PASSWORD | /usr/bin/passwd --stdin root
/usr/sbin/useradd ps2
/usr/bin/chfn -f "PS2 User" ps2
echo $USER_PASSWORD | /usr/bin/passwd --stdin ps2
for s in FreeWnn autofs cWnn gpm httpd ipchain identd kWnn kudzu ldap linuxconf ndtpd netfs nfs nfslock rskkserv sendmail sshd tWnn; do
	/sbin/chkconfig --level 2345 \$s off
done
/sbin/chkconfig --level 0123456 lvm off
# Register the packages from the copies left on the disk (rpm 3.0.4 miscounts free space).
mkdir -p /var/lib/rpm
rpm --initdb
cd /var/tmp/first-boot-rpms
rpm -ivh --justdb --nodeps --force --noscripts --ignoresize \`cat /root/packages.txt\`
cd /
rm -rf /var/tmp/first-boot-rpms
# The scriptlets added these services after their rc slots had passed; run them now so
# X comes up on this same boot: the X font server, and xinitrc, which writes the site
# default session (wmaker) that Xclients needs.
/etc/rc.d/init.d/xfs start
/etc/rc.d/init.d/xinitrc start
echo FIRST_BOOT_DONE
EOF
chmod 755 "$R/root/first-boot.sh"
cat >> "$R/etc/rc.d/rc.local" <<'EOF'

# first boot of a system installed from outside the PS2 (runs once)
if [ -x /root/first-boot.sh ] && [ ! -f /root/.first-boot-done ]; then
	echo "First boot: running package scripts and registering packages (takes a while)..."
	/root/first-boot.sh
	touch /root/.first-boot-done
	echo "First boot done (see /root/first-boot.log)"
fi
EOF
sync
df -h "$R" | tail -1
echo "Built $HDD"
