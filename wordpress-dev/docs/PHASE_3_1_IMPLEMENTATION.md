# Phase 3.1: WordPress Customizer Integration

**Status**: 🔄 IN PROGRESS  
**Started**: 2025-10-22  
**Goal**: Enterprise-grade customizer system with live preview for global branding

---

## Overview

Phase 3.1 creates the **Global Branding Layer** - a WordPress Customizer integration that allows non-technical users to customize site-wide branding (colors, typography, logo, layout) with live preview. This layer feeds into Gutenberg blocks (Phase 3.2) via CSS custom properties for consistent branding.

### Key Architecture Decisions

**1. CSS Custom Properties Strategy**
- **Decision**: Use CSS variables (custom properties) for all brand values
- **Rationale**: Modern, performant, supports live preview without page reload
- **Implementation**: Inject `:root` variables via `wp_head` hook
- **Integration**: Blocks and templates reference these variables

**2. Customizer vs. theme.json**
- **Decision**: Use BOTH - Customizer for UI, theme.json for block editor defaults
- **Rationale**: Customizer provides better live preview UX, theme.json ensures block editor compatibility
- **WordPress 6.8+ Approach**: Hybrid approach is best practice for custom themes

**3. Google Fonts Integration**
- **Decision**: Dynamic font loading with GDPR-compliant self-hosting option
- **Rationale**: Performance + privacy, aligns with enterprise security standards
- **Implementation**: Use WebFontLoader for async loading, cache fonts locally

**4. File Structure**
- **Decision**: Modular architecture with separate concerns
- **Rationale**: Maintainability, scalability, follows WordPress best practices

---

## File Structure

```
template/wp-content/themes/weown-starter/
├── inc/
│   ├── customizer/
│   │   ├── customizer.php              # Main registration file
│   │   ├── customizer-controls.php     # Custom control classes
│   │   ├── customizer-sanitize.php     # Sanitization callbacks
│   │   └── customizer-defaults.php     # Default values
│   └── dynamic-css.php                 # CSS custom properties injection
├── assets/
│   ├── js/
│   │   ├── customizer-preview.js       # Live preview JS
│   │   └── customizer-controls.js      # Enhanced control UI
│   └── css/
│       └── customizer-controls.css     # Customizer panel styles
└── functions.php                       # Include customizer files
```

---

## Implementation Steps

### Step 1: File Structure Setup
**Files to Create**:
- `/inc/customizer/customizer.php`
- `/inc/customizer/customizer-controls.php`
- `/inc/customizer/customizer-sanitize.php`
- `/inc/customizer/customizer-defaults.php`
- `/inc/dynamic-css.php`
- `/assets/js/customizer-preview.js`
- `/assets/js/customizer-controls.js`
- `/assets/css/customizer-controls.css`

**Integration Point**: Add requires to `functions.php`

---

### Step 2: Customizer Panel Structure

**Panel**: `weown_theme_options`
- **Section**: Brand Colors
- **Section**: Typography
- **Section**: Logo & Branding
- **Section**: Layout & Spacing
- **Section**: Header Options
- **Section**: Footer Options
- **Section**: Performance & Features

**WordPress 6.8+ Best Practice**: Use selective refresh for performance

---

### Step 3: Brand Colors Section

**Controls**:
1. Primary Color (color picker)
2. Secondary Color (color picker)
3. Accent Color (color picker)
4. Text Color (color picker)
5. Background Color (color picker)
6. Heading Color (color picker)

**CSS Variables Generated**:
```css
:root {
  --color-primary: #value;
  --color-secondary: #value;
  --color-accent: #value;
  --color-text: #value;
  --color-background: #value;
  --color-heading: #value;
  /* Auto-generated shades */
  --color-primary-light: #value;
  --color-primary-dark: #value;
}
```

**Live Preview**: JavaScript updates CSS variables in real-time

---

### Step 4: Typography Section

