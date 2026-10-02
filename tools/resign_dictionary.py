#!/usr/bin/env python3
"""Works each row's signature out again from its spelling, with the
package's normalization profile as normalization_profiles.tsv has it now,
and rewrites the word lists, their indexes and the manifest in place.

A package built before the profile mapped a letter (ß, æ, œ, ð, þ) has
signatures without it, and a swipe crossing that letter's key no longer
matches them. Words, frequencies and every other file stay as they are;
a row whose spelling the profile can no longer sign is left out.

    python3 tools/resign_dictionary.py --version 2.1.0 PACKAGE_DIR...
"""
import argparse
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import add_contractions as ac  # noqa: E402
import build_dictionary as bd  # noqa: E402


def resign(directory, version):
    manifest = bd.read_manifest(os.path.join(directory, "manifest.tsv"))
    profile = manifest.get("normalization_profile", "latin-extended-v1")
    table = bd.read_profile(profile)
    if not table:
        sys.exit(f"{directory}: no normalization profile {profile}")
    rows, changed, dropped = [], 0, 0
    for row in ac.read_rows(os.path.join(directory, "words.buckets.tsv")):
        sig = bd.signature(row[1], table)
        if not sig:
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
    args = parser.parse_args()
    for directory in args.packages:
        resign(directory, args.version)


if __name__ == "__main__":
    main()
