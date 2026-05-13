<?php
/**
 * WeOwn Starter Theme - Single Post Template
 *
 * Template for displaying individual blog posts with enhanced readability,
 * social sharing, related content, and engagement features.
 *
 * Features:
 * - Hero section with post metadata and featured image
 * - Optimized content layout with typography hierarchy
 * - Author information and bio with social links
 * - Social sharing buttons and engagement metrics
 * - Related posts and content recommendations
 * - Comments section with enhanced UX
 * - Newsletter signup and content upgrades
 * - SEO-optimized meta tags and structured data
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
 * Single Post Configuration
 *
 * Get post-specific configuration for optimal presentation and
 * engagement based on content type and publishing strategy.
 */
$post_config = weown_get_post_config();
$content_type = $post_config['type'] ?? 'blog_post';
$reading_experience = $post_config['experience'] ?? 'enhanced_readability';
$engagement_features = $post_config['engagement'] ?? 'social_sharing';

/**
 * Dynamic Post Branding
 *
 * Load post-specific branding with readable color schemes and
 * content-focused design elements for optimal user experience.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Content Pages
 *
 * Content-optimized header with breadcrumb navigation and
 * reading progress indicators for enhanced user experience.
 */
get_header('single-post');
?>

<?php
/**
 * Post Hero Section - Title & Metadata
 *
 * Engaging hero with post title, metadata, reading time, and
 * featured image for immediate content understanding.
 */
?>
<?php if (have_posts()) : while (have_posts()) : the_post(); ?>
<section class="weown-single-hero">
    <div class="weown-single-hero-container">

        <?php
        /**
         * Post Metadata and Context
         *
         * Category, author, date, reading time, and content type
         * for context and credibility building.
         */
        ?>
        <div class="weown-single-meta">
            <?php weown_single_post_metadata(); ?>
        </div>

        <h1 class="weown-single-title">
            <?php the_title(); ?>
        </h1>

        <?php
        /**
         * Post Excerpt and Introduction
         *
         * Compelling introduction, key takeaways, and
         * content preview for engagement and SEO.
         */
        ?>
        <div class="weown-single-excerpt">
            <?php weown_single_post_excerpt(); ?>
        </div>

        <?php
        /**
         * Author Information and Social Proof
         *
         * Author bio, expertise, social links, and
         * credibility indicators for trust building.
         */
        ?>
        <div class="weown-single-author">
            <?php weown_single_author_info(); ?>
        </div>

    </div><!-- .weown-single-hero-container -->

    <?php
    /**
     * Featured Image or Media
     *
     * High-quality featured image, video, or media element
     * for visual engagement and content enhancement.
     */
    ?>
    <div class="weown-single-featured-media">
        <?php weown_single_featured_media(); ?>
    </div>
</section><!-- .weown-single-hero -->

<?php
/**
 * Post Content Section
 *
 * Main content area with optimized typography, readability features,
 * and engagement elements for enhanced user experience.
 */
?>
<section class="weown-single-content">
    <div class="weown-single-content-container">

        <?php
        /**
         * Reading Progress and Navigation
         *
         * Reading progress bar, table of contents, and
         * content navigation for improved readability.
         */
        ?>
        <div class="weown-single-progress">
            <?php weown_single_reading_progress(); ?>
        </div>

        <?php
        /**
         * Main Post Content
         *
         * The post content with enhanced formatting, code syntax
         * highlighting, and multimedia integration.
         */
        ?>
        <article class="weown-single-article">
            <?php the_content(); ?>
        </article>

        <?php
        /**
         * Content Engagement Elements
         *
         * Social sharing, content upgrades, newsletter signup, and
         * related content recommendations for engagement.
         */
        ?>
        <div class="weown-single-engagement">
            <?php weown_single_engagement_features($engagement_features); ?>
        </div>

    </div><!-- .weown-single-content-container -->
</section><!-- .weown-single-content -->

<?php
/**
 * Related Content Section
 *
 * Related posts, recommended content, and content series
 * for extended engagement and content discovery.
 */
?>
<section class="weown-single-related">
    <div class="weown-single-related-container">

        <?php
        /**
         * Related Posts and Recommendations
         *
         * Algorithm-based related content, series navigation, and
         * content discovery features for user retention.
         */
        ?>
        <div class="weown-single-related-content">
            <?php weown_single_related_content(); ?>
        </div>

    </div><!-- .weown-single-related-container -->
</section><!-- .weown-single-related -->

<?php
/**
 * Comments Section
 *
 * Enhanced comments system with social login, moderation tools,
 * and engagement features for community building.
 */
?>
<?php if (comments_open() || get_comments_number()) : ?>
<section class="weown-single-comments">
    <div class="weown-single-comments-container">

        <?php
        /**
         * Comments and Discussion
         *
         * Comment form, existing comments, and discussion features
         * for community engagement and content interaction.
         */
        ?>
        <div class="weown-single-comments-wrapper">
            <?php comments_template(); ?>
        </div>

    </div><!-- .weown-single-comments-container -->
</section><!-- .weown-single-comments -->
<?php endif; ?>

<?php
/**
 * Newsletter Signup Section
 *
 * Content upgrade and newsletter signup with lead magnets
 * and value propositions for email list building.
 */
?>
<?php if (get_theme_mod('single_show_newsletter')) : ?>
<section class="weown-single-newsletter">
    <div class="weown-single-newsletter-container">

        <?php
        /**
         * Newsletter and Content Upgrades
         *
         * Email signup with content upgrades, lead magnets, and
         * value-driven offers for list building.
         */
        ?>
        <div class="weown-single-newsletter-signup">
            <?php weown_single_newsletter_signup(); ?>
        </div>

    </div><!-- .weown-single-newsletter-container -->
</section><!-- .weown-single-newsletter -->
<?php endif; ?>

<?php endwhile; endif; ?>

<?php
/**
 * Enhanced Footer for Content Pages
 *
 * Content-focused footer with related topics, author information,
 * and additional reading recommendations for engagement.
 */
get_footer('single-post');
?>
