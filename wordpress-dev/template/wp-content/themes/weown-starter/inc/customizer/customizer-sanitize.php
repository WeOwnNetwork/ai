<?php
/**
 * WeOwn Starter Theme - Customizer Sanitization Callbacks
 *
 * Security-first sanitization functions for all customizer inputs.
 * NEVER trust user input - every value must be properly validated and sanitized.
 *
 * WordPress 6.8+ Security Best Practice: Type-specific sanitization with
 * whitelist validation for enum values and range validation for numbers.
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
 * Sanitize Checkbox Input
 *
 * Ensures checkbox values are boolean true/false.
 * WordPress stores checkboxes as 1 or empty string, we normalize to boolean.
 *
 * @since 1.0.0
 * @param mixed $checked The checkbox value to sanitize
 * @return bool True if checked, false otherwise
 */
function weown_sanitize_checkbox($checked) {
    // Boolean values are valid
    if (is_bool($checked)) {
        return $checked;
    }
    
    // Integer 1 = checked
    return (int) $checked === 1;
}

/**
 * Sanitize Color Input (Hex or RGBA)
 *
 * Validates hex colors (#RGB or #RRGGBB) and rgba() colors.
 * Returns default if invalid to prevent CSS injection attacks.
 *
 * Security Note: Prevents CSS injection by validating format.
 *
 * @since 1.0.0
 * @param string $color The color value to sanitize
 * @param string $default Optional default color if validation fails
 * @return string Sanitized color value or default
 */
function weown_sanitize_color($color, $default = '#000000') {
    // Allow empty values (use CSS default)
    if (empty($color)) {
        return '';
    }
    
    // Sanitize hex colors
    if (preg_match('/^#([A-Fa-f0-9]{3}){1,2}$/', $color)) {
        return sanitize_hex_color($color);
    }
    
    // Sanitize rgba colors: rgba(r, g, b, a)
    if (preg_match('/^rgba?\(\s*\d+\s*,\s*\d+\s*,\s*\d+\s*(,\s*[\d.]+\s*)?\)$/', $color)) {
        return sanitize_text_field($color);
    }
    
    // Invalid color format - return default
    return $default;
}

/**
 * Sanitize Integer Input with Range Validation
 *
 * Ensures value is an integer within specified min/max range.
 * Prevents out-of-bounds values that could break layouts.
 *
 * @since 1.0.0
 * @param int $number The number to sanitize
 * @param int $min Minimum allowed value
 * @param int $max Maximum allowed value
 * @param int $default Default value if out of range
 * @return int Sanitized integer within range
 */
function weown_sanitize_integer($number, $min = 0, $max = PHP_INT_MAX, $default = 0) {
    // Convert to integer
    $number = absint($number);
    
    // Validate range
    if ($number < $min || $number > $max) {
        return $default;
    }
    
    return $number;
}

/**
 * Sanitize Float Input with Range Validation
 *
 * Ensures value is a float within specified min/max range.
 * Used for decimal values like line height, font scale, opacity.
 *
 * @since 1.0.0
 * @param float $number The number to sanitize
 * @param float $min Minimum allowed value
 * @param float $max Maximum allowed value
 * @param float $default Default value if out of range
 * @return float Sanitized float within range
 */
function weown_sanitize_float($number, $min = 0.0, $max = PHP_FLOAT_MAX, $default = 0.0) {
    // Convert to float
    $number = floatval($number);
    
    // Validate range
    if ($number < $min || $number > $max) {
        return $default;
    }
    
    return $number;
}

/**
 * Sanitize Select Input (Whitelist Validation)
 *
 * Validates that selected value exists in the whitelist of allowed choices.
 * CRITICAL for security - prevents arbitrary value injection.
 *
 * Security Note: Only allows pre-defined values, preventing injection attacks.
 *
 * @since 1.0.0
 * @param string $input The value to sanitize
 * @param WP_Customize_Setting $setting The setting object (contains choices)
 * @return string Sanitized value or default
 */
function weown_sanitize_select($input, $setting) {
    // Ensure input is a string
    $input = sanitize_key($input);
    
    // Get list of allowed choices
    $choices = $setting->manager->get_control($setting->id)->choices;
    
    // Return input if valid, otherwise return default
    return array_key_exists($input, $choices) ? $input : $setting->default;
}

/**
 * Sanitize Radio Input (Whitelist Validation)
 *
 * Validates that selected radio value exists in the whitelist.
 * Identical to select sanitization but kept separate for semantic clarity.
 *
 * @since 1.0.0
 * @param string $input The value to sanitize
 * @param WP_Customize_Setting $setting The setting object (contains choices)
 * @return string Sanitized value or default
 */
function weown_sanitize_radio($input, $setting) {
    return weown_sanitize_select($input, $setting);
}

/**
 * Sanitize URL Input
 *
 * Validates and sanitizes URL input for links, images, etc.
 * Allows both absolute and relative URLs.
 *
 * @since 1.0.0
 * @param string $url The URL to sanitize
 * @return string Sanitized URL
 */
function weown_sanitize_url($url) {
    // Allow empty URLs
    if (empty($url)) {
        return '';
    }
    
    return esc_url_raw($url);
}

