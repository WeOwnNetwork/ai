# WordPress Custom Site Development Guide

## Overview

This guide covers professional WordPress site development using the WeOwn modular template system. The architecture promotes reusable components, enterprise-grade security practices, performance optimization, and maintainable code patterns.

## Development Philosophy

### Core Principles

- **Child Theme First**: Never modify parent themes directly
- **Plugin Architecture**: Modular features as plugins
- **MU-Plugin Policies**: Site-wide mandatory functionality
- **Security by Design**: Zero-trust security patterns
- **Performance Optimization**: Conditional loading and caching
- **Accessibility Compliance**: WCAG 2.1 AA standards
- **Modern Development**: ES6+, CSS Grid, Progressive Enhancement

### Template System Architecture

```
wordpress-dev/
├── template/                    # Master reusable template
│   └── wp-content/
│       ├── themes/weown-starter/   # Brand-agnostic child theme
│       ├── plugins/                # Feature plugins
│       └── mu-plugins/             # Mandatory site policies
└── sites/{site}/               # Site-specific overlays
    ├── site.config.yaml        # Branding and configuration
    ├── values-staging.yaml     # Staging deployment config
    ├── values-prod.yaml        # Production deployment config
    └── overrides/              # Site-specific customizations
```

## Child Theme Development

### weown-starter Child Theme

The master child theme inherits from Kadence and provides:
- Brand-agnostic styling system
- Conditional asset loading
- Page template system
- Modern development patterns

### Theme Structure

```
template/wp-content/themes/weown-starter/
├── style.css                   # Theme metadata and base styles
├── functions.php               # Theme functionality
├── templates/                  # Page templates
│   └── landing.php            # Landing page template
└── assets/                    # Theme assets
    ├── css/
    │   └── site.css           # Scoped component styles
    └── js/
        └── site.js            # Theme JavaScript
```

### Conditional Asset Loading

The theme implements performance-focused asset loading:

```php
// functions.php - Conditional enqueuing
function weown_starter_enqueue_assets() {
    wp_enqueue_style('weown-starter-style', get_stylesheet_uri());
    
    // Page-specific assets
    if (is_page_template('templates/landing.php')) {
        wp_enqueue_style('weown-landing', 
            get_stylesheet_directory_uri() . '/assets/css/site.css');
        wp_enqueue_script('weown-landing', 
            get_stylesheet_directory_uri() . '/assets/js/site.js', 
            array(), '1.0.0', true);
    }
}
```

### CSS Architecture

Use CSS custom properties for themeable values:

```css
/* style.css - Theme variables */
:root {
    --primary-color: var(--site-primary, #1e40af);
    --secondary-color: var(--site-secondary, #64748b);
    --accent-color: var(--site-accent, #f59e0b);
}

/* Component-scoped styles */
.weown-landing {
    background: var(--primary-color);
    color: var(--text-on-primary, white);
}
```

## Plugin Development

### Feature Plugin Architecture

Develop features as self-contained plugins for modularity:

```php
<?php
/**
 * Plugin Name: WeOwn Landing
 * Description: Custom landing page functionality
 * Version: 1.0.0
 * Author: WeOwn
 */

// Prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

class WeOwn_Landing {
    public function __construct() {
        add_action('init', array($this, 'add_rewrite_rules'));
        add_action('template_redirect', array($this, 'template_redirect'));
        register_activation_hook(__FILE__, array($this, 'activate'));
    }
    
    public function add_rewrite_rules() {
        add_rewrite_rule(
            '^weown-landing/?$',
            'index.php?weown_landing=1',
            'top'
        );
        add_rewrite_tag('%weown_landing%', '([^&]+)');
    }
    
    public function template_redirect() {
        if (get_query_var('weown_landing')) {
            include plugin_dir_path(__FILE__) . 'templates/landing.php';
            exit;
        }
    }
    
    public function activate() {
        $this->add_rewrite_rules();
        flush_rewrite_rules();
    }
}

new WeOwn_Landing();
```

### Plugin Security Patterns

Implement security best practices:

