#!/usr/bin/env python3
"""Builds the Museum's World Currencies collection.

Sources, in order of preference for each note:
  1. curated.py: hand-written placards for notes that have one.
  2. central_banks.json: official images from central bank websites,
     checked by hand, for currencies Wikipedia can't illustrate.
  3. Wikipedia: the banknote tables in each currency's article (every
     denomination of the current series, with what each side shows).

Countries, flags and regions come from Wikidata. Images are not copied:
the collection stores links, and Shelf loads each picture from its source
on first view. Writes Support/Museum/currencies.json.

    /usr/bin/python3 scripts/museum/currencies.py
"""
import json, re, sys, time, pathlib, urllib.parse, urllib.request, urllib.error

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parents[1] / "Support/Museum/currencies.json"
UA = {"User-Agent": "ShelfMuseumSetup/0.2 (https://github.com/imrajjain/my-home-shelf)"}
WIKI = "https://en.wikipedia.org/w/api.php"

sys.path.insert(0, str(HERE))
import curated  # noqa: E402

# ---------------------------------------------------------------- network

def api(**q):
    q.update(format="json", formatversion="2", maxlag="5")
    data = urllib.parse.urlencode(q).encode()
    for i in range(12):
        time.sleep(1.5)
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(WIKI, data=data, headers=UA), timeout=60))
        except urllib.error.HTTPError as e:
            time.sleep(max(int(e.headers.get("Retry-After") or 0), 15 * (i + 1)))
        except Exception:
            time.sleep(5 * (i + 1))
    raise RuntimeError("Wikipedia API unreachable")

def sparql(query):
    url = "https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": query})
    req = urllib.request.Request(url, headers={**UA, "Accept": "application/sparql-results+json"})
    rows = json.load(urllib.request.urlopen(req, timeout=120))["results"]["bindings"]
    return [{k: v["value"] for k, v in r.items()} for r in rows]

# ---------------------------------------------------------------- countries

NOT_CURRENT = {"USN", "XXX", "XDR", "CHE", "CHW", "COU", "MXV", "UYI", "BOV", "CLF", "USS",
               "ZWD", "ZWN", "ZWR", "PLZ", "XCG"}
REGION = {"Asia": "Asia", "Europe": "Europe", "Africa": "Africa", "North America": "Americas",
          "South America": "Americas", "Oceania": "Oceania", "Australia": "Oceania", "Insular Oceania": "Oceania"}
REGION_ORDER = ["Asia", "Europe", "Africa", "Americas", "Oceania"]

def currencies():
    rows = sparql("""
    SELECT ?countryLabel ?iso2 ?continentLabel ?code ?article WHERE {
      ?country wdt:P31 wd:Q3624078; wdt:P297 ?iso2; wdt:P38 ?currency.
      FILTER NOT EXISTS { ?country wdt:P576 ?gone }
      FILTER NOT EXISTS { ?country p:P38 ?st. ?st ps:P38 ?currency; pq:P582 ?end }
      ?currency wdt:P498 ?code.
      OPTIONAL { ?country wdt:P30 ?continent }
      OPTIONAL { ?article schema:about ?currency; schema:isPartOf <https://en.wikipedia.org/> }
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }""")
    out = {}
    for r in rows:
        code = r["code"]
        if code in NOT_CURRENT:
            continue
        article = urllib.parse.unquote(r.get("article", "").rsplit("/", 1)[-1]).replace("_", " ")
        c = out.setdefault(code, {"code": code, "article": article, "countries": []})
        if r["countryLabel"] not in [x["name"] for x in c["countries"]]:
            c["countries"].append({"name": r["countryLabel"], "iso2": r["iso2"],
                                   "region": REGION.get(r.get("continentLabel", ""), "")})
    for c in out.values():
        # The issuing country first: its ISO code usually starts the currency code.
        c["countries"].sort(key=lambda x: (x["iso2"] != c["code"][:2], x["name"]))
    return out

def flag(iso2):
    return "".join(chr(0x1F1E6 + ord(ch) - 65) for ch in iso2.upper())

# ---------------------------------------------------------------- Wikipedia tables