**Controls**:
1. Heading Font Family (select with Google Fonts)
2. Body Font Family (select with Google Fonts)
3. Base Font Size (range: 14-20px)
4. Heading Scale (select: 1.125, 1.25, 1.333, 1.5, 1.618)
5. Line Height (range: 1.2-2.0)
6. Font Weight: Headings (select: 400-900)
7. Font Weight: Body (select: 300-700)

**CSS Variables Generated**:
```css
:root {
  --font-heading: 'Font Name', sans-serif;
  --font-body: 'Font Name', sans-serif;
  --font-size-base: 16px;
  --font-scale: 1.25;
  --line-height: 1.6;
  --font-weight-heading: 700;
  --font-weight-body: 400;
  /* Auto-calculated sizes */
  --font-size-h1: calc(var(--font-size-base) * var(--font-scale) * var(--font-scale) * var(--font-scale));
  --font-size-h2: calc(var(--font-size-base) * var(--font-scale) * var(--font-scale));
  /* ... etc */
}
```

**Google Fonts Integration**:
- Fetch available fonts from Google Fonts API
- Allow font weight/style selection
- Generate optimized embed URLs
- Self-hosting option for GDPR compliance

---

### Step 5: CSS Custom Properties Injection

**Function**: `weown_inject_dynamic_css()`
- Hooked to: `wp_head` (priority 100)
- Generates: Full `:root` CSS variable block
- Includes: Colors, typography, spacing, layout values
- Performance: Cached with transient API, invalidated on customizer save

**Integration with Existing CSS**:
- Theme CSS files reference CSS variables
- No hardcoded values in stylesheets
- Fallback values for unsupported browsers

---

### Step 6: Live Preview JavaScript

**File**: `/assets/js/customizer-preview.js`
**API**: WordPress Customizer Preview API
**Functionality**:
- Listen to customizer value changes
- Update CSS variables in preview iframe
- No page reload required for most changes
- Selective refresh for complex changes (logo, layout)

**Performance Optimization**:
- Debounced updates for rapid changes
- Batch CSS variable updates
- Minimal DOM manipulation

---

### Step 7: Logo Management

**Controls**:
1. Logo Upload (media library)
2. Logo Width (range: 50-400px)
3. Logo Height (auto or manual)
4. Retina Logo Upload (2x resolution)
5. Mobile Logo Upload (optional)
6. Logo Position (left, center, right)

**Implementation**:
- Use WordPress `custom-logo` theme support
- Add responsive sizing controls
- Support SVG, PNG, WebP formats
- Alt text from media library

---

### Step 8: Layout & Spacing Controls

**Controls**:
1. Container Width (range: 1024-1920px)
2. Content Width (range: 640-960px)
3. Section Spacing (range: 40-120px)
4. Element Spacing (range: 16-64px)
5. Border Radius (range: 0-32px)

**CSS Variables Generated**:
```css
:root {
  --container-width: 1200px;
  --content-width: 800px;
  --spacing-section: 80px;
  --spacing-element: 32px;
  --border-radius: 8px;
}
```

---

## Integration with Phases 1 & 2

### Existing Template Integration
**Current State**: Templates use hardcoded styles and helper functions
**Phase 3.1 Integration**: 
1. Update `/assets/css/style.css` to use CSS variables
2. Helper functions read from customizer values
3. Backward compatibility maintained

### Example Integration:
```php
// Phase 2 (old):
function weown_get_brand_colors() {
    return ['primary' => '#0066cc']; // Hardcoded
}

// Phase 3.1 (new):
function weown_get_brand_colors() {
    return [
        'primary' => get_theme_mod('primary_color', '#0066cc'),
        'secondary' => get_theme_mod('secondary_color', '#ff5733'),
        // ... etc
    ];
}
```

---

## Integration with Future Phases

### Phase 3.2: Gutenberg Blocks
**Blocks will**:
- Read CSS variables for consistent styling
- Inherit customizer settings automatically
- Provide block-specific overrides when needed

