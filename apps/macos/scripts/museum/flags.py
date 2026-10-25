#!/usr/bin/env python3
"""One-time content setup for the Museum's Flags & Anthems room.

Every sovereign state's flag and national anthem, from Wikidata, with the
flag images and anthem recordings from Wikimedia Commons (public domain or
freely licensed; many recordings are by the US Navy Band) and short texts
from English Wikipedia. Writes Support/Museum/flags.json.

    /usr/bin/python3 scripts/museum/flags.py
"""
import json, re, time, pathlib, urllib.parse, urllib.request, urllib.error

UA = {"User-Agent": "ShelfMuseumSetup/0.1 (https://github.com/imrajjain/my-home-shelf)"}
WIKI = "https://en.wikipedia.org/w/api.php"
COMMONS = "https://commons.wikimedia.org/w/api.php"
OUT = pathlib.Path(__file__).resolve().parents[2] / "Support/Museum/flags.json"

# Recordings for anthems whose Wikidata entry has none, found on Commons by hand.
AUDIO = {
    "Senegal": "National Anthem of Senegal.ogg",
    "People's Republic of China": "March of the Volunteers instrumental.ogg",
    "Burundi": "Burundi Bwacu instrumental.ogg",
    "Ukraine": "National anthem of Ukraine, instrumental.oga",
    "Spain": "Marcha Real-Royal March by US Navy Band.ogg",
    "United Kingdom": "U.S. Navy Band - God Save the King.oga",
    "Burkina Faso": "National anthem of Burkina Faso.oga",
    "North Macedonia": "North Macedonia's National Anthem.ogg",
    "Tuvalu": "Tuvalu mo te Atua.ogg",
    "Iraq": "United States Navy Band - Mawtini.ogg",
    "Democratic Republic of the Congo": "Debout Congolais.ogg",
    "Papua New Guinea": "O Arise, All You Sons (instrumental).ogg",
    "Palau": "Belau rekid (instrumental).oga",
    "Samoa": "SamoaAnthem.ogg",
    "Solomon Islands": "National Anthem of Solomon Islands (instrumental).wav",
    "Kiribati": "Kiribati Anthem Performed by US Navy Band.oga",
    "Trinidad and Tobago": "Forged from the Love of Liberty (instrumental).ogg",
    "Bhutan": "National Anthem of Bhutan (Instrumental).wav",
    "Togo": "Hymne du Togo - salut a toi.ogg",
    "Ivory Coast": 'United States Navy Band - National Anthem of Côte D\'Ivoire "L\'Abidjanaise".ogg',
    "Cameroon": "Cameroonian national anthem, performed by the United States Navy Band.ogg",
    "The Gambia": "For The Gambia Our Homeland (instrumental).ogg",
    "Moldova": "Imnul Republicii Moldova US NAVY.ogg",
    "Portugal": "A Portuguesa.ogg",
}
# Anthems Wikidata doesn't link to their country.
ANTHEMS = {"Portugal": ("A Portuguesa", "Alfredo Keil", "Henrique Lopes de Mendonça")}
# Plain names for a few Wikidata labels.
NAMES = {"People's Republic of China": "China", "Kingdom of the Netherlands": "Netherlands",
         "Kingdom of Denmark": "Denmark", "The Gambia": "Gambia"}
REGION = {"Asia": "Asia", "Europe": "Europe", "Africa": "Africa", "North America": "Americas",
          "South America": "Americas", "Oceania": "Oceania", "Australia": "Oceania",
          "Insular Oceania": "Oceania", "Australian continent": "Oceania"}

