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
`aaa` → `aa` hold only with `restoreIfInvalid` **off** — they isolate layer 1
in isolation. With `restoreIfInvalid` **on** (the default), those key
sequences revert at commit to the raw keys (`ass`, `aaa`), because the
intermediate form is not a valid syllable AND contains a vowel — a failed
*Vietnamese* syllable that must be protected as English (`ass`/`aaa` aren't
words, but the same rule is what protects `wrong`/`boss`/`coins`, which are).

`ddd` → `dd` and `ww` → `w`, however, hold even with `restoreIfInvalid`
**on** (the default) — a **no-vowel** composed result (`dd`, `w`, `tw`) is
never reverted, restore-on or off. The rule: restore-to-raw fires only when
the composed word contains a vowel; a no-vowel result is a deliberate
literal (standard Telex "double the transform key = one literal key"), not a
failed attempt at a Vietnamese syllable, so there is nothing to protect it
from — it is kept as composed. See `Engine.finalize`'s `compHasVowel` check.

**Doubled-w habit on restore.** Many typists carry over a habit of doubling
`w` to get a literal `w` (since `w`→`ư`, `ww`→`w` in Telex), and apply it to
whole English words: `win`→`wwin`, `swim`→`swwim`. When such a word reverts to
raw at commit, `Engine.collapseDoubledW` first collapses every consecutive
`ww` pair to a single `w`, so it restores to `win`/`swim` rather than keeping
both w's. This is safe because in Telex `w` is *always* the ư/horn key, so a
`ww` pair is always the escape for one literal `w` (never two intended w's);
it only runs on the restore path (invalid/English words), and words without a
`ww` pair (`boss`, `wrong`) are untouched.

## Positional (non-adjacent) marks

Diacritic mark keys may be typed away from their base letter — at the end of the
word or mid-word, the common "bỏ dấu ở cuối" style — not only immediately after
it. Tones are syllable-level (always positional). Quality marks (circumflex,
horn, breve) and đ now also apply to the nearest eligible earlier letter:
`roiof`→rồi, `toiws`→tới, `dangd`/`dadng`→đang, VNI `toi6`→tôi, `moi71`→mới.
A mark is applied non-adjacently only when treating the key as a new nucleus
vowel would form an illegal nucleus (gated by `isNucleusPrefix`), so real
triphthongs (`ngoaos`→ngoáo) and English words (`add`) are left alone. đ only
ever strokes an onset d. Implemented for Telex (aa/ee/oo, w, dd) and VNI (6/7/8/9).

`EngineConfig.allowFreeToneMark` ("Cho phép bỏ dấu tự do") gates this
non-adjacent placement specifically. **Default: `true`** — preserves the
above behavior and the full corpus. When `false`, a quality mark or đ applies
ONLY when adjacent to its target (the current/last nucleus vowel, or an
adjacent `dd`); the non-adjacent branches above don't fire, so the key falls
through to a literal append/restore exactly as it already does whenever a
non-adjacent application is rejected (e.g. `roiof`/`toiws`/`dangd` no longer
reach rồi/tới/đang — they revert to raw keystrokes via `restoreIfInvalid`
instead). Tones (Telex s/f/r/x/j, VNI 1-5/0) are syllable-level and are
never affected by this flag, on or off.

Bounds added to protect common English words (from the full Telex sweep):
- **Circumflex targets only the current (trailing) nucleus** — no consonant
  between the vowel and the buffer end — so `mama`/`nana`/`nono` stay literal
  while `roiof`→rồi, `toio`→tôi (mark within one vowel run) still work.
- **đ fires only on an adjacent `dd` or a closed syllable** (a coda already
  exists): `ddang`/`dangd`→đang, but `dad`/`did`/`deed` stay English. The
  rarer mid-word trigger `dadng` is dropped as the cost of that protection.
- Note: `w` after a vowel and adjacent `oo`→ô are standard Telex (Vietnamese
  keys), so `cow`→cơ, `moon`→môn are correct, not bugs.

## Bỏ dấu ở cuối từ / freeMarkAcrossCoda (Phase 4)

`EngineConfig.freeMarkAcrossCoda` ("Bỏ dấu ở cuối từ (kể cả sau phụ âm)") is a
NEW, separate opt-in flag — **default `false`** — that further EXTENDS the
non-adjacent placement `allowFreeToneMark` already gates. It does not replace
`allowFreeToneMark`; both flags are independent and a user can have either,
both, or neither on. `EngineConfig.freeMarkAcrossCoda` stays **`false`** by
default so the ~251-case corpus and the English-word protection described
under "Positional (non-adjacent) marks" above are completely untouched at the
engine/test level. **The app (`AppModel`), however, ships it ON by default**
(the author types this "bỏ dấu ở cuối" style: `tana→tân`, `dadng→đang`),
accepting the English-word tradeoff (`mama→mâm`); a user can turn it off in
the Control Panel. Keeping the two defaults split lets the corpus keep
exercising the English-safe behavior while the shipped app matches how the
author actually types.

**What it extends, when ON:**
- **Telex circumflex across a coda** (`Telex.swift` case 7): the existing
  non-adjacent search only looks within the trailing, uninterrupted vowel
  run (it breaks at the first consonant walking backward from the end) — so
  `trene` never finds the `e` in `tr` + `e` + `n` to circumflex, because a
  consonant (`n`) sits between them. With the flag on, a fallback search
  walks back across ALL cells (not stopping at a consonant) for the last
  vowel with the same base letter and no mark yet, but only when that vowel
  has at least one consonant between it and the end of the buffer (i.e.
  genuinely across a coda — this never overlaps the existing within-nucleus
  path, which already would have found it otherwise). `trene`→trên.
- **Telex/VNI đ into an open syllable** (`Telex.swift` case 6, `VNI.swift`
  case 9): both already stroke đ on an adjacent `dd`/`d9` or on a
  non-adjacent trigger once the syllable has CLOSED (a coda exists) — gated
  by `allowFreeToneMark`. With `freeMarkAcrossCoda` on, the non-adjacent
  trigger fires even while the syllable is still OPEN (no coda yet):
  `dadng`→đang (the second `d` strokes the onset immediately, before `ng` is
  even typed).

**Accepted English tradeoff, explicit and intentional.** Turning this on
means the same mechanism that enables `trene`→trên and `dadng`→đang also
turns some English words Vietnamese: `mama`→mâm (the across-coda circumflex
fallback) and `dad`→đa (the open-syllable đ extension). This is the
documented cost of the feature and is exactly why it ships OFF by default —
a user opts into it knowingly, the same way `allowFreeToneMark` already
documents its own, narrower version of this tradeoff.

**VNI circumflex-at-end already worked without this flag.** VNI's case 6
(circumflex) already searches across codas via `cells.lastIndex(where:)`
rather than breaking at the first consonant, so `allowFreeToneMark` alone was
already enough for VNI's circumflex-at-end (e.g. an end-of-word `a6` finds
its target across a coda) — there is no English-word ambiguity to gate there
because VNI's mark keys are digits, never letters, so a digit can never be
mistaken for part of an English word the way a repeated `a`/`e`/`o` can in
Telex. `freeMarkAcrossCoda` therefore did not need to change VNI's
circumflex (case 6) at all; it only had to bring **Telex** circumflex to the
same across-coda parity, and add the **đ-open-syllable** extension to both
Telex and VNI (case 9), since đ's onset-only, letter-triggered nature in
Telex has no VNI-digit equivalent that was already safe.

