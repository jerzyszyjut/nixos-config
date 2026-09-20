# Checklista: co wyklikać po kolei

Same kroki. „Dlaczego" jest w [MEDIA.md](MEDIA.md).

**Kolejność ma znaczenie** — prawie każdy krok potrzebuje klucza API
z poprzedniego. Idź z góry na dół.

**Wszystko otwierasz przez Tailscale: `http://kino:<port>`.** Kafelki na
Homepage prowadzą tam wprost. Firewall przepuszcza wyłącznie `tailscale0`,
więc z LAN-u ani z internetu nic nie wejdzie.

**Jeden wyjątek: qBittorrent** (`8080`) zostaje na loopbacku, bo działa
z `LocalHostAuth=false` — połączenie lokalne nie wymaga hasła, co jest
bezpieczne tylko dopóki loopback jest jedyną drogą. Gdy naprawdę musisz:

```fish
ssh -L 8080:localhost:8080 kino    # potem http://localhost:8080
```

W praktyce zaglądasz tam rzadko — kolejką steruje Radarr/Sonarr/Lidarr.

> Klucz API każdej usługi `*arr`: **Settings → General → API Key**.
> Będziesz go kopiował kilkanaście razy.

Całość: ~45 min.

---

## 1. qBittorrent — 1 min

1. `ssh -L 8080:localhost:8080 kino` → otwórz `http://localhost:8080`
2. Nic nie konfigurujesz. Login pusty, hasło puste (loopback + `LocalHostAuth=false`)
3. Ustawienia są nadpisywane z Nixa przy każdym starcie — nie zmieniaj ich w UI

---

## 2. Prowlarr — 5 min

1. `prow` → Settings → Indexers → `+` → **FlareSolverr**
   - Tags: `flaresolverr`
   - Host: `http://localhost:8191`
2. Indexers → **Add Indexer** → `1337x`
   - Tags: `flaresolverr`
   - **Test**
3. Dodaj jeszcze 2–3 publiczne (TheRARBG, Torlock, YTS)
4. Sprawdź wyszukiwanie: **Search** u góry

> Bez kroku 1 indekser przechodzi test na zielono i zwraca zero wyników.

---

## 3. Radarr — filmy, 5 min

1. `rad` → Settings → Download Clients → `+` → **qBittorrent**
   | pole | wartość |
   |---|---|
   | Host | `localhost` |
   | Port | `8080` |
   | Username / Password | puste |
   | Category | `radarr` |
2. W tym samym oknie: **Completed Download Handling** → włącz **Remove Completed**
3. Settings → Media Management
   - Root Folders → Add → `/var/lib/media/library/movies`
   - **Use Hardlinks instead of Copy** ✓
   - **Rename Movies** ✓
4. `prow` → Settings → Apps → `+` → **Radarr**
   - Prowlarr Server `http://localhost:9696`
   - Radarr Server `http://localhost:7878`
   - API Key z Radarra → **Test** → **Save**

---

## 4. Sonarr — seriale, 4 min

1. `son` → Settings → Media Management → Root Folders → Add → `/var/lib/media/library/tv`
2. **Use Hardlinks instead of Copy** ✓
3. Settings → Download Clients → `+` → **qBittorrent**
   - `localhost:8080`, bez loginu, Category `sonarr`
4. `prow` → Settings → Apps → `+` → **Sonarr**
   - Sonarr Server `http://localhost:8989`, API Key z Sonarra

---

## 5. Lidarr — muzyka, 4 min

1. `lid` → Settings → Media Management → Root Folders → Add → `/var/lib/media/library/music`
2. **Use Hardlinks instead of Copy** ✓
3. Settings → Download Clients → `+` → **qBittorrent**
   - `localhost:8080`, bez loginu, Category `lidarr`
4. `prow` → Settings → Apps → `+` → **Lidarr**
   - Lidarr Server `http://localhost:8686`, API Key z Lidarra
5. `lid` → Settings → Indexers → sprawdź, że indeksery same się pojawiły

