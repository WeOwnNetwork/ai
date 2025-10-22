<?php
/**
 * WeOwn Starter Theme - Dynamic CSS Generation
 *
 * Generates CSS custom properties (variables) from WordPress Customizer settings
 * and injects them into the site head. Provides live preview support and caching
 * for optimal performance.
 *
 * Architecture Decision: Use CSS custom properties for maximum flexibility and
 * modern browser compatibility. This allows real-time updates in customizer
 * preview and consistent theming across the entire site.
 *
 * WordPress 6.8+ Best Practice: Cache generated CSS with transient API,
 * invalidate on customizer save for optimal performance.
 *
 * @package WeOwn_Starter
 * @subpackage Dynamic_CSS
 * @since 1.0.0
 * @version 1.0.0
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Inject Dynamic CSS into Site Head
 *
 * Outputs CSS custom properties based on customizer settings.
 * Hooked to wp_head with high priority to ensure variables are available
 * before other stylesheets that reference them.
 *
 * Performance: Uses transient caching, only regenerates when needed.
 *
 * @since 1.0.0
 */
function weown_inject_dynamic_css() {
    // Get cached CSS if available
    $css = get_transient('weown_dynamic_css');
    
    // Generate CSS if cache is empty
    if (false === $css) {
        $css = weown_generate_dynamic_css();
        // Cache for 1 day (customizer save will invalidate)
        set_transient('weown_dynamic_css', $css, DAY_IN_SECONDS);
    }
    
    // Output CSS
    if (!empty($css)) {
        echo "\n<style id=\"weown-dynamic-css\">\n" . $css . "\n</style>\n";
    }
}
add_action('wp_head', 'weown_inject_dynamic_css', 100);

/**
 * Generate Dynamic CSS from Customizer Settings
 *
 * Creates CSS custom properties for all theme customization values.
 * Separated from injection for testability and caching.
 *
 * @since 1.0.0
 * @return string Generated CSS code
 */
function weown_generate_dynamic_css() {
    $css = ":root {\n";
    
    /**
     * Brand Colors
     *
     * Generate color variables with automatic shade generation.
     * Creates light/dark variants for hover states and backgrounds.
     */
    $css .= weown_generate_color_variables();
    
    /**
     * Typography
     *
     * Generate font variables and calculated font sizes using modular scale.
     * Creates consistent typographic hierarchy across the site.
     */
    $css .= weown_generate_typography_variables();
    
    /**
     * Layout & Spacing
     *
     * Generate spacing and layout variables for consistent rhythm.
     * Uses 8px base unit system for responsive design.
     */
    $css .= weown_generate_layout_variables();
    
    /**
     * Component Styles
     *
     * Generate variables for specific components (buttons, cards, etc.).
     * Ensures consistent styling across all page elements.
     */
    $css .= weown_generate_component_variables();
    
    $css .= "}\n";
    
    /**
     * Responsive Typography
     *
     * Generate responsive font sizes for mobile optimization.
     * Scales down typography for better readability on small screens.
     */
    $css .= weown_generate_responsive_typography();
    
    /**
     * Google Fonts Integration
     *
     * Generate @import or @font-face for selected fonts.
     * Handles font loading with performance optimization.
     */
    $css .= weown_generate_font_imports();
    
    return $css;
}

/**
 * Generate Color CSS Variables
 *
 * Creates CSS custom properties for all brand colors.
 * Includes automatic shade generation for hover states.
 *
 * @since 1.0.0
 * @return string CSS color variables
 */
function weown_generate_color_variables() {
    $css = "  /* Brand Colors */\n";
    
    // Color settings to generate
    $colors = [
        'primary_color'      => 'color-primary',
        'secondary_color'    => 'color-secondary',
        'accent_color'       => 'color-accent',
        'text_color'         => 'color-text',
        'heading_color'      => 'color-heading',
        'background_color'   => 'color-background',
        'secondary_bg_color' => 'color-background-secondary',
    ];
    
    foreach ($colors as $setting_id => $var_name) {
        $value = weown_get_theme_mod($setting_id);
        $css .= "  --{$var_name}: {$value};\n";
        
        // Generate light/dark variants for primary, secondary, accent
        if (in_array($setting_id, ['primary_color', 'secondary_color', 'accent_color'], true)) {
            $light = weown_adjust_color_brightness($value, 20);
            $dark = weown_adjust_color_brightness($value, -20);
            $css .= "  --{$var_name}-light: {$light};\n";
            $css .= "  --{$var_name}-dark: {$dark};\n";
        }
    }
    
    $css .= "\n";
    return $css;
}

