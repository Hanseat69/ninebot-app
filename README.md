# NinebotApp — bauen ohne Mac

Dieses Repo enthält eine iOS-App (SwiftUI + CoreBluetooth) für den
**Segway-Ninebot F2 Pro** (und andere Ninebot-Scooter der F-Serie). Sie wird über
GitHub Actions automatisch zu einer `.ipa`-Datei gebaut, ohne dass du selbst
einen Mac oder Xcode brauchst.

## Einmalige Einrichtung

1. **Lege ein neues GitHub-Repository an** (z. B. `ninebot-app`), öffentlich
   oder privat ist egal — privat funktioniert mit GitHub Actions genauso gut.
2. **Lade den gesamten Ordner** in dieses Repository hoch (über die
   GitHub-Website: „Add file“ → „Upload files“, den gesamten Inhalt dieses
   Ordners hineinziehen — inklusive des versteckten Ordners `.github`), oder
   per git:
   ```
   git init
   git remote add origin https://github.com/<dein-benutzername>/ninebot-app.git
   git add .
   git commit -m "Initial commit"
   git push -u origin main
   ```

## Jedes Mal, wenn du einen Build willst

1. Gehe zu deinem Repository auf GitHub → Tab **Actions**
2. Wähle links in der Liste den Workflow **„Build unsigned IPA“**
3. Klicke **„Run workflow“** → **„Run workflow“** (grüner Knopf)
4. Warte 3–5 Minuten, bis der grüne Haken erscheint
5. Klicke auf den fertigen Lauf → unten bei **Artifacts** steht
   `NinebotApp-unsigned-ipa` → herunterladen (eine ZIP-Datei mit der `.ipa`)
6. ZIP entpacken → du hast jetzt `NinebotApp-unsigned.ipa`

Das passiert auch automatisch bei jedem `git push` auf den `main`-Branch —
sobald du Code änderst und pushst, steht ein neuer Build bereit.

## Auf dem iPhone installieren (mit Sideloadly)

1. **Sideloadly** herunterladen und installieren (kostenlos, Windows und
   macOS): https://sideloadly.io
2. iPhone per Kabel anschließen
3. Sideloadly öffnen, `NinebotApp-unsigned.ipa` ins Fenster ziehen
4. Deine **Apple-ID** eingeben (ein normales, kostenloses Konto reicht)
5. **Start** klicken — Sideloadly signiert die App mit deiner Apple-ID und
   installiert sie auf dem iPhone
6. Beim ersten Mal auf dem iPhone: **Einstellungen → Allgemein → VPN und
   Geräteverwaltung** → deine Apple-ID unter „Entwickler-App“ → **Vertrauen**
7. Die App liegt jetzt als Symbol auf deinem Home-Bildschirm

**Hinweis:** Mit einer kostenlosen Apple-ID läuft die Installation nach 7
Tagen ab — dann wiederholst du einfach Schritt 3–6 mit derselben `.ipa` (kein
neuer Build nötig, außer du hast den Code geändert).

## Was steckt in der App

**Tab „Scooter“**
1. **Scooter suchen und verbinden:** Die App findet Ninebot-Scooter anhand der
   Herstellerkennung. Beim ersten Verbinden den **Power-Knopf** am Scooter kurz
   drücken, wenn die App dazu auffordert.
2. **Automatisch verbinden:** Danach merkt sich die App den Scooter und
   verbindet sich beim Einschalten von selbst — auch im Hintergrund.
3. **Live-Werte** (alle 5 Sekunden): Akku, Restreichweite, Spannung, Strom,
   Strecke und Zeit seit dem Einschalten, Gesamtkilometer, GPS-Geschwindigkeit.
4. **Einstellungen:** Tempolimit im Begrenzungsmodus (6–20 km/h),
   Rekuperation (KERS), Tempomat, Rücklicht.
5. **Fahrzeug:** Akkuzustand und -temperatur, Fahrzeugtemperatur, Fahrmodus,
   Tempolimits, Sperrstatus, Fehlercode, Firmware, Seriennummer.

**Tab „Fahrten“ — automatisches Fahrtenbuch**
Solange der Scooter verbunden ist, wird die Fahrt aufgezeichnet; beim
Ausschalten wird sie gespeichert (ab 1 Minute und 100 m): Datum, Abfahrt,
Ankunft, Dauer, Strecke (laut Scooter und GPS), Ø- und Höchstgeschwindigkeit,
Akku vorher/nachher, Verbrauch, Start- und Zieladresse, Karte der Strecke.
Export als **GPX-Datei** (für Komoot, Strava, Google Earth …).

**Tab „Akku“**
Verlauf des Akkuzustands und Verbrauch pro Fahrt (% pro km).

Der Regler für das Tempolimit endet bewusst bei 20 km/h, dem gesetzlichen
Maximum für E-Scooter in Deutschland (eKFV).

### Datenschutz

- Fahrten, Akku-Verlauf und der gemerkte Scooter werden **nur auf dem iPhone**
  gespeichert (Dokumente-Ordner der App bzw. App-Einstellungen).
- Die App enthält keine Fremdbibliotheken, keine Werbung und keine Analyse.
- Einzige Internetverbindungen: **Apple Karten** — Kartenkacheln für die
  Streckenansicht und die Umwandlung von Start/Ziel in Adressen. Dabei gehen die
  jeweiligen Koordinaten an Apple, sonst an niemanden.
- Berechtigungen: Bluetooth und Standort (für die Aufzeichnung im Hintergrund:
  „Immer“).

### Grundlage und Stand

Protokoll, Verschlüsselung und Register folgen den Open-Source-Projekten
[ninebot-ble](https://github.com/ownbee/ninebot-ble) (entwickelt an einem
Ninebot der F-Serie) und [miauth](https://github.com/dnandha/miauth).
Die Verschlüsselung ist mit Testvektoren aus miauth geprüft und liefert
Byte für Byte dasselbe Ergebnis. An einem echten F2 Pro getestet ist die App
noch nicht. Das **Schreiben** der Einstellungen ist in der Referenz nicht
enthalten (dort wird nur gelesen) — nach jeder Änderung liest die App den Wert
zur Kontrolle erneut aus.

Nur mit dem eigenen Fahrzeug verwenden.
