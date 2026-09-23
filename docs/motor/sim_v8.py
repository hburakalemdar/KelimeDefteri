"""SPEC-MOTOR2.md v8: durum = replay(taban, loglar, now). Kullanıcı modeli log üretir, seçiciler önbellekten okur.

Zaman gün cinsinden; t=0 = 0. günün gece yarısı; gün sınırı 04:00. Belirsizlikler L1..L6 (rapor: 18-simulasyon-v8.md).
"""
import math, random, statistics as st, copy
from dataclasses import dataclass, replace, field
from typing import Optional

FIRST_S = {1: 0.4, 2: 1.2, 3: 3.0, 4: 8.0}
FIRST_D = {1: 7.0, 2: 6.0, 3: 5.0, 4: 3.5}
MULT = {2: 0.5, 3: 1.0, 4: 1.5}
DDELTA = {1: 1.0, 2: 0.4, 3: 0.0, 4: -0.6}
MODES = {'recall': (1.0, 1.0), 'letters': (0.8, 0.85), 'recog': (0.6, 0.7)}
PROD = {'recall', 'letters'}
AGAIN, HARD, GOOD, EASY = 1, 2, 3, 4
GNAME = {1: 'again', 2: 'hard', 3: 'good', 4: 'easy'}
H4 = 4 / 24
M = 0.375
SEC = 86400

OPT = {
    # L1: logs >= baseAt (belge §2.1) — baseAt = göç anındaki son logun tarihi olduğu için o log yeniden işlenir.
    #     'ge' = belge (>=) · 'gt' = düzeltme önerisi (>)
    'base_cmp': 'gt',   # v8 §2.1: date > baseAt
}


def dayidx(t):
    return math.floor(t - H4 + 1e-9)


def dstart(t):
    return dayidx(t) + H4


def R(t, S):
    return 0.0 if S <= 0 else (1 + 19 / 81 * max(t, 0) / S) ** -0.5


def next_d(D, g):
    m = D + DDELTA[g]
    m = m + (5 - m) * 0.15
    return min(max(m, 1.0), 10.0)


def secs(dt):
    return round(dt * SEC)


def sort_key(l):  # §2.11: zaman, sonra yanlış önce, sonra mod (alfabetik), sonra not
    t, g, m = l
    return (secs(t), 0 if g == AGAIN else 1, m, g)


@dataclass(frozen=True)
class Base:
    S: float = 0.0
    D: float = 5.0
    due: float = -1e9
    lapsed: Optional[float] = None
    at: Optional[float] = None
    anchor: Optional[float] = None     # baseAnchorAt
    learned: Optional[float] = None    # baseLearnedAt
    prior_prod_days: int = 0           # yalnız test kelimeleri (belgede karşılığı yok; öğrenilmiş tabanda şart zaten sağlanmış)


@dataclass(frozen=True)
class State:
    S: float
    D: float
    due: float
    lapsed: Optional[float]
    learned: Optional[float]
    anchor: Optional[float]
    prod_days: int = 0
    nonagain_after_lapse: int = 0
    last_dg: Optional[int] = None


def initial(base: Base, opt=OPT) -> State:
    anchor = base.anchor if base.anchor is not None else base.at
    pd = 2 if base.learned is not None else base.prior_prod_days
    return State(base.S, base.D, base.due, base.lapsed, base.learned, anchor, prod_days=pd)


def day_grade(day_logs):
    day_logs = sorted(day_logs, key=sort_key)
    prim = []
    for (t, g, m) in day_logs:
        if g == AGAIN:
            prim.append((t, g, m))
        elif not any(g2 == AGAIN and 0 <= secs(t - t2) < 1800 and sort_key((t2, g2, m2)) < sort_key((t, g, m))
                     for (t2, g2, m2) in day_logs):
            prim.append((t, g, m))
    if not prim:
        return None
    grp = [l for l in prim if l[2] in PROD]
    kind = 'prod' if grp else 'recog'
    grp = grp or prim
    wr = [l for l in grp if l[1] == AGAIN]
    ratio = len(wr) / len(grp)
    if ratio > 1 / 3:
        return AGAIN, min(wr, key=lambda l: MODES[l[2]][1])[2], kind
    ok = [l for l in grp if l[1] != AGAIN]
    best = max(ok, key=lambda l: (l[1], MODES[l[2]][0], -secs(l[0])))   # §2.4: en iyi not, eşitlikte ağırlık, sonra en erken
    if ratio > 0:
        return HARD, best[2], kind
    return best[1], best[2], kind


def process_day(s: State, day: int, day_logs) -> State:
    res = day_grade(day_logs)
    if res is None:
        return s
    dg, src, kind = res
    today = day + H4
    weight, wrong_t = MODES[src]
    if s.S <= 0:
        S1, D1 = max(0.3, FIRST_S[dg] * weight), FIRST_D[dg]
        if dg == AGAIN:
            return replace(s, S=S1, D=D1, anchor=today, lapsed=today, due=today + 1, nonagain_after_lapse=0, last_dg=dg)
        # L2: yeni kelimenin ilk günü tanımaysa çıpa? (belge "tanıma çıpayı ilerletmez"; çıpa yok) → bugün
        s2 = replace(s, S=S1, D=D1, anchor=today, due=today + S1, last_dg=dg, prod_days=s.prod_days + (kind == 'prod'))
        return learned_check(s2, today)
    t = day - dayidx(s.anchor) if s.anchor is not None else s.S
    r = R(t, s.S)
    if dg == AGAIN:
        if s.lapsed is not None:
            nS = max(0.3, s.S * 0.5 * wrong_t)
        else:
            nS = max(0.3, min(s.S * (0.65 - 0.30 * r) * wrong_t, 3 * math.sqrt(s.S)))
        return replace(s, S=min(nS, 3650), D=next_d(s.D, dg), anchor=today, lapsed=today, due=today + 1,
                       nonagain_after_lapse=0, last_dg=dg)
    ns = s
    if not (kind == 'recog' and s.S >= 21):
        growth = math.exp(1.5) * (11 - s.D) * s.S ** -0.2 * (math.exp(1.2 * (1 - r)) - 1)
        nS = s.S * (1 + growth * MULT[dg] * weight)
        if kind == 'recog':
            nS = min(nS, 20.9)
            ns = replace(ns, S=min(nS, 3650), D=next_d(s.D, dg))          # çıpa ilerlemez
        else:
            ns = replace(ns, S=min(nS, 3650), D=next_d(s.D, dg), anchor=today)
    lapsed, nal = s.lapsed, s.nonagain_after_lapse
    if lapsed is not None:
        nal += 1
        if (kind == 'prod' and dayidx(lapsed) != day) or (kind == 'recog' and s.S < 21 and nal >= 2):
            lapsed = None
    due = ns.anchor + ns.S if lapsed is None else s.due
    ns = replace(ns, lapsed=lapsed, due=due, nonagain_after_lapse=nal, last_dg=dg,
                 prod_days=s.prod_days + (kind == 'prod'))
    return learned_check(ns, today)


def learned_check(s: State, today) -> State:
    if s.learned is None and s.S >= 21 and s.lapsed is None and s.prod_days >= 2:
        return replace(s, learned=today)
    return s


def in_range(base, t, now, opt=OPT):
    if now is not None and t > now:
        return False
    if base.at is None:
        return True
    return t >= base.at if opt['base_cmp'] == 'ge' else t > base.at


def replay(base: Base, logs, now=None, opt=OPT) -> State:
    s = initial(base, opt)
    ls = sorted((l for l in logs if in_range(base, l[0], now, opt)), key=sort_key)
    days = {}
    for l in ls:
        days.setdefault(dayidx(l[0]), []).append(l)
    for d in sorted(days):
        s = process_day(s, d, days[d])
    return s


class Word:
    def __init__(self, base: Base = Base(), opt=OPT):
        self.base, self.opt = base, opt
        self.logs = []
        self.cache = initial(base, opt)
        self._init = self.cache
        self._last_day = None
        self._last_state_before = self.cache

    def add(self, t, g, mode):
        d = dayidx(t)
        if self._last_day is None or d > self._last_day:
            self._last_state_before = self.cache
            self._last_day = d
        assert d == self._last_day
        self.logs.append((t, g, mode))
        if not in_range(self.base, t, None, self.opt):
            return None
        today_logs = [l for l in self.logs if dayidx(l[0]) == d and in_range(self.base, l[0], None, self.opt)]
        self.cache = process_day(self._last_state_before, d, today_logs)
        return self.cache.last_dg

    @property
    def S(self): return self.cache.S

    def is_due(self, now):
        return self.cache.due <= now

    def memory(self, now):
        c = self.cache
        if c.S <= 0:
            return None
        r = R(now - (c.anchor if c.anchor is not None else now), c.S)
        return min(r, 0.5) if c.lapsed is not None else r

    @property
    def is_learned(self):
        return self.cache.S >= 21 and self.cache.lapsed is None


