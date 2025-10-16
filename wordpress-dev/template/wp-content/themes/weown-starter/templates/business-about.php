<?php
/**
 * Template Name: About Business
 * Description: Professional business page for company information and team profiles
 * @package WeOwn_Starter
 * @version 1.0.0
 * @author WeOwn Development Team
 */

/**
 * WeOwn Starter Theme - About Us Business Page Template
 *
 * Professional business page template for company information, team profiles,
 * company history, mission/vision, and credibility building elements.
 *
 * Features:
 * - Hero section with company value proposition and key statistics
 * - Company story and founding narrative with timeline
 * - Leadership team profiles with social proof and expertise
 * - Company values and culture showcase
 * - Awards, certifications, and industry recognition
 * - Call-to-action for engagement (contact, careers, partnership)
 * - Social proof integration (testimonials, client logos)
 * - Interactive elements (team carousel, company timeline)
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * About Page Configuration
 *
 * Get company-specific configuration for optimal storytelling and
 * credibility building based on business type and industry focus.
 */
$about_config = weown_get_about_config();
$company_type = $about_config['type'] ?? 'technology_company';
$industry_focus = $about_config['industry'] ?? 'ai_technology';
$storytelling_style = $about_config['storytelling'] ?? 'founder_focused';

/**
 * Dynamic Company Branding
 *
 * Load company-specific branding with professional color schemes and
 * trust-building design elements for business credibility.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Business Pages
 *
 * Professional header with company navigation and credibility indicators
 * for trust building and professional presentation.
 */
get_header('business-about');
?>

<!-- Page Content Area -->
<div class="page-content-wrapper">
    <?php the_content(); ?>
</div>

<?php
/**
 * Company Hero Section - Value Proposition & Credibility
 *
 * Trust-building hero with company mission, key metrics, and
 * immediate credibility indicators for professional positioning.
 */
?>
<section class="weown-about-hero">
    <div class="weown-about-hero-container">

        <?php
        /**
         * Company Positioning and Key Metrics
         *
         * Clear company positioning, founding year, employee count,
         * and key achievements for immediate credibility building.
         */
        ?>
        <div class="weown-about-hero-content">
            <div class="weown-about-company-badge">
                <span class="company-industry-badge">
                    <?php echo esc_html(ucfirst(str_replace('_', ' ', $company_type))); ?>
                </span>
            </div>

            <h1 class="weown-about-hero-title">
                <?php echo esc_html(get_theme_mod('about_hero_title', 'Empowering Innovation Through Technology')); ?>
            </h1>

            <p class="weown-about-hero-subtitle">
                <?php echo esc_html(get_theme_mod('about_hero_subtitle', 'Leading the future of AI-powered solutions since our founding')); ?>
            </p>

            <?php
            /**
             * Key Company Metrics and Achievements
             *
             * Quantified achievements, client success metrics, and
             * industry recognition for trust and credibility building.
             */
            ?>
            <div class="weown-about-hero-metrics">
                <?php weown_about_company_metrics(); ?>
            </div>

            <?php
            /**
             * Company Mission and Vision
             *
             * Clear mission statement, vision for the future, and
             * core values for stakeholder alignment and trust.
             */
            ?>
            <div class="weown-about-hero-mission">
                <blockquote class="company-mission">
                    <?php echo esc_html(get_theme_mod('about_mission_statement', 'To democratize AI technology and empower businesses worldwide.')); ?>
                </blockquote>
            </div>
        </div><!-- .weown-about-hero-content -->

        <?php
        /**
         * Company Visual or Leadership Preview
         *
         * Company office photo, leadership team preview, or
         * product demonstration for human connection and trust.
         */
        ?>
        <div class="weown-about-hero-visual">
            <?php weown_about_company_visual($company_type); ?>
        </div>

    </div><!-- .weown-about-hero-container -->
</section><!-- .weown-about-hero -->

<?php
/**
 * Company Story Section
 *
 * Narrative-driven company history with founding story,
 * key milestones, and growth journey for emotional connection.
 */
?>
<section class="weown-about-story">
    <div class="weown-about-story-container">

        <header class="weown-about-section-header">
            <h2><?php echo esc_html(get_theme_mod('about_story_title', 'Our Journey')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('about_story_subtitle', 'From humble beginnings to industry leadership')); ?></p>
        </header>

        <?php
        /**
         * Interactive Company Timeline
         *
         * Key milestones, product launches, funding rounds, and
         * major achievements in an engaging timeline format.
         */
        ?>
        <div class="weown-about-timeline">
            <?php weown_about_company_timeline($storytelling_style); ?>
        </div>

    </div><!-- .weown-about-story-container -->
</section><!-- .weown-about-story -->

<?php
/**
 * Leadership Team Section
 *
 * Executive and key team member profiles with expertise,
 * background, and thought leadership for trust building.
 */
