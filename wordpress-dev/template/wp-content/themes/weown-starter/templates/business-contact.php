<?php
/**
 * WeOwn Starter Theme - Contact Business Page Template
 *
 * Professional contact page template with multiple contact methods,
 * location information, team contacts, and conversion-optimized forms.
 *
 * Features:
 * - Hero section with contact value proposition and key info
 * - Multiple contact methods (phone, email, address, map)
 * - Contact form with progressive profiling and smart routing
 * - Team member contact cards with direct communication
 * - Office locations and hours with interactive map
 * - FAQ section for common inquiries
 * - Call-to-action for immediate engagement
 * - Social media and communication preferences
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
 * Contact Page Configuration
 *
 * Get contact-specific configuration for optimal communication and
 * conversion based on business type and communication preferences.
 */
$contact_config = weown_get_contact_config();
$contact_type = $contact_config['type'] ?? 'business_contact';
$communication_style = $contact_config['style'] ?? 'professional_direct';
$response_time = $contact_config['response'] ?? '24_hour';

/**
 * Dynamic Contact Branding
 *
 * Load contact-specific branding with approachable color schemes and
 * communication-focused design elements for accessibility.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Business Pages
 *
 * Professional header with contact navigation and accessibility features
 * for easy communication and trust building.
 */
get_header('business-contact');
?>

<?php
/**
 * Contact Hero Section - Communication & Accessibility
 *
 * Approachable hero with clear contact information, response times, and
 * multiple communication methods for immediate accessibility.
 */
?>
<section class="weown-contact-hero">
    <div class="weown-contact-hero-container">

        <?php
        /**
         * Contact Value Proposition and Key Info
         *
         * Clear communication promise, response times, and
         * preferred contact methods for trust and accessibility.
         */
        ?>
        <div class="weown-contact-hero-content">
            <div class="weown-contact-urgency-badge">
                <span class="response-time-badge">
                    <?php echo esc_html($response_time); ?> Response Time
                </span>
            </div>

            <h1 class="weown-contact-hero-title">
                <?php echo esc_html(get_theme_mod('contact_hero_title', 'Let\'s Start a Conversation')); ?>
            </h1>

            <p class="weown-contact-hero-subtitle">
                <?php echo esc_html(get_theme_mod('contact_hero_subtitle', 'We\'re here to help with your questions and needs')); ?>
            </p>

            <?php
            /**
             * Key Contact Information and Methods
             *
             * Primary contact details, preferred communication methods, and
             * availability information for easy accessibility.
             */
            ?>
            <div class="weown-contact-hero-info">
                <?php weown_contact_key_information(); ?>
            </div>

            <?php
            /**
             * Communication Preferences and Best Practices
             *
             * Preferred contact methods, best times to reach out, and
             * communication guidelines for optimal response.
             */
            ?>
            <div class="weown-contact-hero-preferences">
                <?php weown_contact_communication_preferences($communication_style); ?>
            </div>
        </div><!-- .weown-contact-hero-content -->

        <?php
        /**
         * Contact Form Preview or Team Visual
         *
         * Contact form preview, team photo, or office environment
         * for personal connection and approachability.
         */
        ?>
        <div class="weown-contact-hero-visual">
            <?php weown_contact_hero_visual($contact_type); ?>
        </div>

    </div><!-- .weown-contact-hero-container -->
</section><!-- .weown-contact-hero -->

<?php
/**
 * Contact Methods Section
 *
 * Multiple communication channels with details, availability, and
 * direct action buttons for comprehensive accessibility.
 */
?>
<section class="weown-contact-methods">
    <div class="weown-contact-methods-container">

        <header class="weown-contact-section-header">
            <h2><?php echo esc_html(get_theme_mod('contact_methods_title', 'Multiple Ways to Reach Us')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('contact_methods_subtitle', 'Choose the method that works best for you')); ?></p>
        </header>

        <?php
        /**
         * Contact Channels and Information
         *
         * Phone, email, address, map, and other communication methods
         * with clear details and direct action capabilities.
         */
        ?>
        <div class="weown-contact-methods-grid">
            <?php weown_contact_methods_grid(); ?>
        </div>

    </div><!-- .weown-contact-methods-container -->
</section><!-- .weown-contact-methods -->

<?php
/**
 * Office Locations Section
 *
 * Physical office locations with addresses, hours, maps, and
 * local contact information for regional accessibility.
 */
