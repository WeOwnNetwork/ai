<?php
/**
 * Template Name: Landing Cohort Webinar
 * Description: Educational cohort programs and webinar registrations with countdown timers
 * @package WeOwn_Starter
 */
// Security check - prevent direct access
if (!defined('ABSPATH')) {
    exit;
}

/**
 * Cohort/Webinar Configuration
 *
 * Get event-specific configuration for optimal conversion and
 * community engagement based on cohort type and webinar format.
 */
$cohort_config = weown_get_cohort_config();
$cohort_type = $cohort_config['type'] ?? 'educational_cohort';
$event_format = $cohort_config['format'] ?? 'live_webinar';
$registration_goal = $cohort_config['goal'] ?? 'enrollment';

/**
 * Dynamic Event Branding
 *
 * Load event-specific branding with educational color schemes and
 * community-focused design elements for cohort positioning.
 */
$brand_config = weown_get_brand_config();
$brand_colors = weown_get_brand_colors($brand_config);

/**
 * Enhanced Header for Educational Events
 *
 * Community-focused header with event countdown and registration CTA
 * for immediate engagement and social proof building.
 */
get_header();
?>

<?php
/**
 * Event Hero Section - Urgency & Social Proof
 *
 * Time-sensitive hero with event countdown, enrollment numbers,
 * and immediate registration opportunity for maximum conversions.
 */
?>
<section class="weown-cohort-hero">
    <div class="weown-cohort-hero-container">

        <?php
        /**
         * Event Countdown and Urgency Elements
         *
         * Live countdown timer, enrollment numbers, and urgency
         * messaging to create FOMO and encourage immediate action.
         */
        ?>
        <div class="weown-cohort-hero-urgency">
            <?php weown_cohort_urgency_elements(); ?>
        </div>

        <?php
        /**
         * Event Positioning and Value Proposition
         *
         * Clear event positioning with learning outcomes and
         * community benefits for target audience resonance.
         */
        ?>
        <div class="weown-cohort-hero-content">
            <div class="weown-cohort-event-badge">
                <span class="event-type-badge">
                    <?php echo esc_html(ucfirst(str_replace('_', ' ', $cohort_type))); ?>
                </span>
            </div>

            <h1 class="weown-cohort-hero-title">
                <?php echo esc_html(get_theme_mod('cohort_hero_title', 'Join Our Exclusive Learning Community')); ?>
            </h1>

            <p class="weown-cohort-hero-subtitle">
                <?php echo esc_html(get_theme_mod('cohort_hero_subtitle', 'Transform your skills with expert-led training and peer collaboration')); ?>
            </p>

            <?php
            /**
             * Event Details and Key Benefits
             *
             * Event format, duration, key learning outcomes, and
             * immediate value proposition for registration decision.
             */
            ?>
            <div class="weown-cohort-event-details">
                <?php weown_cohort_event_details($event_format); ?>
            </div>

            <?php
            /**
             * Primary Registration CTA
             *
             * High-converting registration button with social proof
             * and urgency elements for immediate cohort enrollment.
             */
            ?>
            <div class="weown-cohort-hero-cta">
                <a href="#registration" class="weown-cohort-primary-cta">
                    <?php echo esc_html(get_theme_mod('cohort_primary_cta', 'Reserve Your Spot')); ?>
                </a>

                <a href="#curriculum" class="weown-cohort-secondary-cta">
                    <?php echo esc_html(get_theme_mod('cohort_secondary_cta', 'View Curriculum')); ?>
                </a>
            </div>
        </div><!-- .weown-cohort-hero-content -->

        <?php
        /**
         * Event Preview or Instructor Spotlight
         *
         * Instructor profile, event preview, or community
         * testimonial to build credibility and engagement.
         */
        ?>
        <div class="weown-cohort-hero-preview">
            <?php weown_cohort_hero_preview($cohort_type); ?>
        </div>

    </div><!-- .weown-cohort-hero-container -->
</section><!-- .weown-cohort-hero -->

