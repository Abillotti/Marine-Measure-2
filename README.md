# MarineMeasure 2.0

Measure a blue crab (or 17 other species) with your iPhone camera, find out instantly whether it's legal to keep where you're standing, and build a personal catch journal plus a community map of crab sizes along the coast.

Rebuilt from Anthony Billotti's MATES research: the Junior Research Project ("Catch or Release"), the New Jersey Southern Research Project, and the Senior Capstone (MarineMeasure).

---

## What's in the app

| Tab | What it does |
|---|---|
| **Scan** | Shows your state, today's rules and whether the season is open. Scan with the camera (AR) or type a size from a gauge. |
| **Journal** | Your personal database: every catch with photo, size, verdict, location and notes. Filter, search, edit, delete, and export to CSV. |
| **Species** | A collectible species journal (18 species). Each page has your stats, ID tips, a how-to-measure diagram, the blue crab sex guide, and the rules for every state on file. |
| **Community** | Everyone's shared scans (Firebase): map of average size by area, size histogram with your state's minimum, % legal, sex ratio, monthly trend, table by county. |
| **Profile** | Totals, 22 badges, the **Accuracy Lab** (app vs. gauge percent error, like the original caliper study, with optional calibration) and Settings. |

**How a scan works**

1. Lay the catch flat (cooler lid, dock board). Hold the phone 25–60 cm (10–24 in) above it until the ring turns green ("Ready").
2. Tap the shutter. The photo freezes; drag the two yellow markers to the spine tips (a magnifier appears while you drag; tap anywhere to move the nearest marker there).
3. MarineMeasure computes the real length from the AR camera geometry:
   - **LiDAR iPhones (Pro models):** uses the measured depth of the catch next to each marker.
   - **Other iPhones:** intersects the camera rays with the detected surface, corrected for how high the spine tips sit above the table (otherwise a crab reads about 4–6% too long).
   - Every measurement carries an error margin. If a legal limit falls inside it, the verdict is **"Too close to call — check with a gauge."**
4. The rule engine checks size (by shell stage and sex), season, region, and egg-bearing/female rules for your state, then you record whether you kept or released it.

## Run it on your iPhone

You need a Mac with **Xcode 16 or newer** (use the latest from the Mac App Store), an iPhone on **iOS 17 or newer**, and a cable. A free Apple ID works.

1. **Unzip** `MarineMeasure.zip` and double-click `MarineMeasure.xcodeproj`.
2. In the left sidebar click the blue **MarineMeasure** project → target **MarineMeasure** → **Signing & Capabilities**.
   - Check **Automatically manage signing**.
   - **Team:** pick your name (Personal Team). If it isn't there: Xcode › Settings › Accounts › **+** › Apple ID.
   - If Xcode says the bundle identifier is taken, change `com.anthonybillotti.MarineMeasure` to something unique, e.g. `com.yourname.marinemeasure`.
3. **Plug in your iPhone**, unlock it, and tap **Trust This Computer**.
4. **Turn on Developer Mode** on the iPhone: Settings › Privacy & Security › **Developer Mode** › On, then restart when asked. (The switch appears after the phone has been connected to Xcode once.)
5. In Xcode's toolbar, choose your iPhone as the run destination (top center) and press **Run ▶︎** (⌘R). The first build takes a minute.
6. First launch with a free Apple ID: if the iPhone says "Untrusted Developer", go to Settings › General › **VPN & Device Management** › your Apple ID › **Trust**, then open the app again.
7. Allow **Camera** and **Location** when asked.

Notes
- Free Apple ID builds expire after **7 days**; just press Run again to reinstall (your journal is kept).
- After the first cable run you can go wireless: Window › Devices and Simulators › your iPhone › **Connect via network**.
- The **Simulator** can run everything except the AR camera (use "Enter a size"). Set a fake location with Features › Location › Custom Location (e.g. 26.08, -80.24 for Davie, FL).

## Testing checklist

- **Accuracy:** Settings › Developer › turn on **Flat-object test mode**, then measure a credit card's long side (3.37 in / 85.6 mm) or a ruler a few times from different heights. Turn it off again for real catches.
- **Rules:** on the Scan tab tap the pin to switch states (NJ, MD, VA, FL...), then use "Enter a size from a gauge" to try sizes right at the limits, different shells (hard/peeler/soft) and sexes (Maryland bans recreational females; Virginia exempts mature females; Florida has no blue crab minimum).
- **Accuracy Lab:** after a camera scan, type the gauge reading on the result screen. After 3+ comparisons per method you'll get a percent error, bias, 95% CI and an optional calibration factor.
- **Community:** Settings › Developer › **Sample community data** shows the dashboard with clearly-labeled fake data before Firebase is set up.

## Community database (Firebase, free tier)

The app talks to Cloud Firestore over its REST API, so there are no packages to install.