?>
<section class="weown-about-team">
    <div class="weown-about-team-container">

        <header class="weown-about-section-header">
            <h2><?php echo esc_html(get_theme_mod('about_team_title', 'Meet Our Leadership Team')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('about_team_subtitle', 'Experienced leaders driving innovation and results')); ?></p>
        </header>

        <?php
        /**
         * Team Member Profiles and Expertise
         *
         * Executive profiles, key achievements, industry experience,
         * and thought leadership content for credibility building.
         */
        ?>
        <div class="weown-about-team-grid">
            <?php weown_about_team_profiles(); ?>
        </div>

    </div><!-- .weown-about-team-container -->
</section><!-- .weown-about-team -->

<?php
/**
 * Company Values Section
 *
 * Core values, culture, and company principles with
 * real examples and employee testimonials for authenticity.
 */
?>
<?php if (get_theme_mod('about_show_values')) : ?>
<section class="weown-about-values">
    <div class="weown-about-values-container">

        <header class="weown-about-section-header">
            <h2><?php echo esc_html(get_theme_mod('about_values_title', 'Our Values')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('about_values_subtitle', 'The principles that guide everything we do')); ?></p>
        </header>

        <?php
        /**
         * Company Values and Culture Showcase
         *
         * Core values with descriptions, real-world examples, and
         * employee stories for authentic culture presentation.
         */
        ?>
        <div class="weown-about-values-grid">
            <?php weown_about_company_values(); ?>
        </div>

    </div><!-- .weown-about-values-container -->
</section><!-- .weown-about-values -->
<?php endif; ?>

<?php
/**
 * Awards & Recognition Section
 *
 * Industry awards, certifications, and recognition for
 * third-party credibility and industry leadership positioning.
 */
?>
<?php if (get_theme_mod('about_show_awards')) : ?>
<section class="weown-about-awards">
    <div class="weown-about-awards-container">

        <header class="weown-about-section-header">
            <h2><?php echo esc_html(get_theme_mod('about_awards_title', 'Awards & Recognition')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('about_awards_subtitle', 'Industry acknowledgment of our innovation and excellence')); ?></p>
        </header>

        <?php
        /**
         * Awards, Certifications, and Media Coverage
         *
         * Professional recognition, industry certifications, and
         * media mentions for enhanced credibility and trust.
         */
        ?>
        <div class="weown-about-awards-showcase">
            <?php weown_about_awards_recognition(); ?>
        </div>

    </div><!-- .weown-about-awards-container -->
</section><!-- .weown-about-awards -->
<?php endif; ?>

<?php
/**
 * Social Proof Section
 *
 * Client testimonials, case studies, and partner logos for
 * market validation and trust building through social proof.
 */
?>
<section class="weown-about-social-proof">
    <div class="weown-about-social-proof-container">

        <?php
        /**
         * Client Testimonials and Success Stories
         *
         * Customer testimonials, case study highlights, and
         * recognizable client logos for market validation.
         */
        ?>
        <div class="weown-about-testimonials">
            <?php weown_about_client_testimonials(); ?>
        </div>

        <?php if (get_theme_mod('about_show_partners')) : ?>
        <div class="weown-about-partner-logos">
            <?php weown_about_partner_logos(); ?>
        </div>
        <?php endif; ?>

    </div><!-- .weown-about-social-proof-container -->
</section><!-- .weown-about-social-proof -->

<?php
/**
 * Call-to-Action Section
 *
 * Engagement-focused CTA for next steps like contact,
 * careers, partnership inquiries, or newsletter signup.
 */
?>
<section class="weown-about-cta">
    <div class="weown-about-cta-container">

        <div class="weown-about-cta-content">
            <h2><?php echo esc_html(get_theme_mod('about_cta_title', 'Ready to Work With Us?')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('about_cta_subtitle', 'Join hundreds of companies already transforming their business')); ?></p>

            <div class="weown-about-cta-buttons">
                <a href="<?php echo esc_url(get_permalink(get_page_by_path('contact'))); ?>" class="weown-about-primary-cta">
                    <?php echo esc_html(get_theme_mod('about_primary_cta', 'Get In Touch')); ?>
                </a>

                <?php if (get_theme_mod('about_show_careers_cta')) : ?>
                <a href="<?php echo esc_url(get_theme_mod('about_careers_url', '/careers')); ?>" class="weown-about-secondary-cta">
                    <?php echo esc_html(get_theme_mod('about_careers_text', 'View Careers')); ?>
                </a>
                <?php endif; ?>
            </div>
        </div>

    </div><!-- .weown-about-cta-container -->
</section><!-- .weown-about-cta -->

<?php
/**
 * Enhanced Footer for Business Pages
 *
 * Professional footer with company information, legal links,
 * and additional credibility elements for complete business presentation.
 */
get_footer('business-about');
?>
