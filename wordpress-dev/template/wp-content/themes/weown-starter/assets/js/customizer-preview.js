/**
 * WeOwn Starter Theme - Customizer Live Preview
 *
 * Handles real-time updates in the WordPress Customizer preview pane.
 * Updates CSS custom properties without page reload for instant feedback.
 *
 * Architecture: Uses WordPress Customizer Preview API with postMessage transport
 * to update CSS variables in real-time, providing smooth user experience.
 *
 * WordPress 6.8+ Best Practice: Debounced updates for rapid changes,
 * batched DOM updates for performance.
 *
 * @package WeOwn_Starter
 * @subpackage Customizer
 * @since 1.0.0
 * @version 1.0.0
 */

(function($) {
    'use strict';
    
    /**
     * Helper: Update CSS Variable
     *
     * Updates a CSS custom property on the :root element.
     * Used for instant preview updates without page reload.
     *
     * @param {string} property CSS variable name (with or without --)
     * @param {string} value CSS value
     */
    function updateCSSVariable(property, value) {
        // Ensure property has -- prefix
        if (!property.startsWith('--')) {
            property = '--' + property;
        }
        
        // Update on document root
        document.documentElement.style.setProperty(property, value);
    }
    
    /**
     * Helper: Debounce Function
     *
     * Delays execution until after wait time has elapsed since last call.
     * Prevents performance issues with rapid slider movements.
     *
     * @param {Function} func Function to debounce
     * @param {number} wait Milliseconds to wait
     * @return {Function} Debounced function
     */
    function debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }
    
    /**
     * Color Updates (Instant)
     *
     * Update brand colors in real-time with automatic variant generation.
     * No debouncing needed - color changes are instant and non-intensive.
     */
    
    // Primary Color
    wp.customize('primary_color', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('color-primary', newval);
            // Generate and update light/dark variants
            const light = adjustColorBrightness(newval, 20);
            const dark = adjustColorBrightness(newval, -20);
            updateCSSVariable('color-primary-light', light);
            updateCSSVariable('color-primary-dark', dark);
        });
    });
    
    // Secondary Color
    wp.customize('secondary_color', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('color-secondary', newval);
            const light = adjustColorBrightness(newval, 20);
            const dark = adjustColorBrightness(newval, -20);
            updateCSSVariable('color-secondary-light', light);
            updateCSSVariable('color-secondary-dark', dark);
        });
    });
    
    // Accent Color
    wp.customize('accent_color', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('color-accent', newval);
            const light = adjustColorBrightness(newval, 20);
            const dark = adjustColorBrightness(newval, -20);
            updateCSSVariable('color-accent-light', light);
            updateCSSVariable('color-accent-dark', dark);
        });
    });
    
    // Text Color
    wp.customize('text_color', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('color-text', newval);
        });
    });
    
    // Heading Color
    wp.customize('heading_color', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('color-heading', newval);
        });
    });
    
    // Background Color
    wp.customize('background_color', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('color-background', newval);
        });
    });
    
    // Secondary Background Color
    wp.customize('secondary_bg_color', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('color-background-secondary', newval);
        });
    });
    
    /**
     * Typography Updates (Debounced)
     *
     * Update typography settings with debouncing for slider controls.
     * Prevents excessive updates during rapid slider movements.
     */
    
    // Font Families (Instant - requires font loading)
    wp.customize('font_heading', function(value) {
        value.bind(function(newval) {
            const fontStack = getFontStack(newval);
            updateCSSVariable('font-heading', fontStack);
            // Load font if it's a Google Font
            if (isGoogleFont(newval)) {
                loadGoogleFont(newval);
            }
        });
    });
    
    wp.customize('font_body', function(value) {
        value.bind(function(newval) {
            const fontStack = getFontStack(newval);
            updateCSSVariable('font-body', fontStack);
            if (isGoogleFont(newval)) {
                loadGoogleFont(newval);
            }
        });
    });
    
    // Base Font Size (Debounced)
    wp.customize('font_size_base', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('font-size-base', newval + 'px');
            // Recalculate all heading sizes based on scale
            recalculateFontSizes();
        }, 100));
    });
    
    // Font Scale (Instant - important visual change)
    wp.customize('font_scale', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('font-scale', newval);
            recalculateFontSizes();
        });
    });
    
    // Line Heights (Debounced)
    wp.customize('line_height_base', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('line-height-base', newval);
        }, 100));
    });
    
    wp.customize('line_height_heading', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('line-height-heading', newval);
        }, 100));
    });
    
    // Font Weights (Instant)
    wp.customize('font_weight_heading', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('font-weight-heading', newval);
        });
    });
    
    wp.customize('font_weight_body', function(value) {
        value.bind(function(newval) {
            updateCSSVariable('font-weight-body', newval);
        });
    });
    
    /**
     * Layout Updates (Debounced)
     *
     * Update layout and spacing with debouncing for slider controls.
     * Prevents layout thrashing during rapid adjustments.
     */
    
    // Container Widths
    wp.customize('container_width', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('container-width', newval + 'px');
        }, 150));
    });
    
    wp.customize('content_width', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('content-width', newval + 'px');
        }, 150));
    });
    
    // Section Spacing
    wp.customize('section_spacing_top', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('section-spacing-top', newval + 'px');
        }, 100));
    });
    
    wp.customize('section_spacing_bottom', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('section-spacing-bottom', newval + 'px');
        }, 100));
    });
    
    // Element Spacing (recalculates spacing scale)
    wp.customize('element_spacing', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('spacing-base', newval + 'px');
            // Recalculate spacing scale
            updateCSSVariable('spacing-xs', (newval * 0.25) + 'px');
            updateCSSVariable('spacing-sm', (newval * 0.5) + 'px');
            updateCSSVariable('spacing-md', newval + 'px');
            updateCSSVariable('spacing-lg', (newval * 1.5) + 'px');
            updateCSSVariable('spacing-xl', (newval * 2) + 'px');
            updateCSSVariable('spacing-2xl', (newval * 3) + 'px');
        }, 100));
    });
    
    // Border Radius
    wp.customize('border_radius', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('border-radius', newval + 'px');
            updateCSSVariable('border-radius-sm', Math.max(0, newval - 2) + 'px');
            updateCSSVariable('border-radius-lg', (newval + 4) + 'px');
        }, 100));
    });
    
    // Logo Widths
    wp.customize('logo_width', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('logo-width', newval + 'px');
        }, 150));
    });
    
    wp.customize('logo_width_mobile', function(value) {
        value.bind(debounce(function(newval) {
            updateCSSVariable('logo-width-mobile', newval + 'px');
        }, 150));
    });
    
    /**
     * Text Content Updates (Instant)
     *
     * Update text content in real-time without page reload.
     * Uses selective refresh for better performance.
     */
    
    // Header CTA Text
    wp.customize('header_cta_text', function(value) {
        value.bind(function(newval) {
            $('.header-cta-button').text(newval);
        });
    });
    
    // Header CTA URL
    wp.customize('header_cta_url', function(value) {
        value.bind(function(newval) {
            $('.header-cta-button').attr('href', newval);
        });
    });
    
    // Footer Copyright
    wp.customize('footer_copyright', function(value) {
        value.bind(function(newval) {
            // Replace placeholders
            const year = new Date().getFullYear();
            const siteName = wp.customize('blogname')();
            let text = newval.replace('{{YEAR}}', year);
            text = text.replace('{{SITE_NAME}}', siteName);
            $('.footer-copyright').html(text);
        });
    });
    
    /**
     * Helper Functions
     */
    
    /**
     * Recalculate Font Sizes
     *
     * Recalculates all heading sizes based on base size and scale.
     * Called when base size or scale changes.
     */
    function recalculateFontSizes() {
        const baseSize = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--font-size-base'));
        const scale = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--font-scale'));
        
        // Calculate heading sizes
        const h1 = Math.round(baseSize * Math.pow(scale, 3) * 100) / 100;
        const h2 = Math.round(baseSize * Math.pow(scale, 2.5) * 100) / 100;
        const h3 = Math.round(baseSize * Math.pow(scale, 2) * 100) / 100;
        const h4 = Math.round(baseSize * Math.pow(scale, 1.5) * 100) / 100;
        const h5 = Math.round(baseSize * Math.pow(scale, 1) * 100) / 100;
        const h6 = Math.round(baseSize * Math.pow(scale, 0.75) * 100) / 100;
        
        updateCSSVariable('font-size-h1', h1 + 'px');
        updateCSSVariable('font-size-h2', h2 + 'px');
        updateCSSVariable('font-size-h3', h3 + 'px');
        updateCSSVariable('font-size-h4', h4 + 'px');
        updateCSSVariable('font-size-h5', h5 + 'px');
        updateCSSVariable('font-size-h6', h6 + 'px');
        
        // Calculate small text sizes
        const small = Math.round(baseSize * 0.875 * 100) / 100;
        const tiny = Math.round(baseSize * 0.75 * 100) / 100;
        updateCSSVariable('font-size-small', small + 'px');
        updateCSSVariable('font-size-tiny', tiny + 'px');
    }
    
    /**
     * Get Font Stack
     *
     * Returns font family with appropriate system font fallbacks.
     *
     * @param {string} font Font family name
     * @return {string} Font stack with fallbacks
     */
    function getFontStack(font) {
        // System font stacks already have fallbacks
        if (font.includes(',')) {
            return font;
        }
        
        // Google Fonts get generic fallbacks
        if (isGoogleFont(font)) {
            return `'${font}', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`;
        }
        
        return font + ', sans-serif';
    }
    
    /**
     * Check if Font is Google Font
     *
     * @param {string} font Font family name
     * @return {boolean} True if Google Font
     */
    function isGoogleFont(font) {
        const systemFonts = [
            '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto',
            'Oxygen-Sans', 'Ubuntu', 'Cantarell', 'Helvetica Neue',
            'Arial', 'Georgia', 'Times New Roman', 'Courier New'
        ];
        
        return !systemFonts.some(sysFont => font.includes(sysFont));
    }
    
    /**
     * Load Google Font
     *
     * Dynamically loads a Google Font by injecting a link element.
     * Prevents duplicate loads with ID tracking.
     *
     * @param {string} font Font family name
     */
    function loadGoogleFont(font) {
        const fontId = 'google-font-' + font.replace(/\s+/g, '-').toLowerCase();
        
        // Check if already loaded
        if (document.getElementById(fontId)) {
            return;
        }
        
        // Build Google Fonts URL
        const fontUrl = 'https://fonts.googleapis.com/css2?family=' + 
                       encodeURIComponent(font) + ':wght@300;400;500;600;700&display=swap';
        
        // Create and inject link element
        const link = document.createElement('link');
        link.id = fontId;
        link.rel = 'stylesheet';
        link.href = fontUrl;
        document.head.appendChild(link);
    }
    
    /**
     * Adjust Color Brightness
     *
     * Lightens or darkens a hex color by a percentage.
     *
     * @param {string} hex Hex color code
     * @param {number} percent Percentage to adjust (-100 to 100)
     * @return {string} Adjusted hex color
     */
    function adjustColorBrightness(hex, percent) {
        // Remove # if present
        hex = hex.replace('#', '');
        
        // Convert to RGB
        let r, g, b;
        if (hex.length === 3) {
            r = parseInt(hex[0] + hex[0], 16);
            g = parseInt(hex[1] + hex[1], 16);
            b = parseInt(hex[2] + hex[2], 16);
        } else {
            r = parseInt(hex.substr(0, 2), 16);
            g = parseInt(hex.substr(2, 2), 16);
            b = parseInt(hex.substr(4, 2), 16);
        }
        
        // Adjust brightness
        r = Math.max(0, Math.min(255, r + (r * percent / 100)));
        g = Math.max(0, Math.min(255, g + (g * percent / 100)));
        b = Math.max(0, Math.min(255, b + (b * percent / 100)));
        
        // Convert back to hex
        const rHex = Math.round(r).toString(16).padStart(2, '0');
        const gHex = Math.round(g).toString(16).padStart(2, '0');
        const bHex = Math.round(b).toString(16).padStart(2, '0');
        
        return '#' + rHex + gHex + bHex;
    }
    
})(jQuery);
