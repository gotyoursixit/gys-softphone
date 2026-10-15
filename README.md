# Got Your Six Softphone

Softphone-apps voor **Android** en **iPhone**, gemaakt door [Got Your Six](https://gotyoursix.nl) voor klanten die bij ons telefonie afnemen. De apps werken met onze telefooncentrale (FusionPBX/FreeSWITCH) en onze beheerserver. Inloggen gaat met `toestel@domein`.

Deze repository bevat de volledige broncode van beide apps, zoals de **GNU General Public License versie 3** vraagt (de apps gebruiken de Linphone SDK, die onder GPLv3 valt). Hij wordt bijgewerkt bij nieuwe versies.

## Wat er in staat

| Map | Wat |
|---|---|
| `app/` | Android-app (Kotlin, Linphone SDK 5.4) |
| `ios/` | iPhone-app (Swift 6 + SwiftUI, Linphone SDK 5.4 via Swift Package Manager, iOS 17+) |
| `gradle/`, `build.gradle.kts`, `settings.gradle.kts`, `gradlew` | Bouwen van de Android-app |
| `tools/` | Hulpscripts (iconen, Android-toolchain op Windows) |

## Functies

- Bellen en gebeld worden, met dempen, toetsen (DTMF), luidspreker en ophangen.
- Wacht en doorverbinden: direct of na overleg (Annuleer / Wissel / Verbind door).
- Wisselgesprek.
- Collega's met live status (via de beheerserver), contacten van de telefoon en naamherkenning van bellers.
- Gesprekshistorie.
- Logboek met **Verbinding testen** (DNS en SIP OPTIONS over UDP/TCP/TLS).
- Thema's: Zakelijk (Got Your Six), LCARS en Star Wars-stijl.

## Bouwen

**Android:** JDK 17 en de Android SDK (op Windows: `tools/setup-toolchain.ps1`). Zet in `local.properties` het pad `sdk.dir=...` en bouw met `./gradlew assembleRelease`. Zonder eigen `keystore.properties` en `release.jks` wordt de app met een debug-sleutel ondertekend.

**iPhone:** Xcode 26 of nieuwer. Open `ios/Softphone.xcodeproj`, kies een simulator of iPhone en druk op ▶. Xcode haalt de Linphone SDK zelf op. Om op een echte iPhone te installeren, stelt u bij *Signing & Capabilities* uw eigen team en bundle-ID in.

## Licentie

Copyright © Got Your Six.

Deze programma's zijn vrije software: u mag ze verspreiden en/of aanpassen onder de voorwaarden van de GNU General Public License, versie 3, zoals gepubliceerd door de Free Software Foundation. Ze worden verspreid in de hoop dat ze nuttig zijn, maar **zonder enige garantie**. Zie [`LICENSE`](LICENSE).

Onderdelen van anderen:
- **Linphone SDK**: Belledonne Communications, GPLv3 ([linphone.org](https://www.linphone.org)).
- **Lettertypes** Poppins, Antonio, Orbitron en Exo 2: SIL Open Font License 1.1. Zie `ios/Softphone/Fonts/OFL.txt` en `app/src/main/assets/OFL.txt`.
- **Iconen**: Material Icons van Google, Apache License 2.0.

Merknamen (Got Your Six, Star Trek, Star Wars) vallen niet onder deze licentie. De thema's "LCARS" en "Star Wars-stijl" zijn eigen ontwerpen, zonder officiële logo's of lettertypes.

## Contact

Vragen of problemen: [support@gotyoursix.nl](mailto:support@gotyoursix.nl). Privacy: [bellen.gys-voip.nl/privacy.html](https://bellen.gys-voip.nl/privacy.html).
