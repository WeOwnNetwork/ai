# Wordfence WAF Configuration

This directory contains the Wordfence Web Application Firewall (WAF) configuration for Caddy + PHP-FPM deployments.

## Why This Exists

Wordfence WAF requires PHP to execute `wordfence-waf.php` before any other WordPress code runs. The standard methods to achieve this are:

| Server | Method | File |
|--------|--------|------|
| Apache | `.htaccess` | `php_value auto_prepend_file` |
| Nginx | `php.ini` / `fastcgi_param` | `PHP_VALUE "auto_prepend_file=..."` |
| **Caddy** | `.user.ini` | `auto_prepend_file = '...'` |

Caddy does NOT support `.htaccess` or `fastcgi_param` directives for PHP configuration, so we use `.user.ini` instead.

## Security

The `.user.ini` file is mounted read-only into the WordPress container and direct web access is blocked in the Caddyfile:

```caddyfile
@userini path /.user.ini
respond @userini 403
```

## Activation

1. Deploy the WordPress stack
2. Install the Wordfence plugin via WordPress admin
3. Navigate to Wordfence → Firewall → Manage WAF
4. Click "Optimize Firewall" - it should auto-detect the `.user.ini` configuration

## Troubleshooting

If WAF optimization fails:
1. SSH into the droplet
2. Verify `.user.ini` exists: `docker exec <wp-container> cat /var/www/html/.user.ini`
3. Check PHP is reading it: `docker exec <wp-container> php -i | grep user.ini`