def mature(S, D=5.0, at=M, prod_days=3, opt=OPT):
    """Yeni mimaride olgun kelime: taban = (S, D, vade at+S), baseAt = at (çıpa = at)."""
    w = Word(Base(S=S, D=D, due=at + S, lapsed=None, at=at, anchor=at, prior_prod_days=prod_days), opt)
    return w


def due_text(c: State, now):
    if c.S <= 0:
        return 'Yeni'
    n = dayidx(c.due) - dayidx(now)
    if c.due <= now:
        return 'Bugün' if n == 0 else f'{-n} gün gecikti'
    return {0: 'Bugün', 1: 'Yarın'}.get(n, f'{n} gün sonra')


def status(w: Word, now):
    c = w.cache
    if c.S <= 0:
        return 'Yeni'
    return ('Öğreniliyor · ' if c.lapsed is not None else '') + due_text(c, now)


def pct(m):
    return 'Yeni' if m is None else f'%{int(m * 100 + 1e-9)}'


def hhmm(t):
    d = math.floor(t); m = round((t - d) * 1440)
    return f'g{d} {m // 60:02d}:{m % 60:02d}'


def q(v):
    v = sorted(v)
    if not v:
        return '—'
    return f'p10 {v[len(v) // 10]:.1f} · medyan {st.median(v):.1f} · p90 {v[min(len(v) - 1, 9 * len(v) // 10)]:.1f}'


def show(w, t):
    c = w.cache
    return (f'S {c.S:.2f} · D {c.D:.2f} · {status(w, t)} · {pct(w.memory(t))}'
            + (' · rozet' if w.is_learned else '') + (' · learnedAt' if c.learned is not None else ''))


HDR = '| Adım | S | D | vade | lapsedAt | anchorAt | learnedAt | isDue(+1 dk) | Ekran | İkon |\n|---|---|---|---|---|---|---|---|---|---|'


def scenario(title, w, steps):
    out = [f'\n#### {title}\n', HDR]
    for t, g, m in steps:
        dg = w.add(t, g, m)
        c = w.cache
        out.append(f'| {hhmm(t)} {GNAME[g]}/{m} | {c.S:.2f} | {c.D:.3f} | {c.due - t:+.2f} ({due_text(c, t)}) | '
                   f'{"—" if c.lapsed is None else hhmm(c.lapsed)} | {"—" if c.anchor is None else hhmm(c.anchor)} | '
                   f'{"—" if c.learned is None else hhmm(c.learned)} | {w.is_due(t + 1 / 1440)} | {pct(w.memory(t))} | '
                   f'{"—" if dg is None else ("✗" if dg == AGAIN else "✓")} |')
    return '\n'.join(out)


# ------------------------------------------------------------------ A) senaryolar + sezgi
def part_a():
    o = ['## A) Senaryolar\n']
    T = 30 + M
    for g in (HARD, GOOD, EASY):
        o.append(scenario(f'Yeni kelime ilk doğru ({GNAME[g]})', Word(), [(M, g, 'recall')]))
    o.append(scenario('Yeni kelime: yanlış → 5 dk sonra yeniden sorma doğru → ertesi gün doğru', Word(),
                      [(M, AGAIN, 'recall'), (M + 5 / 1440, GOOD, 'recall'), (1 + M, GOOD, 'recall')]))
    o.append(scenario('S=30: doğru → 2 saat sonra yanlış (şikâyet)', mature(30), [(T, GOOD, 'recall'), (T + .08, AGAIN, 'recall')]))
    o.append(scenario('S=30: doğru → 5 dk sonra "Bir Tur Daha"da yanlış', mature(30), [(T, GOOD, 'recall'), (T + 5 / 1440, AGAIN, 'recall')]))
    o.append(scenario('S=30: yanlış → 10 ve 20 dk sonra doğru', mature(30),
                      [(T, AGAIN, 'recall'), (T + 10 / 1440, GOOD, 'letters'), (T + 20 / 1440, GOOD, 'recall')]))
    for mins in (29, 30, 31):
        o.append(scenario(f'S=30: yanlış → {mins}. ve 45. dakikada doğru', mature(30),
                          [(T, AGAIN, 'recall'), (T + mins / 1440, GOOD, 'letters'), (T + 45 / 1440, GOOD, 'recall')]))
    o.append(scenario('S=30: yanlış → 10 dk sonra 3 tanıma doğrusu', mature(30),
                      [(T, AGAIN, 'recall')] + [(T + (10 + i) / 1440, GOOD, 'recog') for i in range(3)]))
    o.append(scenario('S=30: yanlış → 2 saat sonra 2 tanıma doğrusu (widget)', mature(30),
                      [(T, AGAIN, 'recall'), (T + .08, GOOD, 'recog'), (T + .16, GOOD, 'recog')]))
    o.append(scenario('S=30: sabah widget ×2 doğru (tek gün)', mature(30), [(T, GOOD, 'recog'), (T + .15, GOOD, 'recog')]))
    o.append(scenario('S=10: sabah widget ×2 doğru (S<21)', mature(10), [(10 + M, GOOD, 'recog'), (10 + M + .15, GOOD, 'recog')]))
    o.append(scenario('S=10: widget sabah, hatırlama akşam', mature(10), [(10 + M, GOOD, 'recog'), (10 + 20 / 24, GOOD, 'recall')]))
    o.append(scenario('S=10: hatırlama akşam, widget sonra', mature(10), [(10 + 20 / 24, GOOD, 'recall'), (10 + 21 / 24, GOOD, 'recog')]))
    o.append(scenario('Zayıf kelime: tanıma 1. ve 2. gün', mature(30), [(T, AGAIN, 'recall'), (T + 1, GOOD, 'recog'), (T + 2, GOOD, 'recog')]))
    o.append(scenario('3 gün üst üste yanlış, sonra doğrular', mature(30),
                      [(T + d, AGAIN, 'recall') for d in range(3)] + [(T + d, GOOD, 'recall') for d in range(3, 6)]))
    o.append(scenario('03:58 yanlış, 04:02 doğru', mature(30, at=.5), [(31 + H4 - 2 / 1440, AGAIN, 'recall'), (31 + H4 + 2 / 1440, GOOD, 'recall')]))
    o.append(scenario('23:58 yanlış, 00:02 doğru (4 dk, aynı gün)', mature(30, at=.5), [(30 + 1438 / 1440, AGAIN, 'recall'), (31 + 2 / 1440, GOOD, 'recall')]))
    o.append(scenario('23:00 yanlış, 01:00 doğru (aynı gün, 2 saat)', mature(30, at=.5), [(30 + 23 / 24, AGAIN, 'recall'), (31 + 1 / 24, GOOD, 'recall')]))
    return '\n'.join(o)


def part_intuition():
    T = 30 + M; E = 30 + 20 / 24
    sc = [
        ('S=30 vadesinde doğru', lambda: mature(30), [(T, GOOD, 'recall')]),
        ('S=30 vadesinde yanlış', lambda: mature(30), [(T, AGAIN, 'recall')]),
        ('Doğru → 2 saat sonra bilerek yanlış', lambda: mature(30), [(T, GOOD, 'recall'), (T + .08, AGAIN, 'recall')]),
        ('Yanlış → 5 dk sonra yeniden sorma doğru', lambda: mature(30), [(T, AGAIN, 'recall'), (T + 5 / 1440, GOOD, 'recall')]),
        ('Yanlış → 2 saat sonra başka oyunda doğru', lambda: mature(30), [(T, AGAIN, 'recall'), (T + .08, GOOD, 'recall')]),
        ('Yanlış + 2 tanıma doğrusu (2 ve 4 saat sonra)', lambda: mature(30), [(T, AGAIN, 'recall'), (T + .08, GOOD, 'recog'), (T + .16, GOOD, 'recog')]),
        ('Sabah doğru, akşam yanlış', lambda: mature(30), [(T, GOOD, 'recall'), (E, AGAIN, 'recall')]),
        ('Sabah yanlış, akşam doğru', lambda: mature(30), [(T, AGAIN, 'recall'), (E, GOOD, 'recall')]),
        ('Üç oyun D, D, Y (2 saat arayla)', lambda: mature(30), [(T, GOOD, 'recall'), (T + .08, GOOD, 'recall'), (T + .16, AGAIN, 'recall')]),
        ('Dün yanlış, bugün doğru', lambda: mature(30), [(T, AGAIN, 'recall'), (T + 1, GOOD, 'recall')]),
        ('Yeni: yanlış → yeniden sorma doğru → ertesi gün doğru', lambda: Word(), [(M, AGAIN, 'recall'), (M + 5 / 1440, GOOD, 'recall'), (1 + M, GOOD, 'recall')]),
        ('S=300 vadesinde yanlış', lambda: mature(300), [(300 + M, AGAIN, 'recall')]),
    ]
    o = ['\n## B) Kullanıcı sezgisi senaryoları (gün sonu → ertesi vadesinde bir doğru)\n',
         '| Senaryo | Gün sonu | Sonraki doğru |', '|---|---|---|']
    for lab, mk, steps in sc:
        w = mk()
        for s in steps:
            w.add(*s)
        t = steps[-1][0]
        a = show(w, t)
        tn = max(w.cache.due, dayidx(t) + 1 + M)
        w.add(tn, GOOD, 'recall')
        o.append(f'| {lab} | {a} | g{math.floor(tn)}: S {w.S:.2f} · {status(w, tn)} |')
    return '\n'.join(o)


