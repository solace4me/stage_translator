"""Open Hymnal (ABC Plus) -> MusicXML, one file per hymn, with all verses.

For each hymn: split the voices, convert each voice on its own with music21
(its multi-voice ABC support merges voices), name the parts S/A/T/B, attach
the w: lyric lines to the voice they follow (verse by verse, refrains copied
to every verse), and check every verse lines up note-for-note."""
import re, sys, json, glob, os, warnings, zipfile, io, copy
import music21 as m21
warnings.filterwarnings('ignore')

NOTE_RE = re.compile(r"""
  (?P<grace>\{[^}]*\})
 |(?P<str>"[^"]*")
 |(?P<deco>![^!\s]*!)
 |(?P<inline>\[[A-Za-z]:[^\]]*\])
 |(?P<chord>\[[^\]|:]*\])
 |(?P<note>[_^=]*[A-Ga-g][,']*)
 |(?P<rest>[zx])
""", re.X)

def count_notes(line):
    """Notes that take a syllable in one ABC music line: (all, without tie continuations)."""
    line = re.sub(r'%.*', '', line)
    total = 0; untied = 0; tie_pending = False
    for m in NOTE_RE.finditer(line):
        if m.group('note') or m.group('chord'):
            total += 1
            if not tie_pending: untied += 1
            rest_of = line[m.end():]
            mm = re.match(r"[0-9/]*\s*(-)", rest_of)
            tie_pending = bool(mm)
        elif m.group('rest'):
            tie_pending = False
    return total, untied

def lyric_tokens(line):
    """ABC w: line -> list of (text, syllabic) or None for '*' (no syllable)."""
    out = []
    line = line.replace('\\-', '\u2011')
    for t in re.findall(r'[^\s_-]+-?|_|-', line):
        if t in ('|',): continue
        if t == '-':            # a lone hyphen: next note continues the word (skip)
            out.append(None); continue
        if t == '_':            # hold previous syllable
            out.append(None); continue
        if t == '*':
            out.append(None); continue
        hy = t.endswith('-')
        text = t.rstrip('-').replace('~', ' ').replace('_', '')
        text = re.sub(r'^\d+\.\s*', '', text)
        if text == '':
            out.append(None); continue
        out.append((text.replace('\u2011', '-'), 'begin' if hy else 'single'))
    # fix syllabic: a syllable after a 'begin' is middle/end
    fixed = []; prev_begin = False
    for t in out:
        if t is None:
            fixed.append(None); continue
        text, syl = t
        if prev_begin: syl = 'middle' if syl == 'begin' else 'end'
        prev_begin = syl in ('begin', 'middle')
        fixed.append((text, syl))
    return fixed

def split_voices(src):
    src = '\n'.join(l for l in src.split('\n') if not l.lstrip().startswith('%'))
    head, rest = src.split('\nK:', 1)
    key_line, body = rest.split('\n', 1)
    vdefs = re.findall(r'^V:\s*(\S+)(.*)$', head, re.M)
    head_clean = '\n'.join(l for l in head.split('\n') if not l.startswith('V:') and not l.startswith('W:'))
    if not re.search(r'^L:', head_clean, re.M):
        head_clean += '\nL: 1/8'
    voices = {}  # name -> list of (music_line, [w lines])
    order = [v for v, _ in vdefs]
    cur = order[0] if order else '1'
    for line in body.split('\n'):
        line = line.rstrip()
        if not line: continue
        if line.startswith('w:'):
            if cur in voices and voices[cur]:
                voices[cur][-1][1].append(line[2:].strip())
            continue
        if re.match(r'^[A-Za-z]:', line) and not line.startswith('[V:'):
            m = re.match(r'^V:\s*(\S+)', line)
            if m: cur = m.group(1)
            continue
        parts = re.split(r'\[V:\s*([^\]\s]+)\s*\]', line)
        # parts: text, name, text, name, text ...
        if parts[0].strip():
            voices.setdefault(cur, []).append([parts[0], []])
        for i in range(1, len(parts), 2):
            cur = parts[i]
            if cur not in order: order.append(cur)
            if parts[i+1].strip():
                voices.setdefault(cur, []).append([parts[i+1], []])
    clefs = {v: ('bass' if 'bass' in d else None) for v, d in vdefs}
    return head_clean, key_line, order, voices, clefs

def read_src(path):
    b = open(path, 'rb').read()
    try: return b.decode('utf-8')
    except UnicodeDecodeError: return b.decode('latin-1')

def title_of(src):
    m = re.search(r'^T:\s*(.*)$', src, re.M); return m.group(1).strip() if m else ''

