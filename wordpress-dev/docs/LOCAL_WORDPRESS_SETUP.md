# Local WordPress Setup Guide

**Purpose**: Test Phase 3.1 Customizer implementation in real WordPress environment

---

## **Option 1: LocalWP (Recommended - Easiest)**

### **1. Install LocalWP**
```bash
# Download from https://localwp.com/
# Or install via Homebrew
brew install --cask local
```

### **2. Create New Site**
1. Open LocalWP
2. Click "+" to create new site
3. **Site Name**: `weown-dev`
4. **Environment**: 
   - PHP: **8.2** (WordPress 6.8+ compatible)
   - Web Server: **nginx**
   - Database: **MySQL 8.0**
5. **WordPress**:
   - Username: `admin`
   - Password: (generate secure)
   - Email: your email
6. Click "Add Site"

### **3. Install Theme**
```bash
# Navigate to site directory
cd ~/Local\ Sites/weown-dev/app/public/wp-content/themes/

# Copy our theme
cp -r /Users/romandidomizio/WeOwn/ai/wordpress-dev/template/wp-content/themes/weown-starter ./

# Set permissions
chmod -R 755 weown-starter
```

### **4. Activate Theme**
1. Open site: `http://weown-dev.local/wp-admin`
2. Go to **Appearance → Themes**
3. Click "Activate" on **WeOwn Starter**

### **5. Test Customizer**
1. Go to **Appearance → Customize**
2. Look for **"WeOwn Theme Options"** panel
3. Test all sections:
   - Brand Colors (7 controls)
   - Typography (8 controls)
   - Logo & Branding (4 controls)
   - Layout & Spacing (6 controls)
   - Header Options (3 controls)
   - Footer Options (1 control)
   - Performance & Features (2 controls)
4. **Test Live Preview**:
   - Change primary color → Button colors update instantly
   - Change font → Typography updates live
   - Adjust spacing → Layout changes in real-time

---

## **Option 2: Docker (For Advanced Users)**

### **1. Create docker-compose.yml**
```yaml
version: '3.8'

services:
  wordpress:
    image: wordpress:6.8-php8.2-apache
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
      WORDPRESS_DB_NAME: wordpress
    volumes:
      - ./template/wp-content/themes/weown-starter:/var/www/html/wp-content/themes/weown-starter
    depends_on:
      - db

  db:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: wordpress
      MYSQL_ROOT_PASSWORD: rootpassword
    volumes:
      - db_data:/var/lib/mysql

volumes:
  db_data:
```

### **2. Start WordPress**
```bash
cd /Users/romandidomizio/WeOwn/ai/wordpress-dev
docker-compose up -d
```

### **3. Access WordPress**
- **URL**: http://localhost:8080
- **Complete Installation**:
  - Site Title: WeOwn Dev
  - Username: admin
  - Password: (secure password)
  - Email: your email
- **Activate Theme**: Appearance → Themes → WeOwn Starter

### **4. Stop WordPress**
```bash
docker-compose down
```

---

## **Option 3: MAMP/XAMPP (Traditional)**

### **1. Install MAMP**
```bash
# Download from https://www.mamp.info/
# Or install via Homebrew
brew install --cask mamp
```

### **2. Download WordPress**
```bash
cd /Applications/MAMP/htdocs
curl -O https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz
mv wordpress weown-dev
rm latest.tar.gz
```

### **3. Create Database**
1. Open MAMP
2. Start Servers
3. Go to http://localhost:8888/phpMyAdmin
4. Create database: `weown_dev`

### **4. Install WordPress**
1. Visit: http://localhost:8888/weown-dev
2. Follow installation wizard
3. Database settings:
   - Name: `weown_dev`
   - Username: `root`
   - Password: `root`
   - Host: `localhost`

### **5. Copy Theme**
```bash
cp -r /Users/romandidomizio/WeOwn/ai/wordpress-dev/template/wp-content/themes/weown-starter \
     /Applications/MAMP/htdocs/weown-dev/wp-content/themes/
```

### **6. Activate & Test**
- Appearance → Themes → Activate WeOwn Starter
- Appearance → Customize → WeOwn Theme Options

---

## **Quick Start Command (LocalWP Recommended)**

```bash
# 1. Install LocalWP
brew install --cask local

# 2. Create site manually via LocalWP GUI
# (See Option 1 above)

# 3. Copy theme
cp -r /Users/romandidomizio/WeOwn/ai/wordpress-dev/template/wp-content/themes/weown-starter \
     ~/Local\ Sites/weown-dev/app/public/wp-content/themes/

# 4. Open site
open http://weown-dev.local/wp-admin
```

---

## **Testing Checklist**