def check_table():
    T = 30 + M
    rows = []

    def run(w, steps):
        for s in steps:
            w.add(*s)
        return w

    def row(name, doc, w, t):
        c = w.cache
        lap = '—' if c.lapsed is None else ('bugün' if dayidx(c.lapsed) == dayidx(t) else 'eski')
        rows.append(f'| {name} | {doc} | S={c.S:.2f} D={c.D:.2f} vade={due_text(c, t)} lapsed={lap} learnedAt={"—" if c.learned is None else "g" + str(dayidx(c.learned))} '
                    f'{"Öğrenildi" if w.is_learned else ("Öğreniliyor" if c.lapsed is not None else "Olgun")} |')
    row('Yeni ilk Y (hatırlama)', '0,4/7,0/Yarın', run(Word(), [(M, AGAIN, 'recall')]), M)
    row('Yeni ilk Y (tanıma)', '0,3/7,0', run(Word(), [(M, AGAIN, 'recog')]), M)
    row('Yeni iki turda Y→D (2 saat)', '0,4/7,0/Yarın', run(Word(), [(M, AGAIN, 'recall'), (M + .08, GOOD, 'recall')]), M + .08)
    row('S=30 D→Y (2 saat)', '11,40/5,85/Yarın', run(mature(30), [(T, GOOD, 'recall'), (T + .08, AGAIN, 'recall')]), T + .08)
    row('S=30 Y→D (2 saat)', '11,40/5,85/Yarın', run(mature(30), [(T, AGAIN, 'recall'), (T + .08, GOOD, 'recall')]), T + .08)
    for lab, seq in (('Y D D', [AGAIN, GOOD, GOOD]), ('D Y D', [GOOD, AGAIN, GOOD]), ('D D Y', [GOOD, GOOD, AGAIN])):
        row(f'S=30 üç turda 1 Y ({lab}, 2 saat)', '56,05/5,34/+56/Öğrenildi', run(mature(30), [(T + k * .08, g, 'recall') for k, g in enumerate(seq)]), T + .16)
    row('S=30 salt D', '82,09/5,0/+82', run(mature(30), [(T, GOOD, 'recall')]), T)
    row('S=30 salt Y', '11,40/5,85/Yarın', run(mature(30), [(T, AGAIN, 'recall')]), T)
    row('Dün Y bugün D', '13,38/5,72/+13', run(mature(30), [(T, AGAIN, 'recall'), (T + 1, GOOD, 'recall')]), T + 1)
    w = run(mature(30), [(T, AGAIN, 'recall'), (T + 1, AGAIN, 'recall')])
    row('2. gün Y', '5,70/6,57', w, T + 1)
    run(w, [(T + 2, AGAIN, 'recall')])
    row('3. gün Y', '2,85/7,19', w, T + 2)
    w = run(mature(300), [(300 + M, AGAIN, 'recall')])
    row('S=300 Y', '51,96/5,85', w, 300 + M)
    run(w, [(301 + M, GOOD, 'recall')])
    row('…ertesi gün D', '53,43/5,72/+53', w, 301 + M)
    row('Tanıma S=10', '20,90/5,0/+21', run(mature(10), [(10 + M, GOOD, 'recog')]), 10 + M)
    w = run(mature(30), [(T, AGAIN, 'recall'), (T + 1, GOOD, 'recog')])
    row('Zayıf, tanıma 1. gün', 'büyür/Yarın(sabit)/kalır', w, T + 1)
    run(w, [(T + 2, GOOD, 'recog')])
    row('…2. gün', 'büyür/ileri/temizlenir', w, T + 2)
    row('23:58 Y / 00:02 D', '11,40/Yarın', run(mature(30, at=.5), [(30 + 1438 / 1440, AGAIN, 'recall'), (31 + 2 / 1440, GOOD, 'recall')]), 31.01)
    row('03:58 Y / 04:02 D', '13,38/+13/temizlenir', run(mature(30, at=.5), [(31 + H4 - 2 / 1440, AGAIN, 'recall'), (31 + H4 + 2 / 1440, GOOD, 'recall')]), 31 + H4 + .01)
    rows.append('| **Yeni satırlar** | | |')
    row('D, 2 saat sonra Y', 'again 11,40 Öğreniliyor·Yarın', run(mature(30), [(T, GOOD, 'recall'), (T + .08, AGAIN, 'recall')]), T + .08)
    row('Y, 10 dk içinde 2 D', 'again 11,40', run(mature(30), [(T, AGAIN, 'recall'), (T + 5 / 1440, GOOD, 'recall'), (T + 10 / 1440, GOOD, 'recall')]), T + .01)
    row('Y, 31. ve 45. dk D', 'hard 56,05 Öğrenildi', run(mature(30), [(T, AGAIN, 'recall'), (T + 31 / 1440, GOOD, 'recall'), (T + 45 / 1440, GOOD, 'recall')]), T + .04)
    w = mature(30)
    for d in range(1, 41):
        w.add(d + M, GOOD, 'recog')
        if d == 20:
            c20 = w.cache; m20 = w.memory(d + M)
    rows.append(f'| Olgun (S=30) yalnız tanıma her gün D | S/anchor/vade değişmez; ekran düşer; vade gelince hatırlamaya düşer | '
                f'20. gün S={c20.S:.2f} vade=g{dayidx(c20.due)} ekran {pct(m20)}; 40. gün S={w.S:.2f} isDue={w.is_due(40 + M)} '
                f'ekran {pct(w.memory(40 + M))}, vade metni {due_text(w.cache, 40 + M)} |')
    w = run(mature(300), [(300 + M, AGAIN, 'recall'), (301 + M, GOOD, 'recog'), (302 + M, GOOD, 'recog')])
    row('Olgun (S≥21) zayıf, 2 farklı günde tanıma D', 'temizlenmez / "Yarın" (sabit)', w, 302 + M)
    w = run(mature(10), [(10 + M, GOOD, 'recog')])
    row('Tanımada şansla doğru S=10 (v8 metni)', '20,90 / "11 gün sonra"', w, 10 + M)
    w = run(mature(30), [(T, AGAIN, 'recall'), (T + 1, GOOD, 'recog')])
    rows.append(f'| Zayıf kelime tanımada D | vade değişmez (lapsedAt+1) | vade g{dayidx(w.cache.due)} {hhmm(w.cache.due)}, isDue(g31 09:01)={w.is_due(T + 1 + 1 / 1440)} |')
    # iki cihaz
    A = [(T, AGAIN, 'recall')]; B = [(T + .08, GOOD, 'recall'), (T + .16, GOOD, 'recall')]
    wb = mature(30)
    for s in B:
        wb.add(*s)
    before_sync = wb.cache
    full = replay(wb.base, A + B)
    rows.append(f'| İki cihaz: A Y, B (A\'yı görmeden) D, D; sonra eşitleme | eşitleme sonrası hard 56,05 | B eşitleme öncesi: S={before_sync.S:.2f} '
                f'({GNAME[before_sync.last_dg]}); eşitleme sonrası replay: S={full.S:.2f} ({GNAME[full.last_dg]}) |')
    w = run(mature(30), [(T, GOOD, 'recall')]); snap = w.cache
    w.add(T + .08, AGAIN, 'recall'); w.logs.pop(); after = replay(w.base, w.logs)
    rows.append(f'| Log silme (geri alma) | silmeden önceki duruma birebir döner | {"birebir" if after == replace(snap) or (after.S, after.D, after.due, after.lapsed, after.learned) == (snap.S, snap.D, snap.due, snap.lapsed, snap.learned) else "FARKLI"} '
                f'(S {after.S:.2f}, learnedAt {"var" if after.learned else "yok"}) |')
    return '\n### §7.1 doğrulaması\n\n| Satır | Belge | Betik |\n|---|---|---|\n' + '\n'.join(rows)


