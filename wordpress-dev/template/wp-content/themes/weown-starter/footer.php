<?php
/**
 * WeOwn Starter Theme - Footer Template (footer.php)
 *
 * Site footer with widget areas, copyright information, social media links,
 * and performance-optimized script loading for maximum site speed.
 *
 * Features:
 * - Multiple widget areas for flexible content
 * - Dynamic copyright and branding integration
 * - Social media and contact information
 * - Performance-optimized JavaScript loading
 * - Accessibility-compliant structure
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
 * Footer Widget Areas
 *
 * Multiple widget areas for flexible footer content organization.
 * Supports responsive layouts and conditional display based on content.
 */
?>
<footer id="colophon" class="weown-footer" role="contentinfo"<?php echo weown_get_footer_schema(); ?>>
    <div class="weown-footer-container">

        <?php if (is_active_sidebar('footer-1') || is_active_sidebar('footer-2') || is_active_sidebar('footer-3') || is_active_sidebar('footer-4')) : ?>
        <div class="weown-footer-widgets">
            <div class="weown-footer-widgets-container">

                <?php
                /**
                 * Footer Widget Area 1
                 *
                 * Primary footer widget area for main content like company info,
                 * contact details, or featured content.
                 */
                ?>
                <div class="weown-footer-widget-area footer-widget-1">
                    <?php if (is_active_sidebar('footer-1')) : ?>
                        <?php dynamic_sidebar('footer-1'); ?>
                    <?php else : ?>
                        <?php weown_footer_widget_fallback('footer-1'); ?>
                    <?php endif; ?>
                </div>

                <?php
                /**
                 * Footer Widget Area 2
                 *
                 * Secondary footer widget area for additional content,
                 * recent posts, or service highlights.
                 */
                ?>
                <div class="weown-footer-widget-area footer-widget-2">
                    <?php if (is_active_sidebar('footer-2')) : ?>
                        <?php dynamic_sidebar('footer-2'); ?>
                    <?php else : ?>
                        <?php weown_footer_widget_fallback('footer-2'); ?>
                    <?php endif; ?>
                </div>

                <?php
                /**
                 * Footer Widget Area 3
                 *
                 * Tertiary footer widget area for links, categories,
                 * or additional navigation elements.
                 */
                ?>
                <div class="weown-footer-widget-area footer-widget-3">
                    <?php if (is_active_sidebar('footer-3')) : ?>
                        <?php dynamic_sidebar('footer-3'); ?>
                    <?php else : ?>
                        <?php weown_footer_widget_fallback('footer-3'); ?>
                    <?php endif; ?>
                </div>

                <?php
                /**
                 * Footer Widget Area 4
                 *
                 * Quaternary footer widget area for newsletter signup,
                 * social media links, or contact forms.
                 */
                ?>
                <div class="weown-footer-widget-area footer-widget-4">
                    <?php if (is_active_sidebar('footer-4')) : ?>
                        <?php dynamic_sidebar('footer-4'); ?>
                    <?php else : ?>
                        <?php weown_footer_widget_fallback('footer-4'); ?>
                    <?php endif; ?>
                </div>

            </div><!-- .weown-footer-widgets-container -->
        </div><!-- .weown-footer-widgets -->
        <?php endif; ?>

        <?php
        /**
         * Footer Bottom Bar
         *
         * Copyright information, theme credits, and essential footer links.
         * Dynamically generated based on site configuration and branding.
         */
        ?>
        <div class="weown-footer-bottom">
            <div class="weown-footer-bottom-container">

                <?php
                /**
                 * Copyright Information
                 *
                 * Dynamic copyright notice with site name and current year.
                 * Supports custom copyright text and branding integration.
                 */
                ?>
                <div class="weown-footer-copyright">
                    <?php weown_footer_copyright(); ?>
                </div><!-- .weown-footer-copyright -->

                <?php
                /**
                 * Footer Navigation Menu
                 *
                 * Secondary navigation for legal pages, privacy policy,
                 * terms of service, and other essential links.
                 */
                ?>
                <nav class="weown-footer-navigation" role="navigation" aria-label="<?php esc_attr_e('Footer Navigation', 'weown-starter'); ?>">
                    <?php
                    wp_nav_menu([
                        'theme_location' => 'footer',
                        'menu_id'        => 'footer-menu',
                        'menu_class'     => 'weown-footer-menu',
                        'container'      => false,
                        'depth'          => 1,
                        'fallback_cb'    => false,
                    ]);
                    ?>
                </nav><!-- .weown-footer-navigation -->

                <?php
                /**
                 * Social Media Footer Links
                 *
                 * Social media icons and links for brand social media presence.
                 * Configuration driven by site branding settings.
                 */
                ?>
                <div class="weown-footer-social">
                    <?php weown_footer_social_links(); ?>
                </div><!-- .weown-footer-social -->

            </div><!-- .weown-footer-bottom-container -->
        </div><!-- .weown-footer-bottom -->

    </div><!-- .weown-footer-container -->
</footer><!-- #colophon -->

<?php
/**
 * Mobile Navigation Backdrop (JavaScript Enhanced)
 *
 * Semi-transparent backdrop for mobile navigation overlay.
 * Improves UX by providing clear visual indication of navigation state.
 */
?>
<div class="weown-mobile-nav-backdrop"></div>

<?php
/**
 * WordPress Footer Hook
 *
 * Essential WordPress hook for plugin and theme functionality.
 * Loads all enqueued scripts, tracking codes, and closing elements.
 */
wp_footer();
?>

<?php
/**
 * Performance Monitoring and Analytics
 *
 * Optional performance monitoring and analytics integration.
 * Supports Google Analytics, custom tracking, and performance metrics.
 */
weown_performance_tracking();
?>

</body>
</html>
