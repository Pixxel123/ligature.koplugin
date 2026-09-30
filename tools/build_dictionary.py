#!/usr/bin/env python3
"""Build a dictionary package from word-frequency lists.

Reads word-frequency files from the Leipzig Corpora Collection
(https://wortschatz.uni-leipzig.de, CC BY 4.0): the "*-words.txt" of each
corpus, one "id<TAB>word<TAB>count" line per word as written (see
tools/fetch_dictionary_sources.py). Their counts are summed. A Leipzig word
counts only when it is:

- of two letters or more, as a swipe crosses two keys at least;
- made only of letters the language's normalization profile knows (see
  normalization_profiles.tsv), so numbers, hyphenated words and other
  scripts are left out; a word with an apostrophe only when it is one of
  the language's contractions (--contractions: "don't", "it's"), so no
  possessives ("John's");
- seen at least --min-count times.

Each Leipzig word has one spelling: lower case, unless a capitalized or
upper-case spelling makes up CAPITAL_SHARE of its uses, as for names ("Paris"),
German nouns and "I", and not for words that merely start sentences
("However") or are names only sometimes ("march"). Its frequency is on the
Zipf scale x 1000 the keyboard ranks by: log10 of its count per billion words
of the corpora.

With --base, an existing package (the catalog's, built from wordfreq) keeps
its words and their frequencies, which rank words as people type them better
than news and encyclopedia counts do; Leipzig gives its words their
capitals, and adds the words it lacks at their Leipzig frequency, up to
--size words. Without --base, the package is the --size most frequent
Leipzig words.

With --known, a list of the words and inflected forms Wiktionary knows
(lower case, one a line), a word Wiktionary does not know that the corpora
saw fewer than --min-seen times is left out: misspellings, words typed
without their accents ("reponse"), laughter, web debris.

Writes the package the keyboard reads (words.buckets.tsv and .idx,
words.popular.tsv and .idx, manifest.tsv) and ATTRIBUTION.txt into --out; with
--base, its licence files too. Word-pair tables are not copied: they spell
words as the dictionary did, so rebuild one with tools/build_word_pairs.py.

    python3 tools/build_dictionary.py --id en --name English \\
        --keyboard-layout en_keyboard --out DIR WORDS.txt...
    python3 tools/build_dictionary.py --base OLD --known KNOWN.txt \\
        --id da --name Danish --keyboard-layout da_keyboard --out DIR WORDS.txt...
"""
import argparse
import collections
import math
import os
import shutil
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import add_contractions as ac  # noqa: E402 (the package writing helpers)

PROFILES = os.path.join(os.path.dirname(HERE), "tapless.koplugin",
                        "normalization_profiles.tsv")
CAPITAL_SHARE = 0.95
POPULAR_PER_FIRST = 256
LICENCE_FILES = ("DATA-LICENSE.txt", "LICENSE-wordfreq.txt")
# Manifest fields a rebuilt package works out afresh; a base's other fields
# (name, keyboard layout, profile) are kept.
REBUILT_FIELDS = {"version", "rows", "data", "index", "sha256_data",
                  "sha256_index", "popular_data", "popular_index",
                  "popular_per_first", "sha256_popular_data",
                  "sha256_popular_index", "pairs_data", "pairs_index",
                  "sha256_pairs_data", "sha256_pairs_index", "pairs_source"}


def read_profile(name):
    """The profile's character map, as normalization.lua reads it."""
    table = {}
    with open(PROFILES, encoding="utf-8") as text:
        for line in text:
            if line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) == 3 and fields[0] == name and len(fields[2]) == 1 \
                    and "a" <= fields[2] <= "z":
                table[fields[1]] = fields[2]
    return table


def signature(word, table):
    """The letters a swipe spells, as Normalization:normalizeText has them
    for the lower-cased word: a Latin letter the profile does not map ("ß",
    "æ") is left out, as there; None for a word with any other script."""
    letters = []
    for char in word.lower():
        if char in ("'", "’"):
            continue
        mapped = table.get(char, char)
        if "a" <= mapped <= "z" and len(mapped) == 1:
            letters.append(mapped)
        elif not unicodedata.name(char, "").startswith("LATIN"):
            return None
    return "".join(letters) or None


def read_contractions(path):
    """A contractions list (as tools/contractions_en.tsv): the contractions,
    lower-cased, and the spellings without their apostrophe that are no
    words of their own ("dont", not "its"); none without a list."""
    contractions, no_words = set(), set()
    if not path:
        return contractions, no_words
    with open(path, encoding="utf-8") as text:
        for line in text:
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.rstrip("\n").split("\t")
            word = fields[0].strip().lower()
            contractions.add(word)
            if len(fields) > 2 and fields[2].strip() == "drop":
                no_words.add(word.replace("'", ""))
    return contractions, no_words


