<?php
/**
 * Template Name: Business Services
 * Description: Professional services showcase with pricing and case studies
 * @package WeOwn_Starter
 *
 * Professional services page template showcasing company offerings,
 * service packages, pricing transparency, and value propositions.
 *
 * Features:
 * - Hero section with service value proposition and key benefits
 * - Service categories and detailed offerings with features
 * - Service process/methodology explanation
 * - Pricing packages with clear comparisons
 * - Service guarantees and deliverables
 * - Case studies and success metrics
 * - Call-to-action for service inquiries and consultations
 * - Industry expertise and specialization highlights
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
 * Services Page Configuration
 *
 * Get service-specific configuration for optimal presentation and
 * conversion based on service type and business model.
 */
$services_config = weown_get_services_config();
$service_category = $services_config['category'] ?? 'technology_services';
$pricing_model = $services_config['pricing'] ?? 'project_based';
$service_focus = $services_config['focus'] ?? 'enterprise_solutions';

/**
 * Dynamic Service Branding
 *
 * Load service-specific branding with professional color schemes and
 * expertise-focused design elements for authority positioning.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Business Pages
 *
 * Professional header with service navigation and expertise indicators
 * for authority building and service-focused presentation.
 */
get_header('business-services');
?>

<?php
/**
 * Services Hero Section - Value Proposition & Expertise
 *
 * Expertise-focused hero with service capabilities, key benefits, and
 * immediate credibility indicators for professional positioning.
 */
?>
<section class="weown-services-hero">
    <div class="weown-services-hero-container">

        <?php
        /**
         * Service Positioning and Key Capabilities
         *
         * Clear service positioning, core competencies, and
         * unique value propositions for immediate understanding.
         */
        ?>
        <div class="weown-services-hero-content">
            <div class="weown-services-category-badge">
                <span class="service-category-badge">
                    <?php echo esc_html(ucfirst(str_replace('_', ' ', $service_category))); ?>
                </span>
            </div>

            <h1 class="weown-services-hero-title">
                <?php echo esc_html(get_theme_mod('services_hero_title', 'Expert Solutions for Complex Challenges')); ?>
            </h1>

            <p class="weown-services-hero-subtitle">
                <?php echo esc_html(get_theme_mod('services_hero_subtitle', 'Delivering results through proven methodologies and deep expertise')); ?>
            </p>

            <?php
            /**
             * Key Service Benefits and Capabilities
             *
             * Quantified benefits, service capabilities, and
             * expertise areas for clear value communication.
             */
            ?>
            <div class="weown-services-hero-benefits">
                <?php weown_services_key_benefits(); ?>
            </div>

            <?php
            /**
             * Service Expertise and Specializations
             *
             * Industry focus, technology expertise, and
             * specialized capabilities for authority building.
             */
            ?>
            <div class="weown-services-hero-expertise">
                <?php weown_services_expertise_areas($service_focus); ?>
            </div>
        </div><!-- .weown-services-hero-content -->

        <?php
        /**
         * Service Preview or Process Visualization
         *
         * Service delivery visualization, process flowchart, or
         * capability demonstration for understanding and trust.
         */
        ?>
        <div class="weown-services-hero-visual">
            <?php weown_services_capability_showcase($service_category); ?>
        </div>

    </div><!-- .weown-services-hero-container -->
</section><!-- .weown-services-hero -->

<?php
/**
 * Service Offerings Section
 *
 * Detailed service categories with features, deliverables, and
 * value propositions for comprehensive service understanding.
 */
?>
<section class="weown-services-offerings">
    <div class="weown-services-offerings-container">

        <header class="weown-services-section-header">
            <h2><?php echo esc_html(get_theme_mod('services_offerings_title', 'Our Service Offerings')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('services_offerings_subtitle', 'Comprehensive solutions tailored to your needs')); ?></p>
        </header>

        <?php
        /**
         * Service Categories and Detailed Descriptions
         *
         * Main service areas, sub-services, features, and
         * deliverables for complete service understanding.
         */
        ?>
        <div class="weown-services-categories">
            <?php weown_services_offerings_grid($service_category); ?>
        </div>

    </div><!-- .weown-services-offerings-container -->
</section><!-- .weown-services-offerings -->

<?php
/**
 * Service Process Section
 *
 * Methodology and process explanation with stages, deliverables,
 * and client involvement for transparency and trust building.
 */