/**
 * Generate Typography CSS Variables
 *
 * Creates CSS custom properties for fonts and calculates modular scale
 * for heading sizes. Ensures consistent typographic hierarchy.
 *
 * @since 1.0.0
 * @return string CSS typography variables
 */
function weown_generate_typography_variables() {
    $css = "  /* Typography */\n";
    
    // Font families
    $font_heading = weown_get_theme_mod('font_heading');
    $font_body = weown_get_theme_mod('font_body');
    
    // Add fallback font stacks
    $font_heading_stack = weown_get_font_stack($font_heading);
    $font_body_stack = weown_get_font_stack($font_body);
    
    $css .= "  --font-heading: {$font_heading_stack};\n";
    $css .= "  --font-body: {$font_body_stack};\n";
    
    // Font sizing
    $base_size = weown_get_theme_mod('font_size_base');
    $scale = weown_get_theme_mod('font_scale');
    
    $css .= "  --font-size-base: {$base_size}px;\n";
    $css .= "  --font-scale: {$scale};\n";
    
    // Calculate heading sizes using modular scale
    // Formula: base * scale^n (where n is the heading level inverse)
    $h1_size = round($base_size * pow($scale, 3), 2);
    $h2_size = round($base_size * pow($scale, 2.5), 2);
    $h3_size = round($base_size * pow($scale, 2), 2);
    $h4_size = round($base_size * pow($scale, 1.5), 2);
    $h5_size = round($base_size * pow($scale, 1), 2);
    $h6_size = round($base_size * pow($scale, 0.75), 2);
    
    $css .= "  --font-size-h1: {$h1_size}px;\n";
    $css .= "  --font-size-h2: {$h2_size}px;\n";
    $css .= "  --font-size-h3: {$h3_size}px;\n";
    $css .= "  --font-size-h4: {$h4_size}px;\n";
    $css .= "  --font-size-h5: {$h5_size}px;\n";
    $css .= "  --font-size-h6: {$h6_size}px;\n";
    
    // Small text sizes
    $small_size = round($base_size * 0.875, 2);
    $tiny_size = round($base_size * 0.75, 2);
    $css .= "  --font-size-small: {$small_size}px;\n";
    $css .= "  --font-size-tiny: {$tiny_size}px;\n";
    
    // Line heights
    $line_height_base = weown_get_theme_mod('line_height_base');
    $line_height_heading = weown_get_theme_mod('line_height_heading');
    
    $css .= "  --line-height-base: {$line_height_base};\n";
    $css .= "  --line-height-heading: {$line_height_heading};\n";
    $css .= "  --line-height-tight: 1.2;\n";
    $css .= "  --line-height-relaxed: 1.8;\n";
    
    // Font weights
    $weight_heading = weown_get_theme_mod('font_weight_heading');
    $weight_body = weown_get_theme_mod('font_weight_body');
    
    $css .= "  --font-weight-heading: {$weight_heading};\n";
    $css .= "  --font-weight-body: {$weight_body};\n";
    $css .= "  --font-weight-light: 300;\n";
    $css .= "  --font-weight-medium: 500;\n";
    $css .= "  --font-weight-semibold: 600;\n";
    $css .= "  --font-weight-bold: 700;\n";
    
    $css .= "\n";
    return $css;
}

/**
 * Generate Layout CSS Variables
 *
 * Creates CSS custom properties for spacing and container widths.
 * Uses 8px base unit system for consistent spacing rhythm.
 *
 * @since 1.0.0
 * @return string CSS layout variables
 */