```php
// Nonce verification
if (!wp_verify_nonce($_POST['_wpnonce'], 'weown_action')) {
    wp_die('Security check failed');
}

// Input sanitization
$user_input = sanitize_text_field($_POST['user_data']);

// Output escaping
echo esc_html($user_data);

// SQL preparation
$results = $wpdb->get_results(
    $wpdb->prepare(
        "SELECT * FROM {$wpdb->posts} WHERE post_title = %s",
        $search_term
    )
);
```

## MU-Plugin Development

### Mandatory Site Policies

MU-plugins enforce site-wide policies and cannot be disabled:

```php
<?php
// mu-plugins/weown-loader.php
// Bootstrap loader for WeOwn policies

foreach (glob(dirname(__FILE__) . '/weown/*.php') as $file) {
    require_once $file;
}
```

### Security Hardening

Implement enterprise security policies:

```php
<?php
// mu-plugins/weown/hardening.php

// Disable file editing
define('DISALLOW_FILE_EDIT', true);

// Security headers
function weown_security_headers() {
    if (!is_admin()) {
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: SAMEORIGIN');
        header('X-XSS-Protection: 1; mode=block');
        header('Referrer-Policy: strict-origin-when-cross-origin');
    }
}
add_action('send_headers', 'weown_security_headers');

// Disable XML-RPC
add_filter('xmlrpc_enabled', '__return_false');

// Remove version info
remove_action('wp_head', 'wp_generator');
```

## Site Overlay Development

### Site Configuration

Customize sites via `site.config.yaml`:

```yaml
site:
  key: alpha
  name: "Alpha Cohort Site"
  domain: "alpha.weown.com"
  description: "Alpha cohort member portal"

branding:
  primary_color: "#1e40af"
  secondary_color: "#64748b"
  accent_color: "#f59e0b"
  logo_path: "/assets/images/alpha-logo.svg"

features:
  multisite: false
  ecommerce: false
  membership: true
  analytics: true

integrations:
  google_analytics: "G-XXXXXXXX"
  mailchimp_api: ""
  stripe_publishable: ""
```

### Site-Specific Overrides

Create minimal overrides in `sites/{site}/overrides/wp-content/`:

```php
<?php
// sites/alpha/overrides/wp-content/themes/weown-starter/templates/landing-alt.php

get_header(); ?>

<main class="alpha-landing" role="main">
    <section class="hero alpha-hero">
        <h1>Welcome to Alpha Cohort</h1>
        <p>Exclusive member portal for Alpha participants</p>
    </section>
</main>

<?php get_footer(); ?>
```

## Security Best Practices

### Input Validation

Always validate and sanitize user input:

```php
// Text fields
$name = sanitize_text_field($_POST['name']);

// Email addresses
$email = sanitize_email($_POST['email']);

// URLs
$website = esc_url_raw($_POST['website']);

// Rich text content
$content = wp_kses_post($_POST['content']);

// File uploads
$file = sanitize_file_name($_FILES['upload']['name']);
```

### Output Escaping

Escape all output based on context:

```php
// HTML content
echo esc_html($user_data);

// HTML attributes
echo '<div class="' . esc_attr($css_class) . '">';

// URLs
echo '<a href="' . esc_url($link) . '">';

// JavaScript
echo '<script>var data = ' . wp_json_encode($data) . ';</script>';
```

### Database Security

Use prepared statements for all database queries:

```php
global $wpdb;

// Correct - prepared statement
$results = $wpdb->get_results(
    $wpdb->prepare(
        "SELECT * FROM {$wpdb->posts} WHERE post_status = %s AND post_author = %d",
        'publish',
        $author_id
    )
);
```

## Performance Optimization

### Asset Optimization

Implement efficient asset loading strategies:

```php
// Conditional loading
function weown_conditional_assets() {
    // Only load on specific pages
    if (is_page('contact')) {
        wp_enqueue_script('contact-form');
    }
    
    // Load critical CSS inline
    if (is_front_page()) {
        $critical_css = file_get_contents(get_template_directory() . '/assets/css/critical.css');
        echo '<style>' . $critical_css . '</style>';
    }
}

// Defer non-critical JavaScript
function weown_defer_scripts($tag, $handle, $src) {
    if (in_array($handle, array('non-critical-script'))) {
        return str_replace(' src', ' defer src', $tag);
    }
    return $tag;
}
add_filter('script_loader_tag', 'weown_defer_scripts', 10, 3);
```

