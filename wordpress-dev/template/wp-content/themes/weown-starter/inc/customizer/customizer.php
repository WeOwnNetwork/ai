<?php
/**
 * WeOwn Starter Theme - WordPress Customizer Integration
 *
 * Main customizer registration file that creates the global branding layer.
 * Provides live-preview customization for colors, typography, logo, and layout.
 *
 * Architecture Decision: Modular panel/section structure for scalability.
 * Each major feature area gets its own section for better UX and organization.
 *
 * WordPress 6.8+ Best Practice: Use selective refresh for performance and
 * postMessage transport for instant live preview where possible.
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
 * Register Customizer Settings and Controls
 *
 * Main function that registers all customizer panels, sections, settings, and controls.
 * Organized by feature area for maintainability and scalability.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize WordPress Customizer manager instance
 */
function weown_customize_register($wp_customize) {
    /**
     * Register Main Theme Options Panel
     *
     * Top-level panel that contains all WeOwn theme sections.
     * Provides organized structure for complex customization options.
     */
    $wp_customize->add_panel('weown_theme_options', [
        'title'       => __('WeOwn Theme Options', 'weown-starter'),
        'description' => __('Customize your site branding, colors, typography, and layout settings.', 'weown-starter'),
        'priority'    => 30, // After WordPress core panels
        'capability'  => 'edit_theme_options',
    ]);
    
    /**
     * SECTION: Brand Colors
     *
     * Primary branding colors with automatic shade generation.
     * Live preview via CSS custom properties for instant feedback.
     */
    weown_customizer_register_colors($wp_customize);
    
    /**
     * SECTION: Typography
     *
     * Font family, sizing, and scale controls with Google Fonts integration.
     * Responsive typography system with mobile optimization.
     */
    weown_customizer_register_typography($wp_customize);
    
    /**
     * SECTION: Logo & Branding
     *
     * Logo upload, sizing, and positioning controls.
     * Support for retina and mobile-specific logos.
     */
    weown_customizer_register_logo($wp_customize);
    
    /**
     * SECTION: Layout & Spacing
     *
     * Container widths, section spacing, and layout options.
     * Responsive spacing system with consistent rhythm.
     */
    weown_customizer_register_layout($wp_customize);
    
    /**
     * SECTION: Header Options
     *
     * Header layout, sticky behavior, and CTA button configuration.
     * Advanced header features for conversion optimization.
     */
    weown_customizer_register_header($wp_customize);
    
    /**
     * SECTION: Footer Options
     *
     * Footer layout, widget areas, and copyright settings.
     * Social media links and footer customization.
     */
    weown_customizer_register_footer($wp_customize);
    
    /**
     * SECTION: Performance & Features
     *
     * Feature toggles, performance optimizations, and analytics.
     * Enterprise-grade performance and privacy controls.
     */
    weown_customizer_register_features($wp_customize);
}
add_action('customize_register', 'weown_customize_register');

