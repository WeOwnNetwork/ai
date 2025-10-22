# Assets Folder Analysis

**Last Updated**: 2025-10-22

---

## Current Assets Structure

```
assets/
├── css/
│   └── site.css (489 lines) - Main theme stylesheet
└── js/
    ├── site.js (9 lines) - Smooth scroll utility
    └── customizer-preview.js (414 lines) - Live preview (Phase 3.1)
```

---

## File-by-File Analysis

### **1. `/assets/css/site.css`**

**Purpose**: Main theme stylesheet for front-end rendering

**Current Status**: ⚠️ **NEEDS UPDATE** - Uses Phase 1 variable names

**What It Does**:
- Defines base styles (typography, layout, components)
- Uses CSS custom properties for theming
- Responsive design with mobile breakpoints
- Accessibility features (skip links, focus states)
- Print styles

**Issue**: Variable naming mismatch with Phase 3.1

**Phase 1 Variables (Old)**:
```css
:root {
    --weown-primary-color: #1e40af;
    --weown-secondary-color: #64748b;
    --weown-accent-color: #f59e0b;
}
```

**Phase 3.1 Variables (New)**:
```css
:root {
    --color-primary: #0066cc;
    --color-secondary: #ff5733;
    --color-accent: #17a2b8;
}
```

**Relationship to dynamic-css.php**:
- `dynamic-css.php` generates `:root` variables (injected in `<head>`)
- `site.css` should REFERENCE those variables (loaded as separate stylesheet)
- They work TOGETHER: dynamic-css sets values, site.css uses them

**Action Required**: Update variable names to match Phase 3.1 system

---

### **2. `/assets/js/site.js`**

**Purpose**: Front-end JavaScript utilities

**Current Status**: ✅ **GOOD** - Simple, focused, no dependencies

**What It Does**:
- Smooth scroll to anchors with `data-scrollto` attribute
- Event delegation for performance
- Zero dependencies (vanilla JS)

**Example Usage**:
```html
<a href="#contact" data-scrollto="contact">Contact</a>
```

**Integration**:
- Works independently of customizer
- No conflicts with customizer-preview.js
- Can be extended in Phase 3.2 for block interactions

**Action Required**: None - works as-is

---

### **3. `/assets/js/customizer-preview.js`**

**Purpose**: Live preview for WordPress Customizer (Phase 3.1)

**Current Status**: ✅ **COMPLETE** - Phase 3.1 implementation

**What It Does**:
- Listens to customizer changes via WordPress API
- Updates CSS variables in real-time
- Debounces rapid slider movements (100-150ms)
- Dynamically loads Google Fonts
- Zero page reload required

**When It Loads**:
- ONLY in customizer preview iframe
- NOT on front-end site
- Hooked via `customize_preview_init` action

**Integration**:
- Separate from site.js (different contexts)
- Uses WordPress `wp.customize` API
- Updates :root CSS variables set by dynamic-css.php

**Action Required**: None - complete and tested

---

## CSS Architecture Comparison

### **dynamic-css.php vs site.css**

| Aspect | dynamic-css.php | site.css |
|--------|----------------|----------|
| **Purpose** | Generate CSS variables | Use CSS variables |
| **When** | PHP runtime (server) | CSS load (browser) |
| **Where** | `<head>` inline style | External stylesheet |
| **Content** | `:root { --var: value; }` | `.class { color: var(--var); }` |
| **Dynamic** | YES - changes with customizer | NO - static styles |
| **Caching** | Transient (1 day) | Browser cache |
| **Size** | Small (~100 lines) | Large (~489 lines) |

### **How They Work Together**

```html
<head>
    <!-- 1. Dynamic CSS injected first (sets variables) -->
    <style id="weown-dynamic-css">
    :root {
        --color-primary: #0066cc;
        --font-heading: 'Inter', sans-serif;
        --spacing-base: 32px;
    }
    </style>
    
    <!-- 2. Site CSS loaded second (uses variables) -->
    <link rel="stylesheet" href="assets/css/site.css">
</head>

<body>
    <!-- 3. Elements use classes from site.css -->
    <h1 class="weown-page-title">
        <!-- This will be --font-heading at --font-size-h1 -->
    </h1>
</body>
```

### **Code Example**:

**dynamic-css.php generates**:
```css
:root {
    --color-primary: #0066cc;
    --color-primary-light: #3385d6;
    --color-primary-dark: #0052a3;
}
```

**site.css uses**:
```css
.weown-button {
    background-color: var(--color-primary);
}

.weown-button:hover {
    background-color: var(--color-primary-dark);
}
```

