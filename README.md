# Italiano

An iOS app for practising Italian verbs, for German speakers. It's a native SwiftUI port of
the HTML prototype in [`prototype/index.html`](prototype/index.html).

It has two exercises:

- **Coniugazione**: type the conjugated form of a verb in one of 7 tenses (Presente,
  Passato prossimo, Imperfetto, Futuro, Condizionale, Congiuntivo, Imperativo). Prompts
  show the Italian infinitive, the German form, or a mix. Wrong answers come back in
  repeat rounds. Mastery (0–10) is tracked per verb and tense. A verb's ring shows its level in the
  selected tenses, and a long press shows every tense. Weaker verb/tense pairs come up more often.
  Where the answer depends on the subject's gender (Passato prossimo with essere: sono arrivato /
  arrivata), an italic *m* or *f* next to the pronoun says which form is wanted.
- **Essere o avere?**: pick the right auxiliary form for the Passato prossimo.

Tap a tense name to see how that tense is formed and used, including spelling traps like viaggiare → viaggerò. Tap a verb to see what it means and its own spelling notes.
Settings and progress are saved on the device.

## Run it on your iPhone

You need a Mac with Xcode 26 or newer and an iPhone on iOS 26 or newer. A free Apple ID is enough.

1. Open `Italiano.xcodeproj` in Xcode.
2. The development team is already set to your account. On another account, select the **Italiano** target, go to **Signing & Capabilities**, and choose your Apple ID
   under *Team* (*Add an Account…* if it isn't listed). If Xcode complains about the bundle
   identifier, change `com.larserbach.italiano` to something unique.
3. Connect your iPhone by cable, choose it as the run destination at the top, and press ⌘R.
4. The first time, turn on **Settings → Privacy & Security → Developer Mode** on the iPhone.
   Then trust your developer profile under **Settings → General → VPN & Device Management**.

With a free Apple ID the app stops launching after 7 days, and you have to press ⌘R again.
A paid Apple Developer Program membership removes that limit. It also lets you install the
app through TestFlight.

## Project layout

| Path | Contents |
| --- | --- |
| `Italiano/Model` | Verb data, conjugation rules, lesson and quiz logic, saved progress |
| `Italiano/Views` | SwiftUI screens |
| `ItalianoTests` | Unit tests, including a check that every derived form matches the prototype |
| `tools/` | Scripts that generate `VerbCatalog.swift`, `TenseInfo+Content.swift` and the test fixture from the prototype |

To add verbs, add them to the prototype and run `python3 tools/generate-swift-data.py`
(this needs Node). You can also edit `Italiano/Model/VerbCatalog.swift` directly. The
Passato prossimo, Condizionale, Congiuntivo and Imperativo forms are derived automatically.