?>
<section class="weown-services-process">
    <div class="weown-services-process-container">

        <header class="weown-services-section-header">
            <h2><?php echo esc_html(get_theme_mod('services_process_title', 'Our Proven Process')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('services_process_subtitle', 'How we deliver exceptional results every time')); ?></p>
        </header>

        <?php
        /**
         * Service Delivery Methodology
         *
         * Step-by-step process, key milestones, deliverables, and
         * client touchpoints for transparency and expectation setting.
         */
        ?>
        <div class="weown-services-process-flow">
            <?php weown_services_process_methodology(); ?>
        </div>

    </div><!-- .weown-services-process-container -->
</section><!-- .weown-services-process -->

<?php
/**
 * Pricing Section
 *
 * Service packages with clear pricing, features, and value
 * comparisons for informed decision making and conversions.
 */
?>
<?php if (get_theme_mod('services_show_pricing')) : ?>
<section class="weown-services-pricing">
    <div class="weown-services-pricing-container">

        <header class="weown-services-section-header">
            <h2><?php echo esc_html(get_theme_mod('services_pricing_title', 'Service Packages')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('services_pricing_subtitle', 'Choose the package that best fits your needs and budget')); ?></p>
        </header>

        <?php
        /**
         * Service Pricing Tiers and Comparisons
         *
         * Clear pricing structure, feature comparisons, and
         * value justification for informed purchasing decisions.
         */
        ?>
        <div class="weown-services-pricing-tiers">
            <?php weown_services_pricing_structure($pricing_model); ?>
        </div>

    </div><!-- .weown-services-pricing-container -->
</section><!-- .weown-services-pricing -->
<?php endif; ?>

<?php
/**
 * Service Guarantees Section
 *
 * Service guarantees, SLAs, and success metrics for
 * risk reduction and confidence building in service quality.
 */
?>
<?php if (get_theme_mod('services_show_guarantees')) : ?>
<section class="weown-services-guarantees">
    <div class="weown-services-guarantees-container">

        <header class="weown-services-section-header">
            <h2><?php echo esc_html(get_theme_mod('services_guarantees_title', 'Our Guarantees')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('services_guarantees_subtitle', 'Your satisfaction and success are our top priorities')); ?></p>
        </header>

        <?php
        /**
         * Service Guarantees and Success Metrics
         *
         * Quality guarantees, success metrics, SLAs, and
         * client protection policies for risk reduction.
         */
        ?>
        <div class="weown-services-guarantees-grid">
            <?php weown_services_guarantees_success(); ?>
        </div>

    </div><!-- .weown-services-guarantees-container -->
</section><!-- .weown-services-guarantees -->
<?php endif; ?>

<?php
/**
 * Case Studies Section
 *
 * Client success stories with challenges, solutions, and
 * quantified results for credibility and social proof.
 */
?>
<?php if (get_theme_mod('services_show_cases')) : ?>
<section class="weown-services-case-studies">
    <div class="weown-services-case-studies-container">

        <header class="weown-services-section-header">
            <h2><?php echo esc_html(get_theme_mod('services_cases_title', 'Success Stories')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('services_cases_subtitle', 'Real results for real clients')); ?></p>
        </header>

        <?php
        /**
         * Client Case Studies and Testimonials
         *
         * Detailed success stories, quantified results, and
         * client testimonials for credibility and trust building.
         */
        ?>
        <div class="weown-services-case-studies-showcase">
            <?php weown_services_case_studies(); ?>
        </div>

    </div><!-- .weown-services-case-studies-container -->
</section><!-- .weown-services-case-studies -->
<?php endif; ?>

<?php
/**
 * Call-to-Action Section
 *
 * Service inquiry CTA with consultation booking, quote requests,
 * and next steps for lead generation and conversions.
 */
?>
<section class="weown-services-cta">
    <div class="weown-services-cta-container">

        <div class="weown-services-cta-content">
            <h2><?php echo esc_html(get_theme_mod('services_cta_title', 'Ready to Get Started?')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('services_cta_subtitle', 'Schedule a consultation to discuss your specific needs')); ?></p>

            <div class="weown-services-cta-buttons">
                <a href="<?php echo esc_url(get_permalink(get_page_by_path('contact'))); ?>" class="weown-services-primary-cta">
                    <?php echo esc_html(get_theme_mod('services_primary_cta', 'Schedule Consultation')); ?>
                </a>

                <?php if (get_theme_mod('services_show_quote_cta')) : ?>
                <a href="#get-quote" class="weown-services-secondary-cta">
                    <?php echo esc_html(get_theme_mod('services_quote_text', 'Get Free Quote')); ?>
                </a>
                <?php endif; ?>
            </div>
        </div>

    </div><!-- .weown-services-cta-container -->
</section><!-- .weown-services-cta -->

<?php
/**
 * Enhanced Footer for Business Pages
 *
 * Professional footer with service information, industry resources,
 * and additional expertise elements for complete service presentation.
 */
get_footer('business-services');
?>
