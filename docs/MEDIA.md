# Filmy i seriale: Seerr + Radarr + Sonarr + Bazarr + Prowlarr + qBittorrent + Jellyfin

Włączane przez `profiles.mediaServer.enable = true` w `flake.nix`.
Usługi: `modules/profiles/media-server.nix`, komendy administracyjne:
`home/jerzy/media-server.nix`.

**Ten dokument opisuje serwer — maszynę `kino`.** Odtwarzacze
(jellyfin-media-player, mpv, vlc) to osobny `profiles.entertainment`
w `modules/profiles/entertainment.nix`, włączony na ThinkPadzie. Adresy
`localhost:…` poniżej działają **w powłoce na serwerze**; z laptopa `media`,
`seerr` i `jf` otwierają `http://kino:…` przez Tailscale, a panele admina
(Radarr, Prowlarr, qBittorrent) są zbindowane na loopback i z zewnątrz
niewidoczne — `ssh kino` albo `ssh -L 7878:localhost:7878 kino`.

Stawianie serwera od zera: [SERVER-INSTALL.md](SERVER-INSTALL.md).

```
1337x ─┐         ┌─ Radarr (filmy)  ─┐        ┌─→ Jellyfin ─→ oglądasz
       ├─ Prowlarr┤                   ├─ qBit ─┤
inne  ─┘     ↑    └─ Sonarr (seriale) ┘        └─→ biblioteka (hardlink)
             │
           Seerr  ←── tu klikasz „chcę to"
```

**Na co dzień otwierasz dwie rzeczy:** `seerr` żeby dodać film i `jf` żeby go
obejrzeć. Reszta to kuchnia, do której zaglądasz, jak coś nie działa.

| co        | adres                   | skrót    | do czego                                    |
|-----------|-------------------------|----------|---------------------------------------------|
| Homepage  | http://localhost:8082   | `media`  | **dashboard** — status wszystkiego + linki  |
| Seerr     | http://localhost:5055   | `seerr`  | **tu dodajesz film** jednym kliknięciem     |
| Jellyfin  | http://localhost:8096   | `jf`     | **tu oglądasz**                             |
| Radarr    | http://localhost:7878   | `rad`    | **filmy** — kolejka, import, jakość          |
| Sonarr    | http://localhost:8989   | `son`    | **seriale** — to samo, per sezon/odcinek     |
| Bazarr    | http://localhost:6767   | `baz`    | **napisy** — polskie i angielskie, same się dociągają |
| Prowlarr  | http://localhost:9696   | `prow`   | trackery                                    |
| qBittorrent | http://localhost:8080 | `qbt`    | surowe transfery                            |
| FlareSolverr | http://localhost:8191 | —      | obchodzi Cloudflare, nic tu nie klikasz     |

Gdy coś stanie: `media` (kolorowe kafelki) albo `media-status` (dlaczego).

## Włączanie i wyłączanie całości

| komenda | co robi |
|---|---|
| `media-down` | zatrzymuje wszystkie dziewięć usług |
| `media-up` | uruchamia je z powrotem |
| `media-autostart-off` | przestają wstawać razem z maszyną |
| `media-autostart-on` | znów wstają przy starcie |

Pierwsze dwie działają natychmiast, przez `media.target` — każda usługa jest
jego `PartOf`, więc jedna komenda rusza wszystkie. Niedokończone pobierania nie
przepadają: qBittorrent zapisuje resume data przy zamykaniu.

Dwie ostatnie są cięższe, bo **przebudowują system** (~30 s, pytają o hasło).
Nie da się inaczej: `/etc/systemd/system` to dowiązanie do `/nix/store`, więc
`systemctl disable` i `systemctl mask` nie mają gdzie zapisać swoich symlinków.
Na NixOS to, czy usługa wstaje przy starcie, jest elementem konfiguracji, a nie
stanem — funkcje podmieniają linię `mediaServer.autostart` w `flake.nix`
i wołają `nixos-rebuild switch`.

Na serwerze autostart normalnie zostaje włączony i nie dotykasz tych dwóch —
przydają się, dopóki dopinasz stack.

