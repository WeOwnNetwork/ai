<?php
/**
 * WeOwn Starter Theme Functions
 *
 * Enterprise-grade WordPress child theme with advanced modularity,
 * dynamic branding system, and AI integration capabilities.
 *
 * Features:
 * - Dynamic branding system with site configuration parsing
 * - Template parts architecture for maximum reusability
 * - Performance-optimized asset loading and caching
 * - Accessibility-compliant structure throughout
 * - SEO optimization with schema markup
 * - Security-first development patterns
 *
 * @package WeOwn_Starter
 * @version 1.0.0
 * @author WeOwn Development Team
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Theme Setup and WordPress Integration
 *
 * Initialize theme functionality, register support features, and
 * integrate with WordPress core systems for optimal performance.
 */
function weown_starter_setup() {
    // Theme text domain for internationalization
    load_theme_textdomain('weown-starter', get_template_directory() . '/languages');

    // Add default posts and comments RSS feed links to head
    add_theme_support('automatic-feed-links');

    // Let WordPress manage the document title
    add_theme_support('title-tag');

    // Enable support for Post Thumbnails on posts and pages
    add_theme_support('post-thumbnails');

    // Add theme support for selective refresh for widgets
    add_theme_support('customize-selective-refresh-widgets');

    // Add support for custom logo
    add_theme_support('custom-logo', [
        'height'      => 100,
        'width'       => 300,
        'flex-height' => true,
        'flex-width'  => true,
    ]);

    // Add support for custom header
    add_theme_support('custom-header', [
        'default-image' => '',
        'width'         => 1200,
        'height'        => 400,
        'flex-height'   => true,
        'flex-width'    => true,
    ]);

    // Add support for custom background
    add_theme_support('custom-background', [
        'default-color' => 'ffffff',
    ]);

    // Add support for HTML5 markup
    add_theme_support('html5', [
        'search-form',
        'comment-form',
        'comment-list',
        'gallery',
        'caption',
        'style',
        'script',
    ]);

    // Add support for wide and full alignment
    add_theme_support('align-wide');

    // Add support for editor styles
    add_theme_support('editor-styles');
    add_editor_style('assets/css/editor.css');

    // Register navigation menus
    register_nav_menus([
        'primary' => __('Primary Menu', 'weown-starter'),
        'footer'  => __('Footer Menu', 'weown-starter'),
        'social'  => __('Social Links Menu', 'weown-starter'),
    ]);

    // Register widget areas
    weown_register_widget_areas();
}
add_action('after_setup_theme', 'weown_starter_setup');

/**
 * Register Widget Areas
 *
 * Define footer and sidebar widget areas with proper configuration
 * and accessibility features for flexible content layout.
 */
function weown_register_widget_areas() {
    // Footer widget areas
    for ($i = 1; $i <= 4; $i++) {
        register_sidebar([
            'name'          => sprintf(__('Footer Widget Area %d', 'weown-starter'), $i),
            'id'            => 'footer-' . $i,
            'description'   => sprintf(__('Add widgets here to appear in footer area %d.', 'weown-starter'), $i),
            'before_widget' => '<section id="%1$s" class="widget %2$s">',
            'after_widget'  => '</section>',
            'before_title'  => '<h3 class="widget-title">',
            'after_title'   => '</h3>',
        ]);
    }

    // Sidebar widget area
    register_sidebar([
        'name'          => __('Sidebar', 'weown-starter'),
        'id'            => 'sidebar-1',
        'description'   => __('Add widgets here to appear in the sidebar.', 'weown-starter'),
        'before_widget' => '<section id="%1$s" class="widget %2$s">',
        'after_widget'  => '</section>',
        'before_title'  => '<h3 class="widget-title">',
        'after_title'   => '</h3>',
    ]);
}

/**
 * Enqueue Scripts and Styles
 *
 * Load theme assets with performance optimization and conditional loading
 * for improved page speed and user experience.
 */
