# Yonks Cluster SSL/TLS Fix

## The Problem

We had SSL handshake failures on the Yonks cluster. Apps worked fine inside the cluster but failed on mobile browsers, and sometimes on desktop too.

**Error:**
```
SSL_do_handshake() failed (SSL: error:0A00010B) - HTTP hitting HTTPS port 443
```

**Root Cause:**
Two Load Balancers were pointing to the same nodes, causing routing conflicts:
- App Load Balancer: `cbc86166-2cf0-46b5-a21f-d53d9066a87f` (134.199.133.94) - active
- Old Portainer Load Balancer: `124b7cc4-1249-430c-9303-4b3e399df2b3` (134.199.132.124) - unused but causing conflicts

## Affected Applications

All applications on IP `134.199.133.94`:
- `yonksteam.xyz`
- `ai.yonksteam.xyz`
- `matomo.yonksteam.xyz`
- `n8n.yonksteam.xyz`
- `vault.yonksteam.xyz`

## Scripts

Three scripts to help diagnose and fix this issue:

### `yonks-ssl-diagnostic.sh`
Runs diagnostics to check for SSL issues and load balancer conflicts.

```bash
cd k8s/ssl-tls-fix
chmod +x yonks-ssl-diagnostic.sh
./yonks-ssl-diagnostic.sh
```

Checks cluster context, ingress-nginx pods, NGINX logs, ingress configs, SSL connectivity, and certificates.

### `yonks-ssl-fix.sh`
Removes the old load balancer and restarts ingress.

```bash
cd k8s/ssl-tls-fix
chmod +x yonks-ssl-fix.sh
./yonks-ssl-fix.sh
```

The script:
1. Checks prerequisites (kubectl, doctl)
2. Finds load balancer services
3. Removes old load balancer (via doctl or manual instructions)
4. Verifies app load balancer is healthy
5. Restarts ingress-nginx pods
6. Waits 60 seconds for propagation
7. Tests SSL connectivity
8. Checks NGINX logs for errors

You'll need `kubectl` configured. `doctl` is optional but helpful for automated LB removal.

### `yonks-ssl-verify.sh`
Verifies everything is working after the fix.

```bash
cd k8s/ssl-tls-fix
chmod +x yonks-ssl-verify.sh
./yonks-ssl-verify.sh
```

Tests load balancers, certificates, HTTP redirects, SSL protocols, and app accessibility. Returns exit codes: 0 (success), 1 (warnings), 2 (failures).

## Manual Fix (if scripts don't work)

### Step 1: Remove Old Load Balancer
1. Go to DigitalOcean Console → Networking → Load Balancers
2. Find LB ID: `124b7cc4-1249-430c-9303-4b3e399df2b3`
3. Delete it
4. Wait 2-5 minutes for deletion

### Step 2: Verify App Load Balancer
Make sure the app LB (`cbc86166-2cf0-46b5-a21f-d53d9066a87f`) is active with IP `134.199.133.94`.

### Step 3: Restart Ingress-NGINX
```bash
kubectl delete pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx
kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -w
```

### Step 4: Test
```bash
for domain in yonksteam.xyz ai.yonksteam.xyz matomo.yonksteam.xyz n8n.yonksteam.xyz vault.yonksteam.xyz; do
  echo "Testing $domain..."
  curl -I "https://$domain"
done
```

## Success Criteria

- All apps work on mobile devices
- All apps work on desktop browsers
- No SSL errors in NGINX logs
- Only one load balancer active
- HTTP redirects to HTTPS
- Certificates valid  

## Troubleshooting

### Issue: Script fails with "doctl not found"
**Solution:** Install doctl or use manual fix steps above

### Issue: Old Load Balancer still exists after running script
**Solution:** 
1. Check DigitalOcean console manually
2. Verify LB ID is correct
3. Delete via console if needed

### Issue: SSL errors persist after fix
**Solution:**
1. Check NGINX logs: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100`
2. Verify certificates: `kubectl get certificate --all-namespaces`
3. Check ingress annotations: `kubectl get ingress --all-namespaces -o yaml | grep -A 5 "annotations:"`

### Issue: Applications still not accessible
**Solution:**
1. Verify DNS propagation (wait 5-10 minutes)
2. Check firewall rules
3. Verify ingress resources are correct
4. Check service endpoints: `kubectl get endpoints --all-namespaces`

## Platform-Level Changes

- Remove old/unused load balancer (eliminates routing conflicts)
- Restart ingress-nginx pods to clear cached routing (30-60 seconds downtime)
- Wait 5-10 minutes for DNS propagation after LB removal

## Code-Level Notes

The ingress configs already have proper SSL/TLS settings (force-ssl-redirect, TLS 1.2/1.3, cert-manager). No code changes needed - this was an infrastructure issue (dual load balancer conflict).

## Prevention

- Run diagnostic script monthly
- Remove unused load balancers immediately
- Monitor SSL errors in NGINX logs
- Keep track of all load balancers and their purposes

## Support

If issues persist:
1. Run the diagnostic script
2. Check NGINX logs
3. Verify load balancer status in DigitalOcean
4. Contact the team if needed