def acceptable(word, contractions):
    """Letters only, or one of the language's contractions."""
    word = word.replace("’", "'")
    if "'" in word:
        return word.lower() in contractions
    return word.isalpha()


def read_counts(paths):
    counts = collections.Counter()
    total = 0
    for path in paths:
        with open(path, encoding="utf-8", errors="replace") as text:
            for line in text:
                fields = line.rstrip("\n").split("\t")
                if len(fields) < 3:
                    continue
                try:
                    count = int(fields[2])
                except ValueError:
                    continue
                total += count
                word = fields[1].replace("’", "'")
                counts[word] += count
    return counts, total


def spellings(counts, table, min_count, contractions):
    """{lower-cased word: (spelling, count, signature)}. contractions is
    read_contractions's: its contractions are words, and the spellings
    without their apostrophe it names are not ("dont" types "don't")."""
    contractions, no_words = contractions
    variants = collections.defaultdict(list)
    for word, count in counts.items():
        if acceptable(word, contractions) and word.lower() not in no_words:
            variants[word.lower()].append((count, word))
    words = {}
    for key, forms in variants.items():
        total = sum(count for count, _ in forms)
        if total < min_count:
            continue
        sig = signature(key, table)
        # A swipe crosses two keys at least; a word of one letter is tapped.
        if not sig or len(sig) < 2:
            continue
        lower = sum(count for count, word in forms if word == key)
        if lower >= (1 - CAPITAL_SHARE) * total:
            spelling = key
        else:
            spelling = max(forms)[1]
        words[key] = (spelling, total, sig)
    return words


def zipf(count, total):
    return str(max(1, round(math.log10(count / total * 1e9) * 1000)))


