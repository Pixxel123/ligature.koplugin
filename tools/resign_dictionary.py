#!/usr/bin/env python3
"""Works each row's signature out again from its spelling, with the
package's normalization profile as normalization_profiles.tsv has it now,
and rewrites the word lists, their indexes and the manifest in place.

A package built before the profile mapped a letter (ß, æ, œ, ð, þ) has
signatures without it, and a swipe crossing that letter's key no longer
matches them. Words, frequencies and every other file stay as they are;
a row whose spelling the profile can no longer sign is left out.

--drop-misdecoded also leaves out rows that are another row's spelling
read in the wrong code page: Windows-1250 or 1254 text decoded as Latin-1
in the corpora (siê for się, þüphesiz for şüphesiz). Only rows whose
repaired spelling is in the list go.

    python3 tools/resign_dictionary.py --version 2.1.0 [--drop-misdecoded]
        PACKAGE_DIR...
"""
import argparse
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import add_contractions as ac  # noqa: E402
import build_dictionary as bd  # noqa: E402


CODE_PAGES = ("cp1250", "cp1254")


def misdecoded(word, words):
    """Whether word is another of words read in the wrong code page."""
    if word.isascii():
        return False
    for page in CODE_PAGES:
        try:
            fixed = word.encode("latin-1").decode(page)
        except (UnicodeEncodeError, UnicodeDecodeError):
            continue
        if fixed != word and fixed in words:
            return True
    return False


def resign(directory, version, drop_misdecoded=False):
    manifest = bd.read_manifest(os.path.join(directory, "manifest.tsv"))
    profile = manifest.get("normalization_profile", "latin-extended-v1")
    table = bd.read_profile(profile)
    if not table:
        sys.exit(f"{directory}: no normalization profile {profile}")
    rows, changed, dropped = [], 0, 0
    read = ac.read_rows(os.path.join(directory, "words.buckets.tsv"))
    words = {row[1] for row in read}
    for row in read:
        sig = bd.signature(row[1], table)
        if not sig or (drop_misdecoded and misdecoded(row[1], words)):
            dropped += 1
            continue
        if sig != row[0]:
            changed += 1
            row[0] = sig
        rows.append(row)
    rows.sort(key=lambda row: (ac.bucket_key(row[0]), -int(row[2]), row[1]))
    data = os.path.join(directory, "words.buckets.tsv")
    index = os.path.join(directory, "words.buckets.idx")
    ac.write_indexed(rows, data, index, lambda row: ac.bucket_key(row[0]))
    by_first = collections.defaultdict(list)
    for row in rows:
        by_first[row[0][0]].append(row)
    popular = []
    for first in sorted(by_first):
        popular += sorted(by_first[first],
                          key=lambda row: (-int(row[2]), row[1]))[
                              :bd.POPULAR_PER_FIRST]
    popular_data = os.path.join(directory, "words.popular.tsv")
    popular_index = os.path.join(directory, "words.popular.idx")
    ac.write_indexed(popular, popular_data, popular_index,
                     lambda row: row[0][0])
    values = {
        "rows": str(len(rows)),
        "sha256_data": ac.sha256(data),
        "sha256_index": ac.sha256(index),
        "sha256_popular_data": ac.sha256(popular_data),
        "sha256_popular_index": ac.sha256(popular_index),
    }
    if version:
        values["version"] = version
    ac.update_manifest(directory, values)
    print(f"{directory}: {changed} signatures changed, {dropped} rows "
          f"dropped, {len(rows)} rows")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("packages", nargs="+")
    parser.add_argument("--version", help="the packages' new version")
    parser.add_argument("--drop-misdecoded", action="store_true")
    args = parser.parse_args()
    for directory in args.packages:
        resign(directory, args.version, args.drop_misdecoded)


if __name__ == "__main__":
    main()