### Database Optimization

Optimize database queries and caching:

```php
// Use transients for expensive operations
function weown_get_popular_posts() {
    $cache_key = 'weown_popular_posts';
    $posts = get_transient($cache_key);
    
    if (false === $posts) {
        $posts = get_posts(array(
            'meta_key' => 'view_count',
            'orderby' => 'meta_value_num',
            'order' => 'DESC',
            'posts_per_page' => 5
        ));
        
        set_transient($cache_key, $posts, HOUR_IN_SECONDS);
    }
    
    return $posts;
}
```

## Accessibility Implementation

### Semantic HTML

Use proper HTML5 semantic elements:

```html
<!-- Good semantic structure -->
<article role="article">
    <header>
        <h1>Article Title</h1>
        <time datetime="2024-01-15">January 15, 2024</time>
    </header>
    
    <main>
        <p>Article content...</p>
    </main>
    
    <footer>
        <p>Author: <span itemprop="author">John Doe</span></p>
    </footer>
</article>
```

### ARIA Implementation

Implement ARIA attributes for enhanced accessibility:

```html
<!-- Navigation -->
<nav role="navigation" aria-label="Main navigation">
    <ul>
        <li><a href="/" aria-current="page">Home</a></li>
        <li><a href="/about">About</a></li>
    </ul>
</nav>

<!-- Modal dialogs -->
<div role="dialog" aria-labelledby="modal-title" aria-describedby="modal-desc" aria-modal="true">
    <h2 id="modal-title">Confirmation</h2>
    <p id="modal-desc">Are you sure you want to proceed?</p>
    <button type="button" aria-label="Close dialog">×</button>
</div>
```

## UX Design Patterns

### Progressive Enhancement

Build features that work without JavaScript:

```html
<!-- Base HTML form -->
<form method="post" action="/submit">
    <input type="text" name="query" placeholder="Search...">
    <button type="submit">Search</button>
</form>

<!-- Enhanced with JavaScript -->
<script>
document.addEventListener('DOMContentLoaded', function() {
    const form = document.querySelector('form');
    const input = form.querySelector('input[name="query"]');
    
    // Add real-time search enhancement
    input.addEventListener('input', debounce(function() {
        performSearch(this.value);
    }, 300));
});
</script>
```

### Loading States

Provide clear feedback during async operations:

```javascript
async function submitForm(formData) {
    const button = document.querySelector('button[type="submit"]');
    const originalText = button.textContent;
    
    // Show loading state
    button.textContent = 'Submitting...';
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    
    try {
        const response = await fetch('/api/submit', {
            method: 'POST',
            body: formData
        });
        
        if (response.ok) {
            button.textContent = 'Success!';
        } else {
            throw new Error('Submission failed');
        }
    } catch (error) {
        button.textContent = 'Error - Try Again';
    } finally {
        button.disabled = false;
        button.removeAttribute('aria-busy');
        
        // Reset after delay
        setTimeout(() => {
            button.textContent = originalText;
        }, 3000);
    }
}
```

## Custom Routing Strategies

### Virtual Pages

Create dynamic content without database entries:

```php
class WeOwn_Virtual_Pages {
    private $pages = array();
    
    public function __construct() {
        add_action('init', array($this, 'add_rewrite_rules'));
        add_action('template_redirect', array($this, 'template_redirect'));
    }
    
    public function add_page($slug, $template, $title) {
        $this->pages[$slug] = array(
            'template' => $template,
            'title' => $title
        );
        
        add_rewrite_rule(
            "^{$slug}/?$",
            "index.php?virtual_page={$slug}",
            'top'
        );
        add_rewrite_tag('%virtual_page%', '([^&]+)');
    }
    
    public function template_redirect() {
        $page = get_query_var('virtual_page');
        if ($page && isset($this->pages[$page])) {
            include $this->pages[$page]['template'];
            exit;
        }
    }
}

// Usage
$virtual_pages = new WeOwn_Virtual_Pages();
$virtual_pages->add_page('dashboard', get_template_directory() . '/templates/dashboard.php', 'User Dashboard');
```

