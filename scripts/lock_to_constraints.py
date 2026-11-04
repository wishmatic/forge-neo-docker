"""
Writes a pip constraints file from requirements.lock.

pip cannot take hashes or direct URLs in a constraints file, so this strips the
lock down to name==version and appends the pins that are installed outside it.
"""

import re
import sys

lock, extra_pins = sys.argv[1], sys.argv[2:]

with open(lock, encoding="utf-8") as handle:
    for raw in handle:
        if raw[0].isspace() or raw.startswith(("#", "-", "\n")):
            continue

        spec = raw.split(" \\")[0].strip()
        if " @ " in spec:
            name, url = spec.split(" @ ", 1)
            filename = url.rsplit("/", 1)[-1]
            version = re.search(r"-(\d[^-]*)-", filename)
            if version is None:
                sys.exit(f"cannot read a version out of {filename}")
            print(f"{name}=={version.group(1)}")
        else:
            print(spec)

for pin in extra_pins:
    print(pin)
