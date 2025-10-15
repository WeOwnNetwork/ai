<?php
/**
 * WeOwn Starter Theme - Page Template (page.php)
 *
 * Default template for individual pages with enhanced layout options,
 * dynamic content areas, and flexible component integration.
 *
 * Features:
 * - Flexible page layout with sidebar options
 * - Dynamic content areas for maximum customization
 * - Template part integration for reusable components
 * - Enhanced accessibility and SEO optimization
 * - Gutenberg block editor compatibility
 *
 * @package WeOwn_Starter
 * @version 1.0.0
 * @author WeOwn Development Team
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

get_header();

/**
 * Page Layout Detection and Setup
 *
 * Determine page layout based on theme settings, page meta, or global defaults.
 * Supports full-width, with-sidebar, and centered layout options.
 */
$page_layout = weown_get_page_layout();
$content_class = weown_get_content_class($page_layout);

/**
 * Page Header Section
 *
 * Dynamic page header with title, featured image, and meta information.
 * Supports custom headers and breadcrumb integration.
 */
?>
<header class="weown-page-header">
    <div class="weown-page-header-container">
        <?php
        /**
         * Page Title and Meta
         *
         * Dynamic page title with optional subtitle, meta information,
         * and breadcrumb navigation for better user orientation.
         */
        ?>
        <div class="weown-page-title-area">
            <?php
            /**
             * Page Title with Schema Markup
             *
             * SEO-optimized page title with proper heading hierarchy
             * and structured data markup for search engines.
             */
            ?>
            <h1 class="weown-page-title entry-title"<?php echo weown_get_title_schema(); ?>>
                <?php echo weown_get_page_title(); ?>
            </h1>

            <?php
            /**
             * Page Subtitle (Optional)
             *
             * Secondary page title or tagline for additional context.
             * Can be set via page meta or theme customizer.
             */
            if (weown_show_page_subtitle()) :
            ?>
            <p class="weown-page-subtitle">
                <?php echo esc_html(weown_get_page_subtitle()); ?>
            </p>
            <?php endif; ?>

            <?php
            /**
             * Page Meta Information
             *
             * Author, date, categories, and other meta information.
             * Conditionally displayed based on theme settings.
             */
            ?>
            <div class="weown-page-meta">
                <?php weown_page_meta(); ?>
            </div><!-- .weown-page-meta -->
        </div><!-- .weown-page-title-area -->

        <?php
        /**
         * Featured Image Integration
         *
         * High-quality featured image display with responsive design,
         * lazy loading, and accessibility attributes.
         */
        if (weown_show_featured_image()) {
            weown_featured_image();
        }
        ?>
    </div><!-- .weown-page-header-container -->
</header><!-- .weown-page-header -->

<?php
/**
 * Main Content Area with Layout Support
 *
 * Flexible content layout supporting multiple sidebar configurations
 * and responsive design patterns for optimal user experience.
 */
?>
<div class="weown-page-container">
    <div class="weown-content-area <?php echo esc_attr($content_class); ?>">

        <?php
        /**
         * Page Content Loop
         *
         * Standard WordPress page content with enhanced formatting,
         * Gutenberg block support, and accessibility features.
         */
        while (have_posts()) :
            the_post();
        ?>

        <article id="post-<?php the_ID(); ?>" <?php post_class('weown-page-content'); ?>>

            <?php
            /**
             * Page Content Entry Header
             *
             * Page-specific header elements for individual page context.
             * Supports custom headers and page-specific styling.
             */
            ?>
            <header class="entry-header">
                <?php
                /**
                 * Page Thumbnail (Alternative Featured Image)
                 *
                 * Secondary featured image for page content with
                 * responsive design and accessibility support.
                 */
                if (has_post_thumbnail() && weown_show_page_thumbnail()) {
                    weown_page_thumbnail();
                }
                ?>
            </header><!-- .entry-header -->

            <?php
            /**
             * Main Page Content
             *
             * Primary page content area with Gutenberg block editor support,
             * shortcode compatibility, and enhanced formatting options.
             */
            ?>
            <div class="entry-content">
                <?php
                /**
                 * WordPress Page Content
                 *
                 * Standard the_content() with enhanced formatting and
                 * Gutenberg block editor compatibility.
                 */
                the_content();

                /**
                 * Page Pagination (Multi-page Content)
                 *
                 * Automatic pagination for pages with <!--nextpage--> tags.
                 * Supports both numeric and text-based pagination.
                 */
                wp_link_pages([
                    'before' => '<div class="page-links">' . esc_html__('Pages:', 'weown-starter'),
                    'after'  => '</div>',
                ]);
                ?>
            </div><!-- .entry-content -->

            <?php
            /**
             * Page Footer Meta
             *
             * Additional page meta information, tags, categories,
             * and related content suggestions.
             */
            ?>
            <footer class="entry-footer">
                <?php weown_entry_footer(); ?>
            </footer><!-- .entry-footer -->

        </article><!-- #post-<?php the_ID(); ?> -->

        <?php
        endwhile; // End of the loop.

        /**
         * Page Comments Integration (Optional)
         *
         * Comment system integration with enhanced UX and
         * accessibility features. Can be enabled per page.
         */
        if (weown_show_page_comments()) {
            // If comments are open or we have at least one comment, load up the comment template.
            if (comments_open() || get_comments_number()) :
                comments_template();
            endif;
        }
        ?>

    </div><!-- .weown-content-area -->

    <?php
    /**
     * Sidebar Integration
     *
     * Conditionally load sidebar based on page layout settings.
     * Supports multiple sidebar positions and responsive behavior.
     */
    get_sidebar();
    ?>

</div><!-- .weown-page-container -->

<?php
/**
 * Page Footer Call-to-Action (Optional)
 *
 * Optional call-to-action section after main content.
 * Can be configured per page or globally via theme settings.
 */
if (weown_show_page_cta()) {
    get_template_part('template-parts/call-to-action');
}
?>

<?php get_footer(); ?>