> Każdy `*arr` musi mieć **własną** kategorię w qBittorrencie, inaczej będą
> sobie nawzajem sprzątać pobrania.

---

## 6. Jellyfin — 6 min

1. `http://kino:8096` → kreator (konto, język)
   - **Zapamiętaj hasło** — tym kontem logujesz się potem do Seerr
2. Dashboard → Libraries → Add Media Library
   - **Movies** → `/var/lib/media/library/movies`
   - **Shows** → `/var/lib/media/library/tv`
3. Dashboard → API Keys → `+` → skopiuj klucz
4. `rad` → Settings → Connect → `+` → **Jellyfin**
   - host `localhost`, port `8096`, klucz z kroku 3
5. To samo w `son` → Settings → Connect → `+` → Jellyfin

> Krok 4–5 sprawia, że biblioteka odświeża się po pobraniu, a nie co godzinę.

---

## 7. Seerr — 5 min

1. `http://kino:5055` → **Sign in with Jellyfin**
   - adres `http://localhost:8096`, konto z kroku 6.1
2. Wybierz biblioteki **Movies** i **Shows**
3. **Add Radarr Server**
   | pole | wartość |
   |---|---|
   | Hostname | `localhost` |
   | Port | `7878` |
   | API Key | z Radarra |
   | Quality Profile | np. HD-1080p |
   | Root Folder | `/var/lib/media/library/movies` |
   | Default Server | ✓ |
   | Enable Automatic Search | ✓ |
4. **Add Sonarr Server** — to samo, port `8989`,
   Root Folder `/var/lib/media/library/tv`
5. **Test → Save** przy obu

---

## 8. Bazarr — napisy, 6 min

1. `baz` → Settings → **Sonarr**
   - Address `localhost`, Port `8989`, API Key z Sonarra → **Test** (musi zzielenieć)
2. Settings → **Radarr** — to samo, port `7878`
3. Settings → Languages
   - *Languages Filter*: dodaj **Polish** i **English**
   - *Languages Profiles*: utwórz profil z oboma, **polski pierwszy**
   - *Default Settings*: przypisz profil do **Series** i **Movies**, zaznacz ptaszki
   - **Nie** włączaj *Forced*
4. Settings → Providers — dodaj:
   - **napiprojekt** (bez konta, najlepszy do polskich)
   - **OpenSubtitles.com** (darmowe konto, ~20 napisów/dzień)
   - **Podnapisi** (bez konta)

---

## 9. Navidrome — muzyka na telefon, 5 min

1. `http://kino:4533` **z laptopa**
2. Załóż konto — **pierwsze założone = admin**. Zrób to teraz.
   - Hasło unikalne (Subsonic trzyma je odwracalnie)
3. Settings → **Scan now**
4. Telefon: zainstaluj **Tailscale**, zaloguj na to samo konto
5. Zainstaluj klienta:
   - Android → **Symfonium** (płatna) albo **Tempo** (darmowa)
   - iOS → **Amperfy** (darmowa) albo **play:Sub** (płatna)
6. W kliencie: serwer `http://kino:4533`, login/hasło z kroku 2
7. Jakość: wifi → oryginał, komórka → **opus 96 kbps**

---

## 10. Calibre-Web Automated — 4 min

1. `http://kino:8083`
2. Zaloguj: **`admin` / `admin123`**
3. **Natychmiast zmień hasło**: Admin → Users → admin
4. Test:
   ```fish
   cp jakas-ksiazka.epub /var/lib/media/ingest/books/
   journalctl -fu podman-cwa
   ```
5. Plik ma zniknąć z ingestu i pojawić się w bibliotece

---

## 11. Send-to-Kindle — 10 min

**Google:**

1. <https://myaccount.google.com/security> → włącz **Weryfikację dwuetapową**
2. <https://myaccount.google.com/apppasswords> → nazwa `kino-cwa` → skopiuj 16 znaków