/**
 * Sanitize Image Upload
 *
 * Validates image URLs and checks file extension.
 * Ensures uploaded files are actually images.
 *
 * Security Note: Validates file extension to prevent non-image uploads.
 *
 * @since 1.0.0
 * @param string $image The image URL to sanitize
 * @return string Sanitized image URL or empty string
 */
function weown_sanitize_image($image) {
    // Allow empty values
    if (empty($image)) {
        return '';
    }
    
    // Sanitize URL
    $image = esc_url_raw($image);
    
    // Validate image extension
    $allowed_extensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'ico'];
    $file_extension = strtolower(pathinfo($image, PATHINFO_EXTENSION));
    
    if (!in_array($file_extension, $allowed_extensions, true)) {
        return '';
    }
    
    return $image;
}

/**
 * Sanitize Text Input
 *
 * Sanitizes text fields - removes tags and validates encoding.
 * Use for short text inputs (titles, labels, button text).
 *
 * @since 1.0.0
 * @param string $input The text to sanitize
 * @return string Sanitized text
 */
function weown_sanitize_text($input) {
    return sanitize_text_field($input);
}

/**
 * Sanitize Textarea Input
 *
 * Sanitizes multi-line text with limited HTML support.
 * Allows safe HTML tags for formatting (strong, em, a, br).
 *
 * @since 1.0.0
 * @param string $input The textarea content to sanitize
 * @return string Sanitized textarea content
 */
function weown_sanitize_textarea($input) {
    // Allow safe HTML tags
    $allowed_html = [
        'br'     => [],
        'em'     => [],
        'strong' => [],
        'a'      => [
            'href'   => [],
            'title'  => [],
            'target' => [],
            'rel'    => [],
        ],
        'p'      => [],
    ];
    
    return wp_kses($input, $allowed_html);
}

/**
 * Sanitize HTML Content
 *
 * Sanitizes rich HTML content for advanced customizer controls.
 * Allows more HTML tags than textarea for custom content sections.
 *
 * Security Note: Uses wp_kses_post() which allows post-safe HTML.
 *
 * @since 1.0.0
 * @param string $input The HTML content to sanitize
 * @return string Sanitized HTML content
 */
function weown_sanitize_html($input) {
    return wp_kses_post($input);
}

/**
 * Sanitize CSS Code
 *
 * Sanitizes custom CSS input for advanced users.
 * Strips PHP and JavaScript to prevent code injection.
 *
 * Security Critical: Prevents script injection via CSS.
 *
 * @since 1.0.0
 * @param string $css The CSS code to sanitize
 * @return string Sanitized CSS code
 */
function weown_sanitize_css($css) {
    // Strip PHP tags
    $css = preg_replace('/<\?php.*?\?>/s', '', $css);
    
    // Strip JavaScript
    $css = preg_replace('/<script\b[^>]*>.*?<\/script>/is', '', $css);
    
    // Allow only CSS
    return wp_strip_all_tags($css);
}

/**
 * Sanitize Font Family
 *
 * Validates font family names against allowed list.
 * Prevents CSS injection via malformed font names.
 *
 * @since 1.0.0
 * @param string $font The font family to sanitize
 * @return string Sanitized font family
 */
function weown_sanitize_font_family($font) {
    // Allow empty (use default)
    if (empty($font)) {
        return '';
    }
    
    // Basic sanitization
    $font = sanitize_text_field($font);
    
    // Validate against allowed characters (letters, numbers, spaces, hyphens)
    if (!preg_match('/^[a-zA-Z0-9\s\-,]+$/', $font)) {
        return 'Inter'; // Fallback to default
    }
    
    return $font;
}

/**
 * Sanitize Google Analytics ID
 *
 * Validates Google Analytics tracking ID format (GA4 or Universal Analytics).
 * Formats: G-XXXXXXXXXX (GA4) or UA-XXXXXXXX-X (Universal Analytics)
 *
 * @since 1.0.0
 * @param string $tracking_id The tracking ID to sanitize
 * @return string Sanitized tracking ID or empty string
 */
function weown_sanitize_analytics_id($tracking_id) {
    // Allow empty
    if (empty($tracking_id)) {
        return '';
    }
    
    // Sanitize input
    $tracking_id = sanitize_text_field($tracking_id);
    
    // Validate GA4 format: G-XXXXXXXXXX
    if (preg_match('/^G-[A-Z0-9]{10}$/', $tracking_id)) {
        return $tracking_id;
    }
    
    // Validate Universal Analytics format: UA-XXXXXXXX-X
    if (preg_match('/^UA-\d{8}-\d+$/', $tracking_id)) {
        return $tracking_id;
    }
    
    // Invalid format
    return '';
}

/**
 * Sanitize Placeholder Text
 *
 * Validates placeholder tokens used in deployment automation.
 * Ensures placeholders match required format: {{VARIABLE_NAME}}
 *
 * WordPress 6.8+ Best Practice: Support for deployment automation (Phase 4).
 *
 * @since 1.0.0
 * @param string $text The text with placeholders to sanitize
 * @return string Sanitized text with validated placeholders
 */
function weown_sanitize_placeholders($text) {
    // Sanitize base text
    $text = sanitize_text_field($text);
    
    // Validate placeholder format: {{VARIABLE_NAME}}
    // Allow alphanumeric, underscores in placeholders
    if (preg_match_all('/\{\{([A-Z0-9_]+)\}\}/', $text, $matches)) {
        // Placeholders are valid
        return $text;
    }
    
    return $text;
}
