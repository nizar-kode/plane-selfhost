# Plane Self-Hosted Reverse Proxy & SSL Integration Guide

While Plane includes a built-in Caddy proxy on ports `80` and `443`, many production deployments run behind an external reverse proxy, hardware load balancer, or Cloudflare Tunnel.

This guide explains how to integrate Plane with existing reverse proxies.

---

## 1. Port Reallocation

If your host machine already runs Nginx, Apache, or Traefik on ports `80` and `443`:

1. Change Plane's published host ports in `.env`:
   ```env
   LISTEN_HTTP_PORT=8080
   LISTEN_HTTPS_PORT=8443
   ```
2. Set `SITE_ADDRESS=:80` in `.env` so Plane's internal Caddy proxy listens without attempting to bind host port 80 directly.
3. Configure your external proxy to forward traffic to `http://127.0.0.1:8080`.

---

## 2. Nginx Reverse Proxy Setup

Create `/etc/nginx/sites-available/plane.conf`:

```nginx
server {
    listen 80;
    server_name plane.yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name plane.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/plane.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/plane.yourdomain.com/privkey.pem;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # WebSocket support for Plane Live collaboration
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Enable the site and reload Nginx:
```bash
sudo ln -s /etc/nginx/sites-available/plane.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## 3. Caddy Reverse Proxy Setup

If you run an external Caddy instance, add this block to your `/etc/caddy/Caddyfile`:

```caddy
plane.yourdomain.com {
    tls admin@yourdomain.com

    request_body {
        max_size 100MB
    }

    reverse_proxy 127.0.0.1:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-Proto https
    }
}
```

Reload Caddy:
```bash
sudo systemctl reload caddy
```

---

## 4. Cloudflare Tunnel (cloudflared)

Cloudflare Tunnel lets you publish Plane without opening inbound firewall ports:

1. Create a tunnel in your Cloudflare Zero Trust Dashboard.
2. In the Public Hostname section:
   * **Domain**: `plane.yourdomain.com`
   * **Service**: `HTTP`
   * **URL**: `localhost:8080` (or `localhost:80`)
3. Under Additional Application Settings:
   * **HTTP Settings -> HTTP2 Support**: Enabled
   * **No TLS Verify**: Enabled (if forwarding to HTTPS)
4. In Plane's `.env`, update:
   ```env
   WEB_URL=https://plane.yourdomain.com
   CORS_ALLOWED_ORIGINS=https://plane.yourdomain.com
   NUM_PROXIES=1
   ```
