<?php
/**
 * WeOwn Starter Theme - Customizer Default Values
 *
 * Centralized default values for all customizer settings. These values ensure
 * consistent fallbacks and provide a professional starting point for new sites.
 *
 * WordPress 6.8+ Best Practice: Use centralized defaults for maintainability
 * and easier automation via REST API (Phase 4).
 *
 * @package WeOwn_Starter
 * @subpackage Customizer
 * @since 1.0.0
 * @version 1.0.0
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Get Customizer Default Values
 *
 * Returns an associative array of all customizer setting IDs and their default values.
 * This function is used throughout the theme to ensure consistent defaults.
 *
 * Design Decision: Using a function instead of constants allows for:
 * 1. Dynamic defaults based on site context
 * 2. Filterable defaults for child themes or plugins
 * 3. Easy serialization for REST API responses
 *
 * @since 1.0.0
 * @return array Associative array of setting_id => default_value
 */
function weown_get_customizer_defaults() {
    /**
     * Brand Colors
     *
     * Professional color palette with strong contrast ratios for WCAG 2.1 AA compliance.
     * Primary: Modern blue - trust, professionalism, technology
     * Secondary: Vibrant coral - energy, action, conversion
     * Accent: Deep teal - sophistication, balance, highlight
     */
    $defaults = [
        // Brand Colors Section
        'primary_color'           => '#0066cc', // Primary brand color
        'secondary_color'         => '#ff5733', // Secondary brand color
        'accent_color'            => '#17a2b8', // Accent/highlight color
        'text_color'              => '#333333', // Body text color
        'heading_color'           => '#1a1a1a', // Heading text color
        'background_color'        => '#ffffff', // Page background color
        'secondary_bg_color'      => '#f8f9fa', // Secondary background (sections, cards)
        
        /**
         * Typography Settings
         *
         * Modern font stack with system font fallbacks for performance.
         * Heading: Inter - clean, professional, excellent readability
         * Body: Inter - consistent brand identity, optimized for web
         *
         * Font Scale: 1.25 (Major Third) - balanced hierarchy
         * Base Size: 16px - web standard for optimal readability
         */
        // Typography Section
        'font_heading'            => 'Inter', // Heading font family
        'font_body'               => 'Inter', // Body font family
        'font_size_base'          => 16, // Base font size in pixels
        'font_scale'              => 1.25, // Typographic scale ratio (Major Third)
        'line_height_base'        => 1.6, // Base line height for readability
        'line_height_heading'     => 1.2, // Tighter line height for headings
        'font_weight_heading'     => 700, // Bold headings for emphasis
        'font_weight_body'        => 400, // Regular body text
        'font_weight_bold'        => 600, // Semi-bold for strong emphasis
        
        /**
         * Layout & Spacing
         *
         * Responsive container widths following modern best practices:
         * - Desktop: 1200px (standard for 1920px displays)
         * - Content: 800px (optimal reading width: 60-80 characters per line)
         * - Spacing: 8px base unit system for consistent rhythm
         */
        // Layout Section
        'container_width'         => 1200, // Maximum container width (px)
        'content_width'           => 800, // Maximum content width for readability (px)
        'section_spacing_top'     => 80, // Section top padding (px)
        'section_spacing_bottom'  => 80, // Section bottom padding (px)
        'element_spacing'         => 32, // Element margin/padding (px)
        'grid_gap'                => 24, // Grid/flex gap spacing (px)
        'border_radius'           => 8, // Default border radius (px)
        
        /**
         * Logo & Branding
         *
         * Responsive logo sizing with mobile optimization.
         * Default width ensures logo visibility without overwhelming header.
         */
        // Logo Section
        'logo_width'              => 200, // Desktop logo width (px)
        'logo_width_mobile'       => 150, // Mobile logo width (px)
        'logo_height'             => 0, // Auto height (0 = auto)
        'retina_logo'             => '', // 2x resolution logo URL
        'mobile_logo'             => '', // Optional mobile-specific logo URL
        
        /**
         * Header Options
         *
         * Professional header configuration with modern UX patterns.
         * Sticky header improves navigation accessibility on long pages.
         */
        // Header Section
        'header_layout'           => 'default', // Header layout style
        'header_sticky'           => false, // Enable sticky header on scroll
        'header_transparent'      => false, // Transparent header on homepage
        'header_search'           => false, // Show search in header
        'header_cta_text'         => 'Get Started', // CTA button text
        'header_cta_url'          => '', // CTA button URL
        'header_cta_style'        => 'primary', // CTA button style
        
        /**
         * Footer Options
         *
         * Standard footer configuration with copyright automation.
         * Widget areas controlled separately via WordPress widget system.
         */
        // Footer Section
        'footer_layout'           => 'default', // Footer layout style
        'footer_widgets'          => true, // Enable footer widget areas
        'footer_copyright'        => '&copy; {{YEAR}} {{SITE_NAME}}. All rights reserved.', // Copyright text with placeholders
        'footer_social_links'     => true, // Show social media icons
        
        /**
         * Performance & Features
         *
         * Enterprise performance optimizations enabled by default.
         * Security-first approach with tracking opt-in.
         */
        // Performance Section
        'performance_lazy_load'   => true, // Lazy load images
        'performance_webp'        => true, // Convert images to WebP
        'performance_minify_css'  => false, // Minify CSS (handle via build process)
        'performance_minify_js'   => false, // Minify JS (handle via build process)
        
        // Feature Toggles
        'feature_breadcrumbs'     => false, // Show breadcrumb navigation
        'feature_reading_time'    => true, // Show estimated reading time on posts
        'feature_share_buttons'   => true, // Show social share buttons
        'feature_back_to_top'     => true, // Show back to top button
        
        // Analytics & Tracking (opt-in for privacy)
        'analytics_enabled'       => false, // Enable analytics tracking
        'analytics_id'            => '', // Google Analytics ID (GA4)
        'analytics_anonymize'     => true, // Anonymize IP addresses (GDPR)
    ];
    
    /**
     * Filter: weown_customizer_defaults
     *
     * Allows child themes and plugins to modify default values.
     * Useful for white-label implementations or industry-specific presets.
     *
     * @since 1.0.0
     * @param array $defaults Associative array of default values
     */
    return apply_filters('weown_customizer_defaults', $defaults);
}

/**
 * Get Single Customizer Default Value
 *
 * Convenience function to retrieve a single default value by setting ID.
 * Provides type safety and easier refactoring.
 *
 * @since 1.0.0
 * @param string $setting_id The setting ID to retrieve
 * @return mixed The default value, or null if setting doesn't exist
 */
function weown_get_customizer_default($setting_id) {
    $defaults = weown_get_customizer_defaults();
    return isset($defaults[$setting_id]) ? $defaults[$setting_id] : null;
}

/**
 * Get Theme Mod With Proper Default
 *
 * Wrapper around get_theme_mod() that always uses our centralized defaults.
 * Ensures consistency and reduces code duplication throughout the theme.
 *
 * WordPress 6.8+ Best Practice: Centralized theme mod retrieval.
 *
 * @since 1.0.0
 * @param string $setting_id The setting ID to retrieve
 * @return mixed The theme mod value or default
 */
function weown_get_theme_mod($setting_id) {
    $default = weown_get_customizer_default($setting_id);
    return get_theme_mod($setting_id, $default);
}