function weown_starter_enqueue_assets() {
    $theme_version = wp_get_theme()->get('Version');

    // Parent theme stylesheet
    wp_enqueue_style('parent-style', get_template_directory_uri() . '/style.css', [], wp_get_theme(get_template())->get('Version'));

    // Child theme stylesheet
    wp_enqueue_style('weown-starter-style', get_stylesheet_uri(), ['parent-style'], $theme_version);

    // Theme JavaScript
    wp_enqueue_script('weown-starter-script', get_stylesheet_directory_uri() . '/assets/js/theme.js', ['jquery'], $theme_version, true);

    // Localize script for AJAX and theme data
    wp_localize_script('weown-starter-script', 'weown_starter', [
        'ajax_url' => admin_url('admin-ajax.php'),
        'nonce'    => wp_create_nonce('weown_starter_nonce'),
        'strings'  => [
            'menu_toggle' => __('Toggle Menu', 'weown-starter'),
            'menu_close'  => __('Close Menu', 'weown-starter'),
        ],
    ]);

    // Conditional asset loading for specific pages
    if (is_page_template('templates/landing.php') || is_front_page()) {
        wp_enqueue_style('weown-starter-landing', get_stylesheet_directory_uri() . '/assets/css/landing.css', [], $theme_version);
        wp_enqueue_script('weown-starter-landing', get_stylesheet_directory_uri() . '/assets/js/landing.js', ['weown-starter-script'], $theme_version, true);
    }
}
add_action('wp_enqueue_scripts', 'weown_starter_enqueue_assets');

/**
 * Dynamic Branding System - Site Configuration Parser
 *
 * Parse site configuration files and inject dynamic branding elements
 * for real-time customization without code changes.
 */
function weown_get_brand_config($site_key = null) {
    // Default configuration
    $default_config = [
        'key' => 'default',
        'name' => get_bloginfo('name'),
        'domain' => get_site_url(),
        'palette' => [
            'primary' => '#1e40af',
            'secondary' => '#64748b',
            'accent' => '#f59e0b',
        ],
        'logo' => '',
        'features' => [
            'landing_route' => true,
            'forms' => false,
            'analytics' => true,
        ],
    ];

    // Try to load site-specific configuration
    if ($site_key) {
        $config_file = get_stylesheet_directory() . "/../../sites/{$site_key}/site.config.yaml";
        if (file_exists($config_file)) {
            // Parse YAML configuration (requires YAML parser)
            if (function_exists('yaml_parse_file')) {
                $site_config = yaml_parse_file($config_file);
                return wp_parse_args($site_config, $default_config);
            }
        }
    }

    return $default_config;
}

/**
 * Get Brand Colors for Dynamic CSS Injection
 *
 * Extract brand colors from site configuration for real-time
 * CSS custom property injection and theme customization.
 */
function weown_get_brand_colors($brand_config = null) {
    if (!$brand_config) {
        $brand_config = weown_get_brand_config();
    }

    $palette = $brand_config['palette'] ?? [];

    return [
        'primary' => $palette['primary'] ?? '#1e40af',
        'secondary' => $palette['secondary'] ?? '#64748b',
        'accent' => $palette['accent'] ?? '#f59e0b',
        'text' => '#1f2937',
        'text-light' => '#6b7280',
        'background' => '#ffffff',
        'surface' => '#f9fafb',
    ];
}

/**
 * Inject Brand CSS Custom Properties
 *
 * Dynamically inject brand colors as CSS custom properties for
 * real-time theme customization and consistency.
 */
function weown_inject_brand_css($colors = null) {
    if (!$colors) {
        $colors = weown_get_brand_colors();
    }

    ?>
    <style>
    :root {
        --weown-primary-color: <?php echo esc_attr($colors['primary']); ?>;
        --weown-secondary-color: <?php echo esc_attr($colors['secondary']); ?>;
        --weown-accent-color: <?php echo esc_attr($colors['accent']); ?>;
        --weown-text-color: <?php echo esc_attr($colors['text']); ?>;
        --weown-text-light-color: <?php echo esc_attr($colors['text-light']); ?>;
        --weown-background-color: <?php echo esc_attr($colors['background']); ?>;
        --weown-surface-color: <?php echo esc_attr($colors['surface']); ?>;
    }
    </style>
    <?php
}

/**
 * Template Part Loading Functions
 *
 * Helper functions for conditional template part loading based on
 * page context and theme configuration for optimal flexibility.
 */
function weown_get_hero_config() {
    return [
        'layout' => 'centered',
        'style' => 'solid',
        'show_scroll_indicator' => true,
        'show_social_proof' => false,
    ];
}

function weown_get_cta_config() {
    return [
        'layout' => 'centered',
        'style' => 'primary',
        'show_social_proof' => false,
        'show_urgency' => false,
    ];
}

/**
 * Content and Schema Functions
 *
 * Helper functions for content display, schema markup, and
 * accessibility enhancements throughout the theme.
 */
