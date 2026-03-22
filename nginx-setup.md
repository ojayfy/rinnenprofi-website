# Nginx Setup für Windows

## Installation
1. Download: https://nginx.org/en/download.html (Windows version)
2. Extrahieren nach: C:\nginx

## Konfiguration (C:\nginx\conf\nginx.conf)

```nginx
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    
    # Rate Limiting Zone
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=addr:10m;
    
    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    server {
        listen 8080;
        server_name localhost;
        
        # Document Root
        root C:/Users/Admin/Desktop/rinnenprofi-project;
        index index.html;
        
        # Rate Limiting
        limit_req zone=general burst=20 nodelay;
        limit_conn addr 10;
        
        # Größenlimit für Requests
        client_max_body_size 1M;
        
        # Block common exploit attempts
        location ~ /\. {
            deny all;
            return 404;
        }
        
        location ~ \.(git|env|config|bak|sql|log)$ {
            deny all;
            return 404;
        }
        
        location ~ /(wp-|wordpress|xmlrpc|phpmyadmin|admin) {
            deny all;
            return 404;
        }
        
        # Block bad bots
        if ($http_user_agent ~* (bot|crawler|spider|scraper)) {
            return 403;
        }
        
        # Serve files
        location / {
            try_files $uri $uri/ =404;
        }
        
        # Error pages
        error_page 404 /404.html;
        error_page 500 502 503 504 /50x.html;
    }
}
```

## Starten
```powershell
cd C:\nginx
start nginx
```

## Stoppen
```powershell
cd C:\nginx
nginx -s stop
```

## Neu laden (nach Config-Änderungen)
```powershell
nginx -s reload
```








