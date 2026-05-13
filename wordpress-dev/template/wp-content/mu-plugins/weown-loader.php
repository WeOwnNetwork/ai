<?php
if (!defined('ABSPATH')) { exit; }
$dir = __DIR__ . '/weown';
if (is_dir($dir)) { foreach (glob($dir.'/*.php') as $f) require_once $f; }