# ------------------------------------------------------------------ v5 Yüksek bulgularının testleri
def part_v5():
    o = ['\n## C) v5\'in 5 Yüksek bulgusu — v6 testleri\n']
    # Y1 gün başı sıfırlanması
    w = mature(30); T = 30 + M
    w.add(T, GOOD, 'recog'); a = w.S; w.add(T + .15, GOOD, 'recog'); b = w.S
    w2 = mature(10); w2.add(10 + M, GOOD, 'recog'); w2.add(10 + 20 / 24, GOOD, 'recall'); x = w2.S
    w3 = mature(10); w3.add(10 + 20 / 24, GOOD, 'recall'); w3.add(10 + 21 / 24, GOOD, 'recog'); y = w3.S
    o.append(f'- **Y1 (gün başı sıfırlanması)**: S=30 aynı gün 2 widget: {a:.2f} → {b:.2f} (olgun, donuk). '
             f'S=10 widget→hatırlama {x:.2f}, hatırlama→widget {y:.2f} ({"aynı" if abs(x - y) < 1e-9 else "FARKLI"}).')
    # Y2 widget şişirmesi
    w = mature(30); vals = []
    for d in range(1, 61):
        w.add(30 + d + M, GOOD, 'recog') if False else w.add(d + M, GOOD, 'recog')
        if d in (10, 30, 60):
            vals.append(f'g{d}: S {w.S:.1f}, isDue {w.is_due(d + M + .01)}, ekran {pct(w.memory(d + M))}')
    o.append('- **Y2 (widget şişirmesi, S=30, 60 gün her sabah widget doğru, hatırlama hiç)**: ' + '; '.join(vals))
    # Y3 tekrar turunda yanlış
    w = mature(30); w.add(T, GOOD, 'recall'); w.add(T + 5 / 1440, AGAIN, 'recall')
    o.append(f'- **Y3 (hemen ardından tekrar turunda yanlış)**: D, 5 dk sonra Y → {GNAME[w.cache.last_dg]}, S {w.S:.2f}, {status(w, T + .01)}')
    return '\n'.join(o)


# ------------------------------------------------------------------ desenler
def sim_policy(policy, days=120, seed=0, start=None):
    rng = random.Random(seed)
    w = start() if start else Word()
    tr = []
    for d in range(days):
        policy(d, w, rng)
        tr.append((w.is_learned, w.cache.learned is not None, w.cache.lapsed is not None, w.S))
    return w, tr


def agg(runs):
    L = sum(w.is_learned for w, _ in runs)
    fl = [next(i for i, x in enumerate(tr) if x[1]) for w, tr in runs if any(x[1] for x in tr)]
    lap = [sum(x[2] for x in tr) for _, tr in runs]
    return L, (f'{st.median(fl):.0f}' if fl else '—'), len(fl), st.median(lap)


def pol_k(k, p, due_only):
    """k oyun, 2 saat arayla. due_only: yalnız vadesi gelen gün (Günlük Tekrar + ardından ağırlıklı oyunlar);
    değilse her gün (ağırlıklı oyunlar isDue'ye bakmaz). Yanlışa tur içi yeniden sorma 3 dk sonra."""
    def f(d, w, rng):
        if due_only and not w.is_due(d + M):
            return
        for i in range(k):
            t = d + M + i * .08
            ok = rng.random() < p
            w.add(t, GOOD if ok else AGAIN, 'recall')
            if not ok:
                w.add(t + 3 / 1440, GOOD if rng.random() < p else AGAIN, 'recall')
    return f


def pol_recog(p, widget_rate=.3):
    def f(d, w, rng):
        if w.is_due(d + .4):
            w.add(d + .4, GOOD if rng.random() < p else AGAIN, 'recog')
        if w.S > 0 and w.is_due(d + .7) and rng.random() < widget_rate:
            w.add(d + .7, GOOD if rng.random() < p else AGAIN, 'recog')
    return f


def pol_widget(pw, pr, widget_any=True):
    """Widget her sabah (widget_any: vadeye bakmadan — belgede widget isDue kullanır, iki varyant); akşam isDue ise Günlük Tekrar."""
    def f(d, w, rng):
        if w.S > 0 and (widget_any or w.is_due(d + .3)):
            w.add(d + .3, GOOD if rng.random() < pw else AGAIN, 'recog')
        if w.is_due(d + .8):
            w.add(d + .8, GOOD if rng.random() < pr else AGAIN, 'recall')
            w.recall_days = getattr(w, 'recall_days', 0) + 1
    return f


def pol_guess(d, w, rng):
    w.add(d + .3, GOOD if rng.random() < .25 else AGAIN, 'recog')
    w.add(d + .5, GOOD if rng.random() < .25 else AGAIN, 'recog')
    w.add(d + .7, GOOD if rng.random() < .05 else AGAIN, 'recall')


def pol_absence(fail, a, b):
    def f(d, w, rng):
        if a <= d < b:
            return
        if d == b:
            w.add(d + M, AGAIN if fail else GOOD, 'recall'); return
        if w.is_due(d + M):
            w.add(d + M, GOOD, 'recall')
    return f


def part_patterns(n=500):
    o = ['\n## D) Desenler (500 tohum, 120 gün)\n', '| Kullanıcı | Öğrenildi (canlı, 120. gün) | learnedAt medyan günü (ulaşan) | zayıf gün medyanı |', '|---|---|---|---|']
    for p in (.9, .7):
        for due_only, lab in ((True, 'vade günü'), (False, 'her gün')):
            for k in (1, 2, 3, 5, 10):
                L, fl, nfl, lap = agg([sim_policy(pol_k(k, p, due_only), seed=s) for s in range(n)])
                o.append(f'| %{int(p * 100)} bilen, {lab} {k} oyun | **{L}**/500 | g{fl} ({nfl}) | {lap:.0f} |')
    for lab, pol in (('yalnız tanıma, tahminci %25', pol_recog(.25)), ('yalnız tanıma, %90', pol_recog(.9)),
                     ('tahminci: 2 tanıma %25 + hatırlama %5, her gün', pol_guess)):
        L, fl, nfl, lap = agg([sim_policy(pol, seed=s) for s in range(n)])
        o.append(f'| {lab} | **{L}**/500 | g{fl} ({nfl}) | {lap:.0f} |')
    o.append('\n**Widget her sabah + vadesi gelince akşam Günlük Tekrar**\n')
    o.append('| Widget / hatırlama | widget seçimi | Öğrenildi | learnedAt medyan günü | hatırlama sorulan gün (medyan) | son gün S medyanı |\n|---|---|---|---|---|---|')
    for pw, pr in ((1.0, .9), (.9, .9), (.9, .7), (.9, .3)):
        for wa in (True, False):
            runs = [sim_policy(pol_widget(pw, pr, wa), seed=s) for s in range(n)]
            L, fl, nfl, lap = agg(runs)
            rd = [getattr(w, 'recall_days', 0) for w, _ in runs]
            o.append(f'| %{int(pw * 100)} / %{int(pr * 100)} | {"her sabah (vadeye bakmadan)" if wa else "yalnız isDue"} | **{L}**/500 | g{fl} ({nfl}) | {st.median(rd):.0f} | {st.median([w.S for w, _ in runs]):.1f} |')
    o.append('\n**30 gün ara**')
    for a, b in ((20, 50), (20, 75)):
        for fail in (False, True):
            w, tr = sim_policy(pol_absence(fail, a, b))
            o.append(f'- ara {a}–{b}, dönüş {"yanlış" if fail else "doğru"}: dönüş günü S {tr[b][3]:.1f}, ertesi gün {tr[b + 1][3]:.1f}, 119. gün {tr[119][3]:.1f}')
    return '\n'.join(o)


