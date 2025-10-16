<?php
/**
 * WeOwn Starter Theme - Search Results Template
 *
 * Template for displaying search results with enhanced search functionality,
 * filtering options, and content discovery features.
 *
 * Features:
 * - Search hero with query context and suggestions
 * - Advanced search filtering and sorting
 * - Search results with relevance indicators
 * - Related searches and content recommendations
 * - No results page with helpful suggestions
 * - SEO-optimized search pages with structured data
 * - Search analytics and user behavior tracking
 * - Content discovery and related topics
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
 * Search Page Configuration
 *
 * Get search-specific configuration for optimal presentation and
 * user experience based on search type and user behavior.
 */
$search_config = weown_get_search_config();
$search_type = $search_config['type'] ?? 'content_search';
$result_display = $search_config['display'] ?? 'detailed_results';
$user_experience = $search_config['experience'] ?? 'enhanced_discovery';

/**
 * Dynamic Search Branding
 *
 * Load search-specific branding with user-friendly color schemes and
 * discovery-focused design elements for optimal search experience.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Search Pages
 *
 * Search-optimized header with search context, recent searches, and
 * navigation aids for improved user experience.
 */
get_header('search');
?>

<?php
/**
 * Search Hero Section - Query & Context
 *
 * Search-focused hero with query display, result count, and
 * search refinement options for clear understanding.
 */
?>
<section class="weown-search-hero">
    <div class="weown-search-hero-container">

        <?php
        /**
         * Search Query and Context
         *
         * Search query display, result count, and search type
         * for clear understanding and navigation.
         */
        ?>
        <div class="weown-search-query">
            <?php weown_search_page_header(); ?>
        </div>

        <?php
        /**
         * Search Suggestions and Alternatives
         *
         * Search suggestions, related queries, and alternative
         * search terms for improved search success.
         */
        ?>
        <div class="weown-search-suggestions">
            <?php weown_search_suggestion_system(); ?>
        </div>

        <?php
        /**
         * Search Statistics and Relevance
         *
         * Result count, relevance indicators, and search
         * performance metrics for user guidance.
         */
        ?>
        <div class="weown-search-stats">
            <?php weown_search_statistics(); ?>
        </div>

    </div><!-- .weown-search-hero-container -->
</section><!-- .weown-search-hero -->

<?php
/**
 * Search Filters Section
 *
 * Advanced filtering options for content type, date, relevance,
 * and other search parameters for personalized results.
 */
?>
<section class="weown-search-filters">
    <div class="weown-search-filters-container">

        <?php
        /**
         * Search Filtering and Sorting
         *
         * Content type filters, date ranges, relevance sorting, and
         * display options for personalized search results.
         */
        ?>
        <div class="weown-search-filter-options">
            <?php weown_search_filtering_system(); ?>
        </div>

    </div><!-- .weown-search-filters-container -->
</section><!-- .weown-search-filters -->

<?php
/**
 * Search Results Section
 *
 * Main search results area with result cards, excerpts, metadata,
 * and relevance indicators for comprehensive search experience.
 */
?>
<section class="weown-search-results">
    <div class="weown-search-results-container">

        <?php if (have_posts()) : ?>

            <?php
            /**
             * Search Results Display Options
             *
             * Result layout preferences, sorting options, and display
             * settings for personalized search experience.
             */
            ?>
            <div class="weown-search-controls">
                <?php weown_search_layout_controls($result_display); ?>
            </div>

            <?php
            /**
             * Search Results Listing
             *
             * Result cards with titles, excerpts, metadata, relevance
             * indicators, and content type information.
             */
            ?>
            <div class="weown-search-results-list">
                <?php while (have_posts()) : the_post(); ?>
                    <article class="weown-search-result-card">
                        <?php weown_search_result_card(); ?>
                    </article>
                <?php endwhile; ?>
            </div>

            <?php
            /**
             * Search Pagination
             *
             * Pagination optimized for search browsing with
             * related searches and discovery features.
             */
            ?>
            <div class="weown-search-pagination">
                <?php weown_search_pagination_system(); ?>
            </div>

        <?php else : ?>

            <?php
            /**
             * No Search Results Found
             *
             * Helpful message, search suggestions, related content,
             * and alternative search strategies.
             */
            ?>
            <div class="weown-search-no-results">
                <?php weown_search_no_results_found(); ?>
            </div>

        <?php endif; ?>

    </div><!-- .weown-search-results-container -->
</section><!-- .weown-search-results -->

<?php
/**
 * Search Sidebar Section
 *
 * Search-related content, popular searches, related topics, and
 * additional discovery features for enhanced search experience.
 */
?>
<?php if (get_theme_mod('search_show_sidebar')) : ?>
<aside class="weown-search-sidebar">
    <div class="weown-search-sidebar-container">

        <?php
        /**
         * Search Sidebar Content
         *
         * Popular searches, related topics, search tips, and
         * content discovery features.
         */
        ?>
        <div class="weown-search-sidebar-widgets">
            <?php weown_search_sidebar_content(); ?>
        </div>

    </div><!-- .weown-search-sidebar-container -->
</aside><!-- .weown-search-sidebar -->
<?php endif; ?>

<?php
/**
 * Related Searches Section
 *
 * Related search terms, popular queries, and content topics for
 * extended search discovery and user engagement.
 */
?>
<?php if (get_theme_mod('search_show_related')) : ?>
<section class="weown-search-related">
    <div class="weown-search-related-container">

        <?php
        /**
         * Related Searches and Topics
         *
         * Related search terms, popular queries, and content
         * topics for extended search exploration.
         */
        ?>
        <div class="weown-search-related-content">
            <?php weown_search_related_content(); ?>
        </div>

    </div><!-- .weown-search-related-container -->
</section><!-- .weown-search-related -->
<?php endif; ?>

<?php
/**
 * Search Newsletter Signup Section
 *
 * Search-specific content updates and personalization options
 * for ongoing engagement and content discovery.
 */
?>
<?php if (get_theme_mod('search_show_newsletter')) : ?>
<section class="weown-search-newsletter">
    <div class="weown-search-newsletter-container">

        <?php
        /**
         * Search Newsletter and Updates
         *
         * Search-specific newsletter signup with personalization
         * and content discovery preferences.
         */
        ?>
        <div class="weown-search-newsletter-signup">
            <?php weown_search_newsletter_signup(); ?>
        </div>

    </div><!-- .weown-search-newsletter-container -->
</section><!-- .weown-search-newsletter -->
<?php endif; ?>

<?php
/**
 * Enhanced Footer for Search Pages
 *
 * Search-focused footer with search tips, help resources, and
 * additional discovery recommendations for user support.
 */
get_footer('search');
?>