function weown_generate_layout_variables() {
    $css = "  /* Layout & Spacing */\n";
    
    // Container widths
    $container_width = weown_get_theme_mod('container_width');
    $content_width = weown_get_theme_mod('content_width');
    
    $css .= "  --container-width: {$container_width}px;\n";
    $css .= "  --content-width: {$content_width}px;\n";
    
    // Section spacing
    $section_spacing_top = weown_get_theme_mod('section_spacing_top');
    $section_spacing_bottom = weown_get_theme_mod('section_spacing_bottom');
    
    $css .= "  --section-spacing-top: {$section_spacing_top}px;\n";
    $css .= "  --section-spacing-bottom: {$section_spacing_bottom}px;\n";
    
    // Element spacing (8px base unit system)
    $element_spacing = weown_get_theme_mod('element_spacing');
    
    $css .= "  --spacing-base: {$element_spacing}px;\n";
    $css .= "  --spacing-xs: " . ($element_spacing * 0.25) . "px;\n";
    $css .= "  --spacing-sm: " . ($element_spacing * 0.5) . "px;\n";
    $css .= "  --spacing-md: {$element_spacing}px;\n";
    $css .= "  --spacing-lg: " . ($element_spacing * 1.5) . "px;\n";
    $css .= "  --spacing-xl: " . ($element_spacing * 2) . "px;\n";
    $css .= "  --spacing-2xl: " . ($element_spacing * 3) . "px;\n";
    
    // Border radius
    $border_radius = weown_get_theme_mod('border_radius');
    
    $css .= "  --border-radius: {$border_radius}px;\n";
    $css .= "  --border-radius-sm: " . max(0, $border_radius - 2) . "px;\n";
    $css .= "  --border-radius-lg: " . ($border_radius + 4) . "px;\n";
    $css .= "  --border-radius-full: 9999px;\n";
    
    // Logo sizing
    $logo_width = weown_get_theme_mod('logo_width');
    $logo_width_mobile = weown_get_theme_mod('logo_width_mobile');
    
    $css .= "  --logo-width: {$logo_width}px;\n";
    $css .= "  --logo-width-mobile: {$logo_width_mobile}px;\n";
    
    $css .= "\n";
    return $css;
}

/**
 * Generate Component CSS Variables
 *
 * Creates CSS custom properties for specific components like buttons,
 * cards, forms, etc. Ensures consistent styling across all elements.
 *
 * @since 1.0.0
 * @return string CSS component variables
 */
function weown_generate_component_variables() {
    $css = "  /* Components */\n";
    
    // Transitions (smooth animations)
    $css .= "  --transition-fast: 150ms ease-in-out;\n";
    $css .= "  --transition-base: 250ms ease-in-out;\n";
    $css .= "  --transition-slow: 350ms ease-in-out;\n";
    
    // Shadows (elevation system)
    $css .= "  --shadow-sm: 0 1px 2px 0 rgba(0, 0, 0, 0.05);\n";
    $css .= "  --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);\n";
    $css .= "  --shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05);\n";
    $css .= "  --shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);\n";
    
    // Z-index system (layering)
    $css .= "  --z-dropdown: 1000;\n";
    $css .= "  --z-sticky: 1020;\n";
    $css .= "  --z-fixed: 1030;\n";
    $css .= "  --z-modal: 1050;\n";
    $css .= "  --z-popover: 1060;\n";
    $css .= "  --z-tooltip: 1070;\n";
    
    $css .= "}\n";
    return $css;
}

/**
 * Generate Responsive Typography
 *
 * Creates media queries for responsive font sizing on mobile devices.
 * Scales down typography for better readability on small screens.
 *
 * @since 1.0.0
 * @return string CSS media queries for responsive typography
 */
function weown_generate_responsive_typography() {
    $base_size = weown_get_theme_mod('font_size_base');
    $mobile_base = max(14, $base_size - 2); // Slightly smaller on mobile
    
    $css = "\n/* Responsive Typography */\n";
    $css .= "@media (max-width: 768px) {\n";
    $css .= "  :root {\n";
    $css .= "    --font-size-base: {$mobile_base}px;\n";
    $css .= "  }\n";
    $css .= "}\n";
    
    return $css;
}

/**
 * Generate Google Fonts Imports
 *
 * Creates @import statements for Google Fonts based on selected fonts.
 * Optimizes loading with font-display: swap for better performance.
 *
 * Performance Note: Using @import in CSS for simplicity. For production,
 * consider using WebFontLoader or self-hosting fonts.
 *
 * @since 1.0.0
 * @return string CSS font imports
 */