FILE = re.compile(r"\[\[\s*(?:File|Image)\s*:\s*([^|\]]+?\.(?:jpe?g|png|gif|webp|tiff?))", re.I)

def wikitexts(titles):
    texts = {}
    for i in range(0, len(titles), 20):
        q = api(action="query", prop="revisions", rvprop="content", rvslots="main",
                titles="|".join(titles[i:i + 20]), redirects=1)["query"]
        back = {n["to"]: n["from"] for n in q.get("normalized", [])}
        for rd in q.get("redirects", []):
            back[rd["to"]] = back.get(rd["from"], rd["from"])
        for p in q["pages"]:
            if "revisions" in p:
                texts[back.get(p["title"], p["title"])] = (p["title"], p["revisions"][0]["slots"]["main"]["content"])
    return texts

def sections(text):
    parts = re.split(r"\n(={2,5})\s*([^=\n]+?)\s*\1\s*\n", "\n" + text)
    out, path = [("", parts[0])], []
    for i in range(1, len(parts) - 2, 3):
        path = path[:len(parts[i]) - 2] + [parts[i + 1].strip()]
        out.append((" / ".join(path), parts[i + 2]))
    return out

def clean(cell):
    c = re.sub(r"<ref[^>]*>.*?</ref>|<ref[^>]*/>", "", cell, flags=re.S)
    c = re.sub(r"\[\[(?:File|Image):[^\]]*\]\]", "", c, flags=re.I)
    c = re.sub(r"\{\{(?:nowrap|nobr)\|([^{}]*)\}\}", r"\1", c)
    c = re.sub(r"\{\{[^{}|]+\|([^{}=|]*\d[^{}=|]*)\}\}", r"\1", c)   # {{shilingi|1000}} -> 1000
    c = re.sub(r"\{\{[^{}]*\}\}", "", c)
    c = re.sub(r"<br\s*/?>", "; ", c)
    c = re.sub(r"<[^>]+>", "", c)
    c = re.sub(r"'''?", "", c).replace("&nbsp;", " ")
    c = re.sub(r"^\s*(?:[a-z-]+\s*=\s*(?:\"[^\"]*\"|[^\s|]+)\s*)+\|", "", c)   # cell attributes
    return re.sub(r"\s+", " ", c).strip(" |;")

def table_rows(body):
    out = []
    for table in re.findall(r"\{\|.*?\n\|\}", body, re.S):
        carry = {}   # column -> [rows left, text] for cells that span rows
        for row in re.split(r"\n\|-[^\n]*", table)[1:]:
            raw = [c for c in re.split(r"\n[|!]|\|\|", row) if c.strip()]
            cells, col = [], 0
            for c in raw:
                while col in carry:
                    cells.append(carry[col][1])
                    carry[col][0] -= 1
                    if carry[col][0] == 0: del carry[col]
                    col += 1
                span = re.match(r"\s*[^|\[]*rowspan\s*=\s*\"?(\d+)", c)
                text = clean(c)
                if span and int(span.group(1)) > 1:
                    carry[col] = [int(span.group(1)) - 1, text]
                cells.append(text)
                col += 1
            while col in carry:
                cells.append(carry[col][1]); carry[col][0] -= 1
                if carry[col][0] == 0: del carry[col]
                col += 1
            files = FILE.findall(row)
            if len(files) < 2:
                continue
            out.append({"front": files[0].strip(), "back": files[1].strip(), "cells": [c for c in cells if c]})
    return out

def label(text):
    """Wiki markup to plain text: [[a|b]] -> b."""
    return re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", text or "")

COLOUR = re.compile(r"^(?:light |dark |pale |deep )?(red|blue|green|yellow|orange|purple|violet|brown|gr[ae]y|pink|"
                    r"turquoise|olive|cyan|magenta|teal|black|gold(en)?|beige|lilac|ochre|indigo|maroon|navy|"
                    r"multicolou?r(ed)?|aqua|amber|lavender|mauve|crimson|tan|sepia|bronze|silver)\b", re.I)
