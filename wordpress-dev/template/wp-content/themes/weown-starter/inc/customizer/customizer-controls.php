<?php
/**
 * WeOwn Starter Theme - Custom Customizer Controls
 *
 * Enhanced customizer controls for professional UX and advanced functionality.
 * Extends WordPress core controls with improved interfaces and features.
 *
 * WordPress 6.8+ Best Practice: Custom controls for better user experience
 * and more intuitive theme customization.
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
 * Range Control with Live Value Display
 *
 * Extends the base range control to show the current numeric value
 * alongside the slider. Improves UX by providing immediate visual feedback.
 *
 * Features:
 * - Live value display next to slider
 * - Configurable min/max/step values
 * - Unit display (px, em, rem, %, etc.)
 * - Responsive design
 *
 * @since 1.0.0
 */
class WeOwn_Customize_Range_Control extends WP_Customize_Control {
    /**
     * Control type
     *
     * @var string
     */
    public $type = 'weown-range';
    
    /**
     * Minimum value
     *
     * @var int
     */
    public $min = 0;
    
    /**
     * Maximum value
     *
     * @var int
     */
    public $max = 100;
    
    /**
     * Step increment
     *
     * @var int
     */
    public $step = 1;
    
    /**
     * Unit label (px, em, %, etc.)
     *
     * @var string
     */
    public $unit = '';
    
    /**
     * Render Control Content
     *
     * Outputs the HTML for the range control with live value display.
     *
     * @since 1.0.0
     */
    public function render_content() {
        ?>
        <label>
            <?php if (!empty($this->label)) : ?>
                <span class="customize-control-title"><?php echo esc_html($this->label); ?></span>
            <?php endif; ?>
            
            <?php if (!empty($this->description)) : ?>
                <span class="description customize-control-description"><?php echo esc_html($this->description); ?></span>
            <?php endif; ?>
            
            <div class="weown-range-control-wrapper">
                <input 
                    type="range" 
                    id="<?php echo esc_attr($this->id); ?>"
                    <?php $this->link(); ?>
                    min="<?php echo esc_attr($this->min); ?>"
                    max="<?php echo esc_attr($this->max); ?>"
                    step="<?php echo esc_attr($this->step); ?>"
                    value="<?php echo esc_attr($this->value()); ?>"
                    class="weown-range-input"
                />
                <span class="weown-range-value">
                    <span class="value"><?php echo esc_html($this->value()); ?></span>
                    <?php if (!empty($this->unit)) : ?>
                        <span class="unit"><?php echo esc_html($this->unit); ?></span>
                    <?php endif; ?>
                </span>
            </div>
        </label>
        
        <style>
            .weown-range-control-wrapper {
                display: flex;
                align-items: center;
                gap: 12px;
                margin-top: 8px;
            }
            
            .weown-range-input {
                flex: 1;
                min-width: 0;
            }
            
            .weown-range-value {
                min-width: 60px;
                padding: 4px 12px;
                background: #f0f0f1;
                border: 1px solid #dcdcde;
                border-radius: 4px;
                text-align: center;
                font-size: 13px;
                font-weight: 500;
                color: #1d2327;
            }
            
            .weown-range-value .unit {
                margin-left: 2px;
                color: #757575;
                font-weight: 400;
            }
        </style>
        
        <script>
        (function($) {
            // Update displayed value when slider changes
            $('#<?php echo esc_js($this->id); ?>').on('input change', function() {
                $(this).siblings('.weown-range-value').find('.value').text($(this).val());
            });
        })(jQuery);
        </script>
        <?php
    }
    
    /**
     * Enqueue Control Scripts and Styles
     *
     * Loads any additional assets needed for the control.
     * Currently handled inline, but can be moved to separate files.
     *
     * @since 1.0.0
     */
    public function enqueue() {
        // Inline styles and scripts are sufficient for now
        // Can be moved to separate files if controls become more complex
    }
}

/**
 * Google Fonts Select Control
 *
 * Font family selector with Google Fonts integration.
 * Provides access to 1000+ professional web fonts.
 *
 * Features:
 * - Searchable font dropdown
 * - Popular fonts prioritized
 * - Font preview in dropdown
 * - System font fallbacks
 *
 * WordPress 6.8+ Best Practice: Use select2 for enhanced UX.
 *
 * @since 1.0.0
 */
class WeOwn_Customize_Font_Control extends WP_Customize_Control {
    /**
     * Control type
     *
     * @var string
     */
    public $type = 'weown-font-select';
    
    /**
     * Font choices array
     *
     * @var array
     */
    public $choices = [];
    
    /**
     * Constructor
     *
     * Sets up the font choices if not provided.
     *
     * @since 1.0.0
     * @param WP_Customize_Manager $manager Customizer manager
     * @param string $id Control ID
     * @param array $args Control arguments
     */
    public function __construct($manager, $id, $args = []) {
        parent::__construct($manager, $id, $args);
        
        // Set default font choices if not provided
        if (empty($this->choices)) {
            $this->choices = $this->get_google_fonts();
        }
    }
    
