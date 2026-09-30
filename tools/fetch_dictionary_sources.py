#!/usr/bin/env python3
"""Download what tools/build_dictionary.py builds from.

--leipzig NAME...: Leipzig Corpora Collection corpora by name
("dan_news_2021_1M"), streamed, keeping only each one's word-frequency file,
NAME-words.txt. The names are listed at https://wortschatz.uni-leipzig.de.

--wiktionary LANGUAGE: kaikki.org's extract of Wiktionary for a language by
its English name ("Danish"), streamed into known-LANGUAGE.txt: every
headword and inflected form, lower case, one a line.

    python3 tools/fetch_dictionary_sources.py --out DIR \\
        --leipzig dan_news_2021_1M dan_wikipedia_2021_1M --wiktionary Danish
"""
import argparse
import json
import os
import tarfile
import urllib.request

LEIPZIG = "https://downloads.wortschatz-leipzig.de/corpora/"
KAIKKI = "https://kaikki.org/dictionary/{0}/kaikki.org-dictionary-{0}.jsonl"
# Form entries that describe an inflection table rather than a word.
TABLE_TAGS = {"table-tags", "inflection-template", "class", "romanization"}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "tapless"})
    return urllib.request.urlopen(request, timeout=3600)


def leipzig(name, out):
    path = os.path.join(out, name + "-words.txt")
    with fetch(LEIPZIG + name + ".tar.gz") as response:
        with tarfile.open(fileobj=response, mode="r|gz") as archive:
            for member in archive:
                if member.name.endswith("-words.txt"):
                    with open(path, "wb") as text:
                        text.write(archive.extractfile(member).read())
                    return path
    raise SystemExit(f"{name}: no words file in the archive")


def wiktionary(language, out):
    words = set()
    with fetch(KAIKKI.format(language)) as response:
        for line in response:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            word = entry.get("word")
            if isinstance(word, str) and " " not in word:
                words.add(word.lower())
            for form in entry.get("forms") or []:
                text = form.get("form")
                if isinstance(text, str) and " " not in text \
                        and not set(form.get("tags") or []) & TABLE_TAGS:
                    words.add(text.lower())
    path = os.path.join(out, "known-" + language + ".txt")
    with open(path, "w", encoding="utf-8") as text:
        text.writelines(word + "\n" for word in sorted(words))
    return path


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--out", required=True)
    parser.add_argument("--leipzig", nargs="*", default=[])
    parser.add_argument("--wiktionary")
    args = parser.parse_args()
    os.makedirs(args.out, exist_ok=True)
    for name in args.leipzig:
        print(leipzig(name, args.out))
    if args.wiktionary:
        print(wiktionary(args.wiktionary, args.out))


if __name__ == "__main__":
    main()
