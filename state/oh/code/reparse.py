"""Parse the Ohio Campaign Finance System bulk downloads ("All Candidate & Non-Candidate Committee Files",
https://campaignfinance.ohiosos.gov/public/cf/downloads) into clean CSVs for R.
  python3 state/oh/code/reparse.py <raw dir[,raw dir...]> <kind: contributions|expenditures> <out csv>
Format of the downloads: records end with CRLF; fields are comma-separated and wrapped in quotes only when they hold a
comma; quotes inside values are NOT escaped (e.g. "PATEL, NIRANJAN "NEIL"" and, unquoted, KERMIN "IKE"). So a standard
CSV reader misreads quoted fields that contain quotes; scan() reads a quoted field up to the next '",' instead.
Problems handled (counts are printed and written to <out>.log):
- bare LF inside unquoted fields (e.g. "FANEUFF,\\nJOAN"): records are split on CRLF only, so these stay in the field;
- CRLF inside a field: the record continues on the next line; the two lines are joined (with the CRLF kept);
- quotes that are not escaped (e.g. ""JOE" DICKEY ELECTRIC, INC."): the record is split into fields by segment().
A parse is accepted only if it has the header's field count and a date in Transaction Date, a $ amount in Transaction
Amount and Y/N in Amended. Records no parse fits go to <out>.rejects.txt (none are dropped silently).
Files are UTF-8; one (1995 contributions) has a windows-1252 byte and is read as windows-1252.
ZIPs are exported as ="44484" (an Excel text formula); the wrapper is removed. Everything else is kept as published."""
import csv, glob, io, os, re, sys

raw_dir, kind, out = sys.argv[1], sys.argv[2], sys.argv[3]
DATE = re.compile(r"^\d\d/\d\d/\d{4}$")
XLS = re.compile(r'^="(.*)"$')


def parse(rec):
    """A field starting with a quote runs to the next '",' (or to a final quote at the end of the record); the outer
    quotes are removed and nothing inside is unescaped. Other fields run to the next comma."""
    out, i, n = [], 0, len(rec)
    while True:
        if i < n and rec[i] == '"':
            j = rec.find('",', i + 1)
            if j == -1 and n - 1 > i and rec.endswith('"'):
                j = n - 1
            if j != -1:
                out.append(rec[i + 1:j]); i = j + 2
                if i > n: return out
                continue
        k = rec.find(",", i)
        if k == -1:
            out.append(rec[i:]); return out
        out.append(rec[i:k]); i = k + 1


def std(rec):
    # the csv module's reading, only to count records where the two differ
    x = next(csv.reader([rec.replace("\r", "\x1e").replace("\n", "\x1f")]))
    return [v.replace("\x1e", "\r").replace("\x1f", "\n") for v in x]


def segment(rec, ok):
    """Group the comma-separated pieces of a record into fields: a field of several pieces must start and end with
    a quote (a quoted field holding commas); a one-piece field is anything. Returns the first grouping that passes
    ok(). A field that starts and ends with a quote loses that outer pair; other quotes are kept as text."""
    toks = rec.split(",")
    def strip(v):
        return v[1:-1] if len(v) > 1 and v.startswith('"') and v.endswith('"') else v
    def go(i, acc):
        if i == len(toks):
            x = [strip(v) for v in acc]
            return x if ok(x) else None
        if len(acc) >= 40:
            return None
        r = go(i + 1, acc + [toks[i]])
        if r: return r
        if toks[i].startswith('"'):
            for j in range(i + 1, len(toks)):
                v = ",".join(toks[i:j + 1])
                if v.endswith('"'):
                    r = go(j + 1, acc + [v])
                    if r: return r
        return None
    return go(0, [])


def good(x, idx, n):
    return (len(x) == n and DATE.match(x[idx["Transaction Date"]]) and x[idx["Transaction Amount"]].startswith(("$", "-$", "($"))
            and x[idx["Amended"]] in ("Y", "N"))


# raw_dir may list several download folders separated by commas; a year must appear in only one of them
files = sorted((p for d in raw_dir.split(",") for p in glob.glob(os.path.join(d, f"oh_{kind}_[0-9][0-9][0-9][0-9].csv"))),
               key=os.path.basename)
assert len({os.path.basename(p) for p in files}) == len(files), "a year appears in more than one folder"
log = open(out + ".log", "w"); rej = open(out + ".rejects.txt", "w")
w = None; header = None; tot = {}
def say(*a):
    print(*a); print(*a, file=log)
for f in files:
    raw = open(f, "rb").read()
    try:
        txt, enc = raw.decode("utf-8"), "utf-8"
    except UnicodeDecodeError:
        txt, enc = raw.decode("cp1252"), "windows-1252"
    recs = txt.split("\r\n")
    if recs and recs[-1] == "":
        recs.pop()
    h = next(csv.reader([recs[0]])); n = len(h); idx = {k: i for i, k in enumerate(h)}
    if header is None:
        header = h
        w = csv.writer(open(out, "w", newline="", encoding="utf-8"), lineterminator="\n")
        w.writerow(["source_file"] + [re.sub(r"[^a-z0-9]+", "_", k.lower()).strip("_") for k in h])
    elif h != header:
        if [k.lower() for k in h] != [k.lower() for k in header]:
            say("HEADER DIFFERS", os.path.basename(f), h); sys.exit(1)
    c = {"records": 0, "joined": 0, "segmented": 0, "rejected": 0, "bare_lf": 0, "differs_from_csv_module": 0}
    i = 1
    while i < len(recs):
        r = recs[i]; x = parse(r); used = None
        if good(x, idx, n):
            used = "ok"
        else:
            for k in (1, 2):   # CRLF inside a field: join with the next 1-2 lines
                if i + k < len(recs):
                    j = "\r\n".join(recs[i:i + k + 1]); y = parse(j)
                    if good(y, idx, n):
                        x, used = y, "joined"; i += k; break
            if not used:
                y = segment(r, lambda z: good(z, idx, n))
                if y:
                    x, used = y, "segmented"; print(os.path.basename(f), i + 1, "segmented:", y, file=log)
        if not used:
            c["rejected"] += 1; print(os.path.basename(f), i + 1, repr(r), file=rej)
        else:
            if used != "ok": c[used] += 1
            if "\n" in r: c["bare_lf"] += 1
            if '"' in r and used == "ok" and std(r) != x:
                c["differs_from_csv_module"] += 1
                if c["differs_from_csv_module"] <= 3: print(os.path.basename(f), i + 1, "differs:", [v for v in x if '"' in v], file=log)
            x = [XLS.sub(r"\1", v) for v in x]
            w.writerow([os.path.basename(f)] + x); c["records"] += 1
        i += 1
    tot[os.path.basename(f)] = c
    say(os.path.basename(f), enc, c)
say("TOTAL", {k: sum(c[k] for c in tot.values()) for k in ("records", "joined", "segmented", "rejected", "bare_lf", "differs_from_csv_module")})
