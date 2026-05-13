<?php
/**
 * Template Name: Landing AI Showcase
 * Description: AI product showcase with interactive demos and technical specifications
 * @package WeOwn_Starter
 */

// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * AI Product Showcase Configuration
 *
 * Get product-specific configuration for demo optimization and
 * industry-specific messaging and conversion goals.
 */
$ai_config = weown_get_ai_showcase_config();
$product_type = $ai_config['product_type'] ?? 'saas_ai';
$target_industry = $ai_config['industry'] ?? 'general';
$demo_type = $ai_config['demo_type'] ?? 'interactive';

/**
 * Dynamic Branding Integration
 *
 * Load AI product branding with technical color schemes and
 * modern design elements appropriate for AI/SaaS products.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for AI Product Pages
 *
 * Tech-focused header with demo CTA and industry-specific navigation
 * for B2B AI product positioning and lead qualification.
 */
get_header();
?>

<?php
/**
 * Hero Section - Product Positioning & Demo CTA
 *
 * Technical hero section with product positioning, key benefits,
 * and immediate demo request for qualified prospects.
 */
?>
<section class="weown-ai-hero">
    <div class="weown-ai-hero-container">

        <?php
        /**
         * Product Positioning Hero
         *
         * Industry-leading positioning with technical credibility and
         * clear value proposition for B2B AI decision makers.
         */
        ?>
        <div class="weown-ai-hero-content">
            <div class="weown-ai-hero-badge">
                <span class="product-badge"><?php echo esc_html(get_theme_mod('ai_product_category', 'AI-Powered')); ?></span>
            </div>

            <h1 class="weown-ai-hero-title">
                <?php echo esc_html(get_theme_mod('ai_hero_title', 'Next-Generation AI Automation')); ?>
            </h1>

            <p class="weown-ai-hero-subtitle">
                <?php echo esc_html(get_theme_mod('ai_hero_subtitle', 'Transform your business with intelligent automation that learns and adapts')); ?>
            </p>

            <?php
            /**
             * Key Metrics and Performance Indicators
             *
             * Technical performance metrics and business outcomes to
             * establish credibility and quantify value proposition.
             */
            ?>
            <div class="weown-ai-hero-metrics">
                <?php weown_ai_hero_metrics(); ?>
            </div>

            <?php
            /**
             * Demo CTA with Qualification
             *
             * Primary conversion point with demo request form and
             * basic qualification questions for lead scoring.
             */
            ?>
            <div class="weown-ai-hero-cta">
                <a href="#demo-request" class="weown-demo-primary-cta">
                    <?php echo esc_html(get_theme_mod('ai_primary_cta', 'Request Live Demo')); ?>
                </a>

                <a href="#product-features" class="weown-demo-secondary-cta">
                    <?php echo esc_html(get_theme_mod('ai_secondary_cta', 'View Features')); ?>
                </a>
            </div>
        </div><!-- .weown-ai-hero-content -->

        <?php
        /**
         * Interactive Product Preview
         *
         * Live product demonstration, feature preview, or
         * interactive element showcasing AI capabilities.
         */
        ?>
        <div class="weown-ai-hero-preview">
            <?php weown_ai_product_preview($demo_type); ?>
        </div>

    </div><!-- .weown-ai-hero-container -->
</section><!-- .weown-ai-hero -->

<?php
/**
 * Problem/Solution Section
 *
 * Industry-specific problem identification and AI solution
 * positioning for target market resonance and credibility.
 */
?>
<section class="weown-ai-problem-solution">
    <div class="weown-ai-problem-solution-container">

        <div class="weown-ai-problem-content">
            <h2><?php echo esc_html(get_theme_mod('ai_problem_title', 'The Challenge')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('ai_problem_description', 'Traditional approaches are failing to keep pace with modern demands')); ?></p>

            <?php
            /**
             * Industry-Specific Pain Points
             *
             * Target industry challenges and pain points that
             * the AI solution specifically addresses.
             */
            ?>
            <div class="weown-ai-pain-points">
                <?php weown_ai_pain_points($target_industry); ?>
            </div>
        </div>

        <div class="weown-ai-solution-content">
            <h2><?php echo esc_html(get_theme_mod('ai_solution_title', 'The AI Solution')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('ai_solution_description', 'Intelligent automation that adapts and learns from your data')); ?></p>

            <?php
            /**
             * Solution Benefits and Outcomes
             *
             * Quantified benefits and business outcomes delivered
             * by the AI solution for clear ROI demonstration.
             */
            ?>
            <div class="weown-ai-solution-benefits">
                <?php weown_ai_solution_benefits(); ?>
            </div>
        </div>

    </div><!-- .weown-ai-problem-solution-container -->
</section><!-- .weown-ai-problem-solution -->