def read_manifest(path):
    fields = {}
    with open(path, encoding="utf-8") as text:
        for line in text:
            if line.startswith("#") or "\t" not in line:
                continue
            key, value = line.rstrip("\n").split("\t", 1)
            fields[key] = value
    return fields


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("words", nargs="+", help="Leipzig *-words.txt files")
    parser.add_argument("--id", required=True, help="dictionary id: en, pt-br")
    parser.add_argument("--name", help="default: the base's")
    parser.add_argument("--language", help="default: the base's, or the id")
    parser.add_argument("--source-language",
                        help="the words' language: default the base's, or "
                             "the language")
    parser.add_argument("--keyboard-layout", help="default: the base's")
    parser.add_argument("--profile", help="default: the base's, or "
                                          "latin-extended-v1")
    parser.add_argument("--base", help="package whose words and "
                                       "frequencies to keep")
    parser.add_argument("--known", help="words Wiktionary knows")
    parser.add_argument("--min-seen", type=int, default=3)
    parser.add_argument("--size", type=int, default=150000)
    parser.add_argument("--min-count", type=int, default=3)
    parser.add_argument("--contractions",
                        help="the language's contractions, one a line")
    parser.add_argument("--version", default="2.0.0")
    parser.add_argument("--source", default="Leipzig Corpora Collection",
                        help="for ATTRIBUTION.txt: which corpora")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    base = read_manifest(os.path.join(args.base, "manifest.tsv")) \
        if args.base else {}
    language = args.language or base.get("language") or args.id
    data_language = (args.source_language or base.get("data_language")
                     or base.get("source_language") or language)
    # Each row carries it, as DictionaryIndex reads rows: letters only ("pt"
    # for a "pt-br" dictionary).
    if not data_language.isalpha() or not data_language.islower():
        parser.error(f"--source-language must be letters: {data_language}")
    profile = (args.profile or base.get("normalization_profile")
               or "latin-extended-v1")
    table = read_profile(profile)
    if not table:
        parser.error(f"no normalization profile {profile}")
    name = args.name or base.get("name") or args.id
    layout = args.keyboard_layout or base.get("keyboard_layout")
    if not layout:
        parser.error("--keyboard-layout is needed")

    counts, total = read_counts(args.words)
    leipzig = spellings(counts, table, args.min_count,
                        read_contractions(args.contractions))
    if args.base:
        rows, seen, recased = [], set(), 0
        for row in ac.read_rows(os.path.join(args.base, "words.buckets.tsv")):
            key = row[1].lower()
            found = leipzig.get(key)
            if found and row[1] == key and found[0] != key:
                row[1] = found[0]
                recased += 1
            seen.add(key)
            rows.append(row)
        extra = sorted((item for key, item in leipzig.items()
                        if key not in seen), key=lambda item: -item[1])
        for spelling, count, sig in extra[:max(0, args.size - len(rows))]:
            rows.append([sig, spelling, zipf(count, total), data_language])
        added = len(rows) - len(seen)
    else:
        kept = sorted(leipzig.values(), key=lambda item: -item[1])[:args.size]
        rows = [[sig, spelling, zipf(count, total), data_language]
                for spelling, count, sig in kept]
        recased = added = 0
    dropped = 0
    if args.known:
        with open(args.known, encoding="utf-8") as text:
            known = {line.strip() for line in text}
        seen_counts = collections.Counter()
        for word, count in counts.items():
            seen_counts[word.lower()] += count
        before = len(rows)
        rows = [row for row in rows if row[1].lower() in known
                or seen_counts[row[1].lower()] >= args.min_seen]
        dropped = before - len(rows)

    os.makedirs(args.out, exist_ok=True)
    for name_ in LICENCE_FILES:
        if args.base and os.path.exists(os.path.join(args.base, name_)):
            shutil.copy(os.path.join(args.base, name_), args.out)
    rows.sort(key=lambda row: (ac.bucket_key(row[0]), -int(row[2]), row[1]))
    ac.write_indexed(rows, os.path.join(args.out, "words.buckets.tsv"),
                     os.path.join(args.out, "words.buckets.idx"),
                     lambda row: ac.bucket_key(row[0]))
    by_first = collections.defaultdict(list)
    for row in rows:
        by_first[row[0][0]].append(row)
    popular = []
    for first in sorted(by_first):
        popular += sorted(by_first[first],
                          key=lambda row: (-int(row[2]), row[1]))[
                              :POPULAR_PER_FIRST]
    ac.write_indexed(popular, os.path.join(args.out, "words.popular.tsv"),
                     os.path.join(args.out, "words.popular.idx"),
                     lambda row: row[0][0])
    manifest = {key: value for key, value in base.items()
                if key not in REBUILT_FIELDS}
    manifest.update({
        "format": manifest.get("format", "1"), "id": args.id, "name": name,
        "language": language, "source_language": data_language,
        "data_language": data_language, "keyboard_layout": layout,
        "short_label": manifest.get("short_label", args.id.upper()),
        "normalization_profile": profile,
        "version": args.version, "rows": str(len(rows)),
        "data": "words.buckets.tsv", "index": "words.buckets.idx",
        "sha256_data": ac.sha256(os.path.join(args.out, "words.buckets.tsv")),
        "sha256_index": ac.sha256(os.path.join(args.out,
                                               "words.buckets.idx")),
        "popular_data": "words.popular.tsv",
        "popular_index": "words.popular.idx",
        "popular_per_first": str(POPULAR_PER_FIRST),
        "sha256_popular_data": ac.sha256(os.path.join(
            args.out, "words.popular.tsv")),
        "sha256_popular_index": ac.sha256(os.path.join(
            args.out, "words.popular.idx")),
    })
    with open(os.path.join(args.out, "manifest.tsv"), "w",
              encoding="utf-8") as out:
        out.write("# field\tvalue\n")
        out.writelines(f"{key}\t{value}\n" for key, value in manifest.items())
    attribution = ""
    if args.base and os.path.exists(os.path.join(args.base,
                                                 "ATTRIBUTION.txt")):
        with open(os.path.join(args.base, "ATTRIBUTION.txt"),
                  encoding="utf-8") as text:
            attribution = text.read().rstrip("\n") + "\n\n"
    attribution += (
        "Capitals and added words (words.buckets.tsv, words.popular.tsv)\n\n"
        if args.base else "Word list (words.buckets.tsv, words.popular.tsv)\n\n")
    attribution += (
        f"Counted from the {args.source} of the Leipzig Corpora\n"
        "Collection (https://wortschatz.uni-leipzig.de), licensed under\n"
        "the Creative Commons Attribution 4.0 International licence\n"
        "(CC BY 4.0, https://creativecommons.org/licenses/by/4.0/), by\n"
        "tools/build_dictionary.py: its words, their frequencies and\n"
        "spellings, not its sentences.\n")
    if args.known:
        attribution += (
            "\nWords that neither Wiktionary (https://www.wiktionary.org, via\n"
            "https://kaikki.org) nor the corpora above know were left out;\n"
            "no Wiktionary text is included.\n")
    with open(os.path.join(args.out, "ATTRIBUTION.txt"), "w",
              encoding="utf-8") as out:
        out.write(attribution)
    print(f"{args.id}: {len(rows)} words (recased {recased}, added {added}, "
          f"left out {dropped}) from {total} Leipzig tokens")


if __name__ == "__main__":
    main()
