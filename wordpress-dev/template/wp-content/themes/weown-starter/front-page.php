<?php
/**
 * WeOwn Starter Theme - Front Page Template (front-page.php)
 *
 * Homepage template with hero sections, featured content, and
 * conversion-optimized layout for maximum business impact.
 *
 * Features:
 * - Hero section with call-to-action integration
 * - Featured content sections for key messaging
 * - Service highlights and value propositions
 * - Social proof and testimonials integration
 * - Newsletter signup and lead generation
 * - Performance-optimized loading strategy
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
 * Homepage Layout Configuration
 *
 * Determine homepage layout based on theme settings and content strategy.
 * Supports multiple layout variations for different business needs.
 */
$homepage_layout = weown_get_homepage_layout();
$is_static_front = is_front_page() && !is_home();

/**
 * Homepage Header Integration
 *
 * Enhanced header for homepage with hero section integration and
 * conversion-optimized navigation elements.
 */
get_header('homepage');

/**
 * Homepage Hero Section
 *
 * Primary hero section with headline, value proposition, and
 * primary call-to-action for maximum conversion impact.
 */
?>
<section class="weown-homepage-hero">
    <div class="weown-homepage-hero-container">
        <?php get_template_part('template-parts/hero-section'); ?>
    </div><!-- .weown-homepage-hero-container -->
</section><!-- .weown-homepage-hero -->

<?php
/**
 * Homepage Content Sections
 *
 * Main content areas with flexible section-based layout for
 * maximum customization and conversion optimization.
 */
?>

<?php if ($is_static_front) : ?>
    <?php
    /**
     * Static Front Page Content
     *
     * WordPress static front page content with enhanced layout
     * and Gutenberg block editor support for rich content.
     */
    ?>
    <div class="weown-homepage-content">
        <div class="weown-homepage-content-container">

            <?php
            /**
             * Featured Content Section
             *
             * Primary content area for homepage messaging, value propositions,
             * and key business information with visual hierarchy.
             */
            ?>
            <section class="weown-featured-content">
                <?php
                /**
                 * WordPress Front Page Content Loop
                 *
                 * Standard WordPress content loop for static front page
                 * with enhanced formatting and block editor support.
                 */
                while (have_posts()) :
                    the_post();
                ?>
                <article id="post-<?php the_ID(); ?>" <?php post_class('weown-homepage-article'); ?>>

                    <div class="entry-content">
                        <?php
                        /**
                         * Homepage Content with Block Editor Support
                         *
                         * Rich content editing with Gutenberg blocks for
                         * maximum flexibility and visual appeal.
                         */
                        the_content();

                        /**
                         * Page Break Support
                         *
                         * Automatic section breaks for long homepage content
                         * with enhanced navigation and user experience.
                         */
                        wp_link_pages([
                            'before' => '<div class="page-links">' . esc_html__('Sections:', 'weown-starter'),
                            'after'  => '</div>',
                        ]);
                        ?>
                    </div><!-- .entry-content -->

                </article><!-- #post-<?php the_ID(); ?> -->
                <?php endwhile; ?>
            </section><!-- .weown-featured-content -->

        </div><!-- .weown-homepage-content-container -->
    </div><!-- .weown-homepage-content -->

<?php else : ?>
    <?php
    /**
     * Blog Homepage Layout
     *
     * Alternative layout for sites using blog posts as homepage.
     * Features latest posts, categories, and blog-specific elements.
     */
    ?>
    <div class="weown-homepage-blog">
        <div class="weown-homepage-blog-container">

            <?php
            /**
             * Blog Homepage Header
             *
             * Featured content area for blog-focused homepages with
             * latest posts, featured articles, and category highlights.
             */
            ?>
            <header class="weown-homepage-blog-header">
                <h2 class="weown-homepage-blog-title">
                    <?php echo esc_html(weown_get_homepage_blog_title()); ?>
                </h2>
                <?php if (weown_show_homepage_blog_description()) : ?>
                <p class="weown-homepage-blog-description">
                    <?php echo esc_html(weown_get_homepage_blog_description()); ?>
                </p>
                <?php endif; ?>
            </header><!-- .weown-homepage-blog-header -->

            <?php
            /**
             * Latest Posts Section
             *
             * Featured blog posts with excerpt, meta information, and
             * read more links for optimal content discovery.
             */
            ?>
            <section class="weown-homepage-posts">
                <?php get_template_part('template-parts/homepage-posts'); ?>
            </section><!-- .weown-homepage-posts -->

        </div><!-- .weown-homepage-blog-container -->
    </div><!-- .weown-homepage-blog -->

<?php endif; ?>

<?php
/**
 * Homepage Call-to-Action Sections
 *
 * Strategic CTAs placed throughout the homepage for maximum
 * conversion opportunities and lead generation.
 */
?>

<?php
/**
 * Primary Call-to-Action Section
 *
 * Main conversion-focused CTA section with multiple action options
 * and benefit-focused messaging for optimal user engagement.
 */
?>
<section class="weown-homepage-cta-primary">
    <div class="weown-homepage-cta-container">
        <?php get_template_part('template-parts/call-to-action'); ?>
    </div><!-- .weown-homepage-cta-container -->
</section><!-- .weown-homepage-cta-primary -->

<?php
/**
 * Service Highlights Section (Optional)
 *
 * Featured services or key offerings with visual elements and
 * benefit-focused descriptions for service-based businesses.
 */
if (weown_show_service_highlights()) {
    get_template_part('template-parts/service-highlights');
}
?>

<?php
/**
 * Social Proof Section (Optional)
 *
 * Testimonials, client logos, case studies, and trust indicators
 * for building credibility and encouraging conversions.
 */
if (weown_show_social_proof()) {
    get_template_part('template-parts/social-proof');
}
?>

<?php
/**
 * Newsletter Signup Section (Optional)
 *
 * Email capture form with lead magnet and privacy assurance
 * for building email lists and nurturing prospects.
 */
if (weown_show_newsletter_signup()) {
    get_template_part('template-parts/newsletter-signup');
}
?>

<?php
/**
 * Footer Integration
 *
 * Homepage-optimized footer with reduced content for focus on
 * primary conversion goals and clean visual hierarchy.
 */
get_footer('homepage');
?>
