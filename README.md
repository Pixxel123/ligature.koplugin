# Ligature

Swipe typing for KOReader, tuned for e-ink and for typing with one hand.

<img src="screenshots/swiping.png" width="420" alt="Swiping &quot;acknowledged&quot; into KOReader's search box over a page of Pride and Prejudice, with the grey trail across the keyboard and the suggestions for the word before">

Swiping "acknowledged" while searching a book, on a Kindle Paperwhite's
screen size and resolution.

I mostly use my Kindle's keyboard for searches and quick lookups, and
tapping those out one key at a time on e-ink gets old fast. Ligature lets
you swipe them instead.

It's my fork of
[azac/tapless.koplugin](https://github.com/azac/tapless.koplugin). In type,
a ligature joins letters into one shape, which is what a swipe does. The
fork gets far more swipes right, learns how you type, and adds a one-handed
keyboard. The recognition was tuned on real swipes recorded on a Kindle
Paperwhite (12th gen). Some of the recognition work is up for review
upstream in [#2](https://github.com/azac/tapless.koplugin/pull/2) and
[#4](https://github.com/azac/tapless.koplugin/pull/4).

[Installation](#installation) · [Gestures](#gestures) ·
[One-handed keyboard](#one-handed-keyboard) ·
[Languages](#languages-and-keyboard-size) · [Settings](#settings) ·
[Troubleshooting](#troubleshooting) · [Accuracy](#accuracy) ·
[How it works](#how-it-works) · [Development](#development)

## Features

- Swipe across the letters to type a word. Tapping works as it always has.
- Pause while tapping and the suggestion row offers words that finish the
  one you started.
- The keyboard learns the words you use, which word tends to follow which,
  and where your thumb lands.
- A one-handed keyboard you can move to either side of the screen and
  resize.
- 11 languages. Hold space to switch, and KOReader's layout switches with
  it.
- A thin grey swipe trail, and partial e-ink refreshes that keep flashing
  to a minimum.
- Once your dictionaries are installed, everything works offline.

## Installation

1. Download this repository (`Code → Download ZIP`) and unzip it.
2. Copy the `ligature.koplugin` folder from inside it (not the outer
   `ligature.koplugin-main` folder) into KOReader's `plugins` folder. On a
   Kindle that's `koreader/plugins` when it's plugged in over USB.
3. Restart KOReader.

Ligature supersedes Tapless and isn't compatible with it. It's developed
on a Kindle Paperwhite (12th gen) running KOReader v2026.07.2.

### First run

The first time the keyboard opens, it asks which languages you type in.
English comes with the plugin, and any other language you pick is
downloaded then. The language list has a Show gestures button for a page
with every gesture. You can find that page later under
`Tools → Ligature → Gesture reference`.

## Gestures

| Gesture | What it does |
|---|---|
| Swipe across the letters | Types the word. The keyboard learns your words and where your thumb lands as you go. |
| Tap letters, then pause | Shows words that finish what you've tapped |
| Tap a suggestion | Replaces the word with it |
| Hold a suggestion | Blocks that word, so it's never suggested |
| Tap + in the suggestions | Adds the word you typed to your personal words |
| Tap ⌫ right after a swipe | Deletes the whole swiped word |
| Slide left from ⌫ | Deletes more words the further you slide |
| Slide along space | Moves the text cursor |
| Hold space | Switches to your next language, and to its keyboard layout, if you have more than one |
| Hold 🌐, then lift | Switches the one-handed keyboard on or off |
| Tap ◨ (one-handed) | Menu: other side, leave, resize |
| Swipe from ◨ (one-handed) | Up leaves, outwards moves the keys, inwards resizes them |
| Tap outside the keys (one-handed) | Closes the keyboard |

## One-handed keyboard

- The keys move to one side of the screen, with the page visible beside
  them.
- Move, resize and leave it from the ◨ key at the end of the suggestion
  row.
- Portrait and landscape remember their own place and size.

<details>
<summary><b>One-handed details</b></summary>

Switch it on under `Tools → Ligature → One-handed keyboard → Use
one-handed keyboard`, or hold the globe key 🌐 and lift.

Swipe up from ◨ to leave, outwards to move the keys to the other side, or
inwards, over the keys, to resize them. Tap or hold ◨ for the same choices
as a menu: move on the outer side, leave in the middle, resize on the inner
side.

In resize mode the keys fade. Drag a top corner to change the width and
height, a bottom corner to change the width, or inside to move the keys,
then tap Done. Reset goes back to the default size against the nearer
edge. The keys are 64 to 92 mm wide (68 by default) and 45 to 75 mm tall,
and in landscape no taller than 55% of the screen, so a dialog keeps room
above. Sizes are in millimetres, so a thumb's reach is the same on any
screen. Within 3 mm of an edge the keys snap to it.

Background blur, on by default, covers the space beside the keys with fine
diagonal lines instead of the page. Tapping that space closes the
keyboard.

</details>

## Languages and keyboard size

- Pick your languages the first time the keyboard opens. English comes
  with the plugin, and the other 10 are downloaded when you pick them.
  You can add or remove languages later in the dictionary manager.
- The language is shown on the space bar. Hold space to switch, and the
  keyboard changes to KOReader's layout for that language too.
- The keyboard's height and the size of the key labels can be changed.

<details>
<summary><b>Languages and size details</b></summary>

- Languages can be enabled, disabled, downloaded and removed under
  `Tools → Ligature → Manage dictionaries`. At least one has to stay
  enabled, and the last one can't be removed. The English dictionary that
  comes with the plugin can be removed too.
- The first-run list comes from a copy of the catalog in the plugin, so it
  shows every language offline. Picking languages other than English
  downloads them, asking to turn on Wi-Fi first if it is off. Until they
  are installed, the keyboard types in English.
- A language picked at setup whose download didn't happen (Wi-Fi
  declined, or the download failed) is offered again once, the next time
  the keyboard opens.
- The downloadable dictionaries are Czech, Danish, Dutch, English, French,
  German, Italian, Polish, Portuguese (Brazil), Spanish and Turkish, from
  [Pixxel123/ligature.dictionaries](https://github.com/Pixxel123/ligature.dictionaries).
  Each has an `ATTRIBUTION.txt` saying where its words come from. The
  English one includes the word-pair table.
- With only one language enabled, holding space types a space.
- Personal words and blocked words are kept per language, under
  `Manage dictionaries`, and show the list for the current language.
- `Keyboard size` can be Same as KOReader (the default), Extra compact,
  Compact, Normal or Large. It changes the height and keeps the keyboard
  full width. Same as KOReader follows KOReader's own compact keyboard
  setting.
- `Keyboard text size` can be Auto, Small, Normal or Large. Auto matches
  the keyboard size, or keeps KOReader's key font size when the size is
  Same as KOReader.

</details>

## Settings

Under `Tools → Ligature`:

| Option | Default | What it does |
|---|---|---|
| Manage dictionaries | | Languages, downloads, personal words and blocked words |
| Gesture reference | | The page with every gesture |
| Keyboard size | Same as KOReader | Extra compact to Large; changes the height only |
| Keyboard text size | Auto | Small, Normal or Large key labels |
| Slide on space to move cursor | On | Slide along the space bar to move the text cursor, one character per quarter of the key's height. Holding space still switches language. |
| Double space types a period | Off | A second space right after a word, or a space right after a swiped word, becomes ". ". Not used on input method layouts. |
| Rank offensive words down | On | See [Recognition](#recognition) |
| One-handed keyboard | Off | Use one-handed keyboard, and Background blur (on) |

Tap the globe key (🌐) for KOReader's keyboard layout menu. Picking the
layout of one of your languages switches to that language. Another
layout (Russian, say) leaves the language as it is.

## Troubleshooting

- If a language you picked isn't there, its download didn't happen,
  usually because Wi-Fi was off. The keyboard offers it once more the next
  time it opens, or you can download it under
  `Tools → Ligature → Manage dictionaries`. Until then it types in English.
- If a word never comes up, you might have blocked it by holding it in the
  suggestion row. Blocked words are listed under
  `Tools → Ligature → Manage dictionaries → Blocked words`.
- If a word isn't in the dictionary, tap it out letter by letter, then tap
  \+ in the suggestions to add it to your personal words.
- If a swear word keeps losing to other words, that's on purpose. Words on
  the offensive lists are ranked down until you've kept them twice. You can
  turn that off with `Rank offensive words down`.
- Tapping in Chinese, Japanese, Korean or Vietnamese gets no suggestions.
  Those layouts are still composing the letters you tap.

## Accuracy

The same recorded swipes, replayed through upstream 0.4.0 and through this
fork on the full-width keyboard. "First choice" is the word that gets
typed. "Suggestions" means the word is anywhere in the suggestion row.

| | Upstream 0.4.0 | Ligature |
|---|---|---|
| Sentences, first choice (807 swipes) | 54% | 84% |
| Sentences, suggestions | 63% | 91% |
| Random words, first choice (212 swipes) | 40% | 75% |
| Random words, suggestions | 48% | 84% |
| Random words of 8 or more letters, first choice | 14% | 67% |
| Swipes that didn't start on the word's first key, first choice | 0% | 40% |
| Clean generated swipes, common words | 96% | 98% |
| Clean generated swipes, mid-frequency words | 93% | 96% |
| Clean generated swipes, rare words | 89% | 84% |

On the sentences the fork gets 252 swipes right that upstream got wrong,
and 6 wrong that upstream got right. On the random words it's 80 and 5.

Rare words come out worse. Of 1,500 clean swipes for rare words, the fork
fixes 31 and breaks 113. Common words count for more in the ranking, so a
rare word can lose to a common one with a similar shape.

Upstream has no one-handed keyboard, so the one-handed swipes are only
shown for the fork:

| One-handed | First choice | Suggestions |
|---|---|---|
| Sentences (602 swipes) | 76% | 85% |
| Random words (101 swipes) | 71% | 88% |
| Search-style queries (243 swipes) | 60% | 77% |

The queries are what you'd search for on an e-reader: authors, book
titles, characters and words you'd look up ("perfunctory", "denouement"),
so many aren't everyday words.

Recognising a swipe takes about 70 ms on the Kindle Paperwhite, against
19 ms for upstream. Timed on a PC, about 40% of it goes on the
[shape channel](docs/how-it-works.md#shape-channel), which on two of the
sentence sessions lifts first choice from 77% to 87%.

[How these were measured](docs/development.md#measuring-accuracy) has the
method, and why the numbers lean optimistic.

## How it works

Each part starts with what Ligature does differently from upstream
Tapless. [docs/how-it-works.md](docs/how-it-works.md) has the details and
the numbers.

### Recognition

- Long words are found by the shape of the whole swipe, even when the
  path skips some of their letters.
- Swipes that start just inside the next key over still find the word.
- A corner you cut short can lend a letter from the key next to it.
- Scribbling back and forth on a key types a double letter.
- Rare short fragments like "bq" and "gtg" stop beating real words.
- Common words count for more against the shape of the swipe.
- Swear words and slurs are ranked down, so they stop taking the place of
  the word you meant.
- Spellings that only repeat letters ("wee", "weee") no longer fill the
  row.
- Swipes that start on the number row type a word, not a digit.
- Contractions come out with their apostrophes: "dont" types "don't".

[Details](docs/how-it-works.md#recognition)

### Learning

- Words you keep typing rise up the list.
- The word that usually follows the one before it wins ("the sun", not
  "the sin"). Each language learns its own word pairs.
- Words you tap out letter by letter count as well as swiped ones.
- The keyboard learns where your thumb lands and allows for it.

[Details](docs/how-it-works.md#learning)

### Typing

- Pause while tapping out a word and the row offers words that finish it.
- Tap ⌫ right after a swipe and the whole word goes. Slide left from ⌫ to
  delete more words.
- A second finger touching the screen no longer cuts a swipe short.
- A swipe that only touches one letter types that letter.
- Fast tapping doesn't turn into swiped words.
- Spaces go in front of the next word, so punctuation sits right.

[Details](docs/how-it-works.md#typing)

### Swipe trail

- The trail is a thin grey line that follows your finger smoothly.
- It shows in night mode too.
- The faint ghosting it leaves is cleared with one flash when you pause.

[Details](docs/how-it-works.md#swipe-trail)

### Suggestion row

- Hold a suggestion to block that word.
- The row clears its e-ink ghosting every few changes.
- All four slots are used for words. The language is shown on the space
  bar instead.
- The top suggestion is in bold.

[Details](docs/how-it-works.md#suggestion-row)

## Privacy

Nothing you type leaves the device. Word counts, word pairs and where your
thumb lands are kept in KOReader's settings, and personal and blocked words
in KOReader's data folder. Ligature only goes online to fetch the
dictionary catalog and the dictionaries you pick, from
[Pixxel123/ligature.dictionaries](https://github.com/Pixxel123/ligature.dictionaries).

## Development

`luajit spec/run.lua` runs the tests.
[docs/development.md](docs/development.md) covers the code layout, the
tools for recording and replaying swipes, and how the accuracy numbers
were measured.

## Acknowledgements

1. [azac/tapless.koplugin](https://github.com/azac/tapless.koplugin), the
   plugin Ligature started from.
2. [KOReader](https://github.com/koreader/koreader), whose keyboard module
   Ligature includes in modified form.
3. [wordfreq](https://github.com/rspeer/wordfreq) (CC BY-SA 4.0) and the
   [Leipzig Corpora Collection](https://wortschatz.uni-leipzig.de)
   (CC BY 4.0) for the word lists, with
   [Wiktionary](https://www.wiktionary.org) used to weed out junk.
4. [Tatoeba](https://tatoeba.org) (CC BY 2.0 FR) for the English word
   pairs.
5. The
   [List of Dirty, Naughty, Obscene and Otherwise Bad Words](https://github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words)
   (CC BY 4.0) for the offensive-word lists.

Each dictionary's `ATTRIBUTION.txt` has the details.

## License

GNU Affero General Public License, version 3. See [LICENSE](LICENSE).
