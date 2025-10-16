<?php
/**
 * Template Name: Landing Leadgen
 * Description: Advanced landing page for general lead generation and list building
 * @package WeOwn_Starter
 * @version 1.0.0
 * @author WeOwn Development Team
 */

/**
 * WeOwn Starter Theme - Lead Generation Landing Page Template
 *
 * Advanced landing page optimized for lead capture, newsletter signups,
 * demo requests, and consultation bookings with conversion optimization.
 *
 * Features:
 * - Hero section with value proposition and primary CTA
 * - Progressive profiling forms with multi-step conversion
 * - Trust indicators including testimonials and security badges
 * - Social proof elements with customer logos and metrics
 * - Urgency and scarcity elements for conversion acceleration
 * - Multiple conversion touchpoints throughout the page
 * - Mobile-optimized design for all device types
 * - A/B testing framework integration ready
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Lead Generation Landing Page Configuration
 *
 * Get page-specific configuration for lead gen optimization.
 * Supports A/B testing variations and dynamic content injection.
 */
$lead_config = weown_get_lead_config();
$conversion_goal = $lead_config['goal'] ?? 'newsletter_signup';
$urgency_level = $lead_config['urgency'] ?? 'medium';

/**
 * Dynamic Branding Integration
 *
 * Load site-specific branding for consistent experience across
 * all conversion elements and design components.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Landing Pages
 *
 * Sticky header with primary CTA for immediate conversion opportunity.
 * Includes trust indicators and social proof elements.
 */
get_header();
?>

<!-- Page Content Area -->
<div class="page-content-wrapper">
    <?php the_content(); ?>
</div>

<?php
/**
 * Hero Section - Primary Conversion Point
 *
 * High-converting hero with clear value proposition, primary CTA,
 * and trust indicators for immediate engagement.
 */
?>
<section class="weown-landing-hero weown-leadgen-hero">
    <div class="weown-landing-hero-container">

        <?php
        /**
         * Hero Content with Conversion Optimization
         *
         * Benefit-focused headline, value proposition, and
         * primary call-to-action for maximum conversion impact.
         */
        ?>
        <div class="weown-landing-hero-content">
            <?php if (get_theme_mod('leadgen_hero_headline')) : ?>
            <h1 class="weown-landing-hero-title">
                <?php echo esc_html(get_theme_mod('leadgen_hero_headline')); ?>
            </h1>
            <?php endif; ?>

            <?php if (get_theme_mod('leadgen_hero_subtitle')) : ?>
            <p class="weown-landing-hero-subtitle">
                <?php echo esc_html(get_theme_mod('leadgen_hero_subtitle')); ?>
            </p>
            <?php endif; ?>

            <?php
            /**
             * Primary CTA Button with Conversion Optimization
             *
             * High-visibility CTA button with urgency elements and
             * benefit-focused messaging for immediate action.
             */
            ?>
            <div class="weown-landing-hero-cta">
                <a href="#lead-form" class="weown-primary-cta-button">
                    <?php echo esc_html(get_theme_mod('leadgen_primary_cta_text', 'Get Started Free')); ?>
                    <?php if ($urgency_level === 'high') : ?>
                    <span class="urgency-badge">Limited Time</span>
                    <?php endif; ?>
                </a>

                <?php if (get_theme_mod('leadgen_show_secondary_cta')) : ?>
                <a href="#features" class="weown-secondary-cta-button">
                    <?php echo esc_html(get_theme_mod('leadgen_secondary_cta_text', 'Learn More')); ?>
                </a>
                <?php endif; ?>
            </div>

            <?php
            /**
             * Trust Indicators and Social Proof
             *
             * Trust signals, testimonials, and credibility elements
             * to reduce friction and increase conversion confidence.
             */
            ?>
            <div class="weown-landing-hero-trust">
                <?php weown_leadgen_trust_indicators(); ?>
            </div>
        </div><!-- .weown-landing-hero-content -->

        <?php
        /**
         * Hero Visual Element (Optional)
         *
         * Product demo, feature preview, or visual element that
         * supports the value proposition and conversion goal.
         */
        ?>
        <?php if (get_theme_mod('leadgen_show_hero_visual')) : ?>
        <div class="weown-landing-hero-visual">
            <?php weown_leadgen_hero_visual(); ?>
        </div>
        <?php endif; ?>

    </div><!-- .weown-landing-hero-container -->
</section><!-- .weown-landing-hero -->

<?php
/**
 * Feature Highlights Section
 *
 * Key features and benefits presented in an easy-to-scan format
 * with secondary conversion opportunities throughout.
 */