COLOUR_WORD = re.compile(r"\b(red|blue|green|yellow|orange|purple|violet|brown|gr[ae]y|pink|turquoise|olive|cyan|"
                         r"magenta|teal|lilac|ochre|indigo|maroon|lavender|mauve|chocolate|crimson|beige|amber|"
                         r"aqua|gold|silver|bronze)\b", re.I)
SUBUNIT = re.compile(r"\b(cents?|centavos?|centimes?|möngö|kopeks?|kopiyok|satang|sen|paisa|poisha|fils|halalas?|tiyin|"
                     r"piastres?|santims?|qəpik|luma|tetri|baisa|dirhams? of|coin)\b", re.I)
MONTH = r"(january|february|march|april|may|june|july|august|september|october|november|december)"
YEAR = r"\b(?:1[89]|20)\d\d\b"

def undouble(v):
    """"€10" followed by a template's own copy of the number: "€1010" -> "€10"."""
    m = re.fullmatch(r"(\D*?)([\d,]+)(\D*)", v or "")
    if m:
        digits = m.group(2).replace(",", "")
        half = len(digits) // 2
        if len(digits) % 2 == 0 and digits[:half] == digits[half:]:
            return m.group(1) + format(int(digits[:half]), ",") + m.group(3)
    return v

def read_row(cells):
    value = colour = size = None
    years, desc = [], []
    for c in cells:
        plain = label(c).strip()
        low = plain.lower()
        if not plain:
            continue
        if re.search(r"\d\s*[×x]\s*\d|\d\s*mm\b", plain) and len(plain) < 40:
            size = size or plain
        elif plain in ("None", "N/A", "—", "-", "n/a"):
            continue
        elif (COLOUR.match(low) or (COLOUR_WORD.search(low) and len(low.split()) <= 3)) and len(plain) < 30:
            colour = colour or plain
        elif re.search(YEAR, plain) and (re.search(MONTH, low) or re.fullmatch(r"[\W\d–—-]*|.*present.*", low)) and len(plain) < 40:
            years += [int(y) for y in re.findall(YEAR, plain)]
        elif value is None and re.fullmatch(r"\D{0,4}\d[\d,.\s]*\s*[^\W\d_]{0,12}\.?", plain):
            value = undouble(plain)
        elif len(plain) > 2 and re.search(r"[^\W\d_]{3}", plain):
            desc.append(c.strip())
    return value, colour, size, years, desc

def number(text):
    m = re.search(r"\d[\d,.\s]*", text or "")
    return int(re.sub(r"[^\d]", "", m.group(0)) or 0) if m else 0

# Which table is the current series, where the article makes it ambiguous.
SECTION = {"AZN": "2020 refurbishment", "GEL": "Lari / Banknotes", "JPY": "Reiwa era", "EUR": "Second series",
           "THB": "2003–present", "KRW": "Second South Korean won / Banknotes", "IQD": "2003–present",
           "AUD": "Third series (polymer)", "HUF": "2014 series", "BYN": "Third ruble", "KZT": "2023-2025",
           "KGS": "Fifth series (2023)", "NZD": "Current banknotes", "UZS": "Second sum", "MMK": "1989–present",
           "VND": "Third dong", "FJD": "2012 Series", "MXN": "Series G", "CHF": "Ninth series"}
# Tables that still list long-retired small notes beside the current ones.
MINIMUM = {"UZS": 1000, "LAK": 500, "MMK": 50}
# Tables that only hold a single sample, or an outdated series.
SKIP = {"SGD", "BND", "PYG", "GNF", "ILS", "LBP"}

