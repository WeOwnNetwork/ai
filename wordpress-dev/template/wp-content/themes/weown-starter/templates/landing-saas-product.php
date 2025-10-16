<?php
/**
 * Template Name: Landing Saas Product
 * Description: Advanced landing page for SaaS product launches and free trial signups
 * @package WeOwn_Starter
 * @version 1.0.0
 * @author WeOwn Development Team
 */

/**
 * WeOwn Starter Theme - SaaS/Product Landing Page Template
 *
 * Advanced landing page optimized for SaaS product launches with feature showcases,
 * pricing transparency, free trial conversions, and enterprise sales qualification.
 *
 * Features:
 * - Product positioning with competitive advantages
 * - Interactive feature demonstrations and use cases
 * - Transparent pricing with ROI justification
 * - Free trial signup with progressive qualification
 * - Customer testimonials and case study integration
 * - Integration ecosystem and API showcase
 * - Security and compliance messaging
 * - Enterprise sales contact and demo scheduling
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * SaaS Product Configuration
 *
 * Get product-specific configuration for optimal conversion and
 * target market positioning based on SaaS category and business model.
 */
$saas_config = weown_get_saas_config();
$product_category = $saas_config['category'] ?? 'productivity_saas';
$pricing_model = $saas_config['pricing'] ?? 'subscription';
$target_market = $saas_config['market'] ?? 'smb';

/**
 * Dynamic Product Branding
 *
 * Load SaaS-specific branding with modern, trustworthy color schemes
 * and professional design elements for B2B/SaaS positioning.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for SaaS Products
 *
 * Professional header with free trial CTA and product navigation
 * for immediate engagement and lead qualification.
 */
get_header('saas-product');
?>

<?php
/**
 * Product Hero Section - Value Proposition & Trial CTA
 *
 * Benefit-focused hero with clear value proposition, social proof,
 * and immediate free trial signup for rapid conversion.
 */
?>
<section class="weown-saas-hero">
    <div class="weown-saas-hero-container">

        <?php
        /**
         * Product Positioning and Competitive Advantage
         *
         * Clear market positioning, unique value proposition, and
         * competitive differentiation for target audience resonance.
         */
        ?>
        <div class="weown-saas-hero-content">
            <div class="weown-saas-product-badge">
                <span class="product-category-badge">
                    <?php echo esc_html(ucfirst(str_replace('_', ' ', $product_category))); ?>
                </span>
            </div>

            <h1 class="weown-saas-hero-title">
                <?php echo esc_html(get_theme_mod('saas_hero_title', 'The Complete Solution for Modern Teams')); ?>
            </h1>

            <p class="weown-saas-hero-subtitle">
                <?php echo esc_html(get_theme_mod('saas_hero_subtitle', 'Streamline workflows, boost productivity, and drive results')); ?>
            </p>

            <?php
            /**
             * Key Benefits and Performance Metrics
             *
             * Quantified benefits, performance improvements, and
             * time/cost savings for clear ROI demonstration.
             */
            ?>
            <div class="weown-saas-hero-benefits">
                <?php weown_saas_hero_benefits(); ?>
            </div>

            <?php
            /**
             * Free Trial CTA with Social Proof
             *
             * High-converting trial signup with trust indicators
             * and risk-free positioning for immediate engagement.
             */
            ?>
            <div class="weown-saas-hero-cta">
                <a href="#free-trial" class="weown-saas-primary-cta">
                    <?php echo esc_html(get_theme_mod('saas_primary_cta', 'Start Free Trial')); ?>
                    <span class="trial-badge">14-Day Free</span>
                </a>

                <a href="#product-demo" class="weown-saas-secondary-cta">
                    <?php echo esc_html(get_theme_mod('saas_secondary_cta', 'Watch Demo')); ?>
                </a>
            </div>

            <?php
            /**
             * Trust Indicators and Guarantees
             *
             * Security badges, money-back guarantees, and
             * enterprise trust signals for risk reduction.
             */
            ?>
            <div class="weown-saas-hero-trust">
                <?php weown_saas_trust_indicators(); ?>
            </div>
        </div><!-- .weown-saas-hero-content -->

        <?php
        /**
         * Product Preview or Interactive Demo
         *
         * Product interface preview, feature demonstration, or
         * interactive element showcasing core functionality.
         */
        ?>
        <div class="weown-saas-hero-preview">
            <?php weown_saas_product_preview($product_category); ?>
        </div>

    </div><!-- .weown-saas-hero-container -->
</section><!-- .weown-saas-hero -->

<?php
/**
 * Feature Showcase Section
 *
 * Comprehensive feature presentation with benefits, use cases,
 * and interactive demonstrations for complete product understanding.
 */
?>
<section id="product-features" class="weown-saas-features">
    <div class="weown-saas-features-container">

        <header class="weown-saas-section-header">
            <h2><?php echo esc_html(get_theme_mod('saas_features_title', 'Everything You Need to Succeed')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('saas_features_subtitle', 'Powerful features designed for modern workflows')); ?></p>
        </header>

        <?php
        /**
         * Interactive Feature Grid
         *
         * Feature highlights with benefits, screenshots, and
         * industry-specific use case demonstrations.
         */
        ?>
        <div class="weown-saas-features-grid">
            <?php weown_saas_features_showcase($product_category); ?>
        </div>

    </div><!-- .weown-saas-features-container -->
</section><!-- .weown-saas-features -->

<?php
/**
 * Pricing Section
 *
 * Transparent pricing with clear value justification,
 * feature comparisons, and ROI calculator integration.
 */