<?php
/**
 * Curriculum/Program Overview Section
 *
 * Detailed curriculum breakdown with learning outcomes,
 * skill development path, and progression milestones.
 */
?>
<section id="curriculum" class="weown-cohort-curriculum">
    <div class="weown-cohort-curriculum-container">

        <header class="weown-cohort-section-header">
            <h2><?php echo esc_html(get_theme_mod('cohort_curriculum_title', 'Comprehensive Learning Journey')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('cohort_curriculum_subtitle', 'Structured curriculum designed for maximum skill development')); ?></p>
        </header>

        <?php
        /**
         * Interactive Curriculum Timeline
         *
         * Week-by-week or module-by-module curriculum with
         * learning objectives, projects, and outcomes.
         */
        ?>
        <div class="weown-cohort-curriculum-timeline">
            <?php weown_cohort_curriculum_timeline(); ?>
        </div>

    </div><!-- .weown-cohort-curriculum-container -->
</section><!-- .weown-cohort-curriculum -->

<?php
/**
 * Instructor/Expert Section
 *
 * Instructor profiles, expertise demonstrations, and
 * teaching methodology to establish credibility and trust.
 */
?>
<section class="weown-cohort-instructors">
    <div class="weown-cohort-instructors-container">

        <header class="weown-cohort-section-header">
            <h2><?php echo esc_html(get_theme_mod('cohort_instructors_title', 'Learn from Industry Experts')); ?></h2>
        </header>

        <?php
        /**
         * Instructor Profile Grid
         *
         * Expert profiles with credentials, experience, and
         * teaching style to build trust and credibility.
         */
        ?>
        <div class="weown-cohort-instructors-grid">
            <?php weown_cohort_instructor_profiles(); ?>
        </div>

    </div><!-- .weown-cohort-instructors-container -->
</section><!-- .weown-cohort-instructors -->

<?php
/**
 * Community & Networking Section
 *
 * Community features, networking opportunities, and peer
 * learning elements to highlight collaborative benefits.
 */
?>
<section class="weown-cohort-community">
    <div class="weown-cohort-community-container">

        <div class="weown-cohort-community-content">

            <header class="weown-cohort-section-header">
                <h2><?php echo esc_html(get_theme_mod('cohort_community_title', 'Join a Thriving Learning Community')); ?></h2>
                <p><?php echo esc_html(get_theme_mod('cohort_community_subtitle', 'Connect, collaborate, and grow together')); ?></p>
            </header>

            <?php
            /**
             * Community Features Showcase
             *
             * Peer interaction, networking events, alumni network,
             * and community building features and benefits.
             */
            ?>
            <div class="weown-cohort-community-features">
                <?php weown_cohort_community_features(); ?>
            </div>

        </div><!-- .weown-cohort-community-content -->

    </div><!-- .weown-cohort-community-container -->
</section><!-- .weown-cohort-community -->

<?php
/**
 * Registration Form Section
 *
 * Multi-step registration with progressive profiling,
 * payment options, and community onboarding elements.
 */
?>
<section id="registration" class="weown-cohort-registration">
    <div class="weown-cohort-registration-container">

        <div class="weown-cohort-registration-content">

            <?php
            /**
             * Registration Value Proposition
             *
             * Clear enrollment benefits, investment value, and
             * transformation outcomes for registration decision.
             */
            ?>
            <header class="weown-cohort-registration-header">
                <h2><?php echo esc_html(get_theme_mod('cohort_registration_title', 'Secure Your Spot Today')); ?></h2>
                <p><?php echo esc_html(get_theme_mod('cohort_registration_subtitle', 'Limited seats available - enroll now to guarantee your place')); ?></p>
            </header>

            <?php
            /**
             * Progressive Registration Form
             *
             * Multi-step form with basic info, payment options,
             * and community preferences for complete onboarding.
             */
            ?>
            <div class="weown-cohort-registration-form">
                <?php weown_cohort_registration_form($cohort_type); ?>
            </div>

            <?php
            /**
             * Enrollment Benefits and Guarantees
             *
             * Investment protection, satisfaction guarantees, and
             * post-enrollment support for risk reduction.
             */
            ?>
            <div class="weown-cohort-registration-benefits">
                <?php weown_cohort_enrollment_benefits(); ?>
            </div>

        </div><!-- .weown-cohort-registration-content -->

    </div><!-- .weown-cohort-registration-container -->
