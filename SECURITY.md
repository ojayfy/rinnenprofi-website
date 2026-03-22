# Sicherheitsmaßnahmen für rinnenprofi-muc.de

## 🎯 Schnellstart - Sicherer Server

### ⚠️ WICHTIG: Verwenden Sie IMMER den sicheren Server!

**NIEMALS verwenden:**
```powershell
python -m http.server 8080  # ❌ UNSICHER! Kein Schutz!
```

**IMMER verwenden:**
```powershell
# Installation
pip install -r requirements.txt

# Server starten mit PowerShell-Script (empfohlen)
.\start-rinnenprofi.ps1

# Oder manuell
py secure_server.py
```

**Features des sicheren Servers:**
- ✅ Rate Limiting (20 Anfragen/Sekunde pro IP)
- ✅ Blockiert .git/ Repository (KRITISCH!)
- ✅ Blockiert .env und Credentials
- ✅ Blockiert Backup-Dateien (.sql, .bak, etc.)
- ✅ Blockiert Exploit-Versuche automatisch
- ✅ Blockiert böse Bots
- ✅ Nur GET/HEAD Methoden erlaubt
- ✅ Erweiterte Sicherheits-Headers (CSP, Permissions-Policy)
- ✅ Spezielle Logging für kritische Angriffe

### Option 2: Nginx (Beste Leistung & Sicherheit)

Siehe `nginx-setup.md` für Details.

---

## 🛡️ Cloudflare Security Settings

Falls Sie Cloudflare Tunnel nutzen:

### 1. Firewall Rules (Security → WAF)

**Block common exploits:**
```
(http.request.uri.path contains "wp-admin") or
(http.request.uri.path contains ".git") or
(http.request.uri.path contains ".env") or
(http.request.uri.path contains "xmlrpc") or
(http.request.uri.path contains "phpmyadmin") or
(http.request.uri.path contains "/admin") or
(http.request.uri.path contains ".sql") or
(http.request.uri.path contains ".config") or
(http.request.uri.path contains "boaform") or
(http.request.uri.path contains "goform")
```
Action: **Block**

### 2. Rate Limiting (Security → Rate Limiting Rules)

**Rule 1: General protection**
- Request rate: 20 requests / 10 seconds
- Mit gleicher IP-Adresse
- Action: Block for 10 minutes

**Rule 2: Aggressive protection**
- Request rate: 100 requests / 1 minute
- Mit gleicher IP-Adresse
- Action: Block for 1 hour

### 3. Bot Fight Mode

Security → Bots → Bot Fight Mode: **ON**

### 4. Security Level

Security → Settings → Security Level: **High**

### 5. Browser Integrity Check

Security → Settings → Browser Integrity Check: **ON**

---

## 📊 Monitoring & Logs

### Cloudflare Analytics
- Gehen Sie zu: Analytics → Security
- Überwachen Sie blockierte Anfragen
- Prüfen Sie Top-Angreifer

### Lokale Logs überwachen

Bei `secure_server.py`:
```powershell
# Real-time log viewing
py secure_server.py
```

Symbole:
- ✅ = Legitime Anfrage
- 🚫 = Blockierte IP
- ⚠️  = Rate Limit überschritten
- 🚨 = Exploit-Versuch blockiert
- 🤖 = Bot blockiert
- ⛔ = Methode nicht erlaubt

---

## 🔒 Zusätzliche Empfehlungen

### 1. Firewall (Windows Defender)

```powershell
# Port 8080 nur für localhost öffnen (wenn Cloudflare Tunnel genutzt wird)
# Kein externer Zugriff nötig!
New-NetFirewallRule -DisplayName "Block 8080 External" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Block -RemoteAddress Any

New-NetFirewallRule -DisplayName "Allow 8080 Localhost" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow -RemoteAddress 127.0.0.1
```

### 2. HTTPS erzwingen (in Cloudflare)

SSL/TLS → Overview → SSL/TLS encryption mode: **Full (strict)**
SSL/TLS → Edge Certificates → Always Use HTTPS: **ON**

### 3. DDoS Protection

Automatisch aktiviert bei Cloudflare.

### 4. Geo-Blocking (optional)

Falls Sie nur deutsche Besucher erwarten:

Security → WAF → Create Rule:
```
(ip.geoip.country ne "DE") and (not ip.geoip.country in {"AT" "CH"})
```
Action: **Challenge** oder **Block**

---

## ⚡ Performance & Caching

### Cloudflare Caching

Speed → Caching → Configuration:

- Browser Cache TTL: **1 hour**
- Caching Level: **Standard**

### Cache Rules

```
Cache everything for:
- *.html (30 minutes)
- *.css (1 day)
- *.js (1 day)
- *.jpg, *.png (7 days)
```

---

## 📋 Checkliste

Sicherheit:
- [ ] Cloudflare Firewall Rules aktiviert
- [ ] Rate Limiting konfiguriert
- [ ] Bot Fight Mode aktiviert
- [ ] Security Level auf "High"
- [ ] Browser Integrity Check aktiviert
- [ ] Sicherer Server (nginx oder secure_server.py) läuft
- [ ] robots.txt deployt
- [ ] Windows Firewall konfiguriert

Performance:
- [ ] HTTPS erzwungen
- [ ] Caching aktiviert
- [ ] Browser Cache konfiguriert

Monitoring:
- [ ] Cloudflare Analytics überwacht
- [ ] Logs regelmäßig geprüft

---

## 🆘 Bei Angriff

Wenn Sie unter schwerem Angriff stehen:

1. **Cloudflare "Under Attack Mode"**
   - Security → Settings → Security Level: **I'm Under Attack!**
   - Zeigt Captcha vor dem Zugriff

2. **Alle Non-DE Länder blockieren**
   - Firewall Rule: Block all except Germany

3. **Rate Limits verschärfen**
   - 5 requests / 10 seconds

4. **Server temporär stoppen**
   - Cloudflare zeigt "Offline" Seite

---

## 📞 Support

Bei Fragen zur Sicherheit:
- Cloudflare Support: https://support.cloudflare.com/
- Cloudflare Community: https://community.cloudflare.com/