### API Endpoints

Create custom REST API endpoints:

```php
class WeOwn_API {
    public function __construct() {
        add_action('rest_api_init', array($this, 'register_routes'));
    }
    
    public function register_routes() {
        register_rest_route('weown/v1', '/search', array(
            'methods' => 'GET',
            'callback' => array($this, 'search_content'),
            'permission_callback' => '__return_true',
            'args' => array(
                'query' => array(
                    'required' => true,
                    'sanitize_callback' => 'sanitize_text_field',
                ),
                'limit' => array(
                    'default' => 10,
                    'sanitize_callback' => 'absint',
                ),
            ),
        ));
    }
    
    public function search_content($request) {
        $query = $request->get_param('query');
        $limit = $request->get_param('limit');
        
        $posts = get_posts(array(
            's' => $query,
            'posts_per_page' => $limit,
            'post_status' => 'publish',
        ));
        
        $results = array();
        foreach ($posts as $post) {
            $results[] = array(
                'id' => $post->ID,
                'title' => $post->post_title,
                'excerpt' => get_the_excerpt($post),
                'url' => get_permalink($post),
            );
        }
        
        return new WP_REST_Response($results, 200);
    }
}

new WeOwn_API();
```

## Testing & Quality Assurance

### Unit Testing

Write testable code with dependency injection:

```php
class WeOwn_Service {
    private $db;
    private $cache;
    
    public function __construct($db = null, $cache = null) {
        $this->db = $db ?: $GLOBALS['wpdb'];
        $this->cache = $cache ?: wp_cache_get_instance();
    }
    
    public function get_user_data($user_id) {
        $cache_key = "user_data_{$user_id}";
        $data = $this->cache->get($cache_key);
        
        if (false === $data) {
            $data = $this->db->get_row(
                $this->db->prepare(
                    "SELECT * FROM user_profiles WHERE user_id = %d",
                    $user_id
                )
            );
            $this->cache->set($cache_key, $data, 300);
        }
        
        return $data;
    }
}
```

## Development Tools & Workflow

### Local Development Setup

Use Docker for consistent development environments:

```yaml
# docker-compose.yml
version: '3.8'
services:
  wordpress:
    image: wordpress:php8.3-apache
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: password
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - ./wordpress-dev/template/wp-content:/var/www/html/wp-content
    depends_on:
      - db
  
  db:
    image: mariadb:11.1
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: password
      MYSQL_ROOT_PASSWORD: rootpassword
    volumes:
      - db_data:/var/lib/mysql

volumes:
  db_data:
```

### Build Tools

Use modern build tools for asset optimization:

```json
{
  "name": "weown-theme-build",
  "scripts": {
    "build": "webpack --mode=production",
    "dev": "webpack --mode=development --watch",
    "lint:css": "stylelint 'assets/src/css/**/*.css'",
    "lint:js": "eslint 'assets/src/js/**/*.js'"
  },
  "devDependencies": {
    "webpack": "^5.0.0",
    "babel-loader": "^9.0.0",
    "css-loader": "^6.0.0",
    "postcss-loader": "^7.0.0",
    "eslint": "^8.0.0",
    "stylelint": "^15.0.0"
  }
}
```

## Deployment Considerations

### Environment Configuration

Use environment-specific configurations:

```php
// wp-config.php additions
switch (WP_ENVIRONMENT_TYPE) {
    case 'development':
        define('WP_DEBUG', true);
        define('WP_DEBUG_LOG', true);
        define('WP_DEBUG_DISPLAY', true);
        break;
    
    case 'staging':
        define('WP_DEBUG', true);
        define('WP_DEBUG_LOG', true);
        define('WP_DEBUG_DISPLAY', false);
        break;
    
    case 'production':
    default:
        define('WP_DEBUG', false);
        define('WP_DEBUG_LOG', false);
        define('WP_DEBUG_DISPLAY', false);
        break;
}
```

---

**Last Updated:** $(date)
**Version:** 1.0.0
**Maintainer:** WeOwn Development Team
