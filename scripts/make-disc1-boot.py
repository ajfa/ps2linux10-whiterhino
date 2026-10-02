#!/usr/bin/env python3
"""Make a copy of PS2 Linux 1.0 DISC 1 whose "Rescue" button boots the installed system.

The "Boot" button of this Runtime Environment is disabled (its strings say "This function
isn't implemented yet"). DISC 1's p2lboot.cnf has a ".Rescue" entry that boots the DISC 2
kernel with the rescue initrd; this rewrites that one entry, in place and with the same
length, to boot the kernel with root=/dev/hda1 and no initrd. Nothing else changes: the
RTE has its own CD reader and rejects any re-mastered image.

Usage: make-disc1-boot.py DISC1.iso DISC1-boot.iso
"""
import shutil
import sys

src, dst = sys.argv[1], sys.argv[2]
old = b".Rescue\t\t/boot/ps2/vmlinux.ker\t/boot/ps2/initrd.ins\t203 \x5c\n\t\t\t/dev/cdrom rescue\n"
new = b'.Rescue\t\t/boot/ps2/vmlinux.ker\t""\t203 /dev/hda1\n#'
new += b"#" * (len(old) - len(new) - 1) + b"\n"
assert len(new) == len(old)

shutil.copyfile(src, dst)
with open(dst, "r+b") as f:
    data = f.read()
    pos = data.find(old)
    if pos < 0 or data.find(old, pos + 1) >= 0:
        sys.exit("p2lboot.cnf entry not found exactly once: is this PS2 Linux 1.0 DISC 1?")
    f.seek(pos)
    f.write(new)
print("written", dst)