SPARQL = """
SELECT ?country ?countryLabel ?iso2 ?continentLabel ?flagImg ?anthem ?anthemLabel ?audio ?anthemArticle ?flagArticle
       (GROUP_CONCAT(DISTINCT ?composerLabel; separator="|") AS ?composers)
       (GROUP_CONCAT(DISTINCT ?lyricistLabel; separator="|") AS ?lyricists) WHERE {
  ?country wdt:P31 wd:Q3624078; wdt:P297 ?iso2.
  FILTER NOT EXISTS { ?country wdt:P576 ?dissolved }
  OPTIONAL { ?country wdt:P41 ?flagImg }
  OPTIONAL { ?country wdt:P30 ?continent }
  OPTIONAL { ?country wdt:P163 ?flagItem. ?flagArticle schema:about ?flagItem; schema:isPartOf <https://en.wikipedia.org/> }
  OPTIONAL { ?country wdt:P85 ?anthem.
             OPTIONAL { ?anthem wdt:P51 ?audio }
             OPTIONAL { ?anthem wdt:P86 ?composer. ?composer rdfs:label ?composerLabel FILTER(lang(?composerLabel)="en") }
             OPTIONAL { ?anthem wdt:P676 ?lyricist. ?lyricist rdfs:label ?lyricistLabel FILTER(lang(?lyricistLabel)="en") }
             OPTIONAL { ?anthemArticle schema:about ?anthem; schema:isPartOf <https://en.wikipedia.org/> } }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} GROUP BY ?country ?countryLabel ?iso2 ?continentLabel ?flagImg ?anthem ?anthemLabel ?audio ?anthemArticle ?flagArticle"""

def get(url, data=None, headers=UA):
    for i in range(8):
        time.sleep(1)
        try:
            req = urllib.request.Request(url, data=data, headers=headers)
            return json.load(urllib.request.urlopen(req, timeout=180))
        except urllib.error.HTTPError as e:
            time.sleep(int(e.headers.get("Retry-After") or 0) or 10 * (i + 1))
        except Exception:
            time.sleep(5 * (i + 1))
    raise RuntimeError("unreachable: " + url)

def api(base, **q):
    q.update(format="json", formatversion="2", maxlag="5")
    return get(base, urllib.parse.urlencode(q).encode())

def file_of(url):
    return urllib.parse.unquote(url.rsplit("/", 1)[-1]).replace("_", " ")

def title_of(url):
    return urllib.parse.unquote(url.rsplit("/", 1)[-1]).replace("_", " ")

def clean(url):
    return url.split("?")[0] if url else url

def plain(html):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html or "")).strip()

def credit(meta):
    artist = plain((meta.get("Artist") or {}).get("value", ""))[:80]
    licence = plain((meta.get("LicenseShortName") or {}).get("value", ""))
    return " · ".join(x for x in (artist if len(artist) < 70 else "", licence) if x)

def batched(items, n):
    items = list(items)
    for i in range(0, len(items), n):
        yield items[i:i + n]

def images(files):
    out = {}
    for chunk in batched(sorted(set(files)), 25):
        r = api(COMMONS, action="query", prop="imageinfo", iiprop="url|size|extmetadata",
                iiurlwidth=1280, titles="|".join("File:" + f for f in chunk))
        q = r["query"]; norm = {n["to"]: n["from"] for n in q.get("normalized", [])}
        for p in q["pages"]:
            ii = (p.get("imageinfo") or [None])[0]
            if ii: out[norm.get(p["title"], p["title"])[5:]] = ii
    return out

def recordings(files):
    """MP3 renditions (macOS can't play Ogg), duration and credit."""
    out = {}
    for chunk in batched(sorted(set(files)), 20):
        r = api(COMMONS, action="query", prop="videoinfo", viprop="url|derivatives|extmetadata|size",
                titles="|".join("File:" + f for f in chunk))
        q = r["query"]; norm = {n["to"]: n["from"] for n in q.get("normalized", [])}
        for p in q["pages"]:
            vi = (p.get("videoinfo") or [None])[0]
            if not vi: continue
            mp3 = next((d["src"] for d in vi.get("derivatives", []) if d.get("type", "").startswith("audio/mpeg")), None)
            if not mp3 and vi["url"].lower().endswith((".mp3", ".wav")): mp3 = vi["url"]
            if not mp3: continue
            out[norm.get(p["title"], p["title"])[5:]] = {
                "audio": clean(mp3), "page": clean(vi["descriptionurl"]),
                "credit": credit(vi.get("extmetadata", {})), "duration": vi.get("duration")}
    return out

def intros(titles):
    out = {}
    for chunk in batched(sorted(set(t for t in titles if t)), 20):
        r = api(WIKI, action="query", prop="extracts", exintro=1, explaintext=1, exsentences=4,
                exlimit="max", titles="|".join(chunk), redirects=1)
        q = r["query"]
        back = {n["to"]: n["from"] for n in q.get("redirects", []) + q.get("normalized", [])}
        for p in q["pages"]:
            text = re.sub(r"\s*\([^()]*(?:\([^()]*\)[^()]*)*\)", "", p.get("extract", ""))  # drop parentheticals
            text = re.sub(r"\s+", " ", text).strip()
            title = p["title"]
            while title in back: title = back[title]
            out[title] = text
    return out

