#!/usr/bin/env python3
"""Build a dictionary package from word-frequency lists.

Reads word-frequency files from the Leipzig Corpora Collection
(https://wortschatz.uni-leipzig.de, CC BY 4.0): the "*-words.txt" of each
corpus, one "id<TAB>word<TAB>count" line per word as written. Their counts
are summed, and kept are the words:

- of two letters or more, as a swipe crosses two keys at least;
- made only of letters the language's normalization profile knows (see
  normalization_profiles.tsv), so numbers, hyphenated words and other
  scripts are left out; a word with an apostrophe only when it is one of
  the language's contractions (--contractions: "don't", "it's"), so no
  possessives ("John's");
- seen at least --min-count times;
- the --size most frequent, after that.

Each word is kept in one spelling: lower case, unless a capitalized or
upper-case spelling makes up CAPITAL_SHARE of its uses, as for names ("Paris")
and "I", and not for words that merely start sentences ("However"). Its
frequency is on the Zipf scale x 1000 the keyboard ranks by: log10 of its
count per billion words of the corpora.

Writes the package the keyboard reads (words.buckets.tsv and .idx,
words.popular.tsv and .idx, manifest.tsv) and ATTRIBUTION.txt into --out.

    python3 tools/build_dictionary.py --id en --name English \\
        --keyboard-layout en_keyboard --out DIR WORDS.txt...
"""
import argparse
import collections
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import add_contractions as ac  # noqa: E402 (the package writing helpers)

PROFILES = os.path.join(os.path.dirname(HERE), "tapless.koplugin",
                        "normalization_profiles.tsv")
CAPITAL_SHARE = 0.9
POPULAR_PER_FIRST = 256


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
    for the lower-cased word; None if a letter is not in the profile."""
    letters = []
    for char in word.lower():
        if char in ("'", "’"):
            continue
        mapped = table.get(char, char)
        if "a" <= mapped <= "z" and len(mapped) == 1:
            letters.append(mapped)
        else:
            return None
    return "".join(letters) or None


def read_contractions(path):
    """The lower-cased words of a contractions list (first column, as in
    tools/contractions_en.tsv); none without one."""
    if not path:
        return set()
    with open(path, encoding="utf-8") as text:
        return {line.split("\t")[0].strip().lower() for line in text
                if line.strip() and not line.startswith("#")}


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
    """{lower-cased word: (spelling, count, signature)}."""
    variants = collections.defaultdict(list)
    for word, count in counts.items():
        if acceptable(word, contractions):
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


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("words", nargs="+", help="Leipzig *-words.txt files")
    parser.add_argument("--id", required=True, help="dictionary id: en, pt-br")
    parser.add_argument("--name", required=True)
    parser.add_argument("--language", help="default: the id")
    parser.add_argument("--source-language", help="default: the language")
    parser.add_argument("--keyboard-layout", required=True)
    parser.add_argument("--profile", default="latin-extended-v1")
    parser.add_argument("--size", type=int, default=150000)
    parser.add_argument("--min-count", type=int, default=3)
    parser.add_argument("--contractions",
                        help="the language's contractions, one a line")
    parser.add_argument("--version", default="2")
    parser.add_argument("--source", default="Leipzig Corpora Collection",
                        help="for ATTRIBUTION.txt: which corpora")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    language = args.language or args.id
    # The words' language, as each row carries it: letters only, as
    # DictionaryIndex reads rows ("pt" for a "pt-br" dictionary).
    data_language = args.source_language or language
    if not data_language.isalpha() or not data_language.islower():
        parser.error(f"--source-language must be letters: {data_language}")
    table = read_profile(args.profile)
    if not table:
        parser.error(f"no normalization profile {args.profile}")

    counts, total = read_counts(args.words)
    words = spellings(counts, table, args.min_count,
                      read_contractions(args.contractions))
    kept = sorted(words.values(), key=lambda item: -item[1])[:args.size]
    rows = []
    for spelling, count, sig in kept:
        zipf = math.log10(count / total * 1e9)
        rows.append([sig, spelling, str(max(1, round(zipf * 1000))),
                     data_language])

    os.makedirs(args.out, exist_ok=True)
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
    manifest = [
        ("format", "1"), ("id", args.id), ("name", args.name),
        ("language", language),
        ("source_language", data_language),
        ("data_language", data_language),
        ("keyboard_layout", args.keyboard_layout),
        ("short_label", args.id.upper()),
        ("normalization_profile", args.profile),
        ("version", args.version), ("rows", str(len(rows))),
        ("data", "words.buckets.tsv"), ("index", "words.buckets.idx"),
        ("sha256_data", ac.sha256(os.path.join(args.out,
                                               "words.buckets.tsv"))),
        ("sha256_index", ac.sha256(os.path.join(args.out,
                                                "words.buckets.idx"))),
        ("popular_data", "words.popular.tsv"),
        ("popular_index", "words.popular.idx"),
        ("popular_per_first", str(POPULAR_PER_FIRST)),
        ("sha256_popular_data", ac.sha256(os.path.join(
            args.out, "words.popular.tsv"))),
        ("sha256_popular_index", ac.sha256(os.path.join(
            args.out, "words.popular.idx"))),
    ]
    with open(os.path.join(args.out, "manifest.tsv"), "w",
              encoding="utf-8") as out:
        out.write("# field\tvalue\n")
        out.writelines(f"{key}\t{value}\n" for key, value in manifest)
    with open(os.path.join(args.out, "ATTRIBUTION.txt"), "w",
              encoding="utf-8") as out:
        out.write(
            "Word list (words.buckets.tsv, words.popular.tsv)\n\n"
            f"Counted from the {args.source} of the Leipzig Corpora\n"
            "Collection (https://wortschatz.uni-leipzig.de), licensed under\n"
            "the Creative Commons Attribution 4.0 International licence\n"
            "(CC BY 4.0, https://creativecommons.org/licenses/by/4.0/), by\n"
            "tools/build_dictionary.py: its words, their frequencies and\n"
            "spellings, not its sentences.\n")
    print(f"{args.id}: {len(rows)} words from {len(words)} kept of "
          f"{len(counts)} ({total} tokens)")


if __name__ == "__main__":
    main()