def current_rows(code, rows):
    if code in SKIP:
        return []
    if code in SECTION:
        rows = [r for r in rows if SECTION[code] in r["section"] and "ommemorat" not in r["section"]]
    else:
        groups = {}
        for r in rows:
            groups.setdefault((r["article"], r["section"]), []).append(r)
        order = list(groups)
        def score(key):
            art, sec = key
            s = order.index(key)
            if re.search(r"current|present|circulat|in use|new|latest", sec, re.I): s += 1000
            if re.search(r"withdrawn|former|old|historical|commemorative|first series|provisional|stamped|overprint", sec, re.I): s -= 800
            if art.startswith("Banknotes of"): s += 50
            ys = [int(y) for y in re.findall(YEAR, sec)]
            return s + (max(ys) / 10 if ys else 0)
        big = [k for k in order if len(groups[k]) >= 2] or order
        rows = groups[max(big, key=score)] if big else []
    best = {}
    for r in rows:
        value, colour, size, years, desc = read_row(r["cells"])
        if value is None and desc and re.match(r"\D{0,4}\d", label(desc[0])) and len(label(desc[0])) < 24:
            value, desc = undouble(label(desc[0])), desc[1:]
        if desc and re.search(r"District|Oblast", desc[0]) and len(desc) >= 3:
            desc = desc[1:]   # the ruble's tables lead with the federal district
        key = number(value) or number(r["front"])
        if (not key or SUBUNIT.search(label(value or "")) or re.search(r"\bcoins?\b", " ".join(r["cells"]), re.I)
                or re.search(r"(1[89]|20)\d\d, (1[89]|20)\d\d", value or "")):
            continue
        year = max(years) if years else 0
        if key not in best or year >= best[key]["year"]:
            best[key] = dict(r, value=value, colour=colour, size=size, year=year, desc=desc, key=key)
    return [best[k] for k in sorted(best) if k >= MINIMUM.get(code, 0)]

# ---------------------------------------------------------------- images & text

def file_info(names):
    info = {}
    names = sorted(set(names))
    for i in range(0, len(names), 25):
        q = api(action="query", prop="imageinfo", iiprop="url|size|extmetadata", iiurlwidth=1920,
                titles="|".join("File:" + n for n in names[i:i + 25]), redirects=1)["query"]
        back = {n["to"]: n["from"] for n in q.get("normalized", [])}
        for p in q["pages"]:
            ii = (p.get("imageinfo") or [None])[0]
            if ii:
                info[back.get(p["title"], p["title"])[5:]] = ii
    return info

def intros(titles):
    out = {}
    for i in range(0, len(titles), 20):
        q = api(action="query", prop="extracts", exintro=1, explaintext=1, exlimit="max",
                titles="|".join(titles[i:i + 20]), redirects=1)["query"]
        back = {n["to"]: n["from"] for n in q.get("normalized", [])}
        for rd in q.get("redirects", []):
            back[rd["to"]] = back.get(rd["from"], rd["from"])
        for p in q["pages"]:
            out[back.get(p["title"], p["title"])] = p.get("extract", "")
    return out

def summary(text, sentences=3):
    text = re.sub(r"\s*\([^()]*(?:\([^()]*\)[^()]*)*\)", "", text or "")   # drop pronunciations and codes
    text = re.sub(r"\s+", " ", text).strip()
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z])", text)
    return " ".join(parts[:sentences])

def bare(url):
    return url.split("?")[0]

def credit(ii, fallback="Wikimedia Commons"):
    meta = ii.get("extmetadata", {})
    artist = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", (meta.get("Artist") or {}).get("value", ""))).strip()
    licence = (meta.get("LicenseShortName") or {}).get("value", "").strip()
    who = artist if artist and len(artist) < 60 else fallback
    return " · ".join(x for x in (who, licence) if x)

def thumb(ii, width=330):
    t = ii.get("thumburl")
    return re.sub(r"/\d+px-", f"/{width}px-", bare(t)) if t and ii.get("width", 0) > width else None

UNCOUNTED = ("yen", "won", "baht", "kip", "riel", "dong", "đồng", "rand", "som", "sum", "yuan", "renminbi", "rupiah",
             "ringgit", "kyat", "taka", "afghani", "lari", "tenge", "vatu", "kina", "loti", "lilangeni", "ariary",
             "metical", "kwanza", "pula", "nakfa", "ouguiya", "rufiyaa", "ngultrum", "pataca", "tögrög", "somoni",
             "dobra", "leone", "dalasi", "naira", "cedi", "birr", "kwacha", "manat", "dram", "denar", "lek", "forint",
             "sol", "boliviano", "quetzal", "lempira", "balboa", "gourde", "colón", "córdoba", "real", "tala")