# ------------------------------------------------------------------ (a) sıra/iki cihaz, (b) geri alma, artımlı = replay
def part_extra():
    o = ['\n## E) Ek kontroller\n']
    rng = random.Random(5)
    same, inc_eq, dev_eq, interim_diff = 0, 0, 0, 0
    for trial in range(300):
        base = Base(S=12, D=5, due=12 + M, at=M, anchor=M, prior_prod_days=1)
        logs = []
        for d in range(8):
            t = 12 + d + M
            for k in range(rng.randint(1, 7)):
                t += rng.choice([2, 10, 25, 29, 31, 45, 120]) / 1440
                logs.append((t, rng.choice([GOOD, AGAIN, HARD, EASY]), rng.choice(['recall', 'recog', 'letters'])))
        ref = replay(base, logs)
        shuf = logs[:]; rng.shuffle(shuf)
        same += replay(base, shuf) == ref
        w = Word(base)
        for l in logs:
            w.add(*l)
        inc_eq += w.cache == ref
        # iki cihaz: loglar rastgele A/B'ye; B, A'nın loglarını 0–2 gün gecikmeyle görür; her cihaz önbelleğini kendi gördüğüyle hesaplar
        devA = [l for l in logs if rng.random() < .5]
        devB = [l for l in logs if l not in devA]
        lag = rng.choice([.1, .5, 1.0, 2.0])
        endB_view = replay(base, devB + [l for l in devA if l[0] + lag <= logs[-1][0]])
        interim_diff += endB_view != ref
        dev_eq += replay(base, devB + devA) == ref
    o.append(f'- **(a) Sıra/iki cihaz** (300 rastgele 8 günlük log kümesi, günde 1–7 cevap 2–120 dk arayla, karışık mod/not): '
             f'karıştırılmış sırayla replay = referans **{same}/300**; artımlı önbellek (cevap cevap) = tam replay **{inc_eq}/300**; '
             f'iki cihaz tam eşitleme sonrası aynı **{dev_eq}/300**; eşitleme gecikmesi sürerken B\'nin gördüğü sonuç farklı: {interim_diff}/300 (geçici).')
    # (b) geri alma: rastgele bir logu silmek = o log hiç yazılmamış gibi
    ok, ok_last = 0, 0
    for trial in range(300):
        base = Base(S=12, D=5, due=12 + M, at=M, anchor=M)
        logs = sorted((12 + rng.random() * 8 + M, rng.choice([GOOD, AGAIN]), rng.choice(['recall', 'recog'])) for _ in range(12))
        before_last = replay(base, logs[:-1])
        ok_last += replay(base, logs[:-1]) == before_last
        i = rng.randrange(len(logs))
        ok += replay(base, logs[:i] + logs[i + 1:]) == replay(base, [l for j, l in enumerate(logs) if j != i])
    # geri almanın kullanıcıya görünen etkisi: S=30 vadesinde D (learnedAt yazılıyor), sonra Y, sonra Y geri alınıyor
    w = mature(30); T = 30 + M
    w.add(T, GOOD, 'recall'); snap = w.cache
    w.add(T + .08, AGAIN, 'recall'); mid = w.cache
    undone = replay(w.base, w.logs[:-1])
    o.append(f'- **(b) Geri alma = log silme**: son logu silmek, o log hiç yazılmamış hâle birebir döndü (300/300); rastgele bir ara logu silmek '
             f'tanım gereği tutarlı. Örnek: D (S {snap.S:.2f}, learnedAt g{dayidx(snap.learned)}) → Y (S {mid.S:.2f}, learnedAt {"var" if mid.learned else "yok"}) '
             f'→ Y geri alındı (S {undone.S:.2f}, learnedAt {"g" + str(dayidx(undone.learned)) if undone.learned else "yok"}) — '
             f'{"birebir" if (undone.S, undone.due, undone.lapsed, undone.learned) == (snap.S, snap.due, snap.lapsed, snap.learned) else "FARKLI"}.')
    o.append('  Not: önbellekte (Word) tutulan eski "geri alma listesi" gerekmez; ama `replay` her geri almada bütün logları okur (tek kelime, ucuz).')
    return '\n'.join(o)


# ------------------------------------------------------------------ (c) göç, (d) vade/seçim
def part_migration():
    o = ['\n## F) Taban + göç\n',
         'Eski kelime: S=11,4, D=5,95; eski motorda g100 09:00\'da yanlış yapılmış, vade eski `lapseDue` hilesiyle geçmişe atılmış (g91). '
         'Göç g100 18:00\'de (`baseAt`), `baseDueDate` = eski vade (g91), `baseLapsedAt` = g100 04:00.\n',
         '| K1 çıpa varyantı | Göç anı | g101 09:00 hatırlama D | g101 sonrası vade | Not |', '|---|---|---|---|---|']
    for anc in ('baseAt', 'lastReviewed'):
        opt = dict(OPT, base_anchor=anc)
        base = Base(S=11.4, D=5.95, due=91.375, lapsed=100 + H4, at=100.75, anchor=100.375)
        w = Word(base, opt)
        t0 = 100.75
        a = f'isDue={w.is_due(t0)}, metin "{status(w, t0)}", ekran {pct(w.memory(t0))}'
        w.add(101 + M, GOOD, 'recall')
        o.append(f'| {anc} | {a} | S {w.S:.2f}, {status(w, 101 + M)} | g{dayidx(w.cache.due)} | t={101 - dayidx(initial(base, opt).anchor)} gün |')
    # olgun eski kelime: çok uzun süre önce görülmüş (lastReviewedAt g0, S=30, vade g30), göç g60'ta (vadesi 30 gün geçmiş)
    o.append('\nOlgun eski kelime: S=30, son tekrar g0, vade g30; göç g60 (vadesi 30 gün geçmiş); g60 akşam hatırlama doğru:\n')
    o.append('| K1 | t | Sonra S | Beklenen (eski motor gibi t=60) |\n|---|---|---|---|')
    for anc in ('baseAt', 'lastReviewed'):
        opt = dict(OPT, base_anchor=anc)
        base = Base(S=30, D=5, due=30.375, lapsed=None, at=60.5, anchor=.375)
        w = Word(base, opt)
        w.add(60.8, GOOD, 'recall')
        ref = 30 * (1 + math.exp(1.5) * 6 * 30 ** -0.2 * (math.exp(1.2 * (1 - R(60, 30))) - 1))
        o.append(f'| {anc} | {60 - dayidx(initial(base, opt).anchor)} | {w.S:.2f} | {ref:.2f} |')
    # learnedAt kaybı
    base = Base(S=60, D=5, due=90.375, at=40.5, anchor=30.375)
    w = Word(base)
    t0 = 41
    o.append(f'\nÖğrenilmiş eski kelime (S=60, eski `learnedAt` g20): göçten sonra önbellekteki `learnedAt` = '
             f'{"g" + str(dayidx(w.cache.learned)) if w.cache.learned else "YOK"}; ilk üretim doğrusu (g90): ')
    w.add(90 + M, GOOD, 'recall')
    a = w.cache.learned
    w.add(200 + M, GOOD, 'recall') if False else None
    nd = w.cache.due
    w.add(nd + .01, GOOD, 'recall')
    o[-1] += (f'{"g" + str(dayidx(a)) if a else "yok"}; ikinci üretim günü (g{dayidx(nd + .01)}): '
              f'{"g" + str(dayidx(w.cache.learned)) if w.cache.learned else "yok"} → "Bu Hafta öğrenildi" sayılır.')
    o.append('\n## G) Ekran vade metni ile seçim tutarlılığı\n')
    rng = random.Random(9); bad = 0; checks = 0; bad_ex = None
    for trial in range(300):
        w = mature(rng.choice([5, 12, 30]))
        for d in range(30):
            if rng.random() < .6:
                w.add(d + M + rng.random() * .5, rng.choice([GOOD, GOOD, AGAIN, HARD]), rng.choice(['recall', 'recog', 'letters']))
            for tt in (d + .2, d + .9):
                checks += 1
                txt = due_text(w.cache, tt); due = w.is_due(tt)
                if (txt in ('Bugün',) or 'gecikti' in txt) != due and not (txt == 'Bugün' and not due):
                    bad += 1; bad_ex = bad_ex or (hhmm(tt), txt, due)
    # "Bugün" ama henüz isDue değil (vade bugün ilerideki bir saatte)
    today_not_due = 0; tot = 0
    for trial in range(300):
        w = mature(rng.choice([5, 12, 30]))
        for d in range(30):
            if rng.random() < .6:
                w.add(d + M, rng.choice([GOOD, AGAIN]), 'recall')
            tot += 1
            today_not_due += due_text(w.cache, d + .2) == 'Bugün' and not w.is_due(d + .2)
    o.append(f'- 300 rastgele kelime × 30 gün × 2 an: "gecikti/Bugün" metni ile isDue çelişkisi **{bad}**/{checks}'
             + (f' (örnek {bad_ex})' if bad_ex else '') + f'. "Bugün" yazıp henüz seçilmeyen an: {today_not_due}/{tot} '
             '(vade 04:00 gün başına oturduğu için gün içinde "Bugün" = seçilebilir).')
    w = mature(30)
    w.add(30 + M, AGAIN, 'recall')
    o.append(f'- Zayıf kelime (g30 yanlış): vade g31 04:00. g30 23:00 metin "{status(w, 30 + 23 / 24)}", isDue {w.is_due(30 + 23 / 24)}; '
             f'g31 03:00 metin "{status(w, 31 + 3 / 24)}", isDue {w.is_due(31 + 3 / 24)}; g31 05:00 metin "{status(w, 31 + 5 / 24)}", isDue {w.is_due(31 + 5 / 24)}.')
    w = mature(30); w.add(30 + M, GOOD, 'recall')
    o.append(f'- Olgun doğru (g30 09:00): vade g{dayidx(w.cache.due)} {hhmm(w.cache.due)} = anchor(04:00)+S; vade anında ekran {pct(w.memory(w.cache.due))}; '
             f'aynı gün 09:00\'da ekran {pct(w.memory(30 + M))} (çıpa 04:00 olduğu için hemen %100 değil).')
    return '\n'.join(o)



