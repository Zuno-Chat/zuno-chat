#!/usr/bin/env python3
"""Builds assets/wordlist/recovery_words.txt — the wordlist recovery codes
are drawn from (see docs/features/security-verification.md and
lib/core/security/recovery_code.dart).

Three properties are required, and the test suite re-asserts all three
against the shipped file:

  1. exactly 1296 words (6^4, so a word carries log2(1296) ~= 10.34 bits;
     seven words ~= 72.4 bits)
  2. every word is uniquely identified by its first three characters, so
     entry-time autocomplete needs ~3 keystrokes per word
  3. minimum Levenshtein distance 2 between any two words, so a single
     typo can never land on another valid word — every typo is detectable,
     and the entry screen can offer the near matches

Selection is greedy over a frequency-biased candidate list (words that
appear in both the system dictionary and cracklib-small, which skews
towards words people actually use), shortest first.

Property 3 is enforced with the deletion-neighbourhood lemma: if
edit_distance(a, b) <= k then the sets of strings obtainable by deleting
up to k characters from each must intersect. Testing set intersection is
far cheaper than computing distances, and it is conservative in the safe
direction — it can reject a word whose true distance is one above the
threshold, never accept one below it.

Distance 2 rather than 3 is a deliberate trade. Distance 3 would make
every single-character typo correctable to exactly one candidate, but
1296 words that far apart cannot be drawn from common English — the
selection is forced out into words like "akimbo", "kaolin" and "umlaut",
which is worse for the person reading seven of them off a piece of paper
than an occasional ambiguous correction. Distance 2 still guarantees the
property that actually matters: a single typo can never silently produce
a different valid word.

Regenerating this file after anyone has saved a recovery code does NOT
invalidate their code (the phrase *string* is what gets hashed, and
normalisation is what must stay frozen — see normalizeRecoveryPhrase),
but it does break validation and autocomplete for them. Treat the shipped
file as frozen.
"""

import itertools
import pathlib
import sys

DICT = pathlib.Path("/usr/share/dict/american-english")
COMMON = pathlib.Path("/usr/share/dict/cracklib-small")
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets/wordlist/recovery_words.txt"

TARGET = 1296
MIN_LEN, MAX_LEN = 4, 8

# Words that are fine in a dictionary and wrong in a recovery code read
# aloud over the phone, written on paper, or shown to a stranger who
# picked up the phone: slurs and crude terms, plus a few that are easy to
# mishear or that read as an instruction rather than a word.
BLOCKLIST = {
    "anal", "anus", "arse", "bastard", "bitch", "boob", "boobs", "bugger",
    "cock", "colon", "condom", "crap", "cunt", "damn", "dick", "dildo",
    "dyke", "erotic", "fart", "fuck", "gay", "hell", "homo", "horny",
    "incest", "jerk", "kill", "lesbian", "nazi", "nigger", "orgasm",
    "orgy", "penis", "piss", "porn", "prick", "pubic", "puke", "queer",
    "rape", "rectal", "rectum", "scrotum", "semen", "sexy", "shit",
    "slut", "sperm", "suicide", "testis", "tits", "turd", "urine",
    "vagina", "viagra", "vomit", "whore", "death", "dead", "die", "died",
    "cancer", "corpse", "murder", "abort", "abuse", "bomb", "gun", "gunned",
    "war", "wars", "hate", "hated", "sick", "virus", "fatal", "toxic",
    # Slurs and stereotypes that a dictionary still lists neutrally.
    "gypsy", "gypsies", "negro", "spastic", "cripple", "retard", "midget",
    "savage", "heathen", "infidel", "harlot", "wench",
    # Illness and injury — nobody wants their recovery code to read like a
    # diagnosis, and several are hard to spell from hearing them.
    "lymphoma", "tumor", "tumour", "sepsis", "anemia", "asthma", "eczema",
    "leprosy", "malaria", "measles", "plague", "rabies", "stroke", "ulcer",
    "autopsy", "cadaver", "coffin", "morgue", "funeral", "widow", "orphan",
    "wound", "trauma", "poison", "choke", "drown", "burial", "cremate",
}