?>
<section id="features" class="weown-landing-features">
    <div class="weown-landing-features-container">

        <header class="weown-landing-section-header">
            <h2><?php echo esc_html(get_theme_mod('leadgen_features_title', 'Why Choose Our Solution?')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('leadgen_features_subtitle', 'Everything you need to succeed')); ?></p>
        </header>

        <?php
        /**
         * Feature Grid with Conversion Elements
         *
         * Feature highlights with benefit-focused descriptions and
         * strategic CTA placement for progressive conversion.
         */
        ?>
        <div class="weown-landing-features-grid">
            <?php weown_leadgen_features_grid(); ?>
        </div>

    </div><!-- .weown-landing-features-container -->
</section><!-- .weown-landing-features -->

<?php
/**
 * Social Proof Section
 *
 * Testimonials, case studies, and client logos to build
 * credibility and reduce purchase anxiety.
 */
?>
<section class="weown-landing-social-proof">
    <div class="weown-landing-social-proof-container">

        <header class="weown-landing-section-header">
            <h2><?php echo esc_html(get_theme_mod('leadgen_social_proof_title', 'Trusted by Industry Leaders')); ?></h2>
        </header>

        <?php
        /**
         * Testimonials and Client Logos
         *
         * Social proof elements with authentic testimonials and
         * recognizable brand logos for credibility building.
         */
        ?>
        <div class="weown-landing-testimonials">
            <?php weown_leadgen_testimonials(); ?>
        </div>

        <?php if (get_theme_mod('leadgen_show_client_logos')) : ?>
        <div class="weown-landing-client-logos">
            <?php weown_leadgen_client_logos(); ?>
        </div>
        <?php endif; ?>

    </div><!-- .weown-landing-social-proof-container -->
</section><!-- .weown-landing-social-proof -->

<?php
/**
 * Lead Generation Form Section
 *
 * Primary conversion form with progressive profiling,
 * benefit reinforcement, and trust indicators.
 */
?>
<section id="lead-form" class="weown-landing-lead-form">
    <div class="weown-landing-lead-form-container">

        <div class="weown-landing-form-content">

            <?php
            /**
             * Form Header with Value Proposition
             *
             * Clear value proposition and benefit statement to
             * reinforce the decision to convert at this point.
             */
            ?>
            <header class="weown-landing-form-header">
                <h2><?php echo esc_html(get_theme_mod('leadgen_form_title', 'Get Your Free Access')); ?></h2>
                <p><?php echo esc_html(get_theme_mod('leadgen_form_subtitle', 'Join thousands of successful users')); ?></p>
            </header>

            <?php
            /**
             * Progressive Profiling Form
             *
             * Smart form that asks for minimal information initially
             * and progressively requests more as user engagement increases.
             */
            ?>
            <div class="weown-landing-form-wrapper">
                <?php weown_leadgen_progressive_form(); ?>
            </div>

            <?php
            /**
             * Form Benefits and Trust Signals
             *
             * Benefits of completing the form and trust indicators
             * to reduce friction and increase conversion rates.
             */
            ?>
            <div class="weown-landing-form-benefits">
                <?php weown_leadgen_form_benefits(); ?>
            </div>

        </div><!-- .weown-landing-form-content -->

    </div><!-- .weown-landing-lead-form-container -->
</section><!-- .weown-landing-lead-form -->

<?php
/**
 * FAQ Section (Optional)
 *
 * Common questions and objections addressed to reduce
 * friction and improve conversion confidence.
 */
?>
<?php if (get_theme_mod('leadgen_show_faq')) : ?>
<section class="weown-landing-faq">
    <div class="weown-landing-faq-container">

        <header class="weown-landing-section-header">
            <h2><?php echo esc_html(get_theme_mod('leadgen_faq_title', 'Frequently Asked Questions')); ?></h2>
        </header>

        <div class="weown-landing-faq-accordion">
            <?php weown_leadgen_faq_accordion(); ?>
        </div>

    </div><!-- .weown-landing-faq-container -->
</section><!-- .weown-landing-faq -->
<?php endif; ?>

<?php
/**
 * Final Call-to-Action Section
 *
 * Last-chance conversion opportunity with urgency elements
 * and final value reinforcement before page exit.
 */
?>
<section class="weown-landing-final-cta">
    <div class="weown-landing-final-cta-container">

        <div class="weown-landing-final-cta-content">
            <h2><?php echo esc_html(get_theme_mod('leadgen_final_cta_title', 'Don\'t Miss Out - Get Started Today')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('leadgen_final_cta_subtitle', 'Limited time offer expires soon')); ?></p>

            <div class="weown-landing-final-cta-buttons">
                <a href="#lead-form" class="weown-final-primary-cta">
                    <?php echo esc_html(get_theme_mod('leadgen_final_primary_text', 'Claim Your Free Access')); ?>
                </a>
            </div>
        </div>

    </div><!-- .weown-landing-final-cta-container -->
</section><!-- .weown-landing-final-cta -->

<?php
/**
 * Enhanced Footer for Landing Pages
 *
 * Conversion-optimized footer with trust indicators, guarantees,
 * and final conversion opportunity for exit-intent scenarios.
 */
get_footer('landing-leadgen');
?>