<?php
/**
 * Feature Showcase Section
 *
 * Technical feature presentation with live demonstrations and
 * use case examples for comprehensive product understanding.
 */
?>
<section id="product-features" class="weown-ai-features">
    <div class="weown-ai-features-container">

        <header class="weown-ai-section-header">
            <h2><?php echo esc_html(get_theme_mod('ai_features_title', 'Advanced AI Capabilities')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('ai_features_subtitle', 'Enterprise-grade features designed for scale and reliability')); ?></p>
        </header>

        <?php
        /**
         * Interactive Feature Grid
         *
         * Technical features with live demos, code examples, and
         * industry-specific use case demonstrations.
         */
        ?>
        <div class="weown-ai-features-grid">
            <?php weown_ai_features_showcase($product_type); ?>
        </div>

    </div><!-- .weown-ai-features-container -->
</section><!-- .weown-ai-features -->

<?php
/**
 * Technical Specifications Section
 *
 * Detailed technical specifications, performance metrics, and
 * integration capabilities for technical decision makers.
 */
?>
<section class="weown-ai-technical-specs">
    <div class="weown-ai-technical-specs-container">

        <header class="weown-ai-section-header">
            <h2><?php echo esc_html(get_theme_mod('ai_specs_title', 'Technical Excellence')); ?></h2>
        </header>

        <?php
        /**
         * Technical Specifications Grid
         *
         * Performance metrics, security standards, and integration
         * capabilities for comprehensive technical evaluation.
         */
        ?>
        <div class="weown-ai-specs-grid">
            <?php weown_ai_technical_specifications(); ?>
        </div>

    </div><!-- .weown-ai-technical-specs-container -->
</section><!-- .weown-ai-technical-specs -->

<?php
/**
 * Demo Request Section
 *
 * Comprehensive demo request form with lead qualification,
 * use case specification, and technical requirements gathering.
 */
?>
<section id="demo-request" class="weown-ai-demo-request">
    <div class="weown-ai-demo-request-container">

        <div class="weown-ai-demo-content">

            <?php
            /**
             * Demo Request Value Proposition
             *
             * Clear demonstration of demo value and what prospects
             * will experience during the personalized demo session.
             */
            ?>
            <header class="weown-ai-demo-header">
                <h2><?php echo esc_html(get_theme_mod('ai_demo_title', 'See It In Action')); ?></h2>
                <p><?php echo esc_html(get_theme_mod('ai_demo_subtitle', 'Schedule a personalized demo tailored to your specific use case')); ?></p>
            </header>

            <?php
            /**
             * Qualified Demo Request Form
             *
             * Multi-step form with lead qualification questions,
             * use case specification, and technical requirements.
             */
            ?>
            <div class="weown-ai-demo-form-wrapper">
                <?php weown_ai_demo_request_form($target_industry); ?>
            </div>

            <?php
            /**
             * Demo Benefits and Next Steps
             *
             * Clear next steps, demo format options, and expected
             * outcomes for setting proper expectations.
             */
            ?>
            <div class="weown-ai-demo-benefits">
                <?php weown_ai_demo_benefits(); ?>
            </div>

        </div><!-- .weown-ai-demo-content -->

    </div><!-- .weown-ai-demo-request-container -->
</section><!-- .weown-ai-demo-request -->

<?php
/**
 * Pricing/ROI Section (Optional)
 *
 * Transparent pricing and ROI calculator for budget holders
 * and financial decision makers in the buying process.
 */
?>
<?php if (get_theme_mod('ai_show_pricing')) : ?>
<section class="weown-ai-pricing-roi">
    <div class="weown-ai-pricing-roi-container">

        <header class="weown-ai-section-header">
            <h2><?php echo esc_html(get_theme_mod('ai_pricing_title', 'Transparent Pricing & ROI')); ?></h2>
        </header>

        <?php
        /**
         * Pricing Tiers and ROI Calculator
         *
         * Clear pricing structure with ROI justification and
         * cost-benefit analysis for financial decision makers.
         */
        ?>
        <div class="weown-ai-pricing-content">
            <?php weown_ai_pricing_structure(); ?>
        </div>

    </div><!-- .weown-ai-pricing-roi-container -->
</section><!-- .weown-ai-pricing-roi -->
<?php endif; ?>

<?php
if (have_posts()) :
    while (have_posts()) : the_post();
        ?>
        <main id="primary" class="weown-page-content weown-ai-custom-content">
            <div class="weown-content-container">
                <?php the_content(); ?>
            </div>
        </main>
        <?php
    endwhile;
endif;
?>

<?php
/**
 * Enhanced Footer for AI Product Pages
 *
 * Technical resources, documentation links, and final conversion
 * opportunity for prospects researching the solution.
 */
get_footer();
?>
