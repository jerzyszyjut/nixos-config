# Checklista: co wyklikać po kolei

Krótka wersja. Szersze wyjaśnienia: [MEDIA.md](MEDIA.md).

Wszystko poniżej robisz **na serwerze albo przez Tailscale**. Panele admina są
na loopbacku — z laptopa: `ssh -L <port>:localhost:<port> kino`.

---

## 1. Lidarr — 10 min

1. `lid` → Settings → General → **skopiuj API Key**
2. `prow` → Settings → Apps → `+` → **Lidarr**
   - Prowlarr Server: `http://localhost:9696`
   - Lidarr Server: `http://localhost:8686`
   - API Key: z kroku 1
   - **Test** → **Save**
3. `lid` → Settings → Indexers → sprawdź, że indeksery same się pojawiły
4. `lid` → Settings → Download Clients → `+` → **qBittorrent**
   - Host `localhost`, Port `8080`, Category `lidarr`
5. `lid` → Settings → Media Management
   - Root Folders → Add → `/var/lib/media/library/music`
   - zaznacz **Use Hardlinks instead of Copy**
6. Test: dodaj artystę → Search → sprawdź czy trafia do qBittorrenta

---

## 2. Navidrome — 5 min + telefon

1. Otwórz `http://kino:4533` **z laptopa** (nie localhost)
2. Załóż konto — **pierwsze założone = admin**. Zrób to teraz.
   - Hasło unikalne, nieużywane nigdzie indziej (Subsonic trzyma je odwracalnie)
3. Settings → **Scan now** (potem skanuje sam co godzinę)
4. Na telefonie: zainstaluj **Tailscale**, zaloguj na to samo konto
5. Zainstaluj klienta:
   - Android → **Symfonium** (płatna) albo **Tempo** (darmowa)
   - iOS → **Amperfy** (darmowa) albo **play:Sub** (płatna)
6. W kliencie:
   - Server `http://kino:4533`
   - login/hasło z kroku 2
7. W kliencie ustaw jakość osobno dla wifi i komórki:
   - wifi → oryginał
   - komórka → **opus 96 kbps**

---

## 3. Calibre-Web Automated — 5 min

1. Otwórz `http://kino:8083`
2. Zaloguj: **`admin` / `admin123`**
3. **Natychmiast zmień hasło**: Admin → Users → admin
4. Test ingestu:
   ```fish
   cp jakas-ksiazka.epub /var/lib/media/ingest/books/
   journalctl -fu podman-cwa
   ```
5. Plik ma zniknąć z ingestu i pojawić się w bibliotece

---

## 4. Send-to-Kindle — 15 min

**Google:**

1. <https://myaccount.google.com/security> → włącz **Weryfikację dwuetapową**
2. <https://myaccount.google.com/apppasswords> → nazwa `kino-cwa` → skopiuj 16 znaków

**Amazon** (<https://www.amazon.com/mycd> → Preferences → Personal Document Settings):

3. **Send-to-Kindle E-Mail Settings** → skopiuj adres `…@kindle.com` swojego czytnika
4. **Approved Personal Document E-mail List** → Add → wpisz **swój adres @gmail.com**
   - ⚠️ Bez tego kroku maile znikają bez błędu i bez odbicia

**CWA** (`http://kino:8083`):

5. Admin → **Edit E-mail Server Settings**
   | pole | wartość |
   |---|---|
   | SMTP Hostname | `smtp.gmail.com` |
   | SMTP Port | `587` |
   | Encryption | `STARTTLS` |
   | SMTP Login | Twój `@gmail.com` |
   | SMTP Password | hasło aplikacji z kroku 2 |
   | From E-mail | Twój `@gmail.com` |
6. **Send Test E-Mail** → na własny adres (oddziela problem SMTP od problemu Amazona)
7. Admin → Users → Twój użytkownik → **Kindle E-Mail** → adres z kroku 3
8. Format wysyłki: **EPUB**. Nie MOBI — Amazon go nie przyjmuje od 2022.
9. Test: przy książce kliknij **Send to Kindle**

Zostaw wysyłkę ręczną. Auto-send włącz dopiero, gdy ingest jest czysty.

---

## 5. Jellyfin Live TV — gdy będziesz mieć M3U

**Threadfin** (`ssh -L 34400:localhost:34400 kino`, potem `http://localhost:34400`):

1. Kreator → dodaj **Playlist (M3U)** → URL źródła
2. Dodaj **XMLTV** → URL EPG
3. Zakładka **Mapping** → przypisz `tvg-id`, wyłącz niechciane kanały
4. Zanotuj endpointy Threadfina:
   ```
   http://localhost:34400/m3u/threadfin.m3u
   http://localhost:34400/xmltv/threadfin.xml
   ```

**Jellyfin** (`jf` → Dashboard → Live TV):

5. Tuner Devices → `+` → **M3U Tuner** → adres M3U z kroku 4
6. TV Guide Data Providers → `+` → **XMLTV** → adres XMLTV z kroku 4
7. **Recording Path** → `/var/lib/media/dvr`
8. **Refresh Guide**

---

## 6. ThinkPad — sprzątanie

Dopiero **gdy film poleci z serwera**:

1. Na ThinkPadzie: `nrs`
2. Sprawdź, że usługi zniknęły:
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
