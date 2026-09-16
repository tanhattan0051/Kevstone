# Keystone — Resolved engine decisions (Phase 1)

This resolves the spec's Open Questions for the engine layer.

## Orthography default

Default `Orthography` is **modern** (kiểu mới: `hòa`, `thủy` — tone mark on
the first vowel letter of certain open unmarked diphthongs/triphthongs).
Classic placement (kiểu cũ: `hoà`, `thuỷ`) is opt-in via
`EngineConfig(orthography: .classic)`.

## `z` key semantics

`z` removes the tone only. It does not strip quality marks (circumflex,
breve, horn) by default. E.g. on `â`, `z` yields `a` with tone cleared, not a
plain `a` stripped of the circumflex — the circumflex must be undone by its
own key (double-strike toggle), not by `z`.

## Restore-if-invalid: two layers

1. **Per-key transform rejection (literal fall-through).** A tone or
   quality-mark key that would create an illegal vowel/mark combination is
   *not applied*; the key becomes a literal character appended to the word
   instead. This holds unconditionally, regardless of `restoreIfInvalid`. It
   guarantees, for example, that `chưa` + `a` → `chưaa`, never `chưâ`.

2. **Whole-word restore at commit.** When `restoreIfInvalid` is **on**
   (default) and the committed syllable is not a legal Vietnamese syllable,
   the entire word reverts to the raw keystrokes at commit time. This is what
   makes English words type correctly: `wrong` → `wrong`, `boss` → `boss`.

**Consequence:** the classic double-strike demonstrations `ass` → `as`,
`aaa` → `aa`, `ddd` → `dd` hold only with `restoreIfInvalid` **off** — they
isolate layer 1 in isolation. With `restoreIfInvalid` **on** (the default),
those same key sequences revert at commit to the raw keys (`ass`, `aaa`,
`ddd`), because the intermediate form is not a valid syllable.

## Tone placement

Tone placement follows spec Part A §4 exactly. The modern/classic toggle
affects only the open, unmarked diphthongs/triphthongs `{oa, oe, uy}` — all
other nucleus shapes place the tone identically under both orthographies.

## Stop-coda tone restriction

Syllables closed by a stop coda (`p`, `t`, `c`, `ch`) may carry only **sắc**
or **nặng** — the other four tones (ngang, huyền, hỏi, ngã) are not legal on
a stop-closed syllable and are rejected/restored accordingly.

## Auto-`ươ` policy (spec Open Question #7)

Typing `w` (or `uow`) on an adjacent bare `u`+`o` pair produces **`ươ`** (both
horns) — the common case (`nước`, `được`, `người`, `thương` …). The rare
`uơ` words (`thuở`, `huơ`, `khuơ`) are typed with the `[` direct key on the o
(`hu[` → `huơ`, `thu[r` → `thuở`). Exception: when the `u` is a **`qu`-glide**
(preceded by `q`), only the `o` is horned, since `qươ` is impossible spelling —
so `quow` → `quơ`, `quowr` → `quở`.

## Onset `g` before `i`

`g` needs `gh` before `e`/`ê`, but `g` + `i` is the standard collapsed `gi`
onset before `i` (`gì`, `gìn`, `gỉ`), distinct from `ghì`. The validator allows
`g` before every vowel except `e`/`ê`.

## Nucleus × coda rime (spec §5.3)

A nucleus that ends in a semivowel offglide (falling diphthongs/triphthongs:
`ai`, `oi`, `ui`, `ươi`, `iêu` …) cannot take a true consonant coda. This
protects English words such as `coins`, `ruins`, `rains` (which would otherwise
become pseudo-Vietnamese) while keeping genuine rimes like `oan` (`toán`,
`loán`), `uôn` (`muốn`) and `uyt` (`suýt`) valid.