function weown_get_main_schema() {
    $schema = 'itemscope itemtype="https://schema.org/WebPage"';

    if (is_single()) {
        $schema = 'itemscope itemtype="https://schema.org/BlogPosting"';
    } elseif (is_page()) {
        $schema = 'itemscope itemtype="https://schema.org/WebPage"';
    }

    return $schema;
}

function weown_get_body_classes() {
    $classes = [];

    // Layout classes
    if (is_page_template()) {
        $classes[] = 'page-template-' . sanitize_html_class(str_replace('.', '-', get_page_template_slug()));
    }

    // Customizer classes
    if (get_theme_mod('custom_layout')) {
        $classes[] = 'custom-layout';
    }

    return $classes;
}

/**
 * Navigation and Menu Functions
 *
 * Enhanced navigation functionality with fallback support and
 * accessibility features for optimal user experience.
 */
function weown_navigation_fallback() {
    ?>
    <ul id="primary-menu" class="weown-primary-menu">
        <li><a href="<?php echo esc_url(home_url('/')); ?>"><?php esc_html_e('Home', 'weown-starter'); ?></a></li>
        <?php wp_list_pages(['title_li' => '', 'depth' => 1]); ?>
    </ul>
    <?php
}

/**
 * Widget and Sidebar Functions
 *
 * Helper functions for widget area management and fallback content
 * for improved user experience and design consistency.
 */
function weown_footer_widget_fallback($widget_area) {
    if ($widget_area === 'footer-1') {
        ?>
        <h3><?php esc_html_e('About Us', 'weown-starter'); ?></h3>
        <p><?php esc_html_e('Welcome to our website. We provide quality services and products.', 'weown-starter'); ?></p>
        <?php
    } elseif ($widget_area === 'footer-2') {
        ?>
        <h3><?php esc_html_e('Quick Links', 'weown-starter'); ?></h3>
        <ul>
            <li><a href="#"><?php esc_html_e('Services', 'weown-starter'); ?></a></li>
            <li><a href="#"><?php esc_html_e('About', 'weown-starter'); ?></a></li>
            <li><a href="#"><?php esc_html_e('Contact', 'weown-starter'); ?></a></li>
        </ul>
        <?php
    }
}

/**
 * Performance and Optimization Functions
 *
 * Functions for performance optimization, caching, and
 * improved loading speeds for better user experience.
 */
function weown_get_content_class($layout = 'full-width') {
    $classes = ['weown-main-content'];

    switch ($layout) {
        case 'with-sidebar':
            $classes[] = 'weown-has-sidebar';
            $classes[] = 'weown-sidebar-right';
            break;
        case 'sidebar-left':
            $classes[] = 'weown-has-sidebar';
            $classes[] = 'weown-sidebar-left';
            break;
        default:
            $classes[] = 'weown-full-width';
    }

    return implode(' ', $classes);
}

/**
 * Accessibility and SEO Functions
 *
 * Helper functions for accessibility compliance and SEO optimization
 * to ensure the theme meets modern web standards.
 */
function weown_pagination() {
    global $wp_query;

    if ($wp_query->max_num_pages <= 1) {
        return;
    }

    ?>
    <nav class="weown-pagination" role="navigation" aria-label="<?php esc_attr_e('Posts Navigation', 'weown-starter'); ?>">
        <h3 class="screen-reader-text"><?php esc_html_e('Posts Navigation', 'weown-starter'); ?></h3>

        <?php
        echo paginate_links([
            'mid_size'  => 2,
            'prev_text' => sprintf('<span aria-hidden="true">%s</span>', __('‹ Previous', 'weown-starter')),
            'next_text' => sprintf('<span aria-hidden="true">%s</span>', __('Next ›', 'weown-starter')),
        ]);
        ?>
    </nav>
    <?php
}

/**
 * Security and Validation Functions
 *
 * Security-first helper functions with proper input sanitization
 * and validation for enhanced theme security.
 */
function weown_sanitize_hex_color($color) {
    if (empty($color) || !preg_match('/^#([a-f0-9]{3}){1,2}$/i', $color)) {
        return '';
    }
    return sanitize_hex_color($color);
}

/**
 * Theme Customization API
 *
 * Functions for theme customization, options management, and
 * integration with the WordPress Customizer API.
 */
function weown_get_theme_option($option_name, $default = '') {
    $options = get_theme_mods();
    return isset($options[$option_name]) ? $options[$option_name] : $default;
}

