#!/usr/bin/env python3
"""Leaves the English words out of another language's package.

The packages' frequencies come from wordfreq, which counts a language in
web, subtitle and social media text. That text quotes English, so the 2.1.0
Portuguese list ranks "the" with "casa" and "and" above "livro", and a swipe
for a short Portuguese word can come out in English. A row goes when it is
a word the English package has in lower case, English uses it at least ten
times as often (--lead, on the Zipf scale x 1000), and Wiktionary does not
know it as a word or form of the package's language. These stay:

- names, which English capitalizes ("Michael", "York");
- words both languages have, such as Spanish "no" or German "hand";
- loanwords Wiktionary lists, such as Portuguese "site";
- loanwords the language uses about as much as English, which Wiktionary
  may lack: Danish "team" and "version", Turkish "limit".

KNOWN is the list tools/fetch_dictionary_sources.py --wiktionary writes. A
list of fewer than --min-known words is refused: a download cut short would
take out the language's own words.

The package is rewritten in place, as tools/resign_dictionary.py does, and
the rows left out are listed in --report, most frequent first.

    python3 tools/drop_foreign_words.py --english EN_DIR --known KNOWN.txt \\
        --version 2.2.0 [--report FILE] PACKAGE_DIR
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import add_contractions as ac  # noqa: E402
import build_dictionary as bd  # noqa: E402
import resign_dictionary as rd  # noqa: E402


def drop(directory, english, known, version, report=None,
         lead=bd.ENGLISH_LEAD):
    """Rewrites the package without its English-only rows."""
    kept, dropped = [], []
    for row in ac.read_rows(os.path.join(directory, "words.buckets.tsv")):
        if bd.english_only(row, english, known, lead):
            dropped.append(row)
        else:
            kept.append(row)
    rd.rewrite(directory, kept, version)
    if report:
        dropped.sort(key=lambda row: (-int(row[2]), row[1]))
        with open(report, "w", encoding="utf-8") as out:
            out.write("# spelling\tfrequency\tEnglish frequency\n")
            out.writelines(f"{row[1]}\t{row[2]}\t{english[row[1].lower()]}\n"
                           for row in dropped)
    print(f"{directory}: {len(dropped)} English words left out, "
          f"{len(kept)} rows")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("package")
    parser.add_argument("--english", required=True,
                        help="the English package")
    parser.add_argument("--known", required=True,
                        help="the words Wiktionary knows in the package's "
                             "language")
    parser.add_argument("--min-known", type=int, default=bd.MIN_KNOWN,
                        help="the fewest words --known may hold")
    parser.add_argument("--lead", type=int, default=bd.ENGLISH_LEAD,
                        help="how much more often English must use a word, "
                             "on the Zipf scale x 1000")
    parser.add_argument("--version", required=True,
                        help="the package's new version: the catalog offers "
                             "a package with new words only under a new one")
    parser.add_argument("--report", help="where to list the rows left out")
    args = parser.parse_args()
    manifest = bd.read_manifest(os.path.join(args.package, "manifest.tsv"))
    if (manifest.get("data_language") or manifest.get("id")) == "en":
        parser.error("the package is English")
    known = bd.read_known(args.known)
    if len(known) < args.min_known:
        parser.error(f"{args.known}: fewer than --min-known "
                     f"{args.min_known} words")
    drop(args.package, bd.read_english(args.english), known, args.version,
         args.report, args.lead)


if __name__ == "__main__":
    main()
