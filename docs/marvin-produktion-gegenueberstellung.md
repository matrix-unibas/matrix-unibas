# MARVIN: Optionen für Production

| Thema | Option A | Option B | Tendenz für MARVIN |
|---|---|---|---|
| **Login** | **IDM/OIDC** (MAS + Switch edu-ID): zentrale Accounts, SSO, Offboarding automatisch, MFA vom IdP geerbt. Die sauberere Lösung, aber mit spürbarem Aufwand: MAS-Setup plus Anbindung an Switch edu-ID. | **Tokens/lokale Accounts** (Registration-Tokens, Passwort): schnell aufgesetzt, unabhängig von Switch. Dafür eigenes Account-Lifecycle-Management, kein MFA out of the box. Ein späterer Wechsel auf OIDC bedeutet Migration der bestehenden Accounts. | Offen. IDM ist langfristig besser, lohnt sich aber nur bei gesichertem Dauerbetrieb. Bei unklarer Laufzeit (mögliche Abschaltung) ist Tokens der pragmatischere Start. |
| **E2EE** | **An** (Standard für private Räume): maximaler Datenschutz, Admins können nichts lesen. Nachteile: Key-Backup/Geräte-Verifizierung hakelig, keine serverseitige Suche, Bots/Moderation müssen Crypto unterstützen. | **Aus** (z. B. öffentliche Kurs-Räume): einfache UX, Suche, Bots funktionieren problemlos. Server-Betreiber können Inhalte lesen. | Mischform: Kurs-/Community-Räume unverschlüsselt, private DMs/Räume E2EE. |
| **MFA** | Via IdP (Switch edu-ID), setzt OIDC voraus. | Synapse/Element selbst: kein eigenes MFA. | MFA nur über IDM sinnvoll lösbar. Ein Argument für OIDC, aber kein Muss. |
| **Management** | **Bot** (maubot / Admin-Bot): automatisiert Raum-/Space-Erstellung (z. B. Prof-Bots), skriptbar, Ansible-/Git-tauglich. **Einziger Zugang für alle, die nur Kurse geben.** Aufwand: Eigenentwicklung und Wartung. | **Admin-UI** (Ketesa) / API: manuell, schnell, gut für Einzelfälle. **Nur für eine Handvoll globaler Admins.** Skaliert schlecht, Browser-Bug (Firefox/Safari). | Kombi mit klarer Rollentrennung: globale Admins = Admin-UI + Bot, Kursleitende = ausschließlich Bot. |
| **Client** | **Element Web** (bereits deployed): Referenzclient, vertraut. UI komplex für Discord-Umsteiger. | Alternativen (Cinny, FluffyChat): einfacher, aber weniger Features/Support. | Element Web behalten. |

## Sicherheitsgrad der Aussagen

- **Sicher:** grundlegende E2EE-Tradeoffs (Suche, Bots, Admin-Einsicht); OIDC-Login delegiert MFA an den IdP.
- **Abgeleitet, nicht geprüft:** ob Switch edu-ID MFA für alle Nutzer erzwingt oder nur optional anbietet; wie hoch der Aufwand der edu-ID-Anbindung konkret ist (Onboarding auf Switch-Seite); dass ein späterer Wechsel von Tokens auf OIDC Account-Migration erfordert.
- **Unklar:** ob die aktuelle maubot-Version E2EE-Räume zuverlässig bedient. Nicht verifiziert.