Wyłączony autostart **nie odinstalowuje** niczego. Usługi dalej są w systemie,
`media-up` w każdej chwili je podniesie — po prostu nic nie ciągnie ich w górę
przy bootcie.

---

## Odpalenie

Usługi są systemowe i mają `wantedBy = multi-user.target`, więc startują same —
przy przebudowie i przy każdym kolejnym boocie. Nie ma nic do „uruchamiania”.

```fish
nrs                # sudo nixos-rebuild switch --flake ~/nixos-config#kino
media-status       # wszystkie siedem powinno być active (running)
media              # otwiera dashboard
```

Pierwszy `nrs` po włączeniu profilu pobiera ~300 MB i tworzy `/var/lib/media`.
Jeśli któraś usługa jest `activating` przez chwilę — Jellyfin i Seerr
inicjalizują bazy przy pierwszym starcie, daj im minutę.

Potem zostaje jednorazowe podłączenie usług do siebie (niżej). Klucze API
powstają dopiero przy pierwszym starcie i żyją w bazach usług, więc tego nie da
się zadeklarować w Nixie — robisz to raz na maszynę, ~15 minut.

---

## Jednorazowe podłączenie

Kolejność ma znaczenie: każdy krok potrzebuje klucza API z poprzedniego.

### 1. Prowlarr — trackery

`prow` → najpierw FlareSolverr, bo 1337x siedzi za Cloudflare i bez tego
indekser przechodzi test na zielono, a potem zwraca zero wyników:

* **Settings → Indexers → Add (+) → FlareSolverr**
* Tags: `flaresolverr`
* Host: `http://localhost:8191`

Potem sam tracker:

* **Indexers → Add Indexer → 1337x**
* Tags: wpisz `flaresolverr` (to spina go z proxy powyżej)
* **Test**, a wyniki sprawdź w **Search** u góry

Dorzuć od razu 2–3 inne publiczne trackery (TheRARBG, Torlock, YTS dla małych
plików). Jeden tracker to jeden punkt awarii i sporo filmów, których po prostu
nie znajdzie.

### 2. Radarr — pobieranie i biblioteka

`rad` → **Settings → Download Clients → Add (+) → qBittorrent**

| pole     | wartość     |
|----------|-------------|
| Host     | `localhost` |
| Port     | `8080`      |
| Username | puste       |
| Password | puste       |
| Category | `radarr`    |

Login jest pusty, bo web UI qBittorrenta słucha wyłącznie na loopbacku i ma
`LocalHostAuth=false` — kto dosięga tego portu, ma już shella na maszynie.
**Test → Save.**

W tym samym oknie rozwiń **Completed Download Handling** i włącz **Remove
Completed**. To jest ważne przy wyłączonym seedowaniu: torrent zatrzymuje się
w sekundzie, w której plik jest kompletny, i bez tego zatrzymane torrenty
zbierałyby się w qBittorrencie w nieskończoność. Usunięcie torrenta kasuje
kopię z `torrents/`, ale film w bibliotece zostaje — to ten sam plik pod dwoma
nazwami (twarde dowiązanie), więc znika dopiero ostatnia nazwa.

Dalej **Settings → Media Management**:

* **Root Folders → Add Root Folder** → `/var/lib/media/library/movies`
* **Use Hardlinks instead of Copy** — włączone (domyślnie jest, sprawdź)
* **Rename Movies** — włącz, Jellyfin lepiej rozpozna tytuły

### 3. Prowlarr → Radarr

Wracasz do Prowlarr: **Settings → Apps → Add (+) → Radarr**

| pole            | wartość                                |
|-----------------|----------------------------------------|
| Prowlarr Server | `http://localhost:9696`                |
| Radarr Server   | `http://localhost:7878`                |
| API Key         | Radarr → Settings → General → API Key  |

**Test → Save.** Od tej chwili każdy tracker dodany w Prowlarr sam pojawia się
w Radarr — trackerów nie konfiguruje się dwa razy.

### 4. Jellyfin — biblioteka

`jf` → kreator pierwszego uruchomienia (konto, język). To konto będzie potem
Twoim loginem do Seerr, więc zapamiętaj hasło.

**Dashboard → Libraries → Add Media Library**

