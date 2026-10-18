# Markdown Tree (iOS)

Eine schlanke iOS-/iPadOS-App, um einen Ordner – konkret den **Cowork-OS-Ordner in iCloud Drive** – als Baum zu durchstöbern und alle Markdown-Dateien darin zu lesen.

## Funktionen

- **Ordner einmal auswählen** – die App merkt sich den Zugriff (Security-Scoped Bookmark) und öffnet ihn beim nächsten Start direkt wieder.
- **Baumansicht** mit aufklappbaren Ordnern; der Aufklapp-Zustand bleibt erhalten. Ordner lassen sich per Wischgeste oder Kontextmenü auch einzeln öffnen.
- **Markdown-Ansicht** mit GitHub-Flavored Markdown (Tabellen, Aufgabenlisten, Code-Blöcke), Dark Mode und einstellbarer Schriftgröße. YAML-Front-Matter erscheint als einklappbarer „Metadaten“-Block.
- **Links folgen**: relative Links (`[Plan](../Projekte/Plan.md)`), Links ohne Endung, Obsidian-Wiki-Links (`[[Notiz]]`, `[[Notiz|Alias]]`), Sprungmarken (`#abschnitt`) und relative Bilder funktionieren innerhalb der App; Web-Links öffnen in Safari.
- **Suche** nach Dateinamen oder im Inhalt – im ganzen Ordner oder nur im aktuell geöffneten Unterordner.
- **Angeheftet & Zuletzt geöffnet** auf der Startseite für schnellen Zugriff (z. B. auf `TASKS.md`).
- **iCloud-tauglich**: Noch nicht heruntergeladene Dateien werden mit Wolken-Symbol angezeigt und beim Öffnen automatisch geladen. Beim Zurückkehren in die App wird alles neu eingelesen.
- **Nur lesend** – die App verändert keine Dateien. Quelltext-Ansicht und „Text teilen“ sind im Menü.

## Bauen & installieren

Voraussetzungen: Mac mit **Xcode 16 oder neuer**, iPhone/iPad mit **iOS 17 oder neuer**.

1. `MarkdownTree.xcodeproj` in Xcode öffnen.
2. Target **MarkdownTree** → *Signing & Capabilities* → dein Team auswählen (ein kostenloser Apple-Account reicht; die Bundle-ID `org.christophschneider.markdowntree` ggf. anpassen).
3. Gerät auswählen und **Run** (⌘R).
4. In der App „Ordner auswählen“ → *iCloud Drive* → *Cowork OS* öffnen → „Öffnen“.

Es wird keine iCloud-Capability benötigt: Der Zugriff läuft über die Dateiauswahl von iOS, die der App eine dauerhafte Berechtigung für genau diesen Ordner gibt.

## Aufbau

```
MarkdownTree/
├── App/MarkdownTreeApp.swift        Einstiegspunkt
├── Model/
│   ├── Library.swift                Root-Ordner, Cache, Favoriten, Suche, Wiki-Link-Auflösung
│   ├── FileSystem.swift             Ordner lesen, iCloud-Downloads, Volltextsuche
│   ├── FileItem.swift               Datei-/Ordner-Modell und Pfadlogik
│   └── MarkdownPreprocessor.swift   Front-Matter & [[Wiki-Links]]
├── Views/                           RootView, FolderView (Baum + Suche), DocumentView
├── Web/                             WKWebView-Renderer und mdfile://-Handler für Bilder
└── Resources/                       marked.js (MIT), render.js, style.css
```

Das Projekt nutzt Xcode-„synchronisierte Ordner“: neue Dateien in `MarkdownTree/` landen automatisch im Target. Ein GitHub-Actions-Workflow baut die App bei jedem Push für den Simulator.

Markdown-Rendering: [marked](https://github.com/markedjs/marked) v15.0.12, MIT-Lizenz (siehe `THIRD_PARTY_LICENSE_marked.md`).