**Note on VNI's đ-open-syllable case in practice.** Because VNI's đ trigger
is a separate digit key (`9`), not the letter `d` itself, a sequence like
`dad9` still has a plain, unstruck `d` sitting in the buffer as a literal
consonant by the time `9` is pressed (VNI never gives `d` any special
onset/đ duty the way Telex's `d` key does). That literal `d` ends up parsed
as the syllable's coda, and `d` is not a legal Vietnamese coda
(`Phonology.codas`), so the whole word fails validation and reverts to raw
keystrokes at commit regardless of `freeMarkAcrossCoda` — verified by running
(`Tests/KeystoneEngineTests/FreeMarkAcrossCodaTests.swift`,
`vniDStrokeOnOpenSyllable`). The flag still correctly extends case 9's fire
condition for parity with Telex; it just cannot rescue this particular
key sequence, because VNI's đ trigger has no way to "consume" an intervening
literal letter the way Telex's letter-triggered đ does.

## Open ươ → uơ downgrade (spec Open Question #7)

An OPEN `ươ` (both horns, the u+o pair is the whole nucleus, nothing after the
o) is not a real Vietnamese nucleus, so at commit it downgrades to `uơ`,
letting `thuowr`→thuở, `huow`→huơ, `khuow`→khuơ be typed naturally with `w`.
Closed forms and offglide forms keep `ươ` (they never reach this shape):
`hương`, `nước`, `người`, `rượu`. The `[` direct key still works too.

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

## Input methods (Phase 3)

- **Telex** and **VNI** are fully implemented and share one syllable core
  (`SyllableOps`), so both render byte-identical Vietnamese (pinned by the
  Telex↔VNI differential suite).
- **Quick Telex** (gõ nhanh) is a config toggle (`EngineConfig.quickTelex`, off
  by default) layered on Telex: `cc→ch, gg→gi, kk→kh, nn→ng, pp→ph, qq→qu,
  tt→th` at onset/coda; `dd→đ` is unchanged.
- **Simple Telex 1 / 2**: the spec's reduced-collision definitions (§2.5) are
  explicitly clean-room and unverified against OpenKey (Open Q #1). Until we can
  black-box test real OpenKey behavior, `.simpleTelex1`/`.simpleTelex2` dispatch
  to the full Telex interpreter (a safe superset — the `[`/`]` direct keys are
  already enabled). Revisit with parity testing before claiming distinct
  semantics.

## Macros / gõ tắt (Phase 4)

This resolves the spec's Open Question #9 (where macro expansion fires in the
pipeline).

**Firing point: word commit, against the RAW typed buffer.** A macro is
matched against `Engine.rawKeys` — the literal ASCII keys typed since the
last boundary — not against the rendered/folded Vietnamese text. Matching
happens at commit (a boundary character, or an explicit flush) and is
case-sensitive and exact (no prefix/fuzzy matching). A macro never fires
mid-syllable.

**Precedence: macros win over everything else.** Inside `Engine.finalize`,
the macro check runs first, BEFORE Vietnamese rendering and BEFORE
restore-if-invalid. If the raw word matches an enabled macro, the entire
on-screen composed word (`prevUnits.count` code units — not a diffed
prefix) is deleted and replaced by the macro's expansion; restore-if-invalid
never runs for a macro hit. This means a macro can override what would
otherwise be a perfectly valid Vietnamese syllable (e.g. a macro trigger
`as` beats Telex's `as` → `á`).

**Two-path model**, because Vietnamese rendering only happens while
Vietnamese input is active:
- **Vietnamese-mode**: inside `Engine.finalize(boundary:)`, gated by
  `EngineConfig.macrosEnabled`. On a hit, the boundary character (if any) is
  appended to the synthesized replacement text, since the whole edit
  (backspace + text) replaces everything, including the boundary, on screen.
- **English-mode** (Vietnamese input off): a separate, independent buffer
  (`Engine.englishRawKeys`) and entry points (`processInactive`,
  `flushInactive`, `resetInactive`), gated by BOTH `macrosEnabled` AND
  `macrosExpandWhenVietnameseOff` (checked in `EngineController.handle`, not
  inside `Engine`, so `Engine` doesn't need to know why it was called). Every
  keystroke passes through physically in this mode — `suppress` is always
  `false` — so the boundary character is delivered by the OS itself and must
  NOT be duplicated into the returned edit's text.

**Duplicate triggers: last one wins.** `MacroTable.init` first drops
disabled rules, then builds a `[String: MacroRule]` dictionary from the
survivors in order — so if two *enabled* rules share a trigger, the later
one in the list overwrites the earlier one. A disabled rule is simply
excluded before this step; it cannot "clear" an earlier enabled rule with
the same trigger by appearing later in the list. An **empty trigger** is
rejected too (both in `MacroTable.init` and in `parseTabSeparated`): it
would otherwise match the empty raw buffer and fire on every bare commit.
`MacroStore.importFile` likewise refuses to replace the user's macros with
an empty parse — a file that is neither valid JSON nor a tab-separated macro
list surfaces the decode error instead of silently wiping the list.

**autoCapitalize semantics, and why it's dormant.** `Engine` tracks
`atSentenceStart`: `.`, `!`, `?`, and newline boundaries start a new
sentence; committing any word (via any other boundary) ends it. A macro's
replacement gets its first character uppercased only when ALL of: the
per-macro `MacroRule.autoCapitalize` is on, the global
`EngineConfig.macroAutoCapitalize` is on, the cursor is at a sentence start,
and the replacement's first character is a lowercase letter
(`MacroTable.expandedText`). `MacroRule.autoCapitalize` defaults to `false`
per macro — so even though the global toggle defaults to `true` (mirroring
OpenKey's own default) and `AppModel.macrosEnabled` defaults to `true` (an
existing pre-Phase-4 UI default we keep, per "ships dormant unless already
configured"), the feature has no observable effect until a user (a) adds at
least one macro, and, for capitalization specifically, (b) opts that macro
into `autoCapitalize` explicitly.

**Legacy import.** `MacroTable.parseTabSeparated` reads OpenKey-style
`trigger<TAB>replacement` files: blank lines and lines without a tab are
skipped, and a trailing `\r` is trimmed per line (splitting is done on the
raw LINE FEED *scalar*, not the `Character` "\n", because Swift's grapheme
clustering merges a CRLF pair into a single `Character` that would never
match a bare "\n" separator). `MacroStore.importFile` tries JSON first and
falls back to this parser on failure, so both `.json` exports and legacy
`.txt` files work from the same "Nhập gõ tắt…" menu item.

## Smart-switch / per-app state (Phase 4)

Resolves spec **E.7** ("Smart-switch / đổi app") and **Part C §7** ("Settings
store & engine binding", §7.1 off the hot path / §7.2 persistence).

**Two independent toggles**, both pre-existing on `AppModel` (previously
inert scaffolding, now wired):
- `smartSwitch` ("Chuyển chế độ thông minh") — remember/restore
  **Vietnamese on/off** per frontmost app.
- `rememberCodePerApp` ("Tự ghi nhớ bảng mã theo ứng dụng") — remember/
  restore the **code table** per frontmost app.

Either, both, or neither may be on; each field of the remembered state is
applied independently of the other (`SmartSwitch.resolve` in
`Sources/KeystoneInput/PerAppState.swift`). With both off, behavior is
unchanged from before Phase 4: only the existing engine-buffer reset on app
switch happens. An app Keystone has never seen (`remembered == nil`) always
keeps the current state — there is nothing to restore yet, so the first time
you visit an app it does not silently flip anything.

**Off the hot path (E.7 / §7.1).** All of this runs inside the existing
`NSWorkspace.didActivateApplicationNotification` observer in
`AppModel.bootstrap()`, on the main queue — never inside the CGEventTap
callback. The observer already reset the composing buffer before Phase 4;
that reset is unconditional and now runs first, followed by the per-app
resolve/restore logic only when at least one toggle is on.

**Keystone's own bundle id and `nil` ids are skipped.** The bundle id is read
from `notification.userInfo?[NSWorkspace.applicationUserInfoKey]`. If it's
`nil` or equals `Bundle.main.bundleIdentifier`, Keystone's own windows (e.g.
the Control Panel) never cause a state flip — only the buffer reset applies.

**Save-on-leave + save-on-manual-change + restore-on-enter:**
1. On activation, if tracking is on, the state we're leaving (`enabled` +
   `codeTable` for the previous `currentBundleID`) is saved first, *then*
   `currentBundleID` advances to the new app, *then* — if something was
   previously learned for the new app — `SmartSwitch.resolve` computes what
   to apply and `enabled`/`codeTable` are set under an `applyingPerAppState`
   guard so step 2 doesn't immediately re-learn the state it's restoring.
2. `enabled`'s and `codeTable`'s `didSet`s call `persistPerAppStateIfNeeded()`
   after their existing engine-push work, so a manual toggle/menu change is
   learned for the current app right away, not only at the next app switch.
   This is skipped while `applyingPerAppState` is true (see above), while
   tracking is off, or before `currentBundleID` is known (e.g. at launch,
   before the first activation notification arrives).
3. `currentBundleID` itself is tracked regardless of whether tracking is on,
   so flipping a toggle on mid-session has an app to persist against
   immediately rather than waiting for the next switch.

**Persistence.** The pure `PerAppStateStore` (`Sources/KeystoneInput/PerAppState.swift`,
a `[bundleID: AppInputState]` dictionary, `Codable`, no I/O) is wrapped by
`App/PerAppStore.swift` (`@Observable @MainActor` singleton, mirrors
`MacroStore`'s pattern), which loads/saves it as JSON at
`~/Library/Application Support/com.tanta.keystone/appstates.json`. A missing
file on first run is normal and not logged as an error; a decode failure
*is* logged (via `Logger`) and leaves the in-memory store as-is rather than
silently presenting a corrupt file as "no learned apps".

**`resetToDefaults()` does not erase learned apps.** It resets the
`smartSwitch`/`rememberCodePerApp` *settings* to their defaults (as it
already did), but leaves `PerAppStore` untouched — learned data and settings
are separate concerns. Only the explicit "Xoá ghi nhớ theo ứng dụng" button
in the Control Panel's "Chuyển đổi" section (`AppModel.resetLearnedApps()`)
wipes learned apps.

**Deferred / not unit-testable headless.** The live `NSWorkspace` wiring in
`AppModel.handleAppActivation` is integration-only, same reasoning as the
CGEventTap itself — it needs a real app switch to exercise. What's pinned by
`Tests/KeystoneInputTests/PerAppStateTests.swift` is the pure resolver
(`SmartSwitch.resolve`) and the pure store (`PerAppStateStore`) that the live
wiring is built on.

## Nucleus × coda rime (spec §5.3)

A nucleus that ends in a semivowel offglide (falling diphthongs/triphthongs:
`ai`, `oi`, `ui`, `ươi`, `iêu` …) cannot take a true consonant coda. This
protects English words such as `coins`, `ruins`, `rains` (which would otherwise
become pseudo-Vietnamese) while keeping genuine rimes like `oan` (`toán`,
`loán`), `uôn` (`muốn`) and `uyt` (`suýt`) valid.

## System toggles (Phase 4)

Three of the "Hệ thống" tab toggles in `AppModel` moved from persistence-only
scaffolding to real behavior; a fourth stays dormant on purpose.

**`runAtLogin` → `SMAppService.mainApp`.** `didSet` persists first, then
`register()`/`unregister()`s the login item. A failed call is logged via
`Logger.error` with context and the property is reverted to its actual state
(rather than leaving the toggle claiming a login-item state that isn't true),
guarded by a private `isSyncingLoginItem` flag so the revert's own
reassignment doesn't re-enter `didSet` and fire another register/unregister.
`bootstrap()` calls `reconcileLoginItemStatus()` once at launch, under the
same guard, to catch drift between the persisted toggle and
`SMAppService.mainApp.status` (e.g. the user removed the login item from
System Settings directly): `.enabled` → `true`, `.notRegistered`/`.notFound`
→ `false`, `.requiresApproval` is left as-is and just logged.

**`showDockIcon` → `NSApp.setActivationPolicy`.** `didSet` sets `.regular`/
`.accessory` and, when turning the icon on, also calls
`NSApp.activate(ignoringOtherApps: true)` so the new Dock tile is focused
immediately rather than sitting there unfocused.
`AppDelegate.applicationDidFinishLaunching` in `KeystoneApp.swift` now sets
the *initial* policy from the persisted setting
(`AppModel.shared.showDockIcon ? .regular : .accessory`) instead of the old
hardcoded `.accessory`; the single-instance check → policy → `bootstrap()`
order is unchanged.

**`openControlPanelAtLaunch` → a scene-registered `openWindow` closure.**
`AppDelegate`/`bootstrap()` run before any SwiftUI scene exists, so
`openWindow` isn't available there. Instead, `AppModel.openControlPanelRequest`
is a closure the SwiftUI layer fills in once its scene appears —
`MenuBarContent`'s `.onAppear` captures `@Environment(\.openWindow)` and sets
`model.openControlPanelRequest = { openWindow(id: WindowID.controlPanel) }`,
then calls `model.performLaunchOpenIfNeeded()`, which (guarded by
`didAttemptLaunchOpen` so it only ever acts once) activates the app and
invokes the closure if `openControlPanelAtLaunch` is on.

**`checkForUpdates` stays dormant.** Real update checking needs a signed
release feed / appcast (Sparkle), which is Phase 5 work and doesn't exist
yet. The toggle still persists to `UserDefaults` as before; nothing reads it
yet.

**Integration-only, not unit-testable headless.** `SMAppService`,
`NSApp.setActivationPolicy`, and `openWindow` all need a real running app
(same reasoning as the CGEventTap and the `NSWorkspace` smart-switch wiring
above) — verified by building and by manual exercise on a real Mac, not by
new unit tests.

## Quick consonants & auto-capitalize (Phase 4)

Three more `EngineConfig` fields, all default OFF (dormant):
`quickStartConsonant`, `quickEndConsonant`, `autoCapitalize`.

**Start-shortcut is onset-only, and only on the word's first keystroke.**
`f`, `j`, `w` already have Telex jobs (huyền, nặng, horn/bare-ư) that fire
constantly mid-word — `quickStartConsonant` cannot simply reinterpret those
keys everywhere without breaking existing tone/horn typing (`af`→`à` must
keep working). So the shortcut is gated on `cells.isEmpty`: it only ever
fires as the very first key of a fresh word (`f`→`ph`, `j`→`gi`, `w`→`qu`),
checked at the very top of `Telex.apply`, before the tone-key branch. Casing
rule: the first letter of the cluster takes the typed key's case, the rest is
lowercase — this gives the natural `"Fa "`→`"Pha "`, `"Wa "`→`"Qua "`. A
would-be all-caps cluster (holding shift through the whole shortcut trigger)
isn't specially cased by this feature — that's an accepted rare edge, not a
goal for v1.

**End-shortcut fires only immediately after a vowel.** `g`, `h`, `k` are not
tone/mark keys, so unlike the start-shortcut they always reach Telex's case 8
("any other consonant") — but expanding them unconditionally would corrupt
ordinary words: "tong" (t-o-n-g) must not become "tonng" just because it
contains a trailing `g`. The fix is the same shape check either way: only
expand when `cells.last?.isVowel == true`, i.e. the key lands right where the
nucleus just closed (`"tog"`→`"tong"`, `"vih"`→`"vinh"`, `"bak"`→`"bach"`),
never when a consonant already closed the coda (`"tong"` stays `"tong"`).
This check lives inside case 8, before the existing `quickTelex` doubling
block, so both features can coexist without one shadowing the other.

**Test isolation note:** `EngineTogglesTests`'s end-consonant suite sets
`restoreIfInvalid: false`. This isolates the per-key coda expansion from the
separate whole-word phonotactic-validity restore layer (see "Restore-if-
invalid: two layers" above) — e.g. a *ngang*-toned `"bach"` is rejected by
Phonology's stop-coda tone restriction (§5.4: `p`/`t`/`c`/`ch` codas require
sắc/nặng), so with `restoreIfInvalid` **on** (the real default) that
particular expansion would actually revert to raw keystrokes at commit, same
as any other stop-coda word typed without a sắc/nặng tone. That's expected,
existing behavior of the restore layer, not a bug in the new shortcut.

**Auto-capitalize is commit-time and reuses `atSentenceStart`.** `Engine`
already tracked `atSentenceStart` for macro capitalization; `autoCapitalize`
reuses the same flag instead of adding a second tracker. In `finalize`, when
`config.autoCapitalize && atSentenceStart && !rawKeys.isEmpty`, the
sentence-initial word's first letter is capitalized right before the edit is
computed — on the un-capitalized `Composition` for the restore-if-invalid
branch (uppercasing `rawKeys.first` before `table.plain`, so English words
like `"hello"` also capitalize via the restore path) and on a local `var
comp` for the normal render branch (`comp.cells[0].isUpper = true` before
`encode`). `isValid(comp)` is evaluated on the *un-capitalized* composition
first, since capitalization never changes phonotactic validity. An
already-uppercase first letter is left alone. This only runs after the
macro-hit branch has already returned, so a fired macro's own
`autoCapitalize`/`macroAutoCapitalize` handling is untouched. Because the
first letter's on-screen code unit changes, the commit diff naturally
produces the backspace+retype that turns the lowercase-while-composing first
letter into its capitalized form only once the word commits — so a
sentence-initial word visibly shows lowercase while still being typed and
flips to uppercase at commit. Accepted for v1.

All three flags default OFF; `App/AppModel.swift`'s
`quickStartConsonant`/`quickEndConsonant`/`autoCapitalize` properties (previously
persistence-only scaffolding) now also call `pushConfig()` in their `didSet`,
same pattern as `quickTelex`/`restoreIfInvalid`.

**`autoCapitalize` defaults OFF at the app layer too, and `reset()` clears
`atSentenceStart`.** `App/AppModel.swift`'s `autoCapitalize` UI toggle used
to default `true` (a leftover from before this flag was wired to the
engine), out of step with `EngineConfig`'s own OFF default above — it is now
`false` in both `loadBool(..., default:)` and `resetToDefaults()`.
Sentence-start detection is unreliable in a system-wide IME (no real
knowledge of cursor context), so the feature stays opt-in. Separately,
`Engine.reset()` — called on caret moves, app switches, and other nav keys —
now sets `atSentenceStart = false` instead of `true`: a reset has no actual
information that the next word starts a sentence, so it must not
auto-capitalize it. Only a real sentence terminator (`.`/`!`/`?`/newline)
seen by `updateSentenceStart` sets it back to `true`. A brand-new `Engine`'s
stored-property initial value is untouched (still `true`), so a fresh
engine's very first word is still treated as sentence-initial — this is what
the existing `AutoCapitalizeTests` suite (fresh engines) relies on.

## Auto-capitalize sau Enter / đầu dòng (Return → commitNewline)

**Bug:** `autoCapitalize` never fired at the start of a new LINE. Pressing
Return/KeypadEnter went through `KeyTranslator` as `.commitPassthrough`
(grouped with Tab/arrows/Escape), which calls `Engine.flush()` →
`finalize(boundary: nil)` — that commits the pending word but never touches
`atSentenceStart`. A `.`/`!`/`?` boundary works because those are ordinary
characters that flow through `process` and hit `updateSentenceStart`; Return
never becomes a character at all, since `KeyTranslator` intercepts it by
`keyCode` first. Net effect: a bullet line like `"- muc"` typed right after
Enter stayed `"- muc"` instead of `"- Muc"`.

**Fix:** split Return (keyCode 36) and KeypadEnter (76) out of
`.commitPassthrough` into a new `KeyDecision.commitNewline` case
(`Contracts.swift`). `EngineController.handle(_:)` routes it to two new
`Engine` methods — `flushNewline()` (active) and `flushInactiveNewline()`
(Vietnamese off, English-macro path) — that finalize exactly like
`flush()`/`flushInactive()` (`finalize(boundary: nil)` /
`matchEnglishMacro(boundary: nil)`, so no `\n` is ever added to the returned
edit text — the physical Return key already inserts the newline via
passthrough) and then force `atSentenceStart = true`. Other commit keys
(Tab/arrows/Home/End/PageUp/PageDown/Escape) stay `.commitPassthrough` and do
NOT start a new sentence — only Return/KeypadEnter carry real "new line"
information.

Covered by `EngineTogglesTests.swift`'s `AutoCapitalizeAfterNewline` suite
(newline re-capitalizes after a mid-sentence word; a `- ` bullet right after
Enter capitalizes the word that follows it; behavior is a no-op with
`autoCapitalize` off) and `TranslatorTests.swift` (`keyCode 36`/`76` →
`.commitNewline`, `keyCode 48` (Tab) still `.commitPassthrough`).

## Onboarding / permissions (Phase 4)

Resolves spec **§5 "Onboarding / permissions flow"**.

**No separate `PermissionsModel`.** The spec sketches a standalone
`@Observable PermissionsModel` with its own 1 s poll timer. `AppModel`
already observes `accessibilityTrusted`, `inputMonitoring`, `tapRunning`, and
`needsRelaunch`, refreshed every 1.5 s by the `statusTimer` started in
`bootstrap()` (pre-existing, not new). `App/OnboardingView.swift` binds
directly to those fields instead of duplicating the polling — one status
timer for the whole app, not two.

**Accessibility is required, Input Monitoring is recommended.** The
Accessibility card has no way to be dismissed short of granting it or
finishing/deferring onboarding entirely — the tap cannot exist without it.
The Input Monitoring card is informational: its buttons help, but nothing
in the flow blocks on it, per the spec's "don't hard-block" note.

**The relaunch affordance covers "granted but not yet effective".** A fresh
Accessibility grant often doesn't take effect for an already-running
process. `AppModel.needsRelaunch` (existing) goes true once the tap has
failed to come up a couple of refresh cycles after trust was granted; the
Accessibility card shows a "Khởi động lại Keystone" button (→
`model.relaunch()`, existing) in that state instead of polling forever.

**Auto-opens once at first launch, reachable afterward from the menu.**
`AppModel.needsOnboarding` is `!accessibilityTrusted && !didFinishOnboarding`
— a new persisted flag, same `loadBool`/`Keys` pattern as the app's other
settings. The single-window launch mechanism
(`AppModel.openControlPanelRequest` / `performLaunchOpenIfNeeded()`) is
generalized to `openWindowRequest: ((String) -> Void)?` so it can open either
window; `performLaunchOpenIfNeeded()` now checks `needsOnboarding` first and
falls back to `openControlPanelAtLaunch` — onboarding wins on a first run so
it's seen before any auto-opened Control Panel. Once dismissed, it stays
reachable via the menu bar's new "Hướng dẫn cấp quyền…" item
(`MenuBarContent.swift`), so a user who deferred permissions can come back
to it.

**The user is never trapped.** The footer button
("Bắt đầu gõ" when Accessibility is trusted, "Để sau" otherwise) is never
disabled; either label calls `model.finishOnboarding()` (sets
`didFinishOnboarding = true`) then `dismiss()`. Deferring is always available.

**No macOS-26-only APIs.** The spec's sketch uses `.glassEffect`/
`.buttonStyle(.glassProminent/.glass)` (Liquid Glass, macOS 26). The
deployment target here is conservative (macOS 13/14), so the shipped
`OnboardingView` uses `.regularMaterial` card backgrounds, a `RoundedRectangle`
stroke, SF Symbols, and `.buttonStyle(.borderedProminent)` for primary
actions instead — same visual intent (cards, live status, a prominent
action), widely-available APIs.

**Integration-only, not unit-testable headless.** Same reasoning as the
CGEventTap, `NSWorkspace` smart-switch wiring, and `SMAppService`/
`openWindow` system-toggle wiring above: `AXIsProcessTrusted`,
`IOHIDRequestAccess`, `NSWorkspace.shared.open`, and the SwiftUI
`Window`/`openWindow`/`dismiss` machinery all need a real running app and a
real permission dialog to exercise. Verified by `swift build` staying clean
and by the existing engine/input suites staying green (68 + 36 tests) — no
fabricated unit tests were added for this UI layer.

## Phím chuyển / switch-language hotkey (Phase 4)

Resolves the `switchKeyModifier` scaffolding left in the Phase 4 system-
toggles work ("Phím chuyển:" picker with no hot key actually registered).

**Modifier-only chord, detected via a pure `SwitchKeyDetector`.** OpenKey's
"Phím chuyển" isn't a single key — it's a chord like Ctrl+Shift that toggles
Vietnamese input when pressed and released *cleanly*, with no other key
pressed in between. That "cleanly" requirement is the whole point: it's what
lets `SwitchKeyDetector` tell a bare Ctrl+Shift tap apart from an ordinary
shortcut like Ctrl+Shift+C, which must never toggle the input state. The
detector is a tiny arm/cancel state machine (`Sources/KeystoneInput/
SwitchKeyDetector.swift`): `flagsChanged(active:)` arms when the live
modifier set exactly matches `target`, fires `true` only when the set then
returns to empty while still armed and not cancelled, and `otherKeyPressed()`
(fed from `.keyDown`) cancels an armed chord — so does any modifier joining
the chord that isn't part of `target` (e.g. Command joining a Ctrl+Shift
chord). Pinned by `Tests/KeystoneInputTests/SwitchKeyDetectorTests.swift`.

**`ModifierSet`, not `NSEvent.ModifierFlags`, at the detector boundary.** The
detector lives in `KeystoneInput`, which has no AppKit dependency and must
stay unit-testable headless — same constraint as every other pure type in
`Contracts.swift`. `App/AppModel.swift` maps `NSEvent.modifierFlags` to
`ModifierSet` at the edge (`ModifierSet(nsEventFlags:)`), right next to the
existing `SwitchKeyModifier.chord` mapping.

**`NSEvent` global + local monitors, deliberately NOT the CGEventTap.** The
tap is this project's most stability-critical code and this feature has no
business anywhere near its hot path — a bug here must never be able to wedge
every keystroke in every app. So "Phím chuyển" is wired entirely through
AppKit `NSEvent.addGlobalMonitorForEvents`/`addLocalMonitorForEvents`
(`matching: [.flagsChanged, .keyDown]`) in `AppModel.bootstrap()`/
`shutdown()`, independent of `EventTapController`. The global monitor is what
lets the chord fire while some other app is frontmost; like the tap, it needs
Accessibility to see other apps' events, but unlike the tap its absence is
harmless — the hot key just doesn't fire globally yet, no crash, no
degraded typing. The local monitor covers Keystone's own windows and must
return the event unmodified (`return event`) — this feature only ever reads
modifier/key events, never consumes them.

**Concurrency: extract-then-hop, same pattern as the app-activation
observer.** `NSEvent` monitor closures fire on the main run loop but aren't
statically `@MainActor`-isolated, and `NSEvent` itself isn't `Sendable`. Both
monitors pull out only the two `Sendable` pieces they need (the `NSEvent
.EventType` and a computed `ModifierSet`) synchronously in the closure, then
hop via `Task { @MainActor in ... }` into one shared method,
`handleSwitchKeyEvent(type:modifiers:)` — mirroring exactly how
`bootstrap()`'s `NSWorkspace.didActivateApplicationNotification` observer
already extracts a bundle ID before hopping actors. That method feeds
`switchDetector` and calls `enabled.toggle()` on a fired chord.

**`.off` disables it; default stays `.controlShift`.** `SwitchKeyModifier`
gained an `.off` case (label "Tắt") so the picker can turn the hot key off
entirely — `.off.chord` is `nil`, and `SwitchKeyDetector.flagsChanged`
treats a `nil`/empty target as always-disabled (resets its state, always
returns `false`). `.controlShift` remains the default, matching OpenKey and
the easy V/E switching the design calls for.

**Integration-only, not unit-testable headless.** Same reasoning as the tap
and the `NSWorkspace` smart-switch wiring above: the live `NSEvent` monitors
need a real running app and real system input events to exercise. Only the
pure `SwitchKeyDetector` state machine is unit-tested; the monitor wiring in
`AppModel` is verified by `swift build` staying clean and the existing
engine/input suites staying green. The two `NSEvent` monitor closures run on
the main thread and are handled **synchronously** (`MainActor.assumeIsolated`,
not a `Task` hop) so the detector — an ordered state machine — never sees a
cancelling `keyDown` reordered after the releasing `flagsChanged`.

## Menu-bar mode indicator (V / E)

The `MenuBarExtra` label shows a bold **`V`** while Vietnamese input is on and
**`E`** while it's off, instead of an icon — the current mode is readable at a
glance and is the immediate visual feedback for the "Phím chuyển" toggle above.
Driven by `AppModel.enabled` (see `MenuBarLabel` in `KeystoneApp.swift`).

## Input-layer compatibility toggles (Phase 4)

`sendEachKeystroke` and `autoFixSuggestion` ("Hệ thống" tab) moved from
persistence-only scaffolding to real behavior in `EventTapController`'s
posting path — the CGEventTap output side, this project's most
stability-critical code.

**`InputBehavior` snapshot, same lock/snapshot pattern as `EngineController`.**
`Contracts.swift` gained a plain `InputBehavior` value type
(`sendEachKeystroke`, `textOnKeyDownOnly`). `EventTapController` holds one
behind an `OSAllocatedUnfairLock` (`behaviorLock`) and exposes
`updateBehavior(_:)`; `AppModel.pushInputBehavior()` calls it — mirroring
exactly how `pushConfig()` pushes `EngineConfig` into `EngineController` —
from `bootstrap()` and from both toggles' `didSet`s, after persisting. The
tap's `handle(...)` reads the snapshot **once per edit** (`behaviorLock
.withLock { behavior }`), not once per raw keystroke that passes through
untouched, so the added hot-path cost is exactly one cheap lock acquire on
edits the engine already decided to act on — the same cost class as the
existing `EngineController` config lock.

**`sendEachKeystroke` ("Gửi từng phím") → per-grapheme `postText`.**
`KeystrokeExecutor.execute` gained an `eachGrapheme: Bool = false` parameter:
when true, it calls `sink.postText(String(ch))` once per Swift `Character`
in the result text instead of one `postText(wholeString)` call, after the
same single `postBackspace(count:)` as before. Helps apps that mishandle
multi-char Unicode insertions. Default off, matching `AppModel`'s existing
default.

**`autoFixSuggestion` ("Sửa lỗi gợi ý") → keyDown-only Unicode posting.**
`TapSink.postText` now takes `textOnKeyDownOnly: Bool`. When true, the synthesized Unicode string is set on the keyDown event only —
the keyUp is still posted (tagged with `selfTag`, flags cleared) but carries
no string. When false, both events carry the string, matching the tap's
original behavior. This is the documented remedy for browsers/Excel doubling
synthesized text. It defaults **OFF**, so the tap's default posting is
UNCHANGED (both events, as before) — turning it on is an opt-in switch to
keyDown-only. When enabling it, verify on real browsers/Excel/Terminal — see
HANDOFF.md [VERIFY] #2 for the double-char background. `postBackspace` and the
self-tag/flags logic are unchanged.

**Integration-only, except the executor's per-grapheme split.** Same
reasoning as the tap and the `NSWorkspace`/`NSEvent` wiring elsewhere in this
file: the live keyDown-only posting needs a real synthetic `CGEvent` pair and
a real target app to observe, so it isn't unit-tested. The per-grapheme split
lives in the pure `KeystrokeExecutor` and is covered by
`Tests/KeystoneInputTests/ExecutorTests.swift` against the fake `EventSink`.

## Bảng mã mặc định — Unicode dựng sẵn (NFC), không phải tổ hợp

The app-level default `codeTable` is **`.unicode`** (NFC precomposed), matching
`EngineConfig.codeTable`. This is not a stylistic choice, it is a correctness
one: the tap deletes on-screen text with N literal Backspace keystrokes where
N is `EngineResult.backspaceCount`, and the engine counts that in **code
units** (design spec §6-7). NFC spells every Vietnamese grapheme as exactly one
code unit, so one Backspace = one code unit = one grapheme in every app, and
the count always matches.

`.unicodeCompound` ("Unicode tổ hợp", combining diacritics) spells one grapheme
as base + combining mark(s) — 2-3 code units. A single Backspace then deletes a
whole grapheme in most apps but only one code unit in a few, so the code-unit
`backspaceCount` can under- or over-delete on any diacritic/restore edit,
dropping or duplicating a character in a real app's Backspace handling. NFC has
no such ambiguity. `.unicodeCompound` therefore stays a **Control-Panel opt-in**
for legacy software that specifically needs decomposed Unicode, and must not be
the default. A brief window where it *was* the default (commit "Phase 5 … +
compound default", never tagged/released) is what surfaced this — reverted here.

Related: `AppModel.codeTable`'s `didSet` persists to the global default key only
when `!applyingPerAppState`, so a per-app **restore** can no longer overwrite
the user's chosen startup default (that write is a leak, same class as the
per-app re-learn the flag already guards).

## Duplicate key-down — the phantom-repeat echo guard

**Symptom.** Typing a word with a Telex tone/mark in Vietnamese mode doubled the
diacritic key: `task`→`tassk`, `fix`→`fixx`, `google`→`gooogle`, `mà`→`m`,
`maaf`→`m`. Only keys that make Keystone emit a **Backspace** doubled; plain
keys never did. Worse the faster the typist (more keys, cascading corruption).

**Root cause (a live event-tap file log nailed it).** The tap receives the tone
key **twice** for one physical press. Both copies are indistinguishable — same
keycode, `state=1` (HID), `pid=0`, `autorepeat=0`, each with its own key-up — so
neither source nor flags tell them apart. The duplicate arrives ~120-210ms after
the first, sometimes while the key is still held, sometimes just after its
key-up. It is **100% correlated with Keystone suppressing the key-down and
injecting a Backspace**: on this Mac (`ApplePressAndHoldEnabled=0`, fast
`KeyRepeat`), that suppression makes macOS emit a phantom repeat of the
just-suppressed key. Things that did NOT fix it (verified live): posting via
`CGEventPost` instead of `tapPostEvent`, deferring the injection with
`CFRunLoopPerformBlock`, and OpenKey-style pass-through of unchanged keys — the
phantom is generated regardless.

**Fix — drop exactly one duplicate after a transform (`EventTapController`).**
A physical key cannot be pressed twice without a key-up between, so a key-down
for the just-transformed key — whether it is still held (mis-flagged repeat) or
arrives right after its key-up (phantom) — is spurious. We arm on any key that
emits a Backspace; drop its held repeats until the key-up, then drop one
post-release phantom and disarm; any other key ends the window. Removing exactly
one of a run of identical key-downs is always correct because the engine's own
double-key handling is order-independent (`task`→`task`, `ass`→`as`,
`boss`→`boss` via restore) — it doesn't matter whether the dropped press was the
phantom or a real one. The tap now also masks `keyUp` (to see the release). This
is integration-only (needs a real key stream), so it is not unit-tested; the
pure engine keeps composing whatever keys survive the guard. Synthetic events
still post via `tapPostEvent(proxy)` as before (OpenKey does the same).

## `restoreIfInvalid` back ON (after the duplicate-key-down fix)

`AppModel.restoreIfInvalid` defaults **true** ("Tự khôi phục phím với từ sai") —
the "auto-drop the diacritic when the word isn't Vietnamese" behavior: a word
whose composed form is not a legal Vietnamese syllable reverts to raw keys at
commit (`hehe`→hêh→`hehe`, `task`→ták→`task`). It was briefly flipped OFF while
the duplicate-key-down bug above made those revert edits corrupt (`task`→`tassk`);
with that bug fixed it is back on, which — together with `freeMarkAcrossCoda` ON
(the author's "dấu ở cuối" style, `tana`→tân) — gives the OpenKey-like result:
Vietnamese types cleanly, English/informal words stay literal, no doubling.
`EngineConfig.restoreIfInvalid` also defaults **true**, matching.

## Auto-update (Phase 5, no Apple account)

Keystone ships a self-contained auto-updater instead of Sparkle: no Apple
Developer account, no third-party update framework, just GitHub Releases plus
an Ed25519 signature Keystone verifies itself.

**Source: GitHub Releases on `tanhattan0051/Kevstone`, nothing else.** The
updater only ever calls the hardcoded, HTTPS
`https://api.github.com/repos/tanhattan0051/Kevstone/releases/latest`
endpoint, and only ever downloads the two asset URLs *that exact response*
returns — it never follows an update URL from anywhere else (not a web page,
not user input, not a redirect to a different repo). Each release publishes
exactly two assets: `Keystone.zip` (a zipped `Keystone.app`) and
`Keystone.zip.sig` (base64 of the Ed25519 signature of `Keystone.zip`'s raw
bytes). The release tag must be `vMAJOR.MINOR.PATCH` (e.g. `v1.0.1`).

**Mandatory Ed25519 verification before install — no bypass.** An update is
downloaded from the internet and then executed, so signature verification is
the actual security boundary of this feature, not a nice-to-have. The public
key (`MJ8bmdlgJFAYi+M4+Hm3g+phMGDE+lamYdN3DPuiuvA=`, base64, 32 raw bytes) is
embedded in the app. `App/Updater.swift`'s `downloadAndInstall` calls `guard
UpdateVerifier.isValid(zipData:signatureBase64:publicKeyBase64:) else { abort
}` — a `Keystone.zip` that fails verification, or a missing/unreadable
`.sig` asset, is **never** unzipped-into-place or launched; the user sees
"Chữ ký bản cập nhật không hợp lệ — đã huỷ để an toàn" and nothing else
happens. `UpdateVerifier` (`Sources/KeystoneInput/UpdateCheck.swift`) decodes
both base64 inputs defensively and returns `false` on any decode failure
rather than throwing — a malformed signature or key always reads as "not
verified". `Tests/KeystoneInputTests/UpdateCheckTests.swift` proves the gate
actually rejects bad input with a real round-trip: it generates a
`Curve25519.Signing.PrivateKey`, signs bytes, and asserts `isValid` accepts
the genuine (data, signature, public key) triple but rejects tampered data, a
wrong public key, and garbage base64.

**Pure core vs. app-layer glue, same split as the rest of KeystoneInput.**
`Sources/KeystoneInput/UpdateCheck.swift` holds everything unit-testable:
`SemVer` (parses `vMAJOR.MINOR.PATCH`, tolerates a missing leading `v` and a
pre-release/build suffix, `Comparable` by (major, minor, patch));
`ReleaseInfo.parse(latestReleaseJSON:)` (decodes the GitHub API JSON,
requiring both assets, a parseable tag, and `https://` asset URLs — anything
else, including JSON that doesn't even parse, returns `nil` rather than
crashing); `UpdateVerifier.isValid` (the signature gate above); and
`UpdateCheck.shouldOffer(currentVersion:release:)` (a `currentVersion` that
fails to parse is treated as "don't offer" — safer than assuming every
release is newer than a version we couldn't even read). `App/Updater.swift`
(`@MainActor final class Updater`, singleton `shared`) is the integration
glue on top — `URLSession` fetches, `NSAlert` prompts, `Process` calls — and
is not unit-tested headless, same reasoning as the CGEventTap itself.

**Install: strip quarantine, then swap the bundle via a wait-for-exit
relaunch helper.** Once the zip is verified, `Updater` writes it to a temp
dir, extracts with `ditto -x -k` (via `Process`, failures surfaced, never
swallowed), locates `Keystone.app` inside, and runs `xattr -dr
com.apple.quarantine` on it. A running app bundle can't overwrite itself, so
`Updater` writes a small shell script to a temp file that (a) polls `kill -0
<pid>` until this process has exited, (b) `rm -rf` the current bundle path
(`Bundle.main.bundleURL`), (c) `ditto`s the verified new app into place, (d)
`open`s it — launches that script detached via `Process`, then calls
`AppModel.shared.quit()`. Every path is quoted with POSIX single-quote
escaping before going into the script, even though these come from
`Bundle.main`/the verified zip rather than attacker input.

**Current version from `CFBundleShortVersionString`; dev builds skip
auto-install.** `checkForUpdates(userInitiated:)` reads
`Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")`; a
`swift run` build has no meaningful value there, so a missing/unparseable
version silently returns for a background check and shows "Đang chạy bản dev
(swift run) — không kiểm tra cập nhật được" for a user-initiated one — either
way, no network call and no install ever happens for a dev build. A silent
background check (`checkForUpdates(userInitiated: false)`) is kicked off
from `AppModel.bootstrap()` when the persisted "Kiểm tra bản mới khi khởi
động" toggle is on; network/parse errors are logged and swallowed rather than
surfaced, so a flaky connection at launch never nags the user. The "Kiểm tra
bản mới" button in the About pane calls the same entry point with
`userInitiated: true`, surfacing every outcome (error, already up to date,
or the update prompt) as an alert.

**The Ed25519 private key never enters the repo.** It's kept at
`~/.config/keystone/ed25519_private.b64` on the machine that cuts releases
and is used only by the release tooling that signs `Keystone.zip` before
uploading it as a GitHub Release asset — the app only ever embeds and uses
the matching *public* key.

**Standing limitation: still one Gatekeeper prompt, and Accessibility may
need re-granting.** Without Apple notarization, the very first manual
install of Keystone.app still triggers Gatekeeper's "unidentified developer"
prompt once, exactly like today. And unless the app is signed with a stable
self-signed certificate, macOS may treat the swapped-in bundle as a
different app for TCC purposes, so Accessibility (and Input Monitoring) can
require re-granting after an update — the same class of issue
`AppModel.needsRelaunch` already surfaces for a fresh Accessibility grant.
