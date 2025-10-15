<?php
/**
 * WeOwn Starter Theme - Header Template (header.php)
 *
 * Site header with advanced branding integration, navigation system,
 * and dynamic content injection for maximum customization flexibility.
 *
 * Features:
 * - Dynamic branding system integration
 * - Responsive navigation with accessibility
 * - Schema markup for SEO optimization
 * - Social media integration points
 * - Performance-optimized asset loading
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
 * Dynamic Branding System Integration
 *
 * Load brand configuration and inject dynamic CSS custom properties.
 * This enables real-time brand customization without code changes.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Header Structure with Enhanced Accessibility
 *
 * Implements proper semantic HTML5 structure with ARIA attributes
 * and schema markup for optimal SEO and accessibility.
 */
?>
<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo('charset'); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">

    <?php
    /**
     * Dynamic Meta Tags with Brand Integration
     *
     * Generate meta tags based on site configuration and content context.
     * Supports dynamic title, description, and social media optimization.
     */
    weown_meta_tags($brand_config);
    ?>

    <?php wp_head(); ?>

    <?php
    /**
     * Dynamic CSS Custom Properties Injection
     *
     * Inject brand colors and typography as CSS custom properties for
     * real-time customization and theme consistency.
     */
    weown_inject_brand_css($brand_colors);
    ?>
</head>

<body <?php body_class(weown_get_body_classes()); ?>>
<?php wp_body_open(); ?>

<?php
/**
 * Skip Link for Accessibility
 *
 * Essential accessibility feature that allows keyboard users to skip
 * to main content. Required for WCAG 2.1 AA compliance.
 */
?>
<a class="skip-link screen-reader-text" href="#main">
    <?php esc_html_e('Skip to content', 'weown-starter'); ?>
</a>

<?php
/**
 * Site Header Structure
 *
 * Main header container with logo, navigation, and utility elements.
 * Supports multiple header layouts and responsive behavior.
 */
?>
<header id="masthead" class="weown-header" role="banner"<?php echo weown_get_header_schema(); ?>>
    <div class="weown-header-container">

        <?php
        /**
         * Site Branding Section
         *
         * Logo, site title, and tagline with dynamic branding integration.
         * Supports custom logos, responsive images, and brand customization.
         */
        ?>
        <div class="weown-site-branding">
            <?php weown_site_branding($brand_config); ?>
        </div><!-- .weown-site-branding -->

        <?php
        /**
         * Primary Navigation
         *
         * Main site navigation with responsive design, accessibility features,
         * and dynamic menu integration. Supports WordPress menu system.
         */
        ?>
        <nav id="site-navigation" class="weown-main-navigation" role="navigation" aria-label="<?php esc_attr_e('Main Navigation', 'weown-starter'); ?>">
            <?php
            /**
             * WordPress Navigation Menu Integration
             *
             * Load primary menu with fallback to page structure if no menu exists.
             * Supports custom menu locations and responsive mobile navigation.
             */
            wp_nav_menu([
                'theme_location' => 'primary',
                'menu_id'        => 'primary-menu',
                'menu_class'     => 'weown-primary-menu',
                'container'      => false,
                'depth'          => 3,
                'fallback_cb'    => 'weown_navigation_fallback',
            ]);
            ?>
        </nav><!-- #site-navigation -->

        <?php
        /**
         * Header Utility Area
         *
         * Search, social media links, user account access, and other
         * utility elements. Conditionally displayed based on theme settings.
         */
        ?>
        <div class="weown-header-utilities">
            <?php
            /**
             * Search Integration (Optional)
             *
             * Professional search functionality with AJAX support and
             * accessibility compliance. Can be enabled via theme settings.
             */
            if (weown_show_search()) {
                get_search_form();
            }

            /**
             * Social Media Integration (Optional)
             *
             * Social media links and sharing buttons. Configuration
             * driven by site branding settings.
             */
            weown_social_media_links($brand_config);

            /**
             * User Account Integration (Optional)
             *
             * Login/logout links and user account management.
             * Supports WooCommerce and membership site integration.
             */
            weown_user_account_links();
            ?>
        </div><!-- .weown-header-utilities -->

    </div><!-- .weown-header-container -->
</header><!-- #masthead -->

<?php
/**
 * Mobile Navigation Toggle (JavaScript Enhanced)
 *
 * Responsive mobile navigation with hamburger menu and slide-out
 * functionality. JavaScript-enhanced for smooth animations.
 */
?>
<div class="weown-mobile-nav-toggle">
    <button class="weown-mobile-nav-button" aria-controls="site-navigation" aria-expanded="false">
        <span class="screen-reader-text"><?php esc_html_e('Toggle Navigation', 'weown-starter'); ?></span>
        <span class="weown-hamburger-icon"></span>
    </button>
</div>

<?php
/**
 * Breadcrumb Navigation (Optional)
 *
 * SEO-friendly breadcrumb navigation for better user orientation
 * and search engine optimization. Can be enabled via theme settings.
 */
if (weown_show_breadcrumbs()) {
    weown_breadcrumbs();
}
?>