def flag_emoji(iso2):
    return "".join(chr(0x1F1E6 + ord(c) - 65) for c in iso2.upper())

def main():
    rows = get("https://query.wikidata.org/sparql?" + urllib.parse.urlencode({"query": SPARQL}),
               headers={**UA, "Accept": "application/sparql-results+json"})["results"]["bindings"]
    rows = [{k: v["value"] for k, v in b.items()} for b in rows]

    # One entry per country; prefer the anthem that has a recording.
    countries = {}
    for r in sorted(rows, key=lambda r: (r["countryLabel"], 0 if r.get("audio") else 1)):
        c = countries.setdefault(r["countryLabel"], {**r, "continents": set()})
        if r.get("continentLabel"): c["continents"].add(r["continentLabel"])
    for name, (title, composer, lyricist) in ANTHEMS.items():
        c = countries.get(name)
        if c and not c.get("anthem"):
            c.update(anthem="override", anthemLabel=title, composers=composer, lyricists=lyricist,
                     anthemArticle="https://en.wikipedia.org/wiki/" + title.replace(" ", "_"))
    for name, c in countries.items():
        if name in AUDIO and not c.get("audio"): c["audioFile"] = AUDIO[name]
        elif c.get("audio"): c["audioFile"] = file_of(c["audio"])

    flags = images(file_of(c["flagImg"]) for c in countries.values() if c.get("flagImg"))
    audio = recordings(c["audioFile"] for c in countries.values() if c.get("audioFile"))
    texts = intros([title_of(c[k]) for c in countries.values() for k in ("flagArticle", "anthemArticle") if c.get(k)])

    out = []
    for name, c in sorted(countries.items(), key=lambda kv: NAMES.get(kv[0], kv[0])):
        f = flags.get(file_of(c["flagImg"])) if c.get("flagImg") else None
        if not f: continue
        conts = sorted(c["continents"])
        region = next((REGION[x] for x in conts if x in REGION), "World")
        if name in ("Turkey", "Russia", "Georgia", "Azerbaijan", "Kazakhstan", "Cyprus", "Armenia"):
            region = "Europe" if name not in ("Kazakhstan",) else "Asia"
        anthem = None
        if c.get("anthem"):
            a = audio.get(c.get("audioFile", ""))
            art = title_of(c["anthemArticle"]) if c.get("anthemArticle") else None
            anthem = {
                "title": art or c.get("anthemLabel"),
                "composers": [x for x in (c.get("composers") or "").split("|") if x],
                "lyricists": [x for x in (c.get("lyricists") or "").split("|") if x],
                "about": texts.get(art, ""),
                "source": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(art.replace(" ", "_")) if art else None,
                "recording": a,
            }
        flag_art = title_of(c["flagArticle"]) if c.get("flagArticle") else "Flag of " + name
        out.append({
            "id": c["iso2"].lower(),
            "country": NAMES.get(name, name),
            "emoji": flag_emoji(c["iso2"]),
            "region": region,
            "flag": {"image": clean(f.get("thumburl") or f["url"]), "page": clean(f["descriptionurl"]),
                     "credit": credit(f.get("extmetadata", {})) or "Wikimedia Commons",
                     "aspect": round(f["width"] / f["height"], 4)},
            "flagTitle": flag_art,
            "flagAbout": texts.get(flag_art, ""),
            "flagSource": "https://en.wikipedia.org/wiki/" + urllib.parse.quote(flag_art.replace(" ", "_")),
            "anthem": anthem,
        })
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"countries": out}, ensure_ascii=False, indent=1) + "\n")
    with_audio = sum(1 for x in out if x["anthem"] and x["anthem"]["recording"])
    print(f"wrote {len(out)} countries ({with_audio} with a recording) to {OUT}")
    print("no recording:", [x["country"] for x in out if not (x["anthem"] and x["anthem"]["recording"])])

if __name__ == "__main__":
    main()
