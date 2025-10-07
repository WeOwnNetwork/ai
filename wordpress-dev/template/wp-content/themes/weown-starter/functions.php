<?php
if (!defined('ABSPATH')) { exit; }

add_action('wp_enqueue_scripts', function () {
  wp_enqueue_style('parent-style', get_template_directory_uri().'/style.css', [], wp_get_theme(get_template())->get('Version'));
  wp_enqueue_style('weown-starter-style', get_stylesheet_uri(), ['parent-style'], wp_get_theme()->get('Version'));
});

add_action('wp_enqueue_scripts', function () {
  if (!is_singular() || !is_page_template('templates/landing.php')) return;
  $base = get_stylesheet_directory_uri();
  $path = get_stylesheet_directory();
  $css  = 'assets/css/site.css';
  $js   = 'assets/js/site.js';
  $cv   = file_exists("$path/$css") ? filemtime("$path/$css") : null;
  $jv   = file_exists("$path/$js")  ? filemtime("$path/$js")  : null;
  wp_enqueue_style('weown-starter-page', "$base/$css", [], $cv);
  wp_enqueue_script('weown-starter-page', "$base/$js", [], $jv, true);
}, 20);