def denomination(value, currency):
    v = label(value or "").strip()
    # "€10" followed by the template's own copy of the number: "€1010".
    m = re.fullmatch(r"(\D*?)([\d,]+)", v)
    if m:
        digits = m.group(2).replace(",", "")
        half = len(digits) // 2
        if len(digits) % 2 == 0 and digits[:half] == digits[half:]:
            v = m.group(1) + format(int(digits[:half]), ",")
    if re.search(r"[^\d\s,.]", v):
        return v
    unit = currency.split()[-1].lower()
    plural = unit if unit in UNCOUNTED or unit.endswith("s") else unit + "s"
    return f"{v} {plural}"

def design_line(row):
    bits = []
    if row.get("colour"):
        bits.append(f"{row['colour'].capitalize()} note")
    if row.get("size"):
        bits.append(label(row["size"]).replace(" mm", " mm").strip())
    text = ", ".join(bits)
    if row.get("year"):
        text = (text + ", " if text else "") + f"issued from {row['year']}"
    return (text + ".") if text else ""

# Argentina's Animales Autóctonos notes stand upright on the front.
VERTICAL = {"ars-200": ("front",), "ars-500": ("front",), "ars-1000": ("front",)}

# Wikidata's formal names, shortened to the everyday ones.
SHORT_NAME = {"People's Republic of China": "China", "Kingdom of the Netherlands": "Netherlands",
              "The Bahamas": "Bahamas", "The Gambia": "Gambia"}

# The euro's notes picture invented buildings, one architectural age each.
EURO_STYLE = {5: "[[Classical architecture|Classical]]", 10: "[[Romanesque architecture|Romanesque]]",
              20: "[[Gothic architecture|Gothic]]", 50: "[[Renaissance architecture|Renaissance]]",
              100: "[[Baroque]] and [[Rococo]]", 200: "[[Art Nouveau]] iron-and-glass"}

# ---------------------------------------------------------------- build

