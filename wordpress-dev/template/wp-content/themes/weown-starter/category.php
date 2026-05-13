<?php
/**
 * WeOwn Starter Theme - Category Archive Template
 *
 * Template for displaying category-specific post archives with enhanced
 * filtering, related content, and category-specific features.
 *
 * Features:
 * - Category hero with description and statistics
 * - Category-specific filtering and sorting
 * - Post listings optimized for category content
 * - Related categories and subcategories
 * - Category-specific newsletter signup
 * - SEO-optimized category pages with structured data
 * - Social sharing and engagement features
 * - Category-specific content recommendations
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
 * Category Archive Configuration
 *
 * Get category-specific configuration for optimal presentation and
 * engagement based on category type and content strategy.
 */
$category_config = weown_get_category_config();
$category_type = $category_config['type'] ?? 'content_category';
$content_focus = $category_config['focus'] ?? 'educational_content';
$engagement_level = $category_config['engagement'] ?? 'high_interaction';

/**
 * Dynamic Category Branding
 *
 * Load category-specific branding with topic-appropriate color schemes and
 * content-focused design elements for optimal user experience.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Category Pages
 *
 * Category-optimized header with topic navigation, breadcrumbs, and
 * related category links for improved user experience.
 */
get_header('category');
?>

<?php
/**
 * Category Hero Section - Topic & Context
 *
 * Category-focused hero with description, post count, and
 * topic relevance for clear content understanding.
 */
?>
<section class="weown-category-hero">
    <div class="weown-category-hero-container">

        <?php
        /**
         * Category Context and Metadata
         *
         * Category name, description, post count, and topic
         * relevance for clear content understanding.
         */
        ?>
        <div class="weown-category-context">
            <?php weown_category_page_header(); ?>
        </div>

        <?php
        /**
         * Category Description and Purpose
         *
         * Category purpose, content focus, and reader benefits
         * for improved user experience and engagement.
         */
        ?>
        <div class="weown-category-description">
            <?php weown_category_description_content(); ?>
        </div>

        <?php
        /**
         * Category Statistics and Activity
         *
         * Post count, update frequency, popular posts, and
         * reader engagement metrics for credibility.
         */
        ?>
        <div class="weown-category-stats">
            <?php weown_category_statistics(); ?>
        </div>

        <?php
        /**
         * Category Navigation and Related Topics
         *
         * Parent/child category navigation, related topics, and
         * content discovery features for exploration.
         */
        ?>
        <div class="weown-category-navigation">
            <?php weown_category_navigation_links(); ?>
        </div>

    </div><!-- .weown-category-hero-container -->
</section><!-- .weown-category-hero -->

<?php
/**
 * Category Content Section
 *
 * Main content area with category-optimized post listings, excerpts,
 * and engagement features for comprehensive topic exploration.
 */
?>
<section class="weown-category-content">
    <div class="weown-category-content-container">

        <?php if (have_posts()) : ?>

            <?php
            /**
             * Category-Specific Layout Options
             *
             * Layout preferences, sorting options, and display
             * settings optimized for the category type.
             */
            ?>
            <div class="weown-category-controls">
                <?php weown_category_layout_controls($category_type); ?>
            </div>

            <?php
            /**
             * Category Posts Listing
             *
             * Post cards with featured images, titles, excerpts,
             * metadata, and category-specific elements.
             */
            ?>
            <div class="weown-category-posts">
                <?php while (have_posts()) : the_post(); ?>
                    <article class="weown-category-post-card">
                        <?php weown_category_post_card(); ?>
                    </article>
                <?php endwhile; ?>
            </div>

            <?php
            /**
             * Category Pagination
             *
             * Pagination optimized for category browsing with
             * related content and discovery features.
             */
            ?>
            <div class="weown-category-pagination">
                <?php weown_category_pagination_system(); ?>
            </div>

        <?php else : ?>

            <?php
            /**
             * No Category Content Found
             *
             * Helpful message, search suggestions, and alternative
             * content recommendations for the category.
             */
            ?>
            <div class="weown-category-no-content">
                <?php weown_category_no_content_found(); ?>
            </div>

        <?php endif; ?>

    </div><!-- .weown-category-content-container -->
</section><!-- .weown-category-content -->

<?php
/**
 * Category Sidebar Section
 *
 * Category-specific content, popular posts, related categories,
 * and engagement features for enhanced discovery.
 */
?>
<?php if (get_theme_mod('category_show_sidebar')) : ?>
<aside class="weown-category-sidebar">
    <div class="weown-category-sidebar-container">

        <?php
        /**
         * Category Sidebar Content
         *
         * Popular posts in category, related categories, newsletter
         * signup, and topic-specific content.
         */
        ?>
        <div class="weown-category-sidebar-widgets">
            <?php weown_category_sidebar_content(); ?>
        </div>

    </div><!-- .weown-category-sidebar-container -->
</aside><!-- .weown-category-sidebar -->
<?php endif; ?>

<?php
/**
 * Related Categories Section
 *
 * Related categories, subcategories, and topic clusters for
 * extended content discovery and user engagement.
 */
?>
<?php if (get_theme_mod('category_show_related')) : ?>
<section class="weown-category-related">
    <div class="weown-category-related-container">

        <?php
        /**
         * Related Categories and Topics
         *
         * Related categories, topic clusters, and content
         * recommendations for extended exploration.
         */
        ?>
        <div class="weown-category-related-content">
            <?php weown_category_related_content(); ?>
        </div>

    </div><!-- .weown-category-related-container -->
</section><!-- .weown-category-related -->
<?php endif; ?>

<?php
/**
 * Category Newsletter Signup Section
 *
 * Category-specific newsletter signup with topic preferences
 * and personalization options for targeted list building.
 */
?>
<?php if (get_theme_mod('category_show_newsletter')) : ?>
<section class="weown-category-newsletter">
    <div class="weown-category-newsletter-container">

        <?php
        /**
         * Category Newsletter and Updates
         *
         * Category-specific newsletter signup with content preferences
         * and personalization for targeted engagement.
         */
        ?>
        <div class="weown-category-newsletter-signup">
            <?php weown_category_newsletter_signup(); ?>
        </div>

    </div><!-- .weown-category-newsletter-container -->
</section><!-- .weown-category-newsletter -->
<?php endif; ?>

<?php
/**
 * Enhanced Footer for Category Pages
 *
 * Category-focused footer with related topics, category navigation,
 * and additional reading recommendations for engagement.
 */
get_footer('category');
?>
