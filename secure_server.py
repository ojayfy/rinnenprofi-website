"""
Sicherer HTTP Server mit Rate Limiting und Schutzmaßnahmen
"""
import asyncio
from aiohttp import web
from collections import defaultdict
from datetime import datetime, timedelta, timezone
import re

BLOCK_DURATION_SECONDS = 600
CLEANUP_INTERVAL_SECONDS = 300

def get_timestamp():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

request_counts = defaultdict(list)
blocked_ips = {}  # ip -> unblock_time

BLOCKED_PATTERNS = [
    r'/\.git', r'/\.svn', r'/\.hg',
    r'/\.env', r'/env\.', r'/config\.', r'/\.aws', r'/\.docker',
    r'terraform\.tfstate', r'/credentials', r'/\.DS_Store',
    r'/wp-', r'/wordpress', r'/xmlrpc',
    r'/phpmyadmin', r'/admin', r'/manager', r'/cgi-bin',
    r'/actuator', r'/boaform', r'/goform', r'/hudson', r'/login',
    r'\.bak$', r'\.sql$', r'\.old$', r'\.backup$', r'\.config$',
    r'backup\.zip', r'dump\.sql', r'database\.sql',
    r'/phpinfo', r'/debug', r'/swagger', r'/api-docs',
]

BLOCKED_PATTERN = re.compile('|'.join(BLOCKED_PATTERNS), re.IGNORECASE)

ALLOWED_BOTS = ['googlebot', 'bingbot', 'duckduckbot', 'applebot']
BAD_USER_AGENTS = ['crawler', 'spider', 'scraper', 'scanner', 'nikto',
                   'sqlmap', 'nmap', 'masscan', 'dirbuster']

def cleanup_expired():
    """Remove expired blocks and stale rate-limit entries."""
    now = datetime.now(timezone.utc)

    expired = [ip for ip, unblock in blocked_ips.items() if now >= unblock]
    for ip in expired:
        del blocked_ips[ip]

    stale = [ip for ip, times in request_counts.items() if not times]
    for ip in stale:
        del request_counts[ip]

def is_rate_limited(ip: str, max_requests: int = 20, window_seconds: int = 1) -> bool:
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(seconds=window_seconds)

    request_counts[ip] = [t for t in request_counts[ip] if t > cutoff]

    if len(request_counts[ip]) >= max_requests:
        return True

    request_counts[ip].append(now)
    return False

def is_blocked_request(path: str) -> bool:
    return bool(BLOCKED_PATTERN.search(path))

def is_bad_user_agent(user_agent: str) -> bool:
    if not user_agent:
        return False
    ua_lower = user_agent.lower()
    if any(allowed in ua_lower for allowed in ALLOWED_BOTS):
        return False
    return any(bad in ua_lower for bad in BAD_USER_AGENTS)

@web.middleware
async def security_middleware(request, handler):
    ip = request.headers.get('CF-Connecting-IP') or \
         request.headers.get('X-Forwarded-For', '').split(',')[0].strip() or \
         request.remote
    path = request.path
    user_agent = request.headers.get('User-Agent', '')

    if ip in blocked_ips:
        if datetime.now(timezone.utc) >= blocked_ips[ip]:
            del blocked_ips[ip]
        else:
            print(f"{get_timestamp()} [BLOCKED] IP: {ip}")
            return web.Response(status=403, text="Forbidden")

    if is_rate_limited(ip):
        print(f"{get_timestamp()} [RATE LIMIT] IP exceeded limit: {ip}")
        blocked_ips[ip] = datetime.now(timezone.utc) + timedelta(seconds=BLOCK_DURATION_SECONDS)
        return web.Response(status=429, text="Too Many Requests")

    if is_blocked_request(path):
        if '.git' in path.lower():
            print(f"{get_timestamp()} [CRITICAL] Git repository access blocked: {ip} -> {path}")
            print(f"{get_timestamp()}            User-Agent: {user_agent[:100]}")
        else:
            print(f"{get_timestamp()} [EXPLOIT] Attack blocked: {ip} -> {path}")
        return web.Response(status=404, text="Not Found")

    if is_bad_user_agent(user_agent):
        print(f"{get_timestamp()} [BOT] Bad bot blocked: {ip} -> {user_agent[:50]}")
        return web.Response(status=403, text="Forbidden")

    if request.method not in ['GET', 'HEAD']:
        print(f"{get_timestamp()} [METHOD] Not allowed: {ip} -> {request.method} {path}")
        return web.Response(status=405, text="Method Not Allowed")

    response = await handler(request)

    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'no-referrer-when-downgrade'
    response.headers['Content-Security-Policy'] = "default-src 'self' 'unsafe-inline'"
    response.headers['Permissions-Policy'] = 'geolocation=(), microphone=(), camera=()'

    if path in ['/', '/robots.txt', '/style.css', '/impressum.html']:
        print(f"{get_timestamp()} [OK] {ip} -> {path}")

    return response

async def periodic_cleanup(app):
    """Background task that prunes stale rate-limit and block entries."""
    try:
        while True:
            await asyncio.sleep(CLEANUP_INTERVAL_SECONDS)
            cleanup_expired()
    except asyncio.CancelledError:
        pass

async def start_background_tasks(app):
    app['cleanup_task'] = asyncio.ensure_future(periodic_cleanup(app))

async def stop_background_tasks(app):
    app['cleanup_task'].cancel()
    await app['cleanup_task']

async def serve_file(request, filename):
    try:
        return web.FileResponse(filename)
    except FileNotFoundError:
        return web.Response(status=404, text="Not Found")

async def init_app():
    app = web.Application(middlewares=[security_middleware])

    app.router.add_get('/', lambda req: serve_file(req, 'index.html'))
    app.router.add_get('/index.html', lambda req: serve_file(req, 'index.html'))
    app.router.add_get('/impressum.html', lambda req: serve_file(req, 'impressum.html'))
    app.router.add_get('/style.css', lambda req: serve_file(req, 'style.css'))
    app.router.add_get('/robots.txt', lambda req: serve_file(req, 'robots.txt'))

    app.on_startup.append(start_background_tasks)
    app.on_cleanup.append(stop_background_tasks)

    return app

if __name__ == '__main__':
    print("=" * 50)
    print("SECURE HTTP SERVER")
    print("=" * 50)
    print("Listening on: http://localhost:8080")
    print(f"Rate limit: 20 requests/second per IP")
    print(f"IP block duration: {BLOCK_DURATION_SECONDS}s")
    print(f"Cleanup interval: {CLEANUP_INTERVAL_SECONDS}s")
    print("Exploit patterns: BLOCKED")
    print("=" * 50)

    web.run_app(init_app(), host='localhost', port=8080)