**Amazon** (<https://www.amazon.com/mycd> → Preferences → Personal Document Settings):

3. **Send-to-Kindle E-Mail Settings** → skopiuj adres `…@kindle.com` czytnika
4. **Approved Personal Document E-mail List** → Add → **swój adres @gmail.com**
   - ⚠️ Bez tego maile znikają bez błędu i bez odbicia

**CWA:**

5. Admin → **Edit E-mail Server Settings**
   | pole | wartość |
   |---|---|
   | SMTP Hostname | `smtp.gmail.com` |
   | SMTP Port | `587` |
   | Encryption | `STARTTLS` |
   | SMTP Login | Twój `@gmail.com` |
   | SMTP Password | hasło z kroku 2 |
   | From E-mail | Twój `@gmail.com` |
6. **Send Test E-Mail** → najpierw na własny adres
7. Admin → Users → Twój user → **Kindle E-Mail** → adres z kroku 3
8. Format wysyłki: **EPUB**. Nie MOBI — Amazon nie przyjmuje od 2022.
9. Test: przy książce → **Send to Kindle**

> Zostaw wysyłkę ręczną. Auto-send dopiero, gdy ingest jest czysty.

---

## 12. Homepage — 1 min

1. `media` → sprawdź, że wszystkie kafelki są zielone
2. Nic nie konfigurujesz — układ jest z Nixa

---

## 13. Live TV — gdy będziesz mieć M3U

**Threadfin** (`ssh -L 34400:localhost:34400 kino` → `http://localhost:34400`):

1. Kreator → **Playlist (M3U)** → URL źródła
2. **XMLTV** → URL EPG
3. Zakładka **Mapping** → przypisz `tvg-id`, wyłącz niechciane kanały
4. Endpointy Threadfina:
   ```
   http://localhost:34400/m3u/threadfin.m3u
   http://localhost:34400/xmltv/threadfin.xml
   ```

**Jellyfin** → Dashboard → Live TV:

5. Tuner Devices → `+` → **M3U Tuner** → adres z kroku 4
6. TV Guide Data Providers → `+` → **XMLTV** → adres z kroku 4
7. **Recording Path** → `/var/lib/media/dvr`
8. **Refresh Guide**

---

## 14. Test całości

1. `seerr` → Discover → wybierz film → **Request**
2. Obserwuj: Seerr → Radarr → Prowlarr → qBittorrent → `library/movies` → Jellyfin
3. Postęp: Radarr → **Activity → Queue**; błędy: **System → Events**
4. Obejrzyj go w `jf`

---

## 15. ThinkPad — sprzątanie

Dopiero **gdy film poleci z serwera**:

1. Na ThinkPadzie: `nrs`
2. Sprawdź:
   ```fish
   systemctl list-units 'jellyfin*' 'radarr*' 'sonarr*'   # ma być pusto
   ```
3. Po tygodniu, gdy wszystko działa:
   ```fish
   sudo rm -rf /var/lib/media
   sudo rm -rf /var/lib/{jellyfin,radarr,sonarr,prowlarr,bazarr,qbittorrent}
   sudo nix-collect-garbage --delete-older-than 7d
   ```

---

## Diagnostyka

| komenda | co robi |
|---|---|
| `media` | dashboard, kolorowe kafelki |
| `media-status` | status wszystkich 14 jednostek |
| `media-down` / `media-up` | zatrzymaj / uruchom cały stack |
| `journalctl -fu podman-cwa` | logi CWA na żywo |
| `nrs` | rebuild **tej** maszyny |

| skrót | usługa | port |
|---|---|---|
| `media` | Homepage | 8082 |
| `seerr` | Seerr | 5055 |
| `jf` | Jellyfin | 8096 |
| `nav` | Navidrome | 4533 |
| `cwa` | Calibre-Web | 8083 |
| `rad` | Radarr | 7878 |
| `son` | Sonarr | 8989 |
| `lid` | Lidarr | 8686 |
| `baz` | Bazarr | 6767 |
| `prow` | Prowlarr | 9696 |
| `qbt` | qBittorrent | 8080 (tylko ssh -L) |
| `tf` | Threadfin | 34400 |
