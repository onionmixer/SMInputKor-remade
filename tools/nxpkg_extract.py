#!/usr/bin/env python3
"""
nxpkg_extract.py — extract the non-standard NeXT/OPENSTEP package payload
tar (the inner *.tar[.Z] inside a *.pkg) on Linux.

These payload archives use a tar variant whose numeric header fields sit at
offset 224 (not the standard 100), so GNU/BSD/python tar and even OPENSTEP's
own tar reject them ("directory checksum error 0 != N": standard readers look
for the checksum at offset 148, which is zero here). The file DATA is intact.

Empirically determined header layout (512-byte blocks):
    name   @  0  (100 bytes, NUL-terminated)
    mode   @224  (8, octal)
    uid    @232  (8, octal)
    gid    @240  (8, octal)
    size   @248  (12, octal)
    mtime  @260  (12, octal)
    chksum @272  (8, octal)
Directories are identified by a trailing '/' in the name (size 0).

Usage:
    nxpkg_extract.py <payload.tar> <destdir> [path-prefix-filter]
If a prefix filter is given, only members whose name (after leading './')
starts with it are written. Always lists what it extracts.
"""
import sys, os

BS = 512
OFF_MODE, OFF_SIZE = 224, 248

def octal(b):
    # fields are "\0<spaces>OCTAL<space|\0>"; strip all NULs and spaces
    s = b.translate(None, b'\x00 \t').strip()
    if not s:
        return 0
    try:
        return int(s, 8)
    except ValueError:
        return -1                      # signals "not a valid header field"

def looks_like_header(h):
    """A real header has NUL at offset 224 and an octal mode there."""
    if len(h) < 284 or h[OFF_MODE] != 0:
        return False
    name = h[0:100].split(b'\0')[0]
    if not name:
        return False
    return octal(h[OFF_MODE:OFF_MODE+8]) >= 0 and octal(h[OFF_SIZE:OFF_SIZE+12]) >= 0

def main():
    if len(sys.argv) < 3:
        sys.stderr.write(__doc__)
        sys.exit(2)
    src, dst = sys.argv[1], sys.argv[2]
    pref = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(dst, exist_ok=True)
    n_files = n_dirs = 0
    with open(src, 'rb') as f:
        data = f.read()
    pos = 0
    total = len(data)
    resyncs = 0
    while pos + BS <= total:
        hdr = data[pos:pos+BS]
        if not looks_like_header(hdr):    # drift/pad/bad block: scan forward
            pos += BS
            resyncs += 1
            continue
        name = hdr[0:100].split(b'\0')[0]
        try:
            name = name.decode('latin-1')
        except Exception:
            pos += BS; continue
        size = octal(hdr[OFF_SIZE:OFF_SIZE+12])
        is_dir = name.endswith('/')
        rel = name[2:] if name.startswith('./') else name
        take = (pref is None) or rel.startswith(pref)
        pos += BS
        if is_dir:
            if take and rel:
                os.makedirs(os.path.join(dst, rel), exist_ok=True)
                n_dirs += 1
            continue
        # regular file: data follows, padded to BS
        blocks = (size + BS - 1) // BS
        body = data[pos:pos + size]
        pos += blocks * BS
        if take and rel:
            outp = os.path.join(dst, rel)
            os.makedirs(os.path.dirname(outp), exist_ok=True)
            with open(outp, 'wb') as o:
                o.write(body)
            n_files += 1
    print("extracted %d files, %d dirs -> %s" % (n_files, n_dirs, dst))

if __name__ == '__main__':
    main()