</section><!-- .weown-cohort-registration -->

<?php
/**
 * Testimonials & Success Stories Section
 *
 * Alumni testimonials, success metrics, and transformation
 * stories to demonstrate program effectiveness and outcomes.
 */
?>
<section class="weown-cohort-testimonials">
    <div class="weown-cohort-testimonials-container">

        <header class="weown-cohort-section-header">
            <h2><?php echo esc_html(get_theme_mod('cohort_testimonials_title', 'Success Stories from Our Community')); ?></h2>
        </header>

        <?php
        /**
         * Video Testimonials and Case Studies
         *
         * Authentic alumni stories, transformation journeys, and
         * specific outcomes achieved through the program.
         */
        ?>
        <div class="weown-cohort-testimonials-grid">
            <?php weown_cohort_success_stories(); ?>
        </div>

    </div><!-- .weown-cohort-testimonials-container -->
</section><!-- .weown-cohort-testimonials -->

<?php
/**
 * FAQ Section (Educational Focus)
 *
 * Comprehensive Q&A addressing common concerns about time commitment,
 * learning curve, community dynamics, and post-program support.
 */
?>
<section class="weown-cohort-faq">
    <div class="weown-cohort-faq-container">

        <header class="weown-cohort-section-header">
            <h2><?php echo esc_html(get_theme_mod('cohort_faq_title', 'Common Questions')); ?></h2>
        </header>

        <div class="weown-cohort-faq-accordion">
            <?php weown_cohort_educational_faq(); ?>
        </div>

    </div><!-- .weown-cohort-faq-container -->
</section><!-- .weown-cohort-faq -->

<?php
/**
 * Final Enrollment CTA Section
 *
 * Last-chance enrollment with countdown reinforcement,
 * bonus offers, and community preview elements.
 */
?>
<section class="weown-cohort-final-cta">
    <div class="weown-cohort-final-cta-container">

        <div class="weown-cohort-final-cta-content">
            <h2><?php echo esc_html(get_theme_mod('cohort_final_cta_title', 'Don\'t Miss This Opportunity')); ?></h2>
            <p><?php echo esc_html(get_theme_mod('cohort_final_cta_subtitle', 'Spots are filling up fast - secure your place in our next cohort')); ?></p>

            <?php
            /**
             * Final Enrollment Countdown
             *
             * Live countdown with enrollment numbers and urgency
             * messaging for final conversion push.
             */
            ?>
            <div class="weown-cohort-final-countdown">
                <?php weown_cohort_enrollment_countdown(); ?>
            </div>

            <div class="weown-cohort-final-cta-buttons">
                <a href="#registration" class="weown-cohort-final-primary-cta">
                    <?php echo esc_html(get_theme_mod('cohort_final_primary_text', 'Enroll Now')); ?>
                </a>

                <?php if (get_theme_mod('cohort_show_payment_plans')) : ?>
                <a href="#payment-options" class="weown-cohort-payment-cta">
                    <?php echo esc_html(get_theme_mod('cohort_payment_cta_text', 'View Payment Options')); ?>
                </a>
                <?php endif; ?>
            </div>
        </div>

    </div><!-- .weown-cohort-final-cta-container -->
</section><!-- .weown-cohort-final-cta -->

<?php
if (have_posts()) :
    while (have_posts()) : the_post();
        ?>
        <main id="primary" class="weown-page-content weown-cohort-custom-content">
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
 * Enhanced Footer for Educational Events
 *
 * Community resources, upcoming events, alumni network access,
 * and final touchpoints for ongoing engagement.
 */
get_footer();
?>