def convert(path):
    src = read_src(path)
    head, key_line, order, voices, clefs = split_voices(src)
    names_by_count = {4: ['Soprano', 'Alto', 'Tenor', 'Bass']}
    used = [v for v in order if v in voices]
    roles = names_by_count.get(len(used), [f'Voice {i+1}' for i in range(len(used))])
    score = m21.stream.Score()
    report = {'voices': len(used), 'verses': 0, 'lyric_ok': False, 'notes': 0}
    key_clean = re.sub(r'\s*%.*', '', key_line)
    for idx, v in enumerate(used):
        lines = voices[v]
        music = '\n'.join(re.sub(r'![^!\s]*!', '', l[0]) for l in lines)
        clef = clefs.get(v) or ('bass' if idx >= 2 and len(used) == 4 else None)
        abc = head + '\nK:' + key_clean + (' clef=bass' if clef == 'bass' and 'clef' not in key_clean else '') + '\n' + music
        p = m21.converter.parse(abc, format='abc').parts[0]
        p.partName = roles[idx]; p.id = roles[idx]
        notes = [n for n in p.recurse().notes if not n.duration.isGrace]
        report['notes'] += len(notes)
        if any(l[1] for l in lines):
            n_verses = max(len(l[1]) for l in lines)
            sung = [n for n in notes]
            untied = [n for n in notes if not (n.tie and n.tie.type in ('stop', 'continue'))]
            good = 0
            for verse in range(1, n_verses + 1):
                toks = []
                for music_line, wl in lines:
                    if not wl:
                        toks += [None] * count_notes(music_line)[0]; continue
                    w = wl[verse - 1] if verse - 1 < len(wl) else (wl[0] if len(wl) == 1 else None)
                    if w is None:
                        toks += [None] * count_notes(music_line)[0]; continue
                    t = lyric_tokens(w)
                    toks += t
                target = sung if len([1 for _ in toks]) == len(sung) else (untied if len(toks) == len(untied) else None)
                if target is None:
                    continue
                for n, t in zip(target, toks):
                    if t is None: continue
                    n.addLyric(t[0], lyricNumber=good + 1)
                    n.lyrics[-1].syllabic = t[1]
                good += 1
            report['verses'] = max(report['verses'], good)
            report['lyric_ok'] = report['verses'] > 0
            if idx == 0: report['melody_verses'] = good
        score.insert(0, p)
    t = title_of(src)
    score.metadata = m21.metadata.Metadata(); score.metadata.title = t
    comp = re.findall(r'^C:\s*(.*)$', src, re.M)
    score.metadata.composer = '; '.join(c.strip() for c in comp if 'copyright' not in c.lower())[:200]
    return score, report, t

def oh(src, tag):
    m = re.search(r'^%' + tag + r'\s+(.*)$', src, re.M); return m.group(1).strip() if m else ''

def first_line(score):
    p = score.parts[0]; words = []
    for n in p.recurse().notes:
        for l in n.lyrics:
            if l.number == 1:
                words.append(l.text + ('' if l.syllabic in ('begin', 'middle') else ' '))
        if len(''.join(words)) > 70: break
    t = ''.join(words).strip()
    m = re.search(r'[,;:.!?](\s|$)', t[24:])
    t = t[:24 + m.start()] if m else (t[:t.rfind(' ', 0, 55)] if len(t) > 55 else t)
    return t.rstrip(',;:')

CONTAINER = (b'<?xml version="1.0" encoding="UTF-8"?><container><rootfiles>'
             b'<rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/>'
             b'</rootfiles></container>')

if __name__ == '__main__':
    out = sys.argv[2]; os.makedirs(out, exist_ok=True)
    results = []; index = []
    for f in sorted(glob.glob(sys.argv[1] + '/**/*.abc', recursive=True)):
        try:
            s, r, t = convert(f)
            src = read_src(f)
            r.update(file=f, title=t, ok=True)
            name = re.sub(r'[^A-Za-z0-9]+', '_', os.path.basename(f)[:-4]).strip('_')
            tmp = '/tmp/_h.musicxml'; s.write('musicxml', fp=tmp)
            xml = open(tmp, 'rb').read()
            with zipfile.ZipFile(os.path.join(out, name + '.mxl'), 'w', zipfile.ZIP_DEFLATED) as z:
                z.writestr('META-INF/container.xml', CONTAINER)
                z.writestr('score.musicxml', xml)
            r['out'] = name
            tunes = re.findall(r"'([^']+)'", ''.join(re.findall(r'^C:.*$', src, re.M)))
            km = re.search(r'^K:\s*([^%\n]*)', src, re.M); mm = re.search(r'^M:\s*([^%\n]*)', src, re.M)
            index.append({
                'id': name, 'title': t, 'firstLine': first_line(s),
                'tune': tunes[0] if tunes else '',
                'author': oh(src, 'OHAUTHOR'), 'composer': oh(src, 'OHCOMPOSER'),
                'category': oh(src, 'OHCATEGORY').title(), 'meter': oh(src, 'OHMETRICAL'),
                'key': km.group(1).strip() if km else '', 'time': mm.group(1).strip() if mm else '',
                'voices': r['voices'], 'verses': r.get('melody_verses', 0),
            })
        except Exception as e:
            r = {'file': f, 'ok': False, 'error': str(e)[:200]}
        results.append(r)
    json.dump(results, open(os.path.join(out, '_report.json'), 'w'), indent=1)
    index.sort(key=lambda h: h['title'].lower())
    json.dump(index, open(os.path.join(out, 'index.json'), 'w'), ensure_ascii=False, separators=(',', ':'))
    ok = [r for r in results if r.get('ok')]
    print('converted', len(ok), 'of', len(results))
    print('with lyrics', sum(1 for r in ok if r['lyric_ok']), ' 4 voices', sum(1 for r in ok if r['voices'] == 4))