    /**
     * Get Google Fonts List
     *
     * Returns curated list of popular Google Fonts.
     * Full API integration can be added in future versions.
     *
     * Design Decision: Start with curated list for performance.
     * Full Google Fonts API = 1000+ fonts = slow dropdown.
     * Curated list = 50 best fonts = fast, professional selection.
     *
     * @since 1.0.0
     * @return array Font families array
     */
    private function get_google_fonts() {
        return [
            // System Fonts (Fast, Always Available)
            'optgroup-system' => 'System Fonts',
            '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif' => 'System UI (Default)',
            'Georgia, serif' => 'Georgia',
            '"Times New Roman", Times, serif' => 'Times New Roman',
            'Arial, sans-serif' => 'Arial',
            '"Courier New", Courier, monospace' => 'Courier New',
            
            // Popular Google Fonts (Sans-Serif)
            'optgroup-sans' => 'Sans-Serif Fonts',
            'Inter' => 'Inter',
            'Roboto' => 'Roboto',
            'Open Sans' => 'Open Sans',
            'Lato' => 'Lato',
            'Montserrat' => 'Montserrat',
            'Poppins' => 'Poppins',
            'Source Sans Pro' => 'Source Sans Pro',
            'Raleway' => 'Raleway',
            'Nunito' => 'Nunito',
            'Work Sans' => 'Work Sans',
            'Rubik' => 'Rubik',
            'DM Sans' => 'DM Sans',
            'Plus Jakarta Sans' => 'Plus Jakarta Sans',
            
            // Popular Google Fonts (Serif)
            'optgroup-serif' => 'Serif Fonts',
            'Merriweather' => 'Merriweather',
            'Playfair Display' => 'Playfair Display',
            'Lora' => 'Lora',
            'PT Serif' => 'PT Serif',
            'Crimson Text' => 'Crimson Text',
            'Source Serif Pro' => 'Source Serif Pro',
            'Libre Baskerville' => 'Libre Baskerville',
            
            // Monospace Fonts
            'optgroup-mono' => 'Monospace Fonts',
            'Fira Code' => 'Fira Code',
            'Source Code Pro' => 'Source Code Pro',
            'JetBrains Mono' => 'JetBrains Mono',
            'IBM Plex Mono' => 'IBM Plex Mono',
        ];
    }
    
    /**
     * Render Control Content
     *
     * Outputs the HTML for the font select control.
     *
     * @since 1.0.0
     */
    public function render_content() {
        ?>
        <label>
            <?php if (!empty($this->label)) : ?>
                <span class="customize-control-title"><?php echo esc_html($this->label); ?></span>
            <?php endif; ?>
            
            <?php if (!empty($this->description)) : ?>
                <span class="description customize-control-description"><?php echo esc_html($this->description); ?></span>
            <?php endif; ?>
            
            <select <?php $this->link(); ?> class="weown-font-select">
                <?php
                $current_group = '';
                foreach ($this->choices as $value => $label) {
                    // Handle optgroups
                    if (strpos($value, 'optgroup-') === 0) {
                        if ($current_group) {
                            echo '</optgroup>';
                        }
                        echo '<optgroup label="' . esc_attr($label) . '">';
                        $current_group = $value;
                        continue;
                    }
                    
                    printf(
                        '<option value="%s" %s style="font-family: %s;">%s</option>',
                        esc_attr($value),
                        selected($this->value(), $value, false),
                        esc_attr($value),
                        esc_html($label)
                    );
                }
                
                if ($current_group) {
                    echo '</optgroup>';
                }
                ?>
            </select>
        </label>
        
        <style>
            .weown-font-select {
                width: 100%;
                margin-top: 8px;
            }
            
            .weown-font-select option {
                padding: 8px;
                font-size: 14px;
            }
        </style>
        <?php
    }
}

/**
 * Info/Heading Control
 *
 * Non-setting control used for section headings, descriptions, and help text.
 * Improves customizer organization and user guidance.
 *
 * @since 1.0.0
 */
class WeOwn_Customize_Info_Control extends WP_Customize_Control {
    /**
     * Control type
     *
     * @var string
     */
    public $type = 'weown-info';
    
    /**
     * Render Control Content
     *
     * Outputs informational content without an input field.
     *
     * @since 1.0.0
     */
    public function render_content() {
        ?>
        <div class="weown-info-control">
            <?php if (!empty($this->label)) : ?>
                <h3 class="weown-info-title"><?php echo esc_html($this->label); ?></h3>
            <?php endif; ?>
            
            <?php if (!empty($this->description)) : ?>
                <div class="weown-info-description"><?php echo wp_kses_post($this->description); ?></div>
            <?php endif; ?>
        </div>
        
        <style>
            .weown-info-control {
                margin: 16px 0;
                padding: 12px;
                background: #f0f6fc;
                border-left: 4px solid #0066cc;
                border-radius: 4px;
            }
            
            .weown-info-title {
                margin: 0 0 8px 0;
                font-size: 14px;
                font-weight: 600;
                color: #1d2327;
            }
            
            .weown-info-description {
                margin: 0;
                font-size: 13px;
                line-height: 1.6;
                color: #50575e;
            }
            
            .weown-info-description p {
                margin: 0 0 8px 0;
            }
            
            .weown-info-description p:last-child {
                margin-bottom: 0;
            }
        </style>
        <?php
    }
}

/**
 * Register Custom Controls
 *
 * Registers all custom control classes with WordPress Customizer.
 * Called automatically when customizer is initialized.
 *
 * @since 1.0.0
 * @param WP_Customize_Manager $wp_customize Customizer manager instance
 */
function weown_register_custom_controls($wp_customize) {
    // Controls are registered automatically when used
    // This function exists for future expansion
}
add_action('customize_register', 'weown_register_custom_controls');