?>
<?php if (get_theme_mod('contact_show_locations')) : ?>
<section class="weown-contact-locations">
    <div class="weown-contact-locations-container">

        <header class="weown-contact-section-header">
            <h2><?php echo esc_html(get_theme_mod('contact_locations_title', 'Our Locations')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('contact_locations_subtitle', 'Visit us or find us on the map')); ?></p>
        </header>

        <?php
        /**
         * Office Locations and Interactive Map
         *
         * Office addresses, business hours, local contact info, and
         * interactive map integration for physical accessibility.
         */
        ?>
        <div class="weown-contact-locations-content">
            <?php weown_contact_office_locations(); ?>
        </div>

    </div><!-- .weown-contact-locations-container -->
</section><!-- .weown-contact-locations -->
<?php endif; ?>

<?php
/**
 * Team Contact Section
 *
 * Key team member contact cards with roles, expertise, and
 * direct communication methods for personalized contact.
 */
?>
<?php if (get_theme_mod('contact_show_team')) : ?>
<section class="weown-contact-team">
    <div class="weown-contact-team-container">

        <header class="weown-contact-section-header">
            <h2><?php echo esc_html(get_theme_mod('contact_team_title', 'Meet Our Team')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('contact_team_subtitle', 'Connect directly with the right person for your needs')); ?></p>
        </header>

        <?php
        /**
         * Team Member Contact Profiles
         *
         * Team profiles with roles, expertise areas, direct contact
         * methods, and availability for personalized communication.
         */
        ?>
        <div class="weown-contact-team-grid">
            <?php weown_contact_team_profiles(); ?>
        </div>

    </div><!-- .weown-contact-team-container -->
</section><!-- .weown-contact-team -->
<?php endif; ?>

<?php
/**
 * Contact Form Section
 *
 * Smart contact form with progressive profiling, department routing,
 * and conversion optimization for lead generation.
 */
?>
<section class="weown-contact-form">
    <div class="weown-contact-form-container">

        <header class="weown-contact-section-header">
            <h2><?php echo esc_html(get_theme_mod('contact_form_title', 'Send Us a Message')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('contact_form_subtitle', 'We\'ll get back to you within ' . $response_time)); ?></p>
        </header>

        <?php
        /**
         * Progressive Contact Form
         *
         * Smart form with inquiry type selection, department routing,
         * priority levels, and conversion-optimized design.
         */
        ?>
        <div class="weown-contact-form-wrapper">
            <?php weown_contact_progressive_form($communication_style); ?>
        </div>

    </div><!-- .weown-contact-form-container -->
</section><!-- .weown-contact-form -->

<?php
/**
 * FAQ Section
 *
 * Common questions and answers for self-service support and
 * reduced inquiry volume for better efficiency.
 */
?>
<?php if (get_theme_mod('contact_show_faq')) : ?>
<section class="weown-contact-faq">
    <div class="weown-contact-faq-container">

        <header class="weown-contact-section-header">
            <h2><?php echo esc_html(get_theme_mod('contact_faq_title', 'Frequently Asked Questions')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('contact_faq_subtitle', 'Quick answers to common questions')); ?></p>
        </header>

        <?php
        /**
         * Contact-Related FAQ
         *
         * Common contact questions, response times, process explanations,
         * and self-service options for improved user experience.
         */
        ?>
        <div class="weown-contact-faq-accordion">
            <?php weown_contact_faq_section(); ?>
        </div>

    </div><!-- .weown-contact-faq-container -->
</section><!-- .weown-contact-faq -->
<?php endif; ?>

<?php
/**
 * Call-to-Action Section
 *
 * Final engagement CTA for immediate contact, consultation booking,
 * or next steps in the communication process.
 */
?>
<section class="weown-contact-cta">
    <div class="weown-contact-cta-container">

        <div class="weown-contact-cta-content">
            <h2><?php echo esc_html(get_theme_mod('contact_cta_title', 'Ready to Get In Touch?')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('contact_cta_subtitle', 'We\'re here and ready to help with your needs')); ?></p>

            <div class="weown-contact-cta-buttons">
                <a href="tel:<?php echo esc_attr(get_theme_mod('contact_primary_phone', '+1-555-0123')); ?>" class="weown-contact-primary-cta">
                    <?php echo esc_html(get_theme_mod('contact_primary_cta', 'Call Now')); ?>
                </a>

                <a href="#contact-form" class="weown-contact-secondary-cta">
                    <?php echo esc_html(get_theme_mod('contact_form_cta', 'Send Message')); ?>
                </a>
            </div>
        </div>

    </div><!-- .weown-contact-cta-container -->
</section><!-- .weown-contact-cta -->

<?php
/**
 * Enhanced Footer for Business Pages
 *
 * Professional footer with comprehensive contact information,
 * emergency contacts, and accessibility features for complete communication.
 */
get_footer('business-contact');
?>
