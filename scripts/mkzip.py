#!/usr/bin/env python3
"""Create a zip from a list of files, preserving relative paths.

Usage: python3 scripts/mkzip.py <out.zip> <file> [file...]
Fallback for scripts/dist.sh when the `zip` binary is not available.
"""
import os
import sys
import zipfile


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    out, files = sys.argv[1], sys.argv[2:]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            zf.write(f, f.replace(os.sep, "/"))
    with zipfile.ZipFile(out) as zf:
        bad = zf.testzip()
        if bad is not None:
            print(f"mkzip.py: corrupt entry: {bad}", file=sys.stderr)
            return 1
        print(f"mkzip.py: wrote {out} ({len(zf.namelist())} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