1. Go to [console.firebase.google.com](https://console.firebase.google.com) and create a project (or reuse your old MarineMeasure project).
2. **Build › Authentication › Get started › Sign-in method › Anonymous › Enable.**
3. **Build › Firestore Database › Create database** (production mode, a US region).
4. **Firestore › Rules:** paste `firebase/firestore.rules` and **Publish**.
5. **Firestore › Indexes › Composite › Add index:** collection `scans`, fields `species` Ascending, `takenAt` Descending. (Or skip this; the app shows a one-tap link to create it the first time it's needed.)
6. **Project settings (gear) › General:** copy the **Project ID** and **Web API key**. (If no Web API key is shown, enabling Authentication creates one.)
7. Paste them into `MarineMeasure/App/AppConfig.swift` (so every copy of your app shares the database) or into the app's Settings › Community database.
8. In the app: Settings › **Test connection**.

Privacy: sharing is opt-in, anonymous (an anonymous Firebase user ID), and locations are rounded to about 1 km before upload. Users can remove their shared scans from the journal. With the Firebase CLI you can instead run `firebase deploy --only firestore` from the `firebase/` folder.

## Updating the regulations

All rules live in `MarineMeasure/Resources/Regulations.json` (37 rules, 16 states, verified Oct 12, 2026, with a source link on every rule). To fix or add one:

- Edit the JSON and rebuild, **or**
- Put the edited file somewhere public (for example your GitHub repo) and paste its raw URL into Settings › Regulations › **Check for rule updates**. The app keeps the newer copy (it must have a later `dataVersion`).

Rule format, briefly:

```json
{
  "species": "blue_crab", "state": "NJ", "lastVerified": "2026-10-12",
  "sourceName": "...", "sourceURL": "https://...",
  "sizeLimits": [ { "min": 4.5, "shells": ["hard"], "note": "hard shell" } ],
  "openSeasons": [ { "start": "05-01", "end": "11-30" } ],
  "prohibitions": [ { "condition": "eggBearing", "message": "..." } ],
  "bagLimit": "1 bushel per person per day",
  "regions": [ { "id": "md_bay", "name": "...", "counties": ["Anne Arundel"] } ]
}
```

Size limits can also use `max`, `minInclusive`/`maxInclusive`, `sexes` (`unknown`, `male`, `immatureFemale`, `matureFemale`, `eggBearing`), `regions`, `start`/`end` dates (MM-DD, may wrap past New Year) and `overMaxNote`. Prohibition conditions: `always`, `eggBearing`, `darkSponge`, `female`, `immatureFemale`, `matureFemale`.

**Coverage:** blue crab rules for NJ, NY, CT, DE, MD, VA, NC, SC, GA, FL, AL, MS, LA and TX; New Jersey rules for summer flounder, black sea bass, striped bass, bluefish, tautog, winter flounder, scup, weakfish and rainbow trout; Florida rules for red drum, spotted seatrout, snook, sheepshead, gray snapper, flounder, spiny lobster and stone crab; North Carolina rules for red drum, seatrout, sheepshead, black sea bass and bluefish. Anything else shows "No rules on file" with a link to that state's agency.

Rules change often (season dates are set every year). The app is a guide; the official regulations are what count.

## Optional: AI sex identification

Your capstone trained a model on ~5,000 claw photos. To bring that into the app without any code:

1. Open **Create ML** (Xcode › Open Developer Tool › Create ML) › new **Image Classification** project.
2. Training data: a folder with subfolders named `male` and `female` (and optionally `sponge`) full of photos.
3. Train, then export the model as **`CrabSexClassifier.mlmodel`** and drag it into the Xcode project (check "MarineMeasure" under Add to targets).

The result screen will then show "AI: female 87%" as a one-tap suggestion for blue crabs. Without the model, the guided apron diagrams are used.

## Project layout

```
MarineMeasure.xcodeproj
MarineMeasure/
  App/          app entry, tab bar, theme, settings keys, AppConfig (Firebase)
  Models/       SwiftData CatchRecord, species + regulations models, RuleEngine,
                badges, community stats, Accuracy Lab math
  Measurement/  ARKit camera + capture, measurement geometry, marker editor,
                Vision helpers, the scan flow
  Services/     location + reverse geocoding, Firestore REST client, Keychain,
                CSV export, sample data
  Views/        Home, Scan result, Journal, Species, Community, Profile, Onboarding
  Resources/    Species.json, Regulations.json, Assets (icon)
firebase/       firestore.rules, firestore.indexes.json, firebase.json
```

Tech: SwiftUI, SwiftData, ARKit (+ LiDAR scene depth), Vision, Swift Charts, MapKit, CoreLocation. iOS 17+, iPhone, portrait. No third-party packages.

## Troubleshooting

- **"Signing for MarineMeasure requires a development team"** → step 2 above.
- **"Failed to register bundle identifier"** → change the bundle identifier (step 2).
- **"Developer Mode disabled"** → step 4.
- **"iPhone is not available / unsupported OS"** → update Xcode, or in Xcode › Settings › Components download the iOS platform for your phone's iOS version.
- **Ring never turns green** → more light, a surface with some texture (plain white tables are hard), move the phone slowly side to side.
- **Community tab: index error** → tap "Create the Firestore index", save, wait a minute, pull to refresh.
- **Compile error after an Xcode update** → Xcode shows the line; most fixes are one-word renames. Send the message and file name to Claude.