def main():
    cur = currencies()
    print(len(cur), "currencies")
    titles = []
    for c in cur.values():
        if c["article"]:
            titles += [c["article"], "Banknotes of the " + c["article"]]
    texts = wikitexts(titles)
    print(len(texts), "articles")

    chosen = {}
    for code, c in cur.items():
        rows, used = [], set()
        for t in (c["article"], "Banknotes of the " + c["article"]):
            if t in texts and texts[t][0] not in used:
                real, text = texts[t]
                used.add(real)
                for sec, body in sections(text):
                    if re.search(r"coin", sec, re.I):
                        continue
                    for r in table_rows(body):
                        rows.append(dict(r, section=sec, article=real))
        chosen[code] = current_rows(code, rows)

    curated_files = [f for n in curated.NOTES for f in n[8]]
    info = file_info([f for rows in chosen.values() for r in rows for f in (r["front"], r["back"])] + curated_files)
    intro = intros(sorted({c["article"] for c in cur.values() if c["article"]}))
    banks = json.loads((HERE / "central_banks.json").read_text())
    curated_by = {(curated.CODES[n[0]], number(n[5])): n for n in curated.NOTES}

    notes = []
    for code, c in cur.items():
        home = c["countries"][0]
        region = home["region"] or "Asia"
        base = {
            "country": "Euro area" if code == "EUR" else SHORT_NAME.get(home["name"], home["name"]),
            "flag": flag("EU") if code == "EUR" else flag(home["iso2"]),
            "region": "Europe" if code == "EUR" else region,
            "currency": (c["article"] or code)[:1].upper() + (c["article"] or code)[1:],
            "code": code,
            "alsoUsedIn": [x["name"] for x in c["countries"][1:8]] or None,
        }
        history = summary(intro.get(c["article"], ""))
        source = "https://en.wikipedia.org/wiki/" + urllib.parse.quote((c["article"] or "").replace(" ", "_"))
        made = {}

        def side(ii, subject):
            return {"image": bare(ii.get("thumburl") or ii["url"]), "thumb": thumb(ii), "page": bare(ii["descriptionurl"]),
                    "credit": credit(ii), "subject": subject}

        # Central banks: official images.
        bank = banks.get(code)
        if bank:
            for n in bank["notes"]:
                key = number(n["value"])
                made[key] = dict(base, id=f"{code.lower()}-{key}", denomination=n["value"], issued=n.get("issued", ""),
                                 series=bank.get("series"), history=history, design=n.get("design", ""), source=source,
                                 front={"image": n["front"], "page": n.get("page", bank["page"]), "credit": bank["bank"],
                                        "subject": n.get("frontSubject"), "crop": n.get("frontCrop")},
                                 back={"image": n["back"], "page": n.get("page", bank["page"]), "credit": bank["bank"],
                                       "subject": n.get("backSubject"), "crop": n.get("backCrop"),
                                       "vertical": n.get("backVertical")})
        # Wikipedia tables.
        for r in chosen.get(code, []):
            if r["key"] in made:
                continue
            a, b = info.get(r["front"]), info.get(r["back"])
            if not a or not b or min(a["width"], b["width"]) < 280:
                continue
            front, back = (r["desc"] + [None, None])[:2]
            made[r["key"]] = dict(base, id=f"{code.lower()}-{r['key']}", denomination=denomination(r["value"] or str(r["key"]), base["currency"]),
                                  issued=str(r["year"] or ""), series=None, history=history, design=design_line(r),
                                  source="https://en.wikipedia.org/wiki/" + urllib.parse.quote(r["article"].replace(" ", "_")),
                                  front=side(a, front), back=side(b, back))
        # Hand-written placards win, for text and, where needed, images.
        for (ccode, key), n in curated_by.items():
            if ccode != code:
                continue
            a, b = info.get(n[8][0]), info.get(n[8][1])
            note = made.get(key) or (dict(base, id=f"{code.lower()}-{key}", front=side(a, None), back=side(b, None)) if a and b else None)
            if not note:
                continue
            note = dict(note, denomination=n[5], issued=n[6], series=n[7] or None, history=n[12], design=n[13],
                        source="https://en.wikipedia.org/wiki/" + urllib.parse.quote(n[9].replace(" ", "_")))
            note["front"] = dict(note["front"], subject=n[10])
            note["back"] = dict(note["back"], subject=n[11])
            if code == "ZWL":
                note.update(country="Zimbabwe", flag=flag("ZW"), region="Africa", currency="Zimbabwean dollar")
            made[key] = note
        # One way of writing values per currency: follow the hand-written note's
        # style ("KSh 1,000", "200 kroner") when there is one.
        styled = [n for (cc, _), n in curated_by.items() if cc == code]
        if styled:
            m = re.fullmatch(r"(\D*?)[\d,.]+(\D*)", styled[0][5])
            if m:
                for key, note in made.items():
                    note["denomination"] = m.group(1) + format(key, ",") + m.group(2)
        if code == "EUR":
            for key, note in made.items():
                style = EURO_STYLE.get(key)
                if style:
                    note["front"]["subject"] = f"Windows and a gateway in {style} style, with [[Europa (consort of Zeus)|Europa]] in the hologram"
                    note["back"]["subject"] = f"A bridge in {style} style, and a map of Europe"
                    note["denomination"] = f"€{key}"
        if made:
            notes += [made[k] for k in sorted(made)]

    # Sides whose design runs up the note rather than across it, beyond those
    # a central bank entry already marks.
    for n in notes:
        for side in VERTICAL.get(n["id"], ()):
            n[side]["vertical"] = True

    notes.sort(key=lambda n: (REGION_ORDER.index(n["region"]) if n["region"] in REGION_ORDER else 9, n["country"], number(n["id"].split("-", 1)[1])))
    for n in notes:
        for s in (n["front"], n["back"]):
            for k in ("thumb", "crop", "vertical"):
                if not s.get(k):
                    s.pop(k, None)
        if not n.get("alsoUsedIn"):
            n.pop("alsoUsedIn", None)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"notes": notes}, ensure_ascii=False, indent=1) + "\n")
    print(f"wrote {len(notes)} notes for {len({n['code'] for n in notes})} currencies to {OUT}")
    missing = sorted(code for code in cur if code not in {n["code"] for n in notes})
    print("no notes yet:", " ".join(missing))

if __name__ == "__main__":
    main()