### **Customizer Access**
- [ ] Customizer panel loads without errors
- [ ] "WeOwn Theme Options" panel exists
- [ ] All 7 sections visible
- [ ] All 31 controls render properly

### **Brand Colors Section**
- [ ] Primary color picker works
- [ ] Secondary color picker works
- [ ] Accent color picker works
- [ ] Text color picker works
- [ ] Heading color picker works
- [ ] Background color picker works
- [ ] Secondary background picker works
- [ ] Live preview updates colors instantly

### **Typography Section**
- [ ] Heading font dropdown shows Google Fonts
- [ ] Body font dropdown shows Google Fonts
- [ ] Base font size slider works (14-24px)
- [ ] Font scale selector works
- [ ] Body line height slider works
- [ ] Heading line height slider works
- [ ] Heading font weight selector works
- [ ] Body font weight selector works
- [ ] Live preview updates typography
- [ ] Google Fonts load dynamically

### **Logo & Branding Section**
- [ ] Logo width desktop slider works (50-500px)
- [ ] Logo width mobile slider works (50-300px)
- [ ] Retina logo upload works
- [ ] Mobile logo upload works
- [ ] Logo displays on front-end

### **Layout & Spacing Section**
- [ ] Container width slider works (960-1920px)
- [ ] Content width slider works (640-1200px)
- [ ] Section spacing top slider works (40-160px)
- [ ] Section spacing bottom slider works (40-160px)
- [ ] Element spacing slider works (16-80px)
- [ ] Border radius slider works (0-32px)
- [ ] Live preview updates spacing

### **Header Options Section**
- [ ] Sticky header checkbox works
- [ ] CTA button text input works
- [ ] CTA button URL input works
- [ ] Live preview updates header

### **Footer Options Section**
- [ ] Copyright textarea works
- [ ] {{YEAR}} placeholder works
- [ ] {{SITE_NAME}} placeholder works
- [ ] Live preview updates footer

### **Performance & Features Section**
- [ ] Lazy load images checkbox works
- [ ] Analytics ID input works
- [ ] GA4 format validation works (G-XXXXXXXXXX)
- [ ] UA format validation works (UA-XXXXXXXX-X)

### **Dynamic CSS Injection**
- [ ] View page source → Find `<style id="weown-dynamic-css">`
- [ ] CSS contains `:root { --color-primary: ...; }`
- [ ] CSS variables match customizer values
- [ ] CSS loads before site.css

### **JavaScript Console**
- [ ] No JavaScript errors in console
- [ ] customizer-preview.js loads in customizer
- [ ] site.js loads on front-end
- [ ] No 404 errors for assets

### **Front-End Rendering**
- [ ] Home page uses customizer colors
- [ ] Buttons use correct colors
- [ ] Typography matches customizer settings
- [ ] Spacing matches customizer values
- [ ] Layout widths correct

### **Browser Compatibility**
- [ ] Chrome (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)

---

## **Troubleshooting**

### **Issue: Customizer panel doesn't appear**

**Solution**:
```bash
# Check theme is activated
# Check for PHP errors in debug.log

# Enable WordPress debugging
# Add to wp-config.php:
define('WP_DEBUG', true);
define('WP_DEBUG_LOG', true);
define('WP_DEBUG_DISPLAY', false);

# Check error log
tail -f wp-content/debug.log
```

### **Issue: Live preview doesn't work**

**Solution**:
```bash
# Check browser console for JavaScript errors
# Verify customizer-preview.js is loaded
# Check wp_enqueue_script hook is firing
```

### **Issue: CSS variables not applied**

**Solution**:
```bash
# View page source
# Look for <style id="weown-dynamic-css">
# Verify CSS variables are injected
# Check dynamic-css.php is loaded in functions.php
```

### **Issue: Google Fonts not loading**

**Solution**:
```bash
# Check browser console for font errors
# Verify @import in dynamic CSS
# Test font URL manually
```

---

## **Recommended: LocalWP**

**Why LocalWP is Best**:
- ✅ One-click WordPress setup
- ✅ Automatic SSL (https://)
- ✅ Easy domain management (.local)
- ✅ Built-in database management
- ✅ No manual server configuration
- ✅ Works offline
- ✅ Free and open source

**Alternative for Production Testing**:
- Deploy to Kubernetes WordPress instance
- Test with real domain and SSL
- Validate performance at scale

---

**Next Steps After Setup**:
1. Test all customizer controls
2. Validate live preview
3. Check CSS variable injection
4. Test cross-browser compatibility
5. Document any issues found
6. Proceed to Phase 3.2 (Gutenberg Blocks)

---

**Last Updated**: 2025-10-22  
**Status**: Ready for testing