* Content type: **Movies**
* Folder: `/var/lib/media/library/movies`
* Preferred metadata language: polski, jeśli chcesz polskie opisy

Żeby biblioteka odświeżała się od razu po pobraniu zamiast co godzinę: w Radarr
**Settings → Connect → Add (+) → Jellyfin**, host `localhost`, port `8096`,
API key z Jellyfin (Dashboard → API Keys).

### 5. Seerr — to, czego będziesz używać

`seerr` → kreator:

1. **Sign in with Jellyfin** — adres `http://localhost:8096`, konto z kroku 4
2. Wybierz bibliotekę **Movies** do skanowania
3. **Add Radarr Server**:

| pole             | wartość                               |
|------------------|---------------------------------------|
| Server Name      | cokolwiek                             |
| Hostname         | `localhost`                           |
| Port             | `7878`                                |
| API Key          | Radarr → Settings → General → API Key |
| Quality Profile  | np. HD-1080p                          |
| Root Folder      | `/var/lib/media/library/movies`       |
| Default Server   | tak                                   |
| Enable Automatic Search | tak — to jest to „jedno kliknięcie" |

**Test → Save.**

### 6. Test całości

W Seerr: **Discover**, kliknij film, **Request**. Powinno przelecieć: Seerr →
Radarr → Prowlarr → 1337x → qBittorrent → `library/movies` → Jellyfin.

Postęp widać w Seerr, a szczegóły w Radarr: **Activity → Queue** (co robi
pobieranie) i **System → Events** (co poszło nie tak).

---

## Seedowanie jest wyłączone

`modules/profiles/media-server.nix` ustawia:

```
Session\GlobalMaxRatio=0          zatrzymaj, gdy tylko pobieranie się skończy
Session\GlobalMaxSeedingMinutes=0 to samo, wyrażone czasem
Session\MaxRatioAction=0          0 = zatrzymaj (nie usuwaj — Radarr musi
                                  jeszcze zobaczyć gotowy torrent, żeby go
                                  zaimportować)
Session\GlobalUPSpeedLimit=1      1 KiB/s. UWAGA: 0 w qBittorrencie znaczy
                                  „bez limitu", nie „wyłączone"
```

Czego to **nie** robi: nie sprawia, że wysyłka w trakcie pobierania jest
dokładnie zerowa. BitTorrent wymienia kawałki — peer, który nic nie wysyła,
zostaje odcięty (choked) przez pozostałych i nie pobiera. 1 KiB/s to praktyczne
minimum, nie zero, i kosztuje trochę prędkości pobierania na publicznych rojach.
Podnieś limit, jeśli transfery się wloką, ze świadomością, że podnosisz też to,
ile wysyłasz.

I rzecz osobna: to ogranicza, ile udostępniasz. Nie ukrywa adresu IP, z którego
pobierasz — a to jest to, co realnie notują firmy monitorujące roje. To decyzja
o VPN-ie, nie o ustawieniu w qBittorrencie.

---

## Oglądanie na telefonie i telewizorze

Jellyfin, Seerr i Homepage mają zamknięty firewall dla LAN-u, ale `net.nix` ufa
całemu interfejsowi `tailscale0`. Czyli po `tailscale up` na laptopie i na
telefonie wchodzisz w aplikację Jellyfin i wpisujesz `http://kino:8096` — i
to działa też z kawiarni, bez otwierania czegokolwiek na świat. Seerr pod
`http://kino:5055` pozwala zamówić film z telefonu.

To jest też jedyna droga z ThinkPada: Jellyfin, Seerr i Homepage słuchają na
serwerze, nie tu. `entertainment.serverHost = "kino"` w `flake.nix` sprawia, że
skróty `jf`, `seerr` i `media` na laptopie celują w tailnetową nazwę serwera —
jeśli Tailscale nadał mu inną, popraw tam.

Na laptopie lepiej używać `jellyfin-media-player` niż przeglądarki: odtwarza
przez wbudowanego mpv, więc dekoduje sprzętowo i wentylator milczy. Przy
pierwszym starcie pyta o adres serwera — `http://kino:8096`.

## Port 51413

