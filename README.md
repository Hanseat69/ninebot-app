# Scooterbrise — iOS-App für den Segway-Ninebot F2 Pro

**Scooterbrise** ist eine iOS-App (SwiftUI + CoreBluetooth) für den
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
   `Scooterbrise-ipa` → herunterladen (eine ZIP-Datei mit der `.ipa`)
6. ZIP entpacken → du hast jetzt `Scooterbrise.ipa`

Das passiert auch automatisch bei jedem `git push` auf den `main`-Branch —
sobald du Code änderst und pushst, steht ein neuer Build bereit.

## Auf dem iPhone installieren (mit Sideloadly)

1. **Sideloadly** herunterladen und installieren (kostenlos, Windows und
   macOS): https://sideloadly.io
2. iPhone per Kabel anschließen
3. Sideloadly öffnen, `Scooterbrise.ipa` ins Fenster ziehen
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
- Scooter suchen und koppeln (beim ersten Mal den **Startknopf** am Scooter
  kurz drücken); danach **verbindet sich die App beim Einschalten von selbst**,
  auch im Hintergrund.
- **Live-Werte** alle 5 Sekunden (Akku, Reichweite, Spannung, Strom, Strecke,
  Zeit, Kilometerstand, GPS-Tempo), **Fahrzeugdaten** inkl. Fehlercode mit
  Erklärung.
- **Einstellungen:** Tempolimit im Begrenzungsmodus (6–20 km/h),
  Rekuperation, Tempomat, Rücklicht.
- **Wetter** (optional, Open-Meteo) mit Hinweisen zu Glätte, Wind und Regen.
- **Wartung** nach dem Original-Wartungsplan von Ninebot, mit Erinnerungen.
- **Dokumente:** Versicherungsbestätigung, Betriebserlaubnis/Datenbestätigung,
  Kaufbeleg — per Kamera-Scan, aus Fotos oder als PDF. **Face-ID-geschützt**,
  verschlüsselt gespeichert, austauschbar mit Archiv, Erinnerung vor Ablauf
  des Versicherungsjahres (Ende Februar), als PDF teilbar.
- **Sperrbildschirm und Dynamic Island:** Tempo, Akku, Strecke, Fahrzeit.

**Tab „Route“** — Ziel suchen, Route mit der Restreichweite abgleichen
(inkl. Kälteabschlag), Navigation in Apple Maps. Fahrradrouten in der App ab
iOS 26, sonst Fußwegroute als Näherung.

**Tab „Fahrten“ — automatisches Fahrtenbuch**
Datum, Abfahrt, Ankunft, Dauer, Strecke (Scooter und GPS), Ø-/Höchsttempo,
Akku vorher/nachher, Verbrauch, Start-/Zieladresse, Wetter, Karte **nach
Tempo eingefärbt**. Export als **GPX** und **CSV** (Excel).

**Tab „Akku“** — Verlauf des Akkuzustands, Verbrauch pro Fahrt.

**Tab „Hilfe“** — die **deutschen Seiten des Produkt-Handbuchs als PDF**,
dazu Kurzfassungen: Bedienung und Fahrmodi, technische Daten F2 Pro, Laden
und Reifendruck, Fehlercodes (durchsuchbar), Wartungsplan, Anleitung zur App.
Alles offline verfügbar.

Der Regler für das Tempolimit endet bewusst bei 20 km/h, dem gesetzlichen
Maximum für E-Scooter in Deutschland (eKFV).

### Datenschutz

- Fahrten, Akku-Verlauf, Wartung, Dokumente und der gemerkte Scooter werden
  **nur auf dem iPhone** gespeichert. Dokumente zusätzlich mit iOS-Dateischutz
  (verschlüsselt, solange das iPhone gesperrt ist) und optional Face ID.
- Keine Fremdbibliotheken, kein Konto, keine Werbung, keine Analyse.
- Internetverbindungen: **Apple Karten** (Karten, Adressen, Zielsuche,
  Routen) und — nur wenn eingeschaltet — **Open-Meteo** für das Wetter, mit
  auf ca. 1 km gerundetem Standort.
- Berechtigungen: Bluetooth, Standort („Immer“ für die Automatik),
  Mitteilungen (Wartung, Versicherung), Kamera (Dokumente scannen), Face ID.

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
