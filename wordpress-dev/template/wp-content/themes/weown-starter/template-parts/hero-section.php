<?php
/**
 * WeOwn Starter Theme - Hero Section Template Part (template-parts/hero-section.php)
 *
 * Hero section component with dynamic content, call-to-action integration,
 * and advanced customization options for maximum conversion impact.
 *
 * Features:
 * - Dynamic headline and content from page/post meta
 * - Multiple CTA button configurations
 * - Background image/video support with responsive design
 * - Social proof elements and trust indicators
 * - Performance-optimized loading with lazy loading
 * - Accessibility-compliant structure with ARIA attributes
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
 * Hero Section Configuration
 *
 * Get hero section settings from theme customizer, page meta, or global defaults.
 * Supports multiple hero layouts and customization levels.
 */
$hero_config = weown_get_hero_config();
$hero_layout = $hero_config['layout'] ?? 'centered';
$hero_style = $hero_config['style'] ?? 'solid';

/**
 * Hero Content Variables
 *
 * Extract hero content from current post/page or theme settings.
 * Supports dynamic content injection and customization.
 */
$hero_title = weown_get_hero_title();
$hero_subtitle = weown_get_hero_subtitle();
$hero_description = weown_get_hero_description();
$hero_ctas = weown_get_hero_ctas();
$hero_background = weown_get_hero_background();

/**
 * Hero Section Structure with Layout Variations
 *
 * Support multiple hero layouts for different use cases and design requirements.
 * Each layout optimized for specific conversion goals and user experience.
 */
?>
<section class="weown-hero-section weown-hero-layout-<?php echo esc_attr($hero_layout); ?> weown-hero-style-<?php echo esc_attr($hero_style); ?>"
         <?php echo weown_get_hero_attributes(); ?>>

    <?php
    /**
     * Hero Background Elements
     *
     * Background images, videos, gradients, and overlay elements for
     * visual impact and brand-consistent design.
     */
    ?>
    <div class="weown-hero-background">
        <?php weown_hero_background($hero_background); ?>
        <div class="weown-hero-overlay"></div>
    </div><!-- .weown-hero-background -->

    <?php
    /**
     * Hero Content Container
     *
     * Main content area with responsive design and accessibility features.
     * Supports multiple content layouts and positioning options.
     */
    ?>
    <div class="weown-hero-container">

        <div class="weown-hero-content">

            <?php
            /**
             * Hero Text Content
             *
             * Main headline, subtitle, and description with proper typography
             * hierarchy and responsive text sizing for optimal readability.
             */
            ?>
            <div class="weown-hero-text">

                <?php if ($hero_title) : ?>
                <h1 class="weown-hero-title"<?php echo weown_get_hero_title_attributes(); ?>>
                    <?php echo wp_kses_post($hero_title); ?>
                </h1>
                <?php endif; ?>

                <?php if ($hero_subtitle) : ?>
                <h2 class="weown-hero-subtitle">
                    <?php echo wp_kses_post($hero_subtitle); ?>
                </h2>
                <?php endif; ?>

                <?php if ($hero_description) : ?>
                <div class="weown-hero-description">
                    <p><?php echo wp_kses_post($hero_description); ?></p>
                </div>
                <?php endif; ?>

            </div><!-- .weown-hero-text -->

            <?php
            /**
             * Hero Call-to-Action Buttons
             *
             * Primary and secondary CTA buttons with conversion optimization,
             * accessibility features, and responsive design.
             */
            ?>
            <?php if (!empty($hero_ctas)) : ?>
            <div class="weown-hero-ctas">
                <?php foreach ($hero_ctas as $index => $cta) : ?>
                <a href="<?php echo esc_url($cta['url']); ?>"
                   class="weown-hero-cta weown-hero-cta-<?php echo esc_attr($cta['type'] ?? 'primary'); ?>"
                   <?php echo weown_get_cta_attributes($cta); ?>>
                    <?php echo esc_html($cta['text']); ?>
                </a>
                <?php endforeach; ?>
            </div><!-- .weown-hero-ctas -->
            <?php endif; ?>

            <?php
            /**
             * Social Proof Elements (Optional)
             *
             * Trust indicators, testimonials, client logos, and credibility
             * elements to increase conversion rates and user confidence.
             */
            ?>
            <?php if (weown_show_hero_social_proof()) : ?>
            <div class="weown-hero-social-proof">
                <?php weown_hero_social_proof(); ?>
            </div><!-- .weown-hero-social-proof -->
            <?php endif; ?>

        </div><!-- .weown-hero-content -->

    </div><!-- .weown-hero-container -->

    <?php
    /**
     * Hero Scroll Indicator (Optional)
     *
     * Subtle scroll indicator for long hero sections to guide users
     * to additional content below the fold.
     */
    ?>
    <?php if (weown_show_hero_scroll_indicator()) : ?>
    <div class="weown-hero-scroll-indicator">
        <button class="weown-scroll-to-content" aria-label="<?php esc_attr_e('Scroll to main content', 'weown-starter'); ?>">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <polyline points="6,9 12,15 18,9"></polyline>
            </svg>
        </button>
    </div><!-- .weown-hero-scroll-indicator -->
    <?php endif; ?>

</section><!-- .weown-hero-section -->