Jedyny port otwarty na świat. Przy wyłączonym seedowaniu nie ma sensu
przekierowywać go na routerze — przekierowanie służy temu, żeby inni mogli
łączyć się do Ciebie, czyli dokładnie temu, czego nie chcesz. Zostaje otwarty,
bo bez przyjmowania połączeń przychodzących w trakcie pobierania roje schodzą
zauważalnie wolniej.

## Dashboard z żywymi danymi (opcjonalnie)

Homepage pokazuje teraz status (kafelek zielony/czerwony) i miejsce na dysku,
bez żadnych kluczy API. Może też pokazywać, co się właśnie pobiera i ile filmów
ma Radarr — do tego potrzebuje kluczy API każdej usługi, a te nie mogą trafić
do `/nix/store`, który jest czytelny dla wszystkich. Przez sops:

```fish
sops secrets/secrets.yaml
```

dopisz:

```yaml
homepage:
    env: |
        HOMEPAGE_VAR_RADARR_KEY=...
        HOMEPAGE_VAR_PROWLARR_KEY=...
        HOMEPAGE_VAR_JELLYFIN_KEY=...
```

potem w `modules/nixos/secrets.nix` zadeklaruj `"homepage/env"`, a w
`media-server.nix` dodaj do `services.homepage-dashboard`:

```nix
environmentFiles = [ config.sops.secrets."homepage/env".path ];
```

i przy każdej usłudze widget, np. dla Radarra:

```nix
widget = {
  type = "radarr";
  url = "http://localhost:7878";
  key = "{{HOMEPAGE_VAR_RADARR_KEY}}";
};
```

## Znane pułapki

**Radarr kopiuje zamiast linkować.** Sprawdź `Settings → Media Management →
Use Hardlinks`. Jeśli włączone, a Radarr dalej kopiuje, to katalogi wylądowały
na różnych subwolumenach btrfs — `btrfs subvolume show /var/lib/media/torrents`
i `.../library` muszą pokazać ten sam subwolumen.

**„Permission denied" przy imporcie.** Wszystkie trzy usługi siedzą w grupie
`media`, katalogi mają setgid (2775), a qBittorrent i Radarr mają `UMask=0002`.
Jądro ma `fs.protected_hardlinks=1`, więc Radarr może dowiązać plik tylko wtedy,
gdy ma do niego prawo zapisu — przy domyślnej umasce 0022 dostałby EPERM.
`stat` na pliku powinien pokazać `media` i `rw-rw-r--`.

**Pusta strona zamiast Homepage z telefonu.** Homepage odrzuca żądania z
nagłówkiem Host spoza `allowedHosts`. Nazwa hosta z tailneta jest tam wpisana,
ale jeśli wchodzisz po IP `100.x.y.z`, dopisz je do `allowedHosts`.

**qBittorrent zapomina ustawienia.** Tak ma być. Moduł nadpisuje
`qBittorrent.conf` z `serverConfig` przy każdym starcie, więc źródłem prawdy
jest `modules/profiles/media-server.nix`, nie web UI. To samo dotyczy
transkodowania w Jellyfinie (`forceEncodingConfig = true`).

**Miejsce na dysku.** Nic tutaj nie jest w snapshotach ani w backupie restica —
świadomie, bo to dane odtwarzalne. Kafelek na dashboardzie pokazuje wolne
miejsce na `/` — widget Homepage przyjmuje tylko punkty montowania, a i tak
wszystko siedzi na jednym systemie plików, więc to ta sama liczba. Rozbicie na
katalogi: `dust /var/lib/media`.

## Sonarr — seriale

Radarr obsługuje **wyłącznie filmy**. Seerr decyduje o trasie na podstawie tego,
czym dana pozycja jest w TMDB: film idzie do Radarra, serial do Sonarra. Bez
Sonarra request na serial zostaje w Seerr jako „Pending" i nikt go nie odbiera —
w Radarrze nigdy się nie pojawi, bo Radarr nie ma pojęcia o sezonach.

Konfiguracja jest bliźniacza do Radarra, tylko z innym katalogiem:

1. `son` → **Settings → Media Management → Root Folders → Add**
   → `/var/lib/media/library/tv`