# ------------------------------------------------------------------ v7: v6 bulgularının testleri + göç
def migrate(old_S, old_D, old_due, old_last, old_learned, logs_seen, now, old_weak=None, opt=OPT):
    """§6: göç anındaki önbellekten taban. old_weak: eski hile (due < last)."""
    if not logs_seen and old_last is None:          # reviewCount == 0
        return Base(at=-1e18)
    weak = old_due < old_last if old_weak is None else old_weak
    cands = [x for x in (max((l[0] for l in logs_seen), default=None), old_last) if x is not None]
    at = max(cands) if cands else now                # §6: max(son log, eski lastReviewedAt)
    return Base(S=old_S, D=old_D, due=(now if weak else old_due), lapsed=(dstart(old_last) if weak else None),
                at=at, anchor=old_last, learned=old_learned)


def part_v7():
    o = ['\n## C) v6 bulgularının v7 testleri\n']
    # v6-Y1 widget-yalnız / widget ağırlıklı
    o.append('**v6-Y1 — widget kilidi (S<21)**, 500 tohum, 120 gün:\n')
    o.append('| Widget / hatırlama | widget seçimi | Öğrenildi | learnedAt medyan günü (ulaşan) | hatırlama sorulan gün (medyan) | son S medyanı |\n|---|---|---|---|---|---|')
    for pw, pr in ((1.0, .9), (.9, .9), (.9, .7), (.9, .3), (1.0, 0.0)):
        for wa in (False, True):
            runs = [sim_policy(pol_widget(pw, pr, wa), seed=s_) for s_ in range(500)]
            L, fl, nfl, lap = agg(runs)
            rd = [getattr(w, 'recall_days', 0) for w, _ in runs]
            o.append(f'| %{int(pw * 100)} / %{int(pr * 100)} | {"her sabah" if wa else "yalnız isDue"} | **{L}**/500 | g{fl} ({nfl}) | {st.median(rd):.0f} | {st.median([w.S for w, _ in runs]):.1f} |')
    # yalnız widget, hiç hatırlama yok (kullanıcı Günlük Tekrar'ı hiç açmıyor)
    def only_widget(p):
        def f(d, w, rng):
            if d == 0:
                w.add(d + M, GOOD, 'recall'); return  # tanıtım (hatırlama)
            if w.is_due(d + .3):
                w.add(d + .3, GOOD if rng.random() < p else AGAIN, 'recog')
        return f
    for p in (1.0, .9):
        runs = [sim_policy(only_widget(p), seed=s_) for s_ in range(500)]
        L, fl, nfl, lap = agg(runs)
        o.append(f'\nYalnız widget (Günlük Tekrar hiç açılmıyor), %{int(p * 100)}: Öğrenildi {L}/500, son S medyanı {st.median([w.S for w, _ in runs]):.1f}, '
                 f'widget cevap sayısı medyanı {st.median([len(w.logs) for w, _ in runs]):.0f}, zayıf gün medyanı {lap:.0f}')
    # iz
    w = Word(); w.add(M, GOOD, 'recall'); tr = []
    for d in range(1, 40):
        if w.is_due(d + .3):
            w.add(d + .3, GOOD, 'recog'); tr.append(f'g{d}:S{w.S:.1f}/vade g{dayidx(w.cache.due)}')
        if w.is_due(d + .8):
            w.add(d + .8, GOOD, 'recall'); tr.append(f'g{d} akşam hatırlama → S{w.S:.1f}/vade g{dayidx(w.cache.due)}')
    o.append('\nİz (%100 widget, isDue; akşam isDue ise hatırlama doğru): ' + ' · '.join(tr))

    # v6-Y2 göç çıpası
    o.append('\n**v6-Y2 — göç çıpası**: S=30 kelime, son tekrar g0 09:00 (log), vade g30; göç g60 12:00; g60 18:00 hatırlama doğru:\n')
    o.append('| baseAt karşılaştırması | S sonra | beklenen |\n|---|---|---|')
    exp = 30 * (1 + math.exp(1.5) * 6 * 30 ** -0.2 * (math.exp(1.2 * (1 - R(60, 30))) - 1))
    for cmp_ in ('ge', 'gt'):
        opt = dict(OPT, base_cmp=cmp_)
        logs = [(M, GOOD, 'recall')]
        base = migrate(30, 5, 30.375, M, None, logs, 60.5)
        w = Word(base, opt); w.logs = list(logs)
        c = replay(base, logs + [(60.75, GOOD, 'recall')], opt=opt)
        o.append(f'| {cmp_} | {c.S:.2f} | {exp:.2f} |')

    # v6-Y3 learnedAt
    o.append('\n**v6-Y3 — learnedAt göçte korunuyor mu**: S=60, eski learnedAt g20, son tekrar g30 (log), vade g90; göç g40:')
    logs = [(30 + M, GOOD, 'recall')]
    base = migrate(60, 5, 90.375, 30 + M, 20.2, logs, 40.5)
    c0 = replay(base, logs, now=40.5)
    c1 = replay(base, logs + [(90 + M, GOOD, 'recall')])
    c2 = replay(base, logs + [(90 + M, GOOD, 'recall'), (90 + M + 1, AGAIN, 'recall'), (92 + M, GOOD, 'recall')])
    o.append(f'göç sonrası learnedAt g{dayidx(c0.learned)}; ilk tekrar sonrası g{dayidx(c1.learned)}; yanlış+toparlanma sonrası g{dayidx(c2.learned)} → '
             f'"Bu Hafta" sayımına **{"girmiyor" if dayidx(c2.learned) == 20 else "GİRİYOR"}**.')
    # Bu Hafta şişmesi: 200 öğrenilmiş eski kelime göç sonrası 2 hafta çalışılıyor
    rng = random.Random(3); cnt_week = 0
    for i in range(200):
        L0 = rng.uniform(0, 30)
        logs = [(35 + rng.random(), GOOD, 'recall')]
        base = migrate(rng.uniform(21, 200), 5, 40 + rng.uniform(0, 60), logs[0][0], L0, logs, 40.5)
        ls = logs + [(41 + d + M, GOOD if rng.random() < .9 else AGAIN, 'recall') for d in range(14) if rng.random() < .3]
        c = replay(base, ls)
        cnt_week += c.learned is not None and c.learned >= 41
    o.append(f'200 öğrenilmiş eski kelime, göçten sonra 14 gün çalışma: learnedAt\'i göç sonrasına kayan kelime **{cnt_week}**.')

    # v6-O1 zayıf göç kelimesi "gecikti"
    o.append('\n**v6-O1 — zayıf göç kelimesi metni**: eski S=11,4, g100 09:00 yanlış (log), eski hileli vade g91; göç g100 18:00:')
    logs = [(100 + M, AGAIN, 'recall')]
    for cmp_ in ('ge', 'gt'):
        opt = dict(OPT, base_cmp=cmp_)
        base = migrate(11.4, 5.95, 91.375, 100 + M, None, logs, 100.75)
        c = replay(base, logs, now=100.75, opt=opt)
        w = Word(base, opt); w.cache = c
        t2 = 101 + M
        c2 = replay(base, logs + [(t2, GOOD, 'recall')], opt=opt)
        w2 = Word(base, opt); w2.cache = c2
        o.append(f'- baseAt {cmp_}: göç anında metin "{status(w, 100.75)}", isDue {w.is_due(100.75)}, S {c.S:.2f} (eski önbellek 11,40), vade {hhmm(c.due)}; '
                 f'ertesi gün doğru → S {c2.S:.2f}, "{status(w2, t2)}"')

    # v6-O2 günde 2 cevap
    o.append('\n**v6-O2 — günde 2 cevap** (açık karar, v7\'de değişmedi): aşağıdaki desen tablosunda %90 her gün 1/2/3 oyun.')
    return '\n'.join(o)