### Phase 4: REST API Integration
**API Endpoints will**:
- Accept bulk customizer settings via `/wp-json/weown/v1/customize`
- Update theme_mods programmatically
- Trigger cache invalidation
- Support n8n automation workflows

---

## WordPress 6.8+ Best Practices

### 1. Selective Refresh
```php
$wp_customize->selective_refresh->add_partial('setting_id', [
    'selector' => '.element-class',
    'render_callback' => 'callback_function',
]);
```

### 2. Sanitization
- All inputs sanitized with appropriate callbacks
- Color values: `sanitize_hex_color()`
- URLs: `esc_url_raw()`
- Text: `sanitize_text_field()`
- HTML: `wp_kses_post()`

### 3. Transport Methods
- `postMessage`: For live preview without reload (CSS changes)
- `refresh`: For complex changes requiring page reload (layout structure)

### 4. Default Values
- Always provide defaults in `get_theme_mod()`
- Centralize defaults in `customizer-defaults.php`
- Use constants for maintainability

---

## Testing Checklist

### Functionality Tests
- [ ] Customizer loads without errors
- [ ] All controls display correctly
- [ ] Color pickers work
- [ ] Font selectors populate
- [ ] Media uploads function
- [ ] Settings save correctly

### Live Preview Tests
- [ ] Color changes reflect immediately
- [ ] Typography updates work
- [ ] Logo changes display
- [ ] Spacing adjusts correctly
- [ ] No console errors

### Performance Tests
- [ ] Page load time < 2s
- [ ] No layout shift during load
- [ ] CSS variables apply before render
- [ ] Font loading doesn't block render
- [ ] Customizer opens quickly

### Compatibility Tests
- [ ] Works in Chrome, Firefox, Safari, Edge
- [ ] Mobile responsive
- [ ] Block editor compatibility
- [ ] Theme switcher compatibility
- [ ] Plugin compatibility (caching, security)

---

## Security Considerations

### 1. Capability Checks
```php
if (!current_user_can('edit_theme_options')) {
    return;
}
```

### 2. Nonce Verification
- WordPress Customizer handles nonces automatically
- Additional verification for AJAX calls

### 3. Input Sanitization
- NEVER trust user input
- Use WordPress sanitization functions
- Validate data types and ranges

### 4. Output Escaping
```php
echo esc_attr(get_theme_mod('setting'));
echo esc_html(get_theme_mod('text_setting'));
echo esc_url(get_theme_mod('url_setting'));
```

---

## Performance Optimizations

### 1. CSS Variables Caching
```php
$css = get_transient('weown_dynamic_css');
if (false === $css) {
    $css = weown_generate_dynamic_css();
    set_transient('weown_dynamic_css', $css, DAY_IN_SECONDS);
}
```

### 2. Font Loading Strategy
- Use `font-display: swap` for FOUT
- Preconnect to font CDN
- Self-host option for critical fonts
- Subset fonts to used characters

### 3. Lazy Loading
- Defer non-critical customizer JavaScript
- Load Google Fonts API only when needed
- Async font loading with WebFontLoader

---

## Documentation Requirements

### Code Documentation
- PHPDoc blocks for all functions
- Inline comments for complex logic
- Parameter and return type documentation

### User Documentation
- Customizer section descriptions
- Control tooltips and help text
- Video tutorial (future)

### Developer Documentation
- API reference for customizer functions
- Filter/action hooks documentation
- Extension guidelines

---

## Next Steps After Phase 3.1

1. **Phase 3.2**: Build Gutenberg blocks that inherit customizer settings
2. **Phase 3.3**: Create block patterns using customizer + blocks
3. **Phase 3.4**: Add MU-plugins for security and performance
4. **Phase 4**: REST API for n8n automation

---

**Version**: 1.0.0  
**Last Updated**: 2025-10-22  
**Maintainer**: WeOwn Development Team
