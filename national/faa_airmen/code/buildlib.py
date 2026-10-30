# Copied 2026-10-30 from the datacleaning_agents repo (tools/buildlib.py): helpers used by build.py.
#
"""Small helpers shared by datasets/*/build.py: column naming, ZIP5, sha256, build log."""
import hashlib
import json
import os
import re
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def snake(name):
    """'OTHER NAMES(1)' -> 'other_names_1', 'TYPE-ACFT' -> 'type_acft', ' FIRST NAME' -> 'first_name'."""
    return re.sub(r'[^a-z0-9]+', '_', name.strip().lower()).strip('_')


def uszip5(zip_code, country):
    """First five digits of a US ZIP (ZIP+4 with or without the dash); blank for non-US or malformed."""
    if country.strip().upper() not in ('US', 'USA'):
        return ''
    digits = re.sub(r'\D', '', zip_code)
    return digits[:5] if len(digits) >= 5 else ''


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(8 * 2 ** 20), b''):
            h.update(chunk)
    return h.hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds')


def log_build(ds_dir, rec):
    with open(os.path.join(ds_dir, 'builds.jsonl'), 'a') as f:
        f.write(json.dumps(rec) + '\n')


def rel(path):
    return os.path.relpath(path, HERE)