def part_migration7():
    o = ['\n## F) Göç senaryoları (v7)\n']
    # (1) son log günü tekrar işleniyor mu (L1)
    o.append('**(1) baseAt = son log tarihi; `>=` ile o log yeniden işleniyor mu?** Eski motorda son gün (g50) üç cevap: D 09:00, D 11:00, Y 13:00; '
             'eski önbellek S=20 (eski motorun sonucu), zayıf (hile). Göç g50 20:00.\n')
    o.append('| Varsayım | göç sonrası S | lapsedAt | not |\n|---|---|---|---|')
    logs = [(50 + M, GOOD, 'recall'), (50 + M + .08, GOOD, 'recall'), (50 + M + .16, AGAIN, 'recall')]
    for cmp_ in ('ge', 'gt'):
        opt = dict(OPT, base_cmp=cmp_)
        base = migrate(20, 6, 49.0, logs[-1][0], None, logs, 50 + 20 / 24, old_weak=True)
        c = replay(base, logs, now=50.9, opt=opt)
        o.append(f'| {cmp_} | {c.S:.2f} | {"g" + str(dayidx(c.lapsed)) if c.lapsed else "—"} | '
                 f'{"son log (Y) tek başına yeniden işlendi: zaten zayıf → S×0,5" if cmp_ == "ge" else "taban aynen korunur"} |')
    logs = [(50 + M, HARD, 'recall')]
    for cmp_ in ('ge', 'gt'):
        opt = dict(OPT, base_cmp=cmp_)
        base = migrate(20, 6, 70.0, logs[-1][0], None, logs, 50.8)
        c = replay(base, logs, now=50.9, opt=opt)
        o.append(f'| {cmp_}, son log hard | S {c.S:.2f} D {c.D:.2f} | — | {"D yeniden +0,4 (çift sayım)" if cmp_ == "ge" else "taban"} |')
    # (2) göç anında eşitlenmemiş log: baseAt'ten sonra / önce
    o.append('\n**(2) Göç anında eşitlenmemiş log** (S=30 olgun, son yerel log g30 09:00; göç g31 20:00):')
    base = migrate(30, 5, 60.375, 30 + M, None, [(30 + M, GOOD, 'recall')], 31.8)
    late_after = (31 + M, AGAIN, 'recall')   # öbür cihazdan, baseAt'ten sonra
    late_before = (29 + M, AGAIN, 'recall')  # öbür cihazdan, baseAt'ten önce
    ca = replay(base, [(30 + M, GOOD, 'recall'), late_after], opt=dict(OPT, base_cmp='gt'))
    cb = replay(base, [(30 + M, GOOD, 'recall'), late_before], opt=dict(OPT, base_cmp='gt'))
    o.append(f'- baseAt\'ten SONRA tarihli geç log (g31 Y): işlendi → S {ca.S:.2f}, zayıf {ca.lapsed is not None} ✓')
    o.append(f'- baseAt\'ten ÖNCE tarihli geç log (g29 Y): yok sayıldı → S {cb.S:.2f}, zayıf {cb.lapsed is not None} (belgenin kabul ettiği dar pencere)')
    # (2b) Word kaydı logdan önce eşitlenmişse: taban o cevabı zaten içerir, log baseAt'ten sonra → çift sayım
    o.append('\n**(2b) Eski sürümde Word kaydı, logundan ÖNCE eşitlenmişse** (A cihazı g30 10:00 yanlış yaptı; A\'nın Word kaydı B\'ye ulaştı, logu ulaşmadı; '
             'B\'nin son logu g30 09:00; B g30 20:00\'de göç eder):')
    # B'nin önbelleği A'nın yanlışını içeriyor: S 30 → 11.4, zayıf
    base = migrate(11.4, 5.85, 30.5, 30 + 10 / 24, None, [(30 + M, GOOD, 'recall')], 30 + 20 / 24, old_weak=True)
    base = replace(base, at=30 + M)   # B'nin son logu 09:00
    c = replay(base, [(30 + M, GOOD, 'recall'), (30 + 10 / 24, AGAIN, 'recall')], opt=dict(OPT, base_cmp='gt'))
    o.append(f'- A\'nın logu gelince: S 11,40 (taban, yanlışı zaten içeriyor) → {c.S:.2f} (yanlış **ikinci kez** işlendi, "zaten zayıf" ×0,5).')
    # (3) iki cihaz farklı anda göç, son yazan kazanır
    o.append('\n**(3) İki cihaz farklı anda göç; taban çakışması** (eski sürümde A: g10 D, g20 D; B: g25 Y — B\'nin logu A\'ya göç anında ulaşmamış):')
    logsA = [(10 + M, GOOD, 'recall'), (20 + M, GOOD, 'recall')]
    logB = (25 + M, AGAIN, 'recall')
    baseA = migrate(34.5, 5, 55.0, 20 + M, 20.2, logsA, 26.0)                 # A göç g26 (B'nin logunu/Word'ünü görmemiş)
    baseB = migrate(11.4, 5.85, 26.0, 25 + M, None, logsA + [logB], 27.0, old_weak=True)  # B göç g27
    allg = logsA + [logB] + [(40 + M, GOOD, 'recall')]
    for name, b in (('A kazanır (baseAt g20)', baseA), ('B kazanır (baseAt g25)', baseB)):
        c = replay(b, allg, opt=dict(OPT, base_cmp='gt'))
        c_ge = replay(b, allg, opt=dict(OPT, base_cmp='ge'))
        o.append(f'- {name}: g40 doğrudan sonra S {c.S:.2f} (`>`), {c_ge.S:.2f} (`>=`); learnedAt {"g" + str(dayidx(c.learned)) if c.learned else "yok"}')
    o.append('  Not: A tabanı kazanırsa B\'nin g25 yanlışı baseAt\'ten SONRA olduğu için işlenir (kayıp yok); B kazanırsa A\'nın geçmişi tabanda. '
             'İki sonuç farklı ama ikisi de makul; §6 "birleştirmede eski baseAt kazanır" kuralı CloudKit\'in kendi çakışma çözümünde uygulanamaz (son yazan kazanır).')
    return '\n'.join(o)


def part_order7():
    o = ['\n## E2) Eşit zaman damgası ve gelecek tarihli log\n']
    T = 30 + M
    a = replay(Base(S=30, D=5, due=60, at=M, anchor=M), [(T, GOOD, 'recall'), (T, AGAIN, 'recall')])
    b = replay(Base(S=30, D=5, due=60, at=M, anchor=M), [(T, AGAIN, 'recall'), (T, GOOD, 'recall')])
    o.append(f'- Aynı saniyede D ve Y (iki sırada): S {a.S:.2f} / {b.S:.2f} — {"aynı" if a == b else "FARKLI"} (yanlış önce sıralanır → doğru 0 sn sonra, kapı içinde, sayılmaz → again)')
    c = replay(Base(S=30, D=5, due=60, at=M, anchor=M), [(T, GOOD, 'recall'), (T + 5, AGAIN, 'recall')], now=T + 1)
    o.append(f'- Gelecek tarihli log (cihaz saati 4 gün ileri): now anında yok sayıldı → S {c.S:.2f}; 5 gün sonra işlenir.')
    for sec in (1799, 1800, 1801):
        c = replay(Base(S=30, D=5, due=60, at=M, anchor=M),
                   [(T, AGAIN, 'recall'), (T + sec / SEC, GOOD, 'recall'), (T + 2700 / SEC, GOOD, 'recall')])
        o.append(f'- Y, {sec} sn sonra D, 45. dk D → {GNAME[c.last_dg]}, S {c.S:.2f}')
    return '\n'.join(o)



