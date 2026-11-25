# Rows of the previous Michigan files that belong to filings no longer in the MiTN export (their doc_seq_no does not
# appear in the new data at all), written out as they were in those files so mi_contribs.R / mi_expends.R can add
# them. Rows from filings that are still in the export are not carried over.
#   python3 state/mi/code/carry_over.py      (from the repo root, after unzipping the raw files to state/mi/data/raw/)
# Reads state/mi/{contribs,expends}/data/old/ and state/mi/data/raw/; writes
# state/mi/{contribs,expends}/data/carry/carry_over.csv and prints counts by statement year.
# The two earlier contribution files overlap (both hold some 2021 statements); a row whose
# (doc_seq_no, contribution_id, cont_detail_id) was already carried from the first file is not carried again.
import codecs, csv, collections, glob, os, sys
# The earlier files are mostly UTF-8 with some windows-1252 bytes (e.g. 0x92); invalid UTF-8 bytes are read as
# windows-1252 (Latin-1 where undefined), so the carried rows are written as UTF-8.
def cp1252_fallback(e):
    b = e.object[e.start:e.end]
    return ''.join(bytes([c]).decode('cp1252', 'replace') if c not in (0x81, 0x8d, 0x8f, 0x90, 0x9d) else chr(c) for c in b), e.end
codecs.register_error('cp1252_fallback', cp1252_fallback)
csv.field_size_limit(10**8)
R = os.path.join('state', 'mi')

def new_docs(kind):
    docs = set()
    for f in glob.glob(os.path.join(R, 'data', 'raw', kind + '_*', '*.txt')):
        with open(f, encoding='utf-8') as g:
            next(g)
            for ln in g:
                docs.add(ln.split('\t', 1)[0].strip())
    return docs

def carry(kind, ds, old_files, id_cols):
    docs = new_docs(kind)
    out_dir = os.path.join(R, ds, 'data', 'carry'); os.makedirs(out_dir, exist_ok=True)
    seen = set(); by_year = collections.Counter(); hdr = None; n = 0
    with open(os.path.join(out_dir, 'carry_over.csv'), 'w', newline='', encoding='utf-8') as o:
        w = None
        for fn in old_files:
            with open(os.path.join(R, ds, 'data', 'old', fn), encoding='utf-8', errors='cp1252_fallback') as g:
                r = csv.reader(g); h = next(r)
                if hdr is None:
                    hdr = h; w = csv.writer(o); w.writerow(h + ['source_file'])
                assert h == hdr, fn
                ix = {k: i for i, k in enumerate(h)}
                this = set()
                for row in r:
                    if row[ix['doc_seq_no']] in docs:
                        continue
                    k = tuple(row[ix[c]] for c in id_cols)
                    if k in seen:
                        continue
                    this.add(k); w.writerow(row + [fn]); n += 1; by_year[row[ix['doc_stmnt_year']]] += 1
                seen |= this
    print(ds, 'new filings:', len(docs), ' carried rows:', n)
    for y in sorted(by_year): print(' ', y, by_year[y])

carry('Contribution', 'contribs', ['mi_contribs_clean.csv', 'mi_contribs_clean_2021-2022.csv'],
      ['doc_seq_no', 'contribution_id', 'cont_detail_id'])
carry('Expenditure', 'expends', ['mi_expends_clean.csv'], ['doc_seq_no', 'expense_id', 'detail_id'])
