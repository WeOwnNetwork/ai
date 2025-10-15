<?php
/**
 * WeOwn Starter Theme - Main Template (index.php)
 *
 * This is the main template file that WordPress uses for the template hierarchy.
 * It serves as the fallback template for all content types and includes proper
 * WordPress template hierarchy logic for maximum flexibility and customization.
 *
 * Template Hierarchy (in order of precedence):
 * 1. Specific templates (single.php, page.php, etc.)
 * 2. index.php (fallback for all content)
 * 3. 404.php (if no content found)
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
 * Main content area with WordPress Loop
 *
 * This section handles the main content display using WordPress's standard Loop.
 * The Loop automatically handles different content types and pagination.
 */
?>
<main id="main" class="weown-main" role="main"<?php echo weown_get_main_schema(); ?>>
    <?php
    /**
     * Template Parts Integration
     *
     * Conditionally load template parts based on page context for maximum flexibility.
     * This enables different layouts for different content types while maintaining
     * consistent branding and functionality.
     */

    // Homepage hero section (only on front page)
    if (is_front_page() && !is_paged()) {
        get_template_part('template-parts/hero-section');
    }

    // Archive/Blog header (for archive pages)
    if (is_archive() || is_search()) {
        get_template_part('template-parts/archive-header');
    }

    /**
     * WordPress Content Loop
     *
     * Standard WordPress Loop with enhanced error handling and content structure.
     * Supports all post types and includes proper semantic HTML markup.
     */
    if (have_posts()) :

        // Content wrapper with schema markup
        echo '<div class="weown-content-wrapper">';

        // Individual post/article loop
        while (have_posts()) :
            the_post();

            /**
             * Dynamic Template Part Loading
             *
             * Load appropriate template parts based on content type and context.
             * This provides maximum flexibility for different content layouts.
             */
            if (is_singular()) {
                // Single post/page template part
                get_template_part('template-parts/content-single');
            } else {
                // Archive/listing template part
                get_template_part('template-parts/content-archive');
            }

        endwhile;

        echo '</div><!-- .weown-content-wrapper -->';

        /**
         * Pagination Integration
         *
         * Enhanced pagination with accessibility features and brand styling.
         * Supports both numeric and "Load More" pagination methods.
         */
        weown_pagination();

    else :
        /**
         * No Content Found Handler
         *
         * Professional "no content" template with search suggestions and
         * helpful navigation options for better user experience.
         */
        get_template_part('template-parts/content-none');

    endif;
    ?>
</main><!-- #main -->

<?php
/**
 * Sidebar Integration
 *
 * Conditionally load sidebar based on theme layout settings and page context.
 * Supports multiple sidebar positions and responsive behavior.
 */
get_sidebar();

/**
 * Footer Integration
 *
 * Load the site footer with all closing elements, scripts, and tracking code.
 * Includes proper closing tags and WordPress footer hooks.
 */
get_footer();
?>
