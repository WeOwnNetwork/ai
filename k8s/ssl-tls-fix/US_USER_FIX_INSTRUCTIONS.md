# Fix Instructions for US User

## Quick Fix (Temporary - Works Immediately)

### Option 1: Change DNS to Google DNS

**Windows:**
1. Open Control Panel → Network and Internet → Network and Sharing Center
2. Click on your active network connection
3. Click "Properties"
4. Select "Internet Protocol Version 4 (TCP/IPv4)"
5. Click "Properties"
6. Select "Use the following DNS server addresses"
7. Enter:
   - Preferred: `8.8.8.8`
   - Alternate: `8.8.4.4`
8. Click "OK"
9. Open Command Prompt as Administrator
10. Run: `ipconfig /flushdns`
11. Restart browser
12. Test sites

**Mac:**
1. System Preferences → Network
2. Select your network connection
3. Click "Advanced"
4. Go to "DNS" tab
5. Click "+" and add: `8.8.8.8`
6. Click "+" and add: `8.8.4.4`
7. Click "OK"
8. Open Terminal
9. Run: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`
10. Restart browser
11. Test sites

### Option 2: Use Cloudflare DNS

**Windows/Mac:**
Same steps as above, but use:
- Preferred: `1.1.1.1`
- Alternate: `1.0.0.1`

### Option 3: Use VPN (Already Works)

If VPN works, continue using it until DNS propagates (24-48 hours).

## Why This Works

Your ISP's DNS servers in the US still have old/cached DNS records. Google DNS and Cloudflare DNS have updated records, so they resolve correctly.

## Verify DNS is Working

After changing DNS, verify in Command Prompt (Windows) or Terminal (Mac):

```bash
nslookup ai.yonksteam.xyz 8.8.8.8
nslookup matomo.yonksteam.xyz 8.8.8.8
nslookup n8n.yonksteam.xyz 8.8.8.8
nslookup vault.yonksteam.xyz 8.8.8.8
```

All should show: `134.199.133.94`

## Expected Timeline

**After changing DNS:**
- Should work immediately (within 1-2 minutes)
- No need to wait for ISP DNS to update

**If you revert to ISP DNS:**
- Will work after 24-48 hours (when ISP DNS updates)
- Or when DNS TTL expires (currently ~52 minutes for some domains)

## Why Only yonksteam.xyz Works

The main domain (`yonksteam.xyz`) might have updated faster in your ISP's DNS servers, while subdomains (`ai.yonksteam.xyz`, etc.) are still pointing to old IPs or have different TTL values.

## Permanent Fix

This is a DNS propagation issue that will resolve automatically in 24-48 hours as ISP DNS servers update. The temporary fix (changing DNS) works immediately and is safe to use permanently.