function weown_generate_font_imports() {
    $font_heading = weown_get_theme_mod('font_heading');
    $font_body = weown_get_theme_mod('font_body');
    
    $fonts_to_load = [];
    
    // Only load Google Fonts (not system fonts)
    if (weown_is_google_font($font_heading)) {
        $fonts_to_load[] = $font_heading;
    }
    
    if (weown_is_google_font($font_body) && $font_body !== $font_heading) {
        $fonts_to_load[] = $font_body;
    }
    
    if (empty($fonts_to_load)) {
        return '';
    }
    
    // Build Google Fonts URL
    $families = [];
    foreach ($fonts_to_load as $font) {
        // Load multiple weights for flexibility
        $families[] = urlencode($font) . ':wght@300;400;500;600;700';
    }
    
    $google_fonts_url = 'https://fonts.googleapis.com/css2?family=' . implode('&family=', $families) . '&display=swap';
    
    $css = "\n/* Google Fonts */\n";
    $css .= "@import url('{$google_fonts_url}');\n";
    
    return $css;
}

/**
 * Helper Functions
 */

/**
 * Get Font Stack with Fallbacks
 *
 * Returns font family with appropriate system font fallbacks.
 *
 * @since 1.0.0
 * @param string $font Font family name
 * @return string Font stack with fallbacks
 */
function weown_get_font_stack($font) {
    // System font stacks already have fallbacks
    if (strpos($font, ',') !== false) {
        return $font;
    }
    
    // Google Fonts get generic fallbacks
    if (weown_is_google_font($font)) {
        return "'{$font}', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif";
    }
    
    // Default fallback
    return $font . ', sans-serif';
}

/**
 * Check if Font is Google Font
 *
 * Determines if a font is from Google Fonts vs system font.
 *
 * @since 1.0.0
 * @param string $font Font family name
 * @return bool True if Google Font, false if system font
 */
function weown_is_google_font($font) {
    // System fonts contain commas (full stack) or common system font names
    $system_fonts = [
        '-apple-system',
        'BlinkMacSystemFont',
        'Segoe UI',
        'Roboto',
        'Oxygen-Sans',
        'Ubuntu',
        'Cantarell',
        'Helvetica Neue',
        'Arial',
        'Georgia',
        'Times New Roman',
        'Courier New',
    ];
    
    foreach ($system_fonts as $sys_font) {
        if (stripos($font, $sys_font) !== false) {
            return false;
        }
    }
    
    return true;
}

/**
 * Adjust Color Brightness
 *
 * Lightens or darkens a hex color by a percentage.
 * Used to generate color variants (hover states, etc.)
 *
 * @since 1.0.0
 * @param string $hex Hex color code
 * @param int $percent Percentage to adjust (-100 to 100)
 * @return string Adjusted hex color
 */
function weown_adjust_color_brightness($hex, $percent) {
    // Remove # if present
    $hex = ltrim($hex, '#');
    
    // Convert to RGB
    if (strlen($hex) === 3) {
        $r = hexdec(substr($hex, 0, 1) . substr($hex, 0, 1));
        $g = hexdec(substr($hex, 1, 1) . substr($hex, 1, 1));
        $b = hexdec(substr($hex, 2, 1) . substr($hex, 2, 1));
    } else {
        $r = hexdec(substr($hex, 0, 2));
        $g = hexdec(substr($hex, 2, 2));
        $b = hexdec(substr($hex, 4, 2));
    }
    
    // Adjust brightness
    $r = max(0, min(255, $r + ($r * $percent / 100)));
    $g = max(0, min(255, $g + ($g * $percent / 100)));
    $b = max(0, min(255, $b + ($b * $percent / 100)));
    
    // Convert back to hex
    return sprintf('#%02x%02x%02x', $r, $g, $b);
}

/**
 * Invalidate Dynamic CSS Cache on Customizer Save
 *
 * Deletes the cached CSS transient when customizer settings are saved,
 * forcing regeneration on next page load.
 *
 * @since 1.0.0
 */
function weown_invalidate_dynamic_css_cache() {
    delete_transient('weown_dynamic_css');
}
add_action('customize_save_after', 'weown_invalidate_dynamic_css_cache');