2. **Use Hardlinks instead of Copy** — włączone
3. **Settings → Download Clients → qBittorrent**, `localhost:8080`,
   bez loginu i hasła (jak w kroku 1 wyżej)
4. Prowlarr → **Settings → Apps → Add (+) → Sonarr**,
   Sonarr Server `http://localhost:8989`, API key z Sonarr → Settings → General
5. Jellyfin → **Dashboard → Libraries → Add Media Library**,
   Content type **Shows**, folder `/var/lib/media/library/tv`
6. Seerr → **Settings → Services → Add Sonarr Server**, port `8989`,
   Root Folder `/var/lib/media/library/tv`, Default Server + Enable Automatic
   Search

Dopiero po kroku 6 wcześniejsze wiszące requesty da się wypchnąć: w Seerr
**Requests** znajdź pozycję i kliknij **Retry**.

## Bazarr — napisy

Bazarr pilnuje napisów do tego, co Radarr i Sonarr już zaimportowały. Podpina
się do obu po API, zauważa nowe pozycje i dokłada plik `.srt` obok filmu.
Jellyfin wykrywa go sam, bez skanowania.

**Adres nasłuchu jest zaszczepiany z Nixa.** Bazarr nie ma opcji `bindaddress`
— ani w module NixOS, ani w linii poleceń — a jego własny domyślny adres to
`*`, czyli wszystkie interfejsy. Ponieważ `net.nix` trzyma `tailscale0`
w `trustedInterfaces`, oznaczałoby to panel administracyjny bez logowania
wystawiony na cały tailnet, podczas gdy Radarr, Sonarr, Prowlarr i qBittorrent
są tu celowo tylko na `127.0.0.1`. Dlatego `preStart` zapisuje
`general.ip: 127.0.0.1` do `config.yaml`, zanim Bazarr wystartuje pierwszy raz.

Zabezpieczenie działa tylko przy **pierwszym** starcie i nigdy nie rusza
istniejącego pliku — jeśli kiedyś zmienisz adres w Settings → General, zmiana
zostanie. Sprawdzenie, na czym faktycznie słucha:

```fish
ss -tlnp | grep 6767   # ma być 127.0.0.1:6767, nie 0.0.0.0:6767
```

### 1. Podłączenie do Sonarra i Radarra

`baz` → **Settings** → **Sonarr**:

| pole    | wartość                                |
|---------|----------------------------------------|
| Address | `localhost`                            |
| Port    | `8989`                                 |
| API Key | Sonarr → Settings → General → API Key  |

**Test** musi zzielenieć. To samo w **Settings** → **Radarr**, port `7878`
i klucz z Radarra. Zapisz i daj mu chwilę na wciągnięcie biblioteki.

### 2. Języki

**Settings** → **Languages** → w *Languages Filter* dodaj **Polish**
i **English**, potem w *Languages Profiles* utwórz profil z oboma (polski
pierwszy). Na dole, w *Default Settings*, przypisz go do **Series** i **Movies**
i zaznacz ptaszki obok — inaczej profil dostaną tylko pozycje dodane ręcznie.

Nie włączaj **Forced** — to napisy wyłącznie do obcojęzycznych kwestii, nie do
całego filmu.

### 3. Dostawcy

**Settings** → **Providers**. Do polskich napisów sensowne są:

- **napiprojekt** — bez konta, najlepszy do polskich
- **OpenSubtitles.com** — największa baza, wymaga darmowego konta
  (limit ok. 20 napisów dziennie w zupełności wystarcza)
- **Podnapisi** — bez konta, przyzwoity dodatek

### 4. Test

Wejdź w **Series** → Dexter → ikona lupy przy odcinku. Jeśli coś znajdzie
i pobierze, obok pliku `.mkv` pojawi się `.srt`, a Jellyfin pokaże napisy
przy następnym otwarciu odcinka.

### Dlaczego Bazarr jest w grupie `media`

Bo **zapisuje** do katalogów biblioteki, a te są `2775 radarr:media`
i `2775 sonarr:media`. Do tego ma `UMask=0002`, żeby tworzone przez niego
`.srt` zostały zapisywalne dla grupy — inaczej Radarr i Sonarr nie mogłyby ich
przemianować razem z filmem przy podmianie wydania na lepsze.
