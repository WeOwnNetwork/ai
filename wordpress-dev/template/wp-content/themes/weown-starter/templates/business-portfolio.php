<?php
/**
 * Template Name: Business Portfolio
 * Description: Professional portfolio showcase with project filtering and case studies
 * @package WeOwn_Starter
 *
 * Professional portfolio page template showcasing completed projects,
 * case studies, client work, and expertise demonstrations.
 *
 * Features:
 * - Hero section with portfolio value proposition and key metrics
 * - Project categories and filtering capabilities
 * - Detailed case studies with challenges, solutions, results
 * - Project showcase with before/after and process documentation
 * - Client testimonials and success metrics
 * - Industry expertise and specialization highlights
 * - Call-to-action for project inquiries and consultations
 * - Interactive project gallery with detailed views
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
 * Portfolio Page Configuration
 *
 * Get portfolio-specific configuration for optimal presentation and
 * credibility building based on project types and industries served.
 */
$portfolio_config = weown_get_portfolio_config();
$portfolio_type = $portfolio_config['type'] ?? 'project_portfolio';
$industry_focus = $portfolio_config['industry'] ?? 'technology_industry';
$showcase_style = $portfolio_config['showcase'] ?? 'case_study_focused';

/**
 * Dynamic Portfolio Branding
 *
 * Load portfolio-specific branding with professional color schemes and
 * results-focused design elements for credibility positioning.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Business Pages
 *
 * Professional header with portfolio navigation and project filtering
 * for easy exploration and credibility building.
 */
get_header('business-portfolio');
?>

<?php
/**
 * Portfolio Hero Section - Expertise & Results
 *
 * Results-focused hero with key metrics, success stories, and
 * immediate credibility indicators for professional positioning.
 */
?>
<section class="weown-portfolio-hero">
    <div class="weown-portfolio-hero-container">

        <?php
        /**
         * Portfolio Positioning and Key Metrics
         *
         * Clear expertise positioning, success metrics, and
         * project outcomes for immediate credibility building.
         */
        ?>
        <div class="weown-portfolio-hero-content">
            <div class="weown-portfolio-expertise-badge">
                <span class="portfolio-expertise-badge">
                    <?php echo esc_html(ucfirst(str_replace('_', ' ', $industry_focus))); ?> Experts
                </span>
            </div>

            <h1 class="weown-portfolio-hero-title">
                <?php echo esc_html(get_theme_mod('portfolio_hero_title', 'Proven Results, Exceptional Quality')); ?>
            </h1>

            <p class="weown-portfolio-hero-subtitle">
                <?php echo esc_html(get_theme_mod('portfolio_hero_subtitle', 'Delivering successful projects that drive real business value')); ?>
            </p>

            <?php
            /**
             * Key Portfolio Metrics and Achievements
             *
             * Quantified success metrics, client satisfaction scores, and
             * project delivery statistics for trust building.
             */
            ?>
            <div class="weown-portfolio-hero-metrics">
                <?php weown_portfolio_success_metrics(); ?>
            </div>

            <?php
            /**
             * Portfolio Expertise and Specializations
             *
             * Industry focus, technology expertise, and
             * specialized capabilities for authority building.
             */
            ?>
            <div class="weown-portfolio-hero-expertise">
                <?php weown_portfolio_expertise_areas($industry_focus); ?>
            </div>
        </div><!-- .weown-portfolio-hero-content -->

        <?php
        /**
         * Featured Project Preview or Results Showcase
         *
         * Featured project visual, results dashboard, or
         * success metrics visualization for impact demonstration.
         */
        ?>
        <div class="weown-portfolio-hero-visual">
            <?php weown_portfolio_featured_showcase($showcase_style); ?>
        </div>

    </div><!-- .weown-portfolio-hero-container -->
</section><!-- .weown-portfolio-hero -->

<?php
/**
 * Project Categories Section
 *
 * Project categorization with filtering, search, and organization
 * for easy navigation and project discovery.
 */
?>
<section class="weown-portfolio-categories">
    <div class="weown-portfolio-categories-container">

        <header class="weown-portfolio-section-header">
            <h2><?php echo esc_html(get_theme_mod('portfolio_categories_title', 'Explore Our Work')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('portfolio_categories_subtitle', 'Browse projects by category, industry, or service type')); ?></p>
        </header>

        <?php
        /**
         * Project Filtering and Navigation
         *
         * Category filters, industry tags, service type filters, and
         * search functionality for easy project discovery.
         */
        ?>
        <div class="weown-portfolio-filters">
            <?php weown_portfolio_filtering_system(); ?>
        </div>

        <?php
        /**
         * Project Grid Showcase
         *
         * Visual project grid with thumbnails, titles, categories, and
         * quick preview information for engaging exploration.
         */
        ?>
        <div class="weown-portfolio-grid">
            <?php weown_portfolio_project_grid($portfolio_type); ?>
        </div>

    </div><!-- .weown-portfolio-categories-container -->
