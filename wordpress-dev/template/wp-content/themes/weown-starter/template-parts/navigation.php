<?php
/**
 * WeOwn Starter Theme - Navigation Template Part (template-parts/navigation.php)
 *
 * Main site navigation component with responsive design, accessibility features,
 * and dynamic branding integration for seamless user experience.
 *
 * Features:
 * - Responsive mobile navigation with hamburger menu
 * - Accessibility-compliant structure with ARIA attributes
 * - Dynamic menu highlighting for current page
 * - Search integration and social media links
 * - Performance-optimized loading and animations
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
 * Navigation Container with Brand Integration
 *
 * Main navigation structure with logo integration and responsive layout.
 * Supports multiple navigation levels and custom menu configurations.
 */
?>
<div class="weown-navigation-wrapper">
    <?php
    /**
     * Primary Navigation Menu
     *
     * Main site navigation with WordPress menu system integration.
     * Supports custom menus, social links, and search functionality.
     */
    ?>
    <nav class="weown-primary-navigation" role="navigation" aria-label="<?php esc_attr_e('Primary Navigation', 'weown-starter'); ?>">

        <?php
        /**
         * Mobile Menu Toggle Button
         *
         * Responsive hamburger menu button for mobile navigation.
         * Includes accessibility attributes and smooth animations.
         */
        ?>
        <button class="weown-mobile-menu-toggle" aria-controls="primary-menu" aria-expanded="false" aria-label="<?php esc_attr_e('Toggle mobile menu', 'weown-starter'); ?>">
            <span class="weown-hamburger-line"></span>
            <span class="weown-hamburger-line"></span>
            <span class="weown-hamburger-line"></span>
            <span class="screen-reader-text"><?php esc_html_e('Menu', 'weown-starter'); ?></span>
        </button>

        <?php
        /**
         * WordPress Primary Menu Integration
         *
         * Load the primary navigation menu with fallback support and
         * enhanced accessibility features for optimal user experience.
         */
        wp_nav_menu([
            'theme_location' => 'primary',
            'menu_id'        => 'primary-menu',
            'menu_class'     => 'weown-primary-menu',
            'container'      => 'ul',
            'container_class' => 'weown-menu-container',
            'container_id'   => '',
            'depth'          => 3,
            'fallback_cb'    => 'weown_navigation_fallback',
            'walker'         => new WeOwn_Navigation_Walker(),
        ]);
        ?>

    </nav><!-- .weown-primary-navigation -->

    <?php
    /**
     * Navigation Utility Area
     *
     * Search functionality, social media links, and user account access.
     * Conditionally displayed based on theme settings and available features.
     */
    ?>
    <div class="weown-navigation-utilities">

        <?php
        /**
         * Search Toggle (Optional)
         *
         * Search functionality toggle with modal overlay for
         * improved mobile experience and visual consistency.
         */
        if (weown_show_header_search()) :
        ?>
        <button class="weown-search-toggle" aria-controls="search-modal" aria-expanded="false" aria-label="<?php esc_attr_e('Open search', 'weown-starter'); ?>">
            <svg class="weown-search-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="11" cy="11" r="8"></circle>
                <path d="m21 21-4.35-4.35"></path>
            </svg>
            <span class="screen-reader-text"><?php esc_html_e('Search', 'weown-starter'); ?></span>
        </button>
        <?php endif; ?>

        <?php
        /**
         * Social Media Links (Optional)
         *
         * Social media navigation with brand-appropriate icons and
         * accessibility-compliant link structure.
         */
        if (weown_show_social_nav()) {
            weown_social_navigation();
        }
        ?>

        <?php
        /**
         * User Account Links (Optional)
         *
         * Login/logout functionality and user account management
         * with responsive design and accessibility features.
         */
        if (weown_show_user_nav()) {
            weown_user_navigation();
        }
        ?>

    </div><!-- .weown-navigation-utilities -->

</div><!-- .weown-navigation-wrapper -->

<?php
/**
 * Mobile Navigation Overlay (JavaScript Enhanced)
 *
 * Full-screen mobile navigation overlay with smooth animations,
 * focus management, and accessibility-compliant keyboard navigation.
 */
?>
<div class="weown-mobile-nav-overlay" id="mobile-nav-overlay" aria-hidden="true">
    <div class="weown-mobile-nav-content">

        <?php
        /**
         * Mobile Menu Close Button
         *
         * Accessible close button for mobile navigation overlay
         * with proper focus management and keyboard support.
         */
        ?>
        <button class="weown-mobile-nav-close" aria-controls="mobile-nav-overlay" aria-label="<?php esc_attr_e('Close mobile menu', 'weown-starter'); ?>">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <line x1="18" y1="6" x2="6" y2="18"></line>
                <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
            <span class="screen-reader-text"><?php esc_html_e('Close', 'weown-starter'); ?></span>
        </button>

        <?php
        /**
         * Mobile Navigation Menu
         *
         * Touch-optimized mobile navigation with proper spacing,
         * readable typography, and smooth scroll behavior.
         */
        ?>
        <nav class="weown-mobile-navigation" role="navigation" aria-label="<?php esc_attr_e('Mobile Navigation', 'weown-starter'); ?>">
            <?php
            wp_nav_menu([
                'theme_location' => 'primary',
                'menu_id'        => 'mobile-primary-menu',
                'menu_class'     => 'weown-mobile-primary-menu',
                'container'      => 'ul',
                'container_class' => 'weown-mobile-menu-container',
                'depth'          => 3,
                'fallback_cb'    => 'weown_navigation_fallback',
                'walker'         => new WeOwn_Mobile_Navigation_Walker(),
            ]);
            ?>
        </nav><!-- .weown-mobile-navigation -->

        <?php
        /**
         * Mobile Utility Links
         *
         * Search, social media, and account links optimized for
         * mobile interaction and thumb-friendly design.
         */
        ?>
        <div class="weown-mobile-utilities">
            <?php
            if (weown_show_header_search()) {
                get_search_form();
            }

            if (weown_show_social_nav()) {
                weown_social_navigation();
            }

            if (weown_show_user_nav()) {
                weown_user_navigation();
            }
            ?>
        </div><!-- .weown-mobile-utilities -->

    </div><!-- .weown-mobile-nav-content -->
</div><!-- .weown-mobile-nav-overlay -->