/**
 * Stub Functions for Template Compatibility
 *
 * Temporary stub functions to prevent PHP fatal errors while templates
 * are being developed. These should be replaced with full implementations.
 */

// Cohort/Landing Page Functions
function weown_get_cohort_config() {
    return [
        'type' => 'educational_cohort',
        'format' => 'live_webinar',
        'goal' => 'enrollment'
    ];
}

function weown_cohort_urgency_elements() {
    echo '<div class="urgency-timer">Limited spots available - Register now!</div>';
}

function weown_cohort_event_details($format) {
    echo '<p>Event Format: ' . esc_html(ucfirst(str_replace('_', ' ', $format))) . '</p>';
}

function weown_cohort_hero_preview($type) {
    echo '<div class="hero-preview">Event preview for ' . esc_html($type) . '</div>';
}

function weown_cohort_curriculum_timeline() {
    echo '<div class="curriculum-timeline">Curriculum outline coming soon...</div>';
}

function weown_cohort_instructor_profiles() {
    echo '<div class="instructor-profiles">Instructor profiles coming soon...</div>';
}

function weown_cohort_community_features() {
    echo '<div class="community-features">Community features coming soon...</div>';
}

function weown_cohort_registration_form($type) {
    echo '<div class="registration-form">Registration form for ' . esc_html($type) . '</div>';
}

function weown_cohort_enrollment_benefits() {
    echo '<div class="enrollment-benefits">Enrollment benefits coming soon...</div>';
}

function weown_cohort_success_stories() {
    echo '<div class="success-stories">Success stories coming soon...</div>';
}

function weown_cohort_educational_faq() {
    echo '<div class="faq-section">FAQ section coming soon...</div>';
}

function weown_cohort_enrollment_countdown() {
    echo '<div class="countdown">Enrollment countdown coming soon...</div>';
}

// Lead Generation Functions
function weown_leadgen_trust_indicators() {
    echo '<div class="trust-indicators">Trust indicators coming soon...</div>';
}

function weown_leadgen_hero_visual() {
    echo '<div class="hero-visual">Hero visual coming soon...</div>';
}

function weown_leadgen_features_grid() {
    echo '<div class="features-grid">Features grid coming soon...</div>';
}

function weown_leadgen_testimonials() {
    echo '<div class="testimonials">Testimonials coming soon...</div>';
}

function weown_leadgen_client_logos() {
    echo '<div class="client-logos">Client logos coming soon...</div>';
}

function weown_leadgen_progressive_form() {
    echo '<div class="lead-form">Lead generation form coming soon...</div>';
}

function weown_leadgen_form_benefits() {
    echo '<div class="form-benefits">Form benefits coming soon...</div>';
}

function weown_leadgen_faq_accordion() {
    echo '<div class="faq-accordion">FAQ accordion coming soon...</div>';
}

// AI Showcase Functions
function weown_ai_hero_content() {
    echo '<div class="ai-hero-content">AI showcase content coming soon...</div>';
}

// SaaS Product Functions
function weown_saas_hero_content() {
    echo '<div class="saas-hero-content">SaaS product content coming soon...</div>';
}

// Business Page Functions
function weown_about_company_metrics() {
    echo '<div class="company-metrics">Company metrics coming soon...</div>';
}

function weown_about_company_visual($type) {
    echo '<div class="company-visual">Company visual for ' . esc_html($type) . '</div>';
}

function weown_about_company_timeline($style) {
    echo '<div class="company-timeline">Company timeline coming soon...</div>';
}

function weown_about_team_profiles() {
    echo '<div class="team-profiles">Team profiles coming soon...</div>';
}

function weown_about_company_values() {
    echo '<div class="company-values">Company values coming soon...</div>';
}

function weown_about_awards_recognition() {
    echo '<div class="awards-recognition">Awards coming soon...</div>';
}

function weown_about_client_testimonials() {
    echo '<div class="client-testimonials">Client testimonials coming soon...</div>';
}

function weown_about_partner_logos() {
    echo '<div class="partner-logos">Partner logos coming soon...</div>';
}

// Services Functions
function weown_services_hero_content() {
    echo '<div class="services-hero">Services content coming soon...</div>';
}

// Contact Functions
function weown_contact_hero_content() {
    echo '<div class="contact-hero">Contact content coming soon...</div>';
}

// Portfolio Functions
function weown_portfolio_hero_content() {
    echo '<div class="portfolio-hero">Portfolio content coming soon...</div>';
}
