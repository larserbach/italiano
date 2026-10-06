# Italiano

An iOS app for practising Italian verbs, for German speakers, written in SwiftUI.

It has two exercises. Irregular verbs work in both, and the conjugation exercise has statistics:

- **Coniugazione**: type the conjugated form of a verb in one of 7 tenses (Presente,
  Passato prossimo, Imperfetto, Futuro, Condizionale, Congiuntivo, Imperativo). Prompts
  show the German form, with the Italian infinitive and the tense underneath. Wrong answers come back in
  repeat rounds. Mastery (0–10) is tracked per verb and tense. A verb's ring shows its level in the
  selected tenses, and a long press shows every tense. Weaker verb/tense pairs come up more often.
  Where the answer depends on the subject's gender (Passato prossimo with essere: sono arrivato /
  arrivata), an italic *m* or *f* next to the pronoun says which form is wanted.
- **Essere o avere?**: pick the right auxiliary form for the Passato prossimo. Mistakes
  come back in repeat rounds too, and mastery per verb counts first attempts only.
- **Irregular verbs**: the 30 most frequent ones (essere, avere, fare, andare, …) form their own
  "Unregelmäßig" group in the verb pickers. Their forms are spelled out in
  `Italiano/Model/IrregularVerbCatalog.swift`; only Condizionale and Passato prossimo are derived.
  potere, dovere, volere and piacere have no imperative cards, and fa'/fai, va'/vai, da'/dai and
  sta'/stai are both accepted.
- **Statistik** (chart button on the Coniugazione page): an overview across all tenses, then correct answers vs. mistakes per tense
  over 3 or 14 days, 3, 6 or 12 months, or everything, broken down by verb type, with each tense's
  most frequent mistakes. Only first attempts count.

Tap a tense name to see how that tense is formed and used, including spelling traps like viaggiare → viaggerò. Tap a verb to see what it means, its spelling notes and a conjugation table for every tense.
A one-time hint explains the verb rings; the settings screen (gear on the home screen) shows such hints again.
The same screen can reset all progress (levels, statistics and the red mistake marks) after a confirmation. Exercise settings stay.
Settings and progress are saved on the device. A fresh install starts the Coniugazione page with only parlare, Presente indicativo and 5 questions selected.

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
| `ItalianoTests` | Unit tests, including a check that every derived form matches the fixture `verb-forms.json` |

To add regular verbs, add a `VerbSeed` to `Italiano/Model/VerbCatalog.swift` and list it in the matching group, then add its expected forms to `ItalianoTests/verb-forms.json`.
The Passato prossimo, Condizionale, Congiuntivo and Imperativo forms are derived automatically.
Irregular verbs are added by hand in `Italiano/Model/IrregularVerbCatalog.swift`.
