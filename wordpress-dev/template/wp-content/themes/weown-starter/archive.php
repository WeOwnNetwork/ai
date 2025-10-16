<?php
/**
 * WeOwn Starter Theme - Archive Template
 *
 * Template for displaying post archives including category, tag, date,
 * and author archives with enhanced filtering and content discovery.
 *
 * Features:
 * - Hero section with archive context and metadata
 * - Advanced filtering and sorting options
 * - Post grid/list layout with excerpt and metadata
 * - Pagination and infinite scroll options
 * - Related categories and content recommendations
 * - SEO-optimized archive pages with structured data
 * - Social sharing and engagement features
 * - Newsletter signup and content discovery
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
 * Archive Page Configuration
 *
 * Get archive-specific configuration for optimal presentation and
 * navigation based on archive type and content strategy.
 */
$archive_config = weown_get_archive_config();
$archive_type = $archive_config['type'] ?? 'blog_archive';
$layout_style = $archive_config['layout'] ?? 'grid_layout';
$content_strategy = $archive_config['strategy'] ?? 'content_discovery';

/**
 * Dynamic Archive Branding
 *
 * Load archive-specific branding with navigation-friendly color schemes and
 * content-focused design elements for optimal browsing experience.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Archive Pages
 *
 * Navigation-optimized header with archive context, breadcrumbs, and
 * filtering options for improved user experience.
 */
get_header('archive');
?>

<?php
/**
 * Archive Hero Section - Context & Navigation
 *
 * Informative hero with archive title, description, post count, and
 * filtering options for clear content understanding.
 */
?>
<section class="weown-archive-hero">
    <div class="weown-archive-hero-container">

        <?php
        /**
         * Archive Context and Metadata
         *
         * Archive title, description, post count, and type
         * for clear content understanding and navigation.
         */
        ?>
        <div class="weown-archive-context">
            <?php weown_archive_page_header(); ?>
        </div>

        <?php
        /**
         * Archive Description and Purpose
         *
         * Archive purpose, content focus, and navigation
         * guidance for improved user experience.
         */
        ?>
        <div class="weown-archive-description">
            <?php weown_archive_description_content(); ?>
        </div>

        <?php
        /**
         * Archive Statistics and Metrics
         *
         * Post count, update frequency, popular topics, and
         * content metrics for credibility and engagement.
         */
        ?>
        <div class="weown-archive-stats">
            <?php weown_archive_statistics(); ?>
        </div>

    </div><!-- .weown-archive-hero-container -->
</section><!-- .weown-archive-hero -->

<?php
/**
 * Archive Filtering Section
 *
 * Advanced filtering, sorting, and search options for
 * personalized content discovery and navigation.
 */
?>
<section class="weown-archive-filters">
    <div class="weown-archive-filters-container">

        <?php
        /**
         * Content Filtering and Sorting
         *
         * Category filters, date ranges, author filters, and
         * sorting options for personalized content discovery.
         */
        ?>
        <div class="weown-archive-filter-options">
            <?php weown_archive_filtering_system(); ?>
        </div>

    </div><!-- .weown-archive-filters-container -->
</section><!-- .weown-archive-filters -->

<?php
/**
 * Archive Content Section
 *
 * Main content area with post listings, excerpts, metadata, and
 * engagement features for comprehensive content browsing.
 */
?>
<section class="weown-archive-content">
    <div class="weown-archive-content-container">

        <?php if (have_posts()) : ?>

            <?php
            /**
             * Posts Navigation and Layout Options
             *
             * Grid/list toggle, pagination preferences, and
             * layout options for personalized browsing.
             */
            ?>
            <div class="weown-archive-controls">
                <?php weown_archive_layout_controls($layout_style); ?>
            </div>

            <?php
            /**
             * Posts Listing
             *
             * Post cards with featured images, titles, excerpts,
             * metadata, and engagement elements.
             */
            ?>
            <div class="weown-archive-posts <?php echo esc_attr($layout_style); ?>">
                <?php while (have_posts()) : the_post(); ?>
                    <article class="weown-archive-post-card">
                        <?php weown_archive_post_card(); ?>
                    </article>
                <?php endwhile; ?>
            </div>

            <?php
            /**
             * Pagination and Load More
             *
             * Pagination, infinite scroll, and load more options
             * for seamless content browsing and discovery.
             */
            ?>
            <div class="weown-archive-pagination">
                <?php weown_archive_pagination_system(); ?>
            </div>

        <?php else : ?>

            <?php
            /**
             * No Content Found
             *
             * Helpful message, search suggestions, and alternative
             * content recommendations when no posts are found.
             */
            ?>
            <div class="weown-archive-no-content">
                <?php weown_archive_no_content_found(); ?>
            </div>

        <?php endif; ?>

    </div><!-- .weown-archive-content-container -->
</section><!-- .weown-archive-content -->

<?php
/**
 * Archive Sidebar Section
 *
 * Related content, popular posts, newsletter signup, and
 * additional engagement features for enhanced discovery.
 */
?>
<?php if (get_theme_mod('archive_show_sidebar')) : ?>
<aside class="weown-archive-sidebar">
    <div class="weown-archive-sidebar-container">

        <?php
        /**
         * Archive Sidebar Content
         *
         * Popular posts, related categories, newsletter signup,
         * and content discovery features.
         */
        ?>
        <div class="weown-archive-sidebar-widgets">
            <?php weown_archive_sidebar_content(); ?>
        </div>

    </div><!-- .weown-archive-sidebar-container -->
</aside><!-- .weown-archive-sidebar -->
<?php endif; ?>

<?php
/**
 * Related Archives Section
 *
 * Related categories, tags, and content series for
 * extended content discovery and user engagement.
 */
?>
<?php if (get_theme_mod('archive_show_related')) : ?>
<section class="weown-archive-related">
    <div class="weown-archive-related-container">

        <?php
        /**
         * Related Content and Archives
         *
         * Related categories, popular tags, content series, and
         * discovery recommendations for engagement.
         */
        ?>
        <div class="weown-archive-related-content">
            <?php weown_archive_related_content(); ?>
        </div>

    </div><!-- .weown-archive-related-container -->
</section><!-- .weown-archive-related -->
<?php endif; ?>

<?php
/**
 * Newsletter Signup Section
 *
 * Archive-specific newsletter signup with content preferences
 * and personalization options for list building.
 */
?>
<?php if (get_theme_mod('archive_show_newsletter')) : ?>
<section class="weown-archive-newsletter">
    <div class="weown-archive-newsletter-container">

        <?php
        /**
         * Newsletter and Content Updates
         *
         * Archive-specific newsletter signup with content preferences
         * and personalization for targeted list building.
         */
        ?>
        <div class="weown-archive-newsletter-signup">
            <?php weown_archive_newsletter_signup(); ?>
        </div>

    </div><!-- .weown-archive-newsletter-container -->
</section><!-- .weown-archive-newsletter -->
<?php endif; ?>

<?php
/**
 * Enhanced Footer for Archive Pages
 *
 * Content-focused footer with related topics, category navigation,
 * and additional reading recommendations for engagement.
 */
get_footer('archive');
?>