def deletions(word, k):
    """Every string obtainable by deleting up to k characters from word."""
    out = {word}
    for n in range(1, k + 1):
        for idxs in itertools.combinations(range(len(word)), n):
            drop = set(idxs)
            out.add("".join(c for i, c in enumerate(word) if i not in drop))
    return out


def levenshtein(a, b):
    if a == b:
        return 0
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def load(path):
    words = set()
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        w = line.strip()
        if w.isascii() and w.isalpha() and w.islower():
            words.add(w)
    return words


def is_inflected(word, dictionary):
    """True for plurals/past tenses/adverbs whose base form is also a word.

    A dictionary is full of these and they hurt in three ways: they crowd
    out the base form, they are easy to mis-transcribe by ear ("abides" vs
    "abide"), and they make the list read as obscure even when the stems
    are common.
    """
    suffixes = (
        ("s", (word[:-1], word[:-2])),
        ("es", (word[:-2], word[:-1])),
        ("ed", (word[:-2], word[:-1], word[:-3] + "e")),
        ("ing", (word[:-3], word[:-3] + "e")),
        ("ly", (word[:-2],)),
        ("er", (word[:-2], word[:-1])),
        ("est", (word[:-3], word[:-2])),
    )
    for suffix, stems in suffixes:
        if word.endswith(suffix):
            if any(len(stem) >= 3 and stem in dictionary for stem in stems):
                return True
    return False


def main():
    if not DICT.exists():
        sys.exit(f"missing {DICT}")
    dictionary = load(DICT)
    # cracklib-small is a password-cracking dictionary, i.e. words people
    # actually reach for — a decent stand-in for the frequency data we
    # don't otherwise have here.
    common = load(COMMON) if COMMON.exists() else dictionary

    pool = [
        w
        for w in dictionary & common
        if MIN_LEN <= len(w) <= MAX_LEN
        and w not in BLOCKLIST
        and not is_inflected(w, dictionary)
    ]

    # Property 2 allows exactly one word per three-character prefix, so
    # the choice within each prefix decides how familiar the list reads.
    # Taking the alphabetically first word per bucket produces
    # "aardvark, aback, abbot, abduct, abed"; taking the *shortest* first
    # produces "able, about, above". Shortest is also fewest keystrokes
    # and fewest characters to mis-transcribe.
    buckets = {}
    for word in pool:
        buckets.setdefault(word[:3], []).append(word)
    for words in buckets.values():
        words.sort(key=lambda w: (len(w), w))

    ordered = sorted(buckets.items(), key=lambda kv: (len(kv[1][0]), kv[1][0]))

    accepted = []
    neighbourhood = set()

    for _prefix, words in ordered:
        if len(accepted) == TARGET:
            break
        # Fall through to the next word in the bucket if the preferred one
        # sits too close to something already accepted — losing the whole
        # prefix over one collision would need a much larger pool.
        for word in words:
            variants = deletions(word, 1)
            if variants & neighbourhood:
                continue
            accepted.append(word)
            neighbourhood |= variants
            break

    if len(accepted) < TARGET:
        sys.exit(f"only found {len(accepted)} words, need {TARGET}")

    accepted.sort()

    # Verify for real rather than trusting the conservative filter above.
    for i in range(len(accepted)):
        for j in range(i + 1, len(accepted)):
            a, b = accepted[i], accepted[j]
            if abs(len(a) - len(b)) >= 2:
                continue
            if levenshtein(a, b) < 2:
                sys.exit(f"distance check failed: {a} / {b}")
    if len({w[:3] for w in accepted}) != TARGET:
        sys.exit("prefix collision")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(accepted) + "\n", encoding="utf-8")
    lengths = {}
    for w in accepted:
        lengths[len(w)] = lengths.get(len(w), 0) + 1
    print(f"wrote {len(accepted)} words to {OUT}")
    print("lengths:", dict(sorted(lengths.items())))


if __name__ == "__main__":
    main()
