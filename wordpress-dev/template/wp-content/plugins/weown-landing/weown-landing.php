<?php
/**
 * Plugin Name: WeOwn Landing
 * Description: Adds vanity route /weown-landing and renders a template with scoped assets.
 * Version: 1.0.0
 */
if (!defined('ABSPATH')) { exit; }

register_activation_hook(__FILE__, function(){
  add_rewrite_rule('^weown-landing/?$', 'index.php?weown_landing=1', 'top');
  add_rewrite_tag('%weown_landing%', '1');
  flush_rewrite_rules();
});
register_deactivation_hook(__FILE__, function(){ flush_rewrite_rules(); });

add_action('init', function () {
  add_rewrite_rule('^weown-landing/?$', 'index.php?weown_landing=1', 'top');
  add_rewrite_tag('%weown_landing%', '1');
});

add_action('template_redirect', function () {
  if (get_query_var('weown_landing') !== '1') return;
  status_header(200); nocache_headers();
  get_header();
  echo '<main class="weown-wrap"><section class="weown-container"><h1>WeOwn Landing (Plugin Route)</h1></section></main>';
  get_footer();
  exit;
});