/**
 * Register Brand Colors Section
 *
 * Color controls for primary brand colors with live preview.
 * Generates CSS custom properties for consistent theming.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_customizer_register_colors($wp_customize) {
    // Add Colors Section
    $wp_customize->add_section('weown_colors', [
        'title'       => __('Brand Colors', 'weown-starter'),
        'description' => __('Configure your brand color palette. These colors will be used throughout your site for consistent branding.', 'weown-starter'),
        'panel'       => 'weown_theme_options',
        'priority'    => 10,
        'capability'  => 'edit_theme_options',
    ]);
    
    // Info: Color System
    $wp_customize->add_setting('colors_info', [
        'sanitize_callback' => 'sanitize_text_field',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Info_Control($wp_customize, 'colors_info', [
        'label'       => __('Color System', 'weown-starter'),
        'description' => __('Choose colors that align with your brand identity. Ensure sufficient contrast for accessibility (WCAG 2.1 AA compliance).', 'weown-starter'),
        'section'     => 'weown_colors',
        'priority'    => 1,
    ]));
    
    $colors = [
        'primary_color' => [
            'label'       => __('Primary Brand Color', 'weown-starter'),
            'description' => __('Main brand color used for buttons, links, and key elements.', 'weown-starter'),
            'priority'    => 10,
        ],
        'secondary_color' => [
            'label'       => __('Secondary Brand Color', 'weown-starter'),
            'description' => __('Secondary color for accents and supporting elements.', 'weown-starter'),
            'priority'    => 20,
        ],
        'accent_color' => [
            'label'       => __('Accent Color', 'weown-starter'),
            'description' => __('Highlight color for calls-to-action and emphasis.', 'weown-starter'),
            'priority'    => 30,
        ],
        'text_color' => [
            'label'       => __('Body Text Color', 'weown-starter'),
            'description' => __('Primary text color for body content.', 'weown-starter'),
            'priority'    => 40,
        ],
        'heading_color' => [
            'label'       => __('Heading Color', 'weown-starter'),
            'description' => __('Color for headings and titles.', 'weown-starter'),
            'priority'    => 50,
        ],
        'background_color' => [
            'label'       => __('Background Color', 'weown-starter'),
            'description' => __('Main page background color.', 'weown-starter'),
            'priority'    => 60,
        ],
        'secondary_bg_color' => [
            'label'       => __('Secondary Background', 'weown-starter'),
            'description' => __('Background color for sections, cards, and alternate areas.', 'weown-starter'),
            'priority'    => 70,
        ],
    ];
    
    foreach ($colors as $setting_id => $args) {
        // Add Setting
        $wp_customize->add_setting($setting_id, [
            'default'           => weown_get_customizer_default($setting_id),
            'transport'         => 'postMessage', // Live preview without refresh
            'sanitize_callback' => 'weown_sanitize_color',
            'capability'        => 'edit_theme_options',
        ]);
        
        // Add Control
        $wp_customize->add_control(new WP_Customize_Color_Control($wp_customize, $setting_id, [
            'label'       => $args['label'],
            'description' => $args['description'],
            'section'     => 'weown_colors',
            'priority'    => $args['priority'],
        ]));
        
        // Add Selective Refresh (partial refresh for better UX)
        $wp_customize->selective_refresh->add_partial($setting_id, [
            'selector'        => ':root',
            'render_callback' => '__return_false', // Handled by JS
            'fallback_refresh' => false,
        ]);
    }
}

/**
 * Register Typography Section
 *
 * Font controls with Google Fonts integration and responsive sizing.
 * Generates typographic scale based on modular scale ratio.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_customizer_register_typography($wp_customize) {
    // Add Typography Section
    $wp_customize->add_section('weown_typography', [
        'title'       => __('Typography', 'weown-starter'),
        'description' => __('Configure fonts, sizes, and typographic hierarchy for your site.', 'weown-starter'),
        'panel'       => 'weown_theme_options',
        'priority'    => 20,
        'capability'  => 'edit_theme_options',
    ]);
    
    // Info: Typography System
    $wp_customize->add_setting('typography_info', [
        'sanitize_callback' => 'sanitize_text_field',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Info_Control($wp_customize, 'typography_info', [
        'label'       => __('Typography System', 'weown-starter'),
        'description' => __('Choose professional fonts and configure sizing. The theme uses a modular scale for consistent typography hierarchy.', 'weown-starter'),
        'section'     => 'weown_typography',
        'priority'    => 1,
    ]));
    
    // Heading Font Family
    $wp_customize->add_setting('font_heading', [
        'default'           => weown_get_customizer_default('font_heading'),
        'transport'         => 'postMessage',
        'sanitize_callback' => 'weown_sanitize_font_family',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Font_Control($wp_customize, 'font_heading', [
        'label'       => __('Heading Font', 'weown-starter'),
        'description' => __('Font family for headings and titles.', 'weown-starter'),
        'section'     => 'weown_typography',
        'priority'    => 10,
    ]));
    
    // Body Font Family
    $wp_customize->add_setting('font_body', [
        'default'           => weown_get_customizer_default('font_body'),
        'transport'         => 'postMessage',
        'sanitize_callback' => 'weown_sanitize_font_family',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Font_Control($wp_customize, 'font_body', [
        'label'       => __('Body Font', 'weown-starter'),
        'description' => __('Font family for body text and paragraphs.', 'weown-starter'),
        'section'     => 'weown_typography',
        'priority'    => 20,
    ]));
    
    // Base Font Size
    $wp_customize->add_setting('font_size_base', [
        'default'           => weown_get_customizer_default('font_size_base'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 12, 24, 16);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'font_size_base', [
        'label'       => __('Base Font Size', 'weown-starter'),
        'description' => __('Root font size in pixels. Standard is 16px.', 'weown-starter'),
        'section'     => 'weown_typography',
        'priority'    => 30,
        'min'         => 12,
        'max'         => 24,
        'step'        => 1,
        'unit'        => 'px',
    ]));
    
    // Font Scale (Modular Scale)
    $wp_customize->add_setting('font_scale', [
        'default'           => weown_get_customizer_default('font_scale'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_float($value, 1.0, 2.0, 1.25);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('font_scale', [
        'label'       => __('Typographic Scale', 'weown-starter'),
        'description' => __('Ratio for heading size progression. Common values: 1.125 (Minor Second), 1.25 (Major Third), 1.333 (Perfect Fourth), 1.5 (Perfect Fifth).', 'weown-starter'),
        'section'     => 'weown_typography',
        'type'        => 'select',
        'priority'    => 40,
        'choices'     => [
            '1.125' => __('1.125 - Minor Second (Subtle)', 'weown-starter'),
            '1.25'  => __('1.25 - Major Third (Balanced)', 'weown-starter'),
            '1.333' => __('1.333 - Perfect Fourth (Moderate)', 'weown-starter'),
            '1.414' => __('1.414 - Augmented Fourth (Bold)', 'weown-starter'),
            '1.5'   => __('1.5 - Perfect Fifth (Dramatic)', 'weown-starter'),
            '1.618' => __('1.618 - Golden Ratio (Luxe)', 'weown-starter'),
        ],
    ]);
    
    // Line Height (Base)
    $wp_customize->add_setting('line_height_base', [
        'default'           => weown_get_customizer_default('line_height_base'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_float($value, 1.0, 2.5, 1.6);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'line_height_base', [
        'label'       => __('Body Line Height', 'weown-starter'),
        'description' => __('Line height for body text. 1.5-1.6 is optimal for readability.', 'weown-starter'),
        'section'     => 'weown_typography',
        'priority'    => 50,
        'min'         => 1.0,
        'max'         => 2.5,
        'step'        => 0.1,
        'unit'        => '',
    ]));
    
    // Line Height (Headings)
    $wp_customize->add_setting('line_height_heading', [
        'default'           => weown_get_customizer_default('line_height_heading'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_float($value, 1.0, 2.0, 1.2);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'line_height_heading', [
        'label'       => __('Heading Line Height', 'weown-starter'),
        'description' => __('Line height for headings. Tighter than body (1.1-1.3).', 'weown-starter'),
        'section'     => 'weown_typography',
        'priority'    => 60,
        'min'         => 1.0,
        'max'         => 2.0,
        'step'        => 0.1,
        'unit'        => '',
    ]));
    
    // Font Weight (Headings)
    $wp_customize->add_setting('font_weight_heading', [
        'default'           => weown_get_customizer_default('font_weight_heading'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 100, 900, 700);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('font_weight_heading', [
        'label'       => __('Heading Font Weight', 'weown-starter'),
        'description' => __('Weight for headings. Bold (700) is standard.', 'weown-starter'),
        'section'     => 'weown_typography',
        'type'        => 'select',
        'priority'    => 70,
        'choices'     => [
            '400' => __('400 - Regular', 'weown-starter'),
            '500' => __('500 - Medium', 'weown-starter'),
            '600' => __('600 - Semi-Bold', 'weown-starter'),
            '700' => __('700 - Bold', 'weown-starter'),
            '800' => __('800 - Extra Bold', 'weown-starter'),
            '900' => __('900 - Black', 'weown-starter'),
        ],
    ]);
    
    // Font Weight (Body)
    $wp_customize->add_setting('font_weight_body', [
        'default'           => weown_get_customizer_default('font_weight_body'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 100, 700, 400);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('font_weight_body', [
        'label'       => __('Body Font Weight', 'weown-starter'),
        'description' => __('Weight for body text. Regular (400) is standard.', 'weown-starter'),
        'section'     => 'weown_typography',
        'type'        => 'select',
        'priority'    => 80,
        'choices'     => [
            '300' => __('300 - Light', 'weown-starter'),
            '400' => __('400 - Regular', 'weown-starter'),
            '500' => __('500 - Medium', 'weown-starter'),
            '600' => __('600 - Semi-Bold', 'weown-starter'),
        ],
    ]);
}

/**
 * Register Logo & Branding Section
 *
 * Logo upload and sizing controls with retina and mobile support.
 * Integrated with WordPress core custom logo feature.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_customizer_register_logo($wp_customize) {
    // Add Logo Section
    $wp_customize->add_section('weown_logo', [
        'title'       => __('Logo & Branding', 'weown-starter'),
        'description' => __('Upload and configure your site logo. Supports retina displays and mobile-specific logos.', 'weown-starter'),
        'panel'       => 'weown_theme_options',
        'priority'    => 30,
        'capability'  => 'edit_theme_options',
    ]);
    
    // Logo Width (Desktop)
    $wp_customize->add_setting('logo_width', [
        'default'           => weown_get_customizer_default('logo_width'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 50, 500, 200);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'logo_width', [
        'label'       => __('Logo Width (Desktop)', 'weown-starter'),
        'description' => __('Maximum logo width on desktop devices.', 'weown-starter'),
        'section'     => 'weown_logo',
        'priority'    => 10,
        'min'         => 50,
        'max'         => 500,
        'step'        => 10,
        'unit'        => 'px',
    ]));
    
    // Logo Width (Mobile)
    $wp_customize->add_setting('logo_width_mobile', [
        'default'           => weown_get_customizer_default('logo_width_mobile'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 50, 300, 150);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'logo_width_mobile', [
        'label'       => __('Logo Width (Mobile)', 'weown-starter'),
        'description' => __('Maximum logo width on mobile devices.', 'weown-starter'),
        'section'     => 'weown_logo',
        'priority'    => 20,
        'min'         => 50,
        'max'         => 300,
        'step'        => 10,
        'unit'        => 'px',
    ]));
    
    // Retina Logo
    $wp_customize->add_setting('retina_logo', [
        'default'           => weown_get_customizer_default('retina_logo'),
        'transport'         => 'refresh',
        'sanitize_callback' => 'weown_sanitize_image',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WP_Customize_Image_Control($wp_customize, 'retina_logo', [
        'label'       => __('Retina Logo (2x)', 'weown-starter'),
        'description' => __('Optional high-resolution logo for retina displays. Should be 2x the size of your main logo.', 'weown-starter'),
        'section'     => 'weown_logo',
        'priority'    => 30,
    ]));
    
    // Mobile Logo
    $wp_customize->add_setting('mobile_logo', [
        'default'           => weown_get_customizer_default('mobile_logo'),
        'transport'         => 'refresh',
        'sanitize_callback' => 'weown_sanitize_image',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WP_Customize_Image_Control($wp_customize, 'mobile_logo', [
        'label'       => __('Mobile Logo', 'weown-starter'),
        'description' => __('Optional mobile-specific logo (e.g., simplified or icon version).', 'weown-starter'),
        'section'     => 'weown_logo',
        'priority'    => 40,
    ]));
}

/**
 * Register Layout & Spacing Section
 *
 * Container widths, section spacing, and layout rhythm controls.
 * Uses 8px base unit system for consistent spacing.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_customizer_register_layout($wp_customize) {
    // Add Layout Section
    $wp_customize->add_section('weown_layout', [
        'title'       => __('Layout & Spacing', 'weown-starter'),
        'description' => __('Configure container widths, section spacing, and layout settings.', 'weown-starter'),
        'panel'       => 'weown_theme_options',
        'priority'    => 40,
        'capability'  => 'edit_theme_options',
    ]);
    
    // Container Width
    $wp_customize->add_setting('container_width', [
        'default'           => weown_get_customizer_default('container_width'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 960, 1920, 1200);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'container_width', [
        'label'       => __('Container Width', 'weown-starter'),
        'description' => __('Maximum width for page content container.', 'weown-starter'),
        'section'     => 'weown_layout',
        'priority'    => 10,
        'min'         => 960,
        'max'         => 1920,
        'step'        => 40,
        'unit'        => 'px',
    ]));
    
    // Content Width
    $wp_customize->add_setting('content_width', [
        'default'           => weown_get_customizer_default('content_width'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 640, 1200, 800);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'content_width', [
        'label'       => __('Content Width', 'weown-starter'),
        'description' => __('Maximum width for readable content (60-80 characters per line).', 'weown-starter'),
        'section'     => 'weown_layout',
        'priority'    => 20,
        'min'         => 640,
        'max'         => 1200,
        'step'        => 40,
        'unit'        => 'px',
    ]));
    
    // Section Spacing (Top)
    $wp_customize->add_setting('section_spacing_top', [
        'default'           => weown_get_customizer_default('section_spacing_top'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 40, 160, 80);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'section_spacing_top', [
        'label'       => __('Section Spacing (Top)', 'weown-starter'),
        'description' => __('Top padding for sections.', 'weown-starter'),
        'section'     => 'weown_layout',
        'priority'    => 30,
        'min'         => 40,
        'max'         => 160,
        'step'        => 8,
        'unit'        => 'px',
    ]));
    
    // Section Spacing (Bottom)
    $wp_customize->add_setting('section_spacing_bottom', [
        'default'           => weown_get_customizer_default('section_spacing_bottom'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 40, 160, 80);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'section_spacing_bottom', [
        'label'       => __('Section Spacing (Bottom)', 'weown-starter'),
        'description' => __('Bottom padding for sections.', 'weown-starter'),
        'section'     => 'weown_layout',
        'priority'    => 40,
        'min'         => 40,
        'max'         => 160,
        'step'        => 8,
        'unit'        => 'px',
    ]));
    
    // Element Spacing
    $wp_customize->add_setting('element_spacing', [
        'default'           => weown_get_customizer_default('element_spacing'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 16, 80, 32);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'element_spacing', [
        'label'       => __('Element Spacing', 'weown-starter'),
        'description' => __('Spacing between elements (margins, gaps).', 'weown-starter'),
        'section'     => 'weown_layout',
        'priority'    => 50,
        'min'         => 16,
        'max'         => 80,
        'step'        => 8,
        'unit'        => 'px',
    ]));
    
    // Border Radius
    $wp_customize->add_setting('border_radius', [
        'default'           => weown_get_customizer_default('border_radius'),
        'transport'         => 'postMessage',
        'sanitize_callback' => function($value) {
            return weown_sanitize_integer($value, 0, 32, 8);
        },
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control(new WeOwn_Customize_Range_Control($wp_customize, 'border_radius', [
        'label'       => __('Border Radius', 'weown-starter'),
        'description' => __('Roundness of corners for buttons, cards, and elements.', 'weown-starter'),
        'section'     => 'weown_layout',
        'priority'    => 60,
        'min'         => 0,
        'max'         => 32,
        'step'        => 2,
        'unit'        => 'px',
    ]));
}

/**
 * Register Header Options Section
 *
 * Header layout, sticky behavior, and CTA button controls.
 * Advanced features for navigation and conversion optimization.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_customizer_register_header($wp_customize) {
    // Add Header Section
    $wp_customize->add_section('weown_header', [
        'title'       => __('Header Options', 'weown-starter'),
        'description' => __('Configure header layout, behavior, and call-to-action button.', 'weown-starter'),
        'panel'       => 'weown_theme_options',
        'priority'    => 50,
        'capability'  => 'edit_theme_options',
    ]);
    
    // Sticky Header
    $wp_customize->add_setting('header_sticky', [
        'default'           => weown_get_customizer_default('header_sticky'),
        'transport'         => 'refresh',
        'sanitize_callback' => 'weown_sanitize_checkbox',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('header_sticky', [
        'label'       => __('Sticky Header', 'weown-starter'),
        'description' => __('Keep header fixed at top when scrolling.', 'weown-starter'),
        'section'     => 'weown_header',
        'type'        => 'checkbox',
        'priority'    => 10,
    ]);
    
    // Header CTA Text
    $wp_customize->add_setting('header_cta_text', [
        'default'           => weown_get_customizer_default('header_cta_text'),
        'transport'         => 'postMessage',
        'sanitize_callback' => 'weown_sanitize_text',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('header_cta_text', [
        'label'       => __('CTA Button Text', 'weown-starter'),
        'description' => __('Text for header call-to-action button.', 'weown-starter'),
        'section'     => 'weown_header',
        'type'        => 'text',
        'priority'    => 20,
    ]);
    
    // Header CTA URL
    $wp_customize->add_setting('header_cta_url', [
        'default'           => weown_get_customizer_default('header_cta_url'),
        'transport'         => 'postMessage',
        'sanitize_callback' => 'weown_sanitize_url',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('header_cta_url', [
        'label'       => __('CTA Button URL', 'weown-starter'),
        'description' => __('Link for header call-to-action button.', 'weown-starter'),
        'section'     => 'weown_header',
        'type'        => 'url',
        'priority'    => 30,
    ]);
}

/**
 * Register Footer Options Section
 *
 * Footer layout, copyright text, and social links.
 * Basic footer customization options.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_customizer_register_footer($wp_customize) {
    // Add Footer Section
    $wp_customize->add_section('weown_footer', [
        'title'       => __('Footer Options', 'weown-starter'),
        'description' => __('Configure footer layout and content.', 'weown-starter'),
        'panel'       => 'weown_theme_options',
        'priority'    => 60,
        'capability'  => 'edit_theme_options',
    ]);
    
    // Footer Copyright
    $wp_customize->add_setting('footer_copyright', [
        'default'           => weown_get_customizer_default('footer_copyright'),
        'transport'         => 'postMessage',
        'sanitize_callback' => 'weown_sanitize_placeholders',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('footer_copyright', [
        'label'       => __('Copyright Text', 'weown-starter'),
        'description' => __('Footer copyright text. Use {{YEAR}} for current year, {{SITE_NAME}} for site name.', 'weown-starter'),
        'section'     => 'weown_footer',
        'type'        => 'textarea',
        'priority'    => 10,
    ]);
}

/**
 * Register Performance & Features Section
 *
 * Feature toggles, performance optimizations, and analytics integration.
 * Enterprise-grade controls for optimization and tracking.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_customizer_register_features($wp_customize) {
    // Add Features Section
    $wp_customize->add_section('weown_features', [
        'title'       => __('Performance & Features', 'weown-starter'),
        'description' => __('Configure performance optimizations and optional features.', 'weown-starter'),
        'panel'       => 'weown_theme_options',
        'priority'    => 70,
        'capability'  => 'edit_theme_options',
    ]);
    
    // Lazy Loading
    $wp_customize->add_setting('performance_lazy_load', [
        'default'           => weown_get_customizer_default('performance_lazy_load'),
        'transport'         => 'refresh',
        'sanitize_callback' => 'weown_sanitize_checkbox',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('performance_lazy_load', [
        'label'       => __('Lazy Load Images', 'weown-starter'),
        'description' => __('Defer loading of offscreen images for better performance.', 'weown-starter'),
        'section'     => 'weown_features',
        'type'        => 'checkbox',
        'priority'    => 10,
    ]);
    
    // Analytics ID
    $wp_customize->add_setting('analytics_id', [
        'default'           => weown_get_customizer_default('analytics_id'),
        'transport'         => 'refresh',
        'sanitize_callback' => 'weown_sanitize_analytics_id',
        'capability'        => 'edit_theme_options',
    ]);
    $wp_customize->add_control('analytics_id', [
        'label'       => __('Google Analytics ID', 'weown-starter'),
        'description' => __('GA4 tracking ID (e.g., G-XXXXXXXXXX) or Universal Analytics (UA-XXXXXXXX-X).', 'weown-starter'),
        'section'     => 'weown_features',
        'type'        => 'text',
        'priority'    => 20,
    ]);
}

/**
 * Enqueue Customizer Preview Assets
 *
 * Loads JavaScript for live preview functionality in the customizer.
 * Only loads in customizer preview context for better performance.
 *
 * @since 1.0.0
 */
function weown_customizer_preview_js() {
    wp_enqueue_script(
        'weown-customizer-preview',
        get_template_directory_uri() . '/assets/js/customizer-preview.js',
        ['customize-preview', 'jquery'],
        '1.0.0',
        true
    );
}
add_action('customize_preview_init', 'weown_customizer_preview_js');