</section><!-- .weown-portfolio-categories -->

<?php
/**
 * Featured Case Studies Section
 *
 * In-depth case studies with challenges, solutions, results, and
 * detailed project documentation for credibility building.
 */
?>
<?php if (get_theme_mod('portfolio_show_cases')) : ?>
<section class="weown-portfolio-case-studies">
    <div class="weown-portfolio-case-studies-container">

        <header class="weown-portfolio-section-header">
            <h2><?php echo esc_html(get_theme_mod('portfolio_cases_title', 'Featured Case Studies')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('portfolio_cases_subtitle', 'Deep dives into successful projects and client outcomes')); ?></p>
        </header>

        <?php
        /**
         * Detailed Case Study Presentations
         *
         * Comprehensive case studies with project background, challenges,
         * solutions implemented, and quantified results.
         */
        ?>
        <div class="weown-portfolio-case-studies-showcase">
            <?php weown_portfolio_featured_cases(); ?>
        </div>

    </div><!-- .weown-portfolio-case-studies-container -->
</section><!-- .weown-portfolio-case-studies -->
<?php endif; ?>

<?php
/**
 * Project Process Section
 *
 * Methodology and approach explanation with project stages,
 * deliverables, and client involvement for transparency.
 */
?>
<?php if (get_theme_mod('portfolio_show_process')) : ?>
<section class="weown-portfolio-process">
    <div class="weown-portfolio-process-container">

        <header class="weown-portfolio-section-header">
            <h2><?php echo esc_html(get_theme_mod('portfolio_process_title', 'Our Project Approach')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('portfolio_process_subtitle', 'How we deliver successful projects every time')); ?></p>
        </header>

        <?php
        /**
         * Project Delivery Methodology
         *
         * Step-by-step process, key milestones, deliverables, and
         * client collaboration points for transparency.
         */
        ?>
        <div class="weown-portfolio-process-flow">
            <?php weown_portfolio_project_methodology(); ?>
        </div>

    </div><!-- .weown-portfolio-process-container -->
</section><!-- .weown-portfolio-process -->
<?php endif; ?>

<?php
/**
 * Client Testimonials Section
 *
 * Client feedback, success stories, and satisfaction metrics for
 * social proof and credibility building through client voices.
 */
?>
<section class="weown-portfolio-testimonials">
    <div class="weown-portfolio-testimonials-container">

        <header class="weown-portfolio-section-header">
            <h2><?php echo esc_html(get_theme_mod('portfolio_testimonials_title', 'What Our Clients Say')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('portfolio_testimonials_subtitle', 'Real feedback from real clients')); ?></p>
        </header>

        <?php
        /**
         * Client Testimonials and Success Metrics
         *
         * Authentic client feedback, satisfaction scores, and
         * success stories for trust and credibility building.
         */
        ?>
        <div class="weown-portfolio-testimonials-carousel">
            <?php weown_portfolio_client_feedback(); ?>
        </div>

    </div><!-- .weown-portfolio-testimonials-container -->
</section><!-- .weown-portfolio-testimonials -->

<?php
/**
 * Call-to-Action Section
 *
 * Project inquiry CTA with consultation booking, project scoping,
 * and next steps for lead generation and conversions.
 */
?>
<section class="weown-portfolio-cta">
    <div class="weown-portfolio-cta-container">

        <div class="weown-portfolio-cta-content">
            <h2><?php echo esc_html(get_theme_mod('portfolio_cta_title', 'Ready to Start Your Project?')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('portfolio_cta_subtitle', 'Let\'s discuss how we can help achieve your goals')); ?></p>

            <div class="weown-portfolio-cta-buttons">
                <a href="<?php echo esc_url(get_permalink(get_page_by_path('contact'))); ?>" class="weown-portfolio-primary-cta">
                    <?php echo esc_html(get_theme_mod('portfolio_primary_cta', 'Start Your Project')); ?>
                </a>

                <?php if (get_theme_mod('portfolio_show_portfolio_cta')) : ?>
                <a href="#view-more" class="weown-portfolio-secondary-cta">
                    <?php echo esc_html(get_theme_mod('portfolio_more_text', 'View All Projects')); ?>
                </a>
                <?php endif; ?>
            </div>
        </div>

    </div><!-- .weown-portfolio-cta-container -->
</section><!-- .weown-portfolio-cta -->

<?php
/**
 * Enhanced Footer for Business Pages
 *
 * Professional footer with project resources, industry insights,
 * and additional expertise elements for complete portfolio presentation.
 */
get_footer('business-portfolio');
?>
