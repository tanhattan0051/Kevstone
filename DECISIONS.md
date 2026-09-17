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

Bounds added to protect common English words (from the full Telex sweep):
- **Circumflex targets only the current (trailing) nucleus** — no consonant
  between the vowel and the buffer end — so `mama`/`nana`/`nono` stay literal
  while `roiof`→rồi, `toio`→tôi (mark within one vowel run) still work.
- **đ fires only on an adjacent `dd` or a closed syllable** (a coda already
  exists): `ddang`/`dangd`→đang, but `dad`/`did`/`deed` stay English. The
  rarer mid-word trigger `dadng` is dropped as the cost of that protection.
- Note: `w` after a vowel and adjacent `oo`→ô are standard Telex (Vietnamese
  keys), so `cow`→cơ, `moon`→môn are correct, not bugs.

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
