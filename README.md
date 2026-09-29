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

1. **Scooter suchen:** Die App findet Ninebot-Scooter in der Nähe anhand der
   Ninebot-Herstellerkennung in der Bluetooth-Werbung. Ein fester Gerätename
   ist nicht nötig — einfach den eigenen Scooter in der Liste antippen.
2. **Koppeln:** Beim ersten Verbinden fordert die App auf, den **Power-Knopf**
   am Scooter kurz zu drücken (60 Sekunden Zeit).
3. **Werte:** Akku (%, Spannung, Strom, Temperatur, Zustand), Restreichweite,
   Gesamtkilometer, Fahrzeugtemperatur, Fahrmodus, Tempolimits, Sperrstatus,
   Fehlercode, Firmware und Seriennummer.
4. **Tempolimit (Begrenzungsmodus):** Setzt die Höchstgeschwindigkeit im
   Begrenzungsmodus (6–20 km/h). Der Regler endet bewusst bei 20 km/h, dem
   gesetzlichen Maximum für E-Scooter in Deutschland (eKFV).

### Grundlage und Stand

Protokoll, Verschlüsselung und Register folgen den Open-Source-Projekten
[ninebot-ble](https://github.com/ownbee/ninebot-ble) (entwickelt an einem
Ninebot der F-Serie) und [miauth](https://github.com/dnandha/miauth).
Die Verschlüsselung ist mit Testvektoren aus miauth geprüft und liefert
Byte für Byte dasselbe Ergebnis. An einem echten F2 Pro getestet ist die App
noch nicht. Das **Schreiben** des Tempolimits ist in der Referenz nicht
enthalten (dort wird nur gelesen) — nach dem Setzen liest die App den Wert
zur Kontrolle erneut aus.

Nur mit dem eigenen Fahrzeug verwenden.