**Result**: Button color changes when user updates customizer!

---

## Optimization Status

### **Current Optimization Level**: ⭐⭐⭐ (3/5)

**What's Optimized** ✅:
- Vanilla JavaScript (no jQuery dependency in site.js)
- Event delegation for performance
- CSS containment for critical elements
- Lazy loading support
- Print styles
- Responsive images

**What Needs Optimization** ⚠️:
- CSS file size could be reduced (currently 489 lines)
- No critical CSS extraction
- No CSS minification
- No JavaScript minification
- No asset bundling/build process

**Recommended for Phase 3.4** 📅:
- Add build process (webpack/vite)
- Critical CSS extraction
- Asset minification
- Tree shaking for unused CSS
- Image optimization

---

## What Still Needs to Be Done

### **Immediate (Phase 3.1 Completion)** 🔴

1. **Update site.css variable names** ⚠️ CRITICAL
   ```css
   /* OLD */
   color: var(--weown-primary-color);
   
   /* NEW */
   color: var(--color-primary);
   ```

2. **Test CSS variable integration**
   - Verify dynamic-css.php injects before site.css loads
   - Confirm variables cascade properly
   - Check browser compatibility

3. **Add missing CSS variables**
   - Spacing system (--spacing-xs, --spacing-sm, etc.)
   - Typography scale (--font-size-h1, etc.)
   - Component variables (--shadow-md, --transition-base)

### **Phase 3.2 (Gutenberg Blocks)** 📅

1. **Create block-specific CSS**
   - Hero block styles
   - Feature block grid
   - Team member cards
   - CTA buttons

2. **Block editor styles**
   - `editor-style.css` for block editor
   - Match front-end rendering
   - Custom block controls

### **Phase 3.3 (Block Patterns)** 📅

1. **Pattern-specific styles**
   - Pre-designed layouts
   - Section combinations
   - Template variations

### **Phase 3.4 (MU-Plugins)** 📅

1. **Asset optimization plugin**
   - Minification
   - Concatenation
   - Critical CSS
   - Lazy loading

2. **Performance monitoring**
   - Asset load time tracking
   - CSS/JS bloat detection
   - Image optimization

---

## Enqueue Status

### **How Files Are Currently Loaded**:

**functions.php enqueue**:
```php
function weown_enqueue_assets() {
    // Main stylesheet
    wp_enqueue_style('weown-style', get_stylesheet_uri());
    
    // Site JavaScript
    wp_enqueue_script(
        'weown-site-js',
        get_template_directory_uri() . '/assets/js/site.js',
        [],
        '1.0.0',
        true
    );
}
add_action('wp_enqueue_scripts', 'weown_enqueue_assets');
```

**Customizer preview** (separate):
```php
function weown_customizer_preview_js() {
    wp_enqueue_script(
        'weown-customizer-preview',
        get_template_directory_uri() . '/assets/js/customizer-preview.js',
        ['customize-preview', 'jquery'],
        '1.0.0',
        true
    );
}
add_action('customize_preview_init', 'weown_customizer_preview_js');
```

**Dynamic CSS** (inline):
```php
function weown_inject_dynamic_css() {
    $css = weown_generate_dynamic_css(); // From dynamic-css.php
    echo '<style id="weown-dynamic-css">' . $css . '</style>';
}
add_action('wp_head', 'weown_inject_dynamic_css', 100);
```

---

## Browser Compatibility

### **CSS Custom Properties**:
- ✅ Chrome 49+
- ✅ Firefox 31+
- ✅ Safari 9.1+
- ✅ Edge 15+
- ❌ IE 11 (no support)

**Fallback Strategy**: Not implemented yet (Phase 3.4)

**Current Status**: Modern browsers only (96%+ global support)

---

## Summary & Next Steps

### **Current State**:
- ✅ site.js is production-ready
- ✅ customizer-preview.js is complete
- ⚠️ site.css needs variable name updates
- 📅 Optimization deferred to Phase 3.4

### **Action Items**:
1. **NOW**: Update site.css to use Phase 3.1 variable names
2. **NOW**: Test dynamic CSS injection order
3. **Phase 3.2**: Add block-specific styles
4. **Phase 3.4**: Implement asset optimization

### **Integration Success Criteria**:
- [ ] dynamic-css.php injects variables in `<head>`
- [ ] site.css loads after dynamic CSS
- [ ] All Phase 2 templates render with customizer values
- [ ] Live preview updates work in customizer
- [ ] No JavaScript console errors
- [ ] No CSS fallback issues

---

**Last Updated**: 2025-10-22  
**Status**: In Progress - Variable name update required