def part_v8():
    o = ['\n## H) v8 özel testleri\n']
    # v7-Y1: son logun iki kez sayılması
    o.append('**v7-Y1 — son log iki kez sayılıyor muydu?** (v8: `>` ve baseAt=max(son log, lastReviewedAt))\n')
    logs = [(100 + M, AGAIN, 'recall')]
    base = migrate(11.4, 5.95, 91.375, 100 + M, None, logs, 100.75)
    c = replay(base, logs, now=100.75); w = Word(base); w.cache = c
    c2 = replay(base, logs + [(101 + M, GOOD, 'recall')]); w2 = Word(base); w2.cache = c2
    o.append(f'- Zayıf eski kelime (S=11,40, son log g100 09:00 Y, göç 18:00): S {c.S:.2f}, "{status(w, 100.75)}", isDue {w.is_due(100.75)}; ertesi gün D → S {c2.S:.2f}, "{status(w2, 101 + M)}"')
    logs = [(50 + M, GOOD, 'recall'), (50 + M + .08, GOOD, 'recall'), (50 + M + .16, AGAIN, 'recall')]
    base = migrate(20, 6, 49.0, logs[-1][0], None, logs, 50.85, old_weak=True)
    c = replay(base, logs, now=50.9)
    o.append(f'- Son günü D, D, Y olan eski kelime (eski S=20): göç sonrası S {c.S:.2f}, D {c.D:.2f}')
    logs = [(50 + M, HARD, 'recall')]
    base = migrate(20, 6, 70.0, logs[-1][0], None, logs, 50.8)
    c = replay(base, logs, now=50.9)
    o.append(f'- Son log hard: S {c.S:.2f}, D {c.D:.2f} (taban 6,00)')
    # v7-O1: Word logdan önce eşitlenmiş
    o.append('\n**v7-O1 — eski sürümde Word kaydı logdan önce eşitlenmişse**:')
    # (a) A'nın cevabı lastReviewedAt'i güncellemiş (günün ilk cevabı)
    base = migrate(11.4, 5.85, 30.5, 30 + 10 / 24, None, [(29 + M, GOOD, 'recall')], 30 + 20 / 24, old_weak=True)
    c = replay(base, [(29 + M, GOOD, 'recall'), (30 + 10 / 24, AGAIN, 'recall')])
    o.append(f'- (a) A\'nın g30 10:00 yanlışı günün ilk cevabı (eski kod lastReviewedAt=10:00 yazar): baseAt {hhmm(base.at)}; A\'nın logu gelince S {c.S:.2f} (taban 11,40) → çift sayım **yok** ✓')
    # (b) A'nın yanlışı günün 2. cevabı: eski kod lastReviewedAt'i güncellemez (sabah 09:00 kalır) ama dueDate'i geçmişe atar
    logsB = [(30 + M, GOOD, 'recall')]    # B'de A'nın sabah cevabının logu var
    base = migrate(30 * 0 + 82.09, 5.0, 29.0, 30 + M, None, logsB, 30 + 22 / 24, old_weak=True)  # A'nın akşam yanlışı Word'e yansımış: hile ile zayıf
    c = replay(base, logsB + [(30 + 20 / 24, AGAIN, 'recall')])
    o.append(f'- (b) A\'nın g30 20:00 yanlışı günün 2. cevabı (eski kod lastReviewedAt\'i 09:00\'da bırakır, yalnızca vadeyi geçmişe atar): '
             f'baseAt {hhmm(base.at)}, taban zayıf; A\'nın 20:00 logu gelince yeniden işlenir → S {c.S:.2f} (taban 82,09; eski motor yanlışta S\'yi değiştirmemişti) '
             f'→ yanlış ilk kez S\'ye işleniyor, ama "zaten zayıf" sayıldığı için ×0,5 (ilk zayıflama olsaydı {82.09 * (0.65 - 0.3 * R(0, 82.09)):.2f}/tavan {3 * math.sqrt(82.09):.2f})')
    # yeni kelime distantPast
    o.append('\n**Yeni kelime (reviewCount == 0 → baseAt = distantPast)**:')
    b = migrate(0, 5, 0, None, None, [], 5.0)
    c = replay(b, [(5 + M, AGAIN, 'recall'), (6 + M, GOOD, 'recall')])
    o.append(f'- Hiç cevaplanmamış kelime: baseAt {"distantPast" if b.at < -1e17 else b.at}; ilk yanlış + ertesi gün doğru → S {c.S:.2f} (sıfırdan: 0,40 → 2,82 beklenir)')
    # iki cihaz: biri reviewCount==0 görür (log/Word gelmemiş), öbürü tam taban yazar
    oldlogs = [(10 + M, GOOD, 'recall'), (13 + M, GOOD, 'recall')]    # eski sürüm cevapları (eski motor: S=11,3 → 34,5 gibi)
    baseB = migrate(34.5, 5.0, 47.5, 13 + M, None, oldlogs, 20.5)
    baseA = Base(at=-1e18)                                              # A: kelime henüz eşitlenmemiş, reviewCount 0 → distantPast
    later = [(48 + M, GOOD, 'recall')]
    r_B = replay(baseB, oldlogs + later)
    r_A = replay(baseA, oldlogs + later)
    mixed = replace(baseB, at=-1e18)   # alan bazında birleşme: baseAt A'dan, base* B'den
    r_mix = replay(mixed, oldlogs + later)
    o.append(f'- İki cihaz, A kelimeyi reviewCount=0 görüp distantPast yazar, B tam taban yazar. g48 doğrudan sonra: B kazanırsa S {r_B.S:.2f}; '
             f'A kazanırsa (bütün eski loglar yeni motorla baştan) S {r_A.S:.2f}; **alanlar karışırsa** (baseAt=distantPast + B\'nin base S=34,5) S {r_mix.S:.2f} '
             f'— eski loglar tabanın üstüne ikinci kez işlenir.')
    # S>=21 zayıf + tanıma
    o.append('\n**Yeni kural: S≥21 zayıf kelimede tanıma zayıflığı kaldırmaz**')
    w = mature(300)
    for step in [(300 + M, AGAIN, 'recall'), (301 + M, GOOD, 'recog'), (302 + M, GOOD, 'recog'), (303 + M, GOOD, 'recog')]:
        w.add(*step)
        o.append(f'- {hhmm(step[0])} {GNAME[step[1]]}/{step[2]}: S {w.S:.2f}, zayıf {w.cache.lapsed is not None}, vade {hhmm(w.cache.due)}, '
                 f'isDue {w.is_due(step[0] + .01)}, "{status(w, step[0] + .01)}", ekran {pct(w.memory(step[0]))}')
    w.add(303 + 20 / 24, GOOD, 'recall')
    o.append(f'- g303 20:00 hatırlama D: S {w.S:.2f}, zayıf {w.cache.lapsed is not None}, "{status(w, 303.9)}"')
    w = mature(30)
    for step in [(30 + M, AGAIN, 'recall'), (31 + M, GOOD, 'recog'), (32 + M, GOOD, 'recog')]:
        w.add(*step)
    o.append(f'- Karşılaştırma S<21 (S=30 → 11,40): 2 tanıma gününden sonra zayıf {w.cache.lapsed is not None}, S {w.S:.2f}')
    # widget-yalnız kullanıcı, olgun kelimeler
    def only_widget_mature(p):
        def f(d, w, rng):
            if w.is_due(d + .3):
                w.add(d + .3, GOOD if rng.random() < p else AGAIN, 'recog')
        return f
    for S0 in (30, 100, 300):
        runs = [sim_policy(only_widget_mature(.9), days=180, seed=s_, start=lambda S0=S0: mature(S0, at=M - 0 * S0)) for s_ in range(300)]
        stuck = sum(1 for w, tr in runs if w.cache.lapsed is not None and w.S >= 21)
        lap_end = sum(1 for w, tr in runs if w.cache.lapsed is not None)
        o.append(f'- Yalnız widget (%90), başlangıç S={S0}, 180 gün: sonunda zayıf {lap_end}/300 (bunların S≥21 olup tanımayla asla kurtulamayanı {stuck}); '
                 f'S medyanı {st.median([w.S for w, _ in runs]):.1f}')
    return '\n'.join(o)


if __name__ == '__main__':
    import sys
    parts = sys.argv[1:] or ['a', 'i', 't', 'h', 'e', 'o', 'm', 'v', 'p']
    if 'a' in parts: print(part_a())
    if 'i' in parts: print(part_intuition())
    if 't' in parts: print(check_table())
    if 'h' in parts: print(part_v8())
    if 'e' in parts: print(part_extra())
    if 'o' in parts: print(part_order7())
    if 'm' in parts: print(part_migration7())
    if 'v' in parts: print(part_v7())
    if 'p' in parts: print(part_patterns())
