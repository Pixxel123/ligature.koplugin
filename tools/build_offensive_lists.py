#!/usr/bin/env python3
"""Build the offensive-word lists the keyboard ranks down, one per language.

Reads the "List of Dirty, Naughty, Obscene and Otherwise Bad Words"
(https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words,
CC BY 4.0), one file per language code, and writes
tapless.koplugin/dictionary/offensive/<code>.txt: its single words, lower
case as the dictionaries spell them, sorted, with the source in a comment.
Phrases are left out: the keyboard types a word at a time.

    python3 tools/build_offensive_lists.py [--source DIR]

--source reads the lists from a folder of files named by language code
(with or without .txt) instead of downloading them.
"""
import argparse
import os
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tapless.koplugin", "dictionary", "offensive")
BASE = ("https://raw.githubusercontent.com/LDNOOBW/"
        "List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words/master/")
LANGUAGES = ["ar", "cs", "da", "de", "en", "eo", "es", "fa", "fi", "fil",
             "fr", "hi", "hu", "it", "ja", "ko", "nl", "no", "pl", "pt", "ru",
             "sv", "th", "tr", "zh"]
HEADER = ("# Offensive words the keyboard ranks down ({code}), from the List\n"
          "# of Dirty, Naughty, Obscene and Otherwise Bad Words,\n"
          "# https://github.com/LDNOOBW/"
          "List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words\n"
          "# (CC BY 4.0). Single words only, lower case. Rebuilt by\n"
          "# tools/build_offensive_lists.py.\n")


def read(code, source):
    if source:
        path = os.path.join(source, code)
        if not os.path.exists(path):
            path += ".txt"
        with open(path, encoding="utf-8") as text:
            return text.read()
    with urllib.request.urlopen(BASE + code, timeout=30) as response:
        return response.read().decode("utf-8")


def words_of(text):
    words = set()
    for line in text.splitlines():
        word = line.strip().lower()
        if word and not word.startswith("#") and not any(
                char.isspace() for char in word):
            words.add(word)
    return sorted(words)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--source", help="folder of lists by language code")
    args = parser.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for code in LANGUAGES:
        words = words_of(read(code, args.source))
        with open(os.path.join(OUT, code + ".txt"), "w",
                  encoding="utf-8") as out:
            out.write(HEADER.format(code=code))
            out.writelines(word + "\n" for word in words)
        print(f"{code}: {len(words)} words")


if __name__ == "__main__":
    main()