?>
<section class="weown-saas-pricing">
    <div class="weown-saas-pricing-container">

        <header class="weown-saas-section-header">
            <h2><?php echo esc_html(get_theme_mod('saas_pricing_title', 'Simple, Transparent Pricing')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('saas_pricing_subtitle', 'Choose the plan that fits your team size and needs')); ?></p>
        </header>

        <?php
        /**
         * Pricing Tiers and Feature Matrix
         *
         * Clear pricing structure with feature comparisons,
         * value justification, and conversion-optimized CTAs.
         */
        ?>
        <div class="weown-saas-pricing-tiers">
            <?php weown_saas_pricing_structure($pricing_model); ?>
        </div>

    </div><!-- .weown-saas-pricing-container -->
</section><!-- .weown-saas-pricing -->

<?php
/**
 * Social Proof Section
 *
 * Customer testimonials, case studies, and logos from
 * recognizable brands to build credibility and trust.
 */
?>
<section class="weown-saas-social-proof">
    <div class="weown-saas-social-proof-container">

        <header class="weown-saas-section-header">
            <h2><?php echo esc_html(get_theme_mod('saas_social_proof_title', 'Trusted by Industry Leaders')); ?></h2>
        </header>

        <?php
        /**
         * Customer Testimonials and Success Metrics
         *
         * Authentic customer stories, quantified results, and
         * recognizable brand logos for credibility building.
         */
        ?>
        <div class="weown-saas-testimonials">
            <?php weown_saas_customer_testimonials(); ?>
        </div>

        <?php if (get_theme_mod('saas_show_case_studies')) : ?>
        <div class="weown-saas-case-studies">
            <?php weown_saas_case_studies(); ?>
        </div>
        <?php endif; ?>

    </div><!-- .weown-saas-social-proof-container -->
</section><!-- .weown-saas-social-proof -->

<?php
/**
 * Free Trial Signup Section
 *
 * Progressive trial signup with benefit reinforcement,
 * feature preview, and risk-free positioning.
 */
?>
<section id="free-trial" class="weown-saas-trial-signup">
    <div class="weown-saas-trial-signup-container">

        <div class="weown-saas-trial-content">

            <?php
            /**
             * Trial Value Proposition
             *
             * Clear trial benefits, feature access, and
             * success outcomes for trial signup motivation.
             */
            ?>
            <header class="weown-saas-trial-header">
                <h2><?php echo esc_html(get_theme_mod('saas_trial_title', 'Experience the Power of Our Platform')); ?></h2>
                <p><?php echo esc_html(get_theme_mod('saas_trial_subtitle', 'Full access to all features with no credit card required')); ?></p>
            </header>

            <?php
            /**
             * Progressive Trial Signup Form
             *
             * Multi-step form with basic info, use case questions,
             * and setup preferences for qualified trial starts.
             */
            ?>
            <div class="weown-saas-trial-form-wrapper">
                <?php weown_saas_trial_signup_form($product_category); ?>
            </div>

            <?php
            /**
             * Trial Benefits and Setup Process
             *
             * Clear next steps, setup time, and expected
             * outcomes for smooth onboarding experience.
             */
            ?>
            <div class="weown-saas-trial-benefits">
                <?php weown_saas_trial_benefits(); ?>
            </div>

        </div><!-- .weown-saas-trial-content -->

    </div><!-- .weown-saas-trial-signup-container -->
</section><!-- .weown-saas-trial-signup -->

<?php
/**
 * Integration & Security Section
 *
 * API capabilities, security standards, and integration
 * ecosystem for technical decision makers and IT teams.
 */
?>
<?php if (get_theme_mod('saas_show_integrations')) : ?>
<section class="weown-saas-integrations">
    <div class="weown-saas-integrations-container">

        <header class="weown-saas-section-header">
            <h2><?php echo esc_html(get_theme_mod('saas_integrations_title', 'Seamless Integration & Security')); ?></h2>
        </header>

        <?php
        /**
         * Integration Ecosystem and Security Standards
         *
         * API capabilities, security certifications, and
         * integration options for enterprise evaluation.
         */
        ?>
        <div class="weown-saas-integrations-content">
            <?php weown_saas_integration_showcase(); ?>
        </div>

    </div><!-- .weown-saas-integrations-container -->
</section><!-- .weown-saas-integrations -->
<?php endif; ?>

<?php
/**
 * Final CTA Section
 *
 * Last-chance conversion with trial reinforcement,
 * urgency elements, and multiple conversion paths.
 */
?>
<section class="weown-saas-final-cta">
    <div class="weown-saas-final-cta-container">

        <div class="weown-saas-final-cta-content">
            <h2><?php echo esc_html(get_theme_mod('saas_final_cta_title', 'Ready to Transform Your Workflow?')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('saas_final_cta_subtitle', 'Join thousands of teams already seeing results')); ?></p>

            <div class="weown-saas-final-cta-buttons">
                <a href="#free-trial" class="weown-saas-final-primary-cta">
                    <?php echo esc_html(get_theme_mod('saas_final_primary_text', 'Start Your Free Trial')); ?>
                </a>

                <?php if (get_theme_mod('saas_show_enterprise_cta')) : ?>
                <a href="#enterprise-contact" class="weown-saas-enterprise-cta">
                    <?php echo esc_html(get_theme_mod('saas_enterprise_cta_text', 'Contact Sales')); ?>
                </a>
                <?php endif; ?>
            </div>
        </div>

    </div><!-- .weown-saas-final-cta-container -->
</section><!-- .weown-saas-final-cta -->

<?php
/**
 * Enhanced Footer for SaaS Products
 *
 * Product resources, support documentation, compliance info,
 * and final conversion opportunity for ongoing engagement.
 */
get_footer('saas-product');
?>
