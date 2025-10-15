<?php
/**
 * WeOwn Starter Theme - Call-to-Action Template Part (template-parts/call-to-action.php)
 *
 * Reusable call-to-action component with multiple layouts, button styles,
 * and conversion optimization features for maximum business impact.
 *
 * Features:
 * - Multiple CTA layouts (inline, centered, sidebar)
 * - Primary and secondary button configurations
 * - Benefit-focused messaging and urgency elements
 * - Social proof integration and trust indicators
 * - Performance-optimized loading and animations
 * - Accessibility-compliant structure with proper focus management
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
 * Call-to-Action Configuration
 *
 * Get CTA settings from theme customizer, page meta, or global defaults.
 * Supports multiple CTA types and strategic placement options.
 */
$cta_config = weown_get_cta_config();
$cta_layout = $cta_config['layout'] ?? 'centered';
$cta_style = $cta_config['style'] ?? 'primary';

/**
 * CTA Content Variables
 *
 * Extract CTA content from current context or theme settings.
 * Supports dynamic content injection and A/B testing capabilities.
 */
$cta_headline = weown_get_cta_headline();
$cta_description = weown_get_cta_description();
$cta_buttons = weown_get_cta_buttons();
$cta_urgency = weown_get_cta_urgency();
$cta_social_proof = weown_get_cta_social_proof();

/**
 * Call-to-Action Section Structure
 *
 * Flexible CTA layout system supporting multiple use cases and
 * conversion optimization strategies for different business goals.
 */
?>
<section class="weown-cta-section weown-cta-layout-<?php echo esc_attr($cta_layout); ?> weown-cta-style-<?php echo esc_attr($cta_style); ?>"
         <?php echo weown_get_cta_attributes(); ?>>

    <div class="weown-cta-container">

        <?php
        /**
         * CTA Background and Visual Elements
         *
         * Background patterns, gradients, and visual elements that
         * enhance conversion rates and draw attention to the CTA.
         */
        ?>
        <div class="weown-cta-background">
            <?php weown_cta_background(); ?>
        </div><!-- .weown-cta-background -->

        <?php
        /**
         * CTA Content Area
         *
         * Main content area with headline, description, and conversion elements.
         * Supports multiple content layouts and responsive design patterns.
         */
        ?>
        <div class="weown-cta-content">

            <?php if ($cta_headline) : ?>
            <header class="weown-cta-header">
                <h2 class="weown-cta-headline"<?php echo weown_get_cta_headline_attributes(); ?>>
                    <?php echo wp_kses_post($cta_headline); ?>
                </h2>

                <?php if ($cta_urgency) : ?>
                <div class="weown-cta-urgency">
                    <span class="weown-urgency-badge">
                        <?php echo wp_kses_post($cta_urgency); ?>
                    </span>
                </div><!-- .weown-cta-urgency -->
                <?php endif; ?>
            </header><!-- .weown-cta-header -->
            <?php endif; ?>

            <?php if ($cta_description) : ?>
            <div class="weown-cta-description">
                <p><?php echo wp_kses_post($cta_description); ?></p>
            </div><!-- .weown-cta-description -->
            <?php endif; ?>

            <?php
            /**
             * CTA Buttons and Actions
             *
             * Primary and secondary call-to-action buttons with conversion
             * optimization, accessibility features, and responsive design.
             */
            ?>
            <?php if (!empty($cta_buttons)) : ?>
            <div class="weown-cta-buttons">
                <?php foreach ($cta_buttons as $index => $button) : ?>
                <a href="<?php echo esc_url($button['url']); ?>"
                   class="weown-cta-button weown-cta-button-<?php echo esc_attr($button['type'] ?? 'primary'); ?>"
                   <?php echo weown_get_cta_button_attributes($button); ?>>
                    <?php echo esc_html($button['text']); ?>
                    <?php if (!empty($button['icon'])) : ?>
                    <svg class="weown-cta-button-icon" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                        <?php echo $button['icon']; ?>
                    </svg>
                    <?php endif; ?>
                </a>
                <?php endforeach; ?>
            </div><!-- .weown-cta-buttons -->
            <?php endif; ?>

            <?php
            /**
             * Social Proof Integration (Optional)
             *
             * Trust indicators, testimonials, and credibility elements
             * to increase conversion confidence and user trust.
             */
            ?>
            <?php if ($cta_social_proof && weown_show_cta_social_proof()) : ?>
            <div class="weown-cta-social-proof">
                <?php weown_cta_social_proof($cta_social_proof); ?>
            </div><!-- .weown-cta-social-proof -->
            <?php endif; ?>

        </div><!-- .weown-cta-content -->

        <?php
        /**
         * CTA Visual Enhancement (Optional)
         *
         * Additional visual elements like icons, illustrations, or
         * graphics that support the conversion message and design.
         */
        ?>
        <?php if (weown_show_cta_visual()) : ?>
        <div class="weown-cta-visual">
            <?php weown_cta_visual(); ?>
        </div><!-- .weown-cta-visual -->
        <?php endif; ?>

    </div><!-- .weown-cta-container -->

</section><!-- .weown-cta-section -->
