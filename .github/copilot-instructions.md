# WeOwn AI Infrastructure - GitHub Copilot Code Review Instructions

## Repository Overview

**Purpose**: Enterprise-grade, production-ready AI infrastructure for WeOwn's decentralized agentic ecosystem.

**Stack**: Kubernetes-native deployments (DigitalOcean K8s 1.33.1) with Helm charts, Docker containers, and zero-trust security architecture.

**Applications**: AnythingLLM (AI assistant), WordPress (CMS), Matomo (analytics), Vaultwarden (secrets), n8n (automation) - all with SOC2/ISO/IEC 42001 compliance.

**Deployment Philosophy**: Self-contained Helm charts, official images (no Bitnami dependencies), enterprise security by default, cohort replication ready.

---

## Critical: SOC2 Compliance Requirements

### Trust Services Criteria - ALL REQUIRED

#### 1. Security Controls (MANDATORY)
- **Access Control**: RBAC configured for all K8s namespaces, ServiceAccounts with least privilege, no cluster-admin bindings
- **Network Security**: NetworkPolicy resources REQUIRED for all deployments (deny-all ingress + explicit allow rules)
- **Authentication**: 2FA/MFA for admin access, Machine Identity for service accounts (e.g., Infisical Universal Auth)
- **Encryption in Transit**: TLS 1.3 ONLY via cert-manager/Let's Encrypt, strong cipher suites configured in Ingress annotations
- **Encryption at Rest**: Kubernetes etcd encryption enabled, PVC encryption via storage class, secrets encrypted at rest
- **Vulnerability Management**: Container images scanned for CVEs, non-root users (UID 1000+), minimal base images (Alpine/distroless)
- **Intrusion Detection**: Pod Security Standards "restricted" profile enforced, readOnlyRootFilesystem where possible
- **Secret Management**: Never use --from-literal, always use $(mktemp) for temp files, Kubernetes secrets with proper RBAC

#### 2. Availability Controls (MANDATORY)
- **Service Level Guarantees**: Resource requests/limits defined, HPA for production workloads, PodDisruptionBudgets for critical services
- **Failover**: Multi-replica deployments for stateless workloads, StatefulSets for databases with persistent storage
- **Health Checks**: livenessProbe and readinessProbe REQUIRED for all containers, proper grace periods configured
- **Backup & Recovery**: CronJob-based backups with 30-day retention minimum, documented restore procedures, tested recovery

#### 3. Processing Integrity Controls (MANDATORY)
- **Data Validation**: Input sanitization in all user-facing applications, content security policies, CSRF protection
- **Completeness**: Audit logs for all administrative actions, immutable log storage, retention policies documented
- **Accuracy**: Automated testing (unit, integration, E2E) before production deployment, validation scripts in CI/CD
- **Timeliness**: Monitoring and alerting for processing delays, SLO/SLI tracking, incident response procedures

#### 4. Confidentiality Controls (MANDATORY)
- **Data Classification**: Secrets vs ConfigMaps properly segregated, PII identified and encrypted, data flow diagrams maintained
- **Access Restrictions**: Namespace isolation, service mesh policies (if applicable), no cross-namespace access without justification
- **Secure Transmission**: No plain HTTP, all inter-service communication over TLS, DNS over TLS where supported

#### 5. Privacy Controls (IF APPLICABLE)
- **GDPR/CCPA**: Data minimization, right to erasure, consent management, privacy policies documented
- **Data Retention**: Automatic PVC cleanup after retention period, backup rotation policies, secure deletion procedures
- **Third-Party Sharing**: DPA agreements with cloud providers, data processing addendums, vendor risk assessments

### SOC2 Audit Evidence Requirements
- **90-day audit logs**: Centralized logging (e.g., Elasticsearch/Loki), tamper-proof storage, compliance reports generated
- **Change management**: Git-based deployments only, PRs required for main branch, approval workflows, rollback procedures
- **Incident response**: Documented procedures, escalation paths, post-mortem reports, corrective actions tracked
- **Access reviews**: Quarterly RBAC audits, ServiceAccount cleanup, SSH key rotation, credential rotation schedules

---

## Critical: ISO/IEC 42001 AI Management System Requirements

### Annex A: AI Risk Management Controls

#### AI System Lifecycle (ISO 5338)
- **Design Phase**: Impact assessments (ISO 42005), ethical considerations (ISO 24368), bias mitigation strategies
- **Development**: Model versioning, training data lineage, reproducibility requirements, validation datasets
- **Deployment**: Canary releases, A/B testing, gradual rollouts, monitoring for drift
- **Monitoring**: Performance metrics, accuracy tracking, fairness metrics, model degradation alerts
- **Retirement**: Decommissioning procedures, data retention policies, model archival

#### AI-Specific Security Controls
- **Model Security**: Adversarial robustness testing, input validation, rate limiting on inference APIs
- **Data Governance**: Training data provenance, bias audits, data lineage tracking, GDPR compliance for training data
- **Transparency**: Model cards, explainability requirements, decision audit trails, user consent for AI processing
- **Human Oversight**: Human-in-the-loop validation, override mechanisms, escalation procedures, appeal processes

#### Risk Assessment (ISO 23894 + ISO 31000)
- **AI Risk Sources** (Annex C):
  - Data quality issues (poisoning, drift, bias)
  - Model failures (overfitting, hallucinations, confidence miscalibration)
  - Privacy violations (membership inference, data leakage)
  - Security threats (adversarial attacks, model extraction)
  - Ethical concerns (discrimination, fairness, accountability)
- **Risk Mitigation**: Document risk register, implement controls, monitor effectiveness, periodic reviews

### ISO/IEC 42001 Documentation Requirements
- **AI Management Policy**: Defined objectives, scope, governance structure, roles/responsibilities
- **Risk Management Framework**: Risk assessment procedures, risk treatment plans, residual risk acceptance
- **Impact Assessments**: Societal impact, ethical implications, environmental considerations, stakeholder analysis
- **Performance Monitoring**: KPIs defined, dashboards implemented, periodic reviews, continuous improvement
- **Compliance Tracking**: Gap analysis documented, corrective actions tracked, audit readiness maintained

### AI Governance (ISO 38500/38507)
- **Board Oversight**: AI strategy alignment, resource allocation, risk appetite definition, policy approval
- **Accountability**: Clear ownership, decision authority, escalation paths, liability allocation
- **Vendor Management**: Third-party AI services vetted, contracts reviewed, SLAs enforced, exit strategies
- **Continuous Learning**: Training programs, competency frameworks, knowledge sharing, lessons learned

---

## Security Best Practices - ENFORCE STRICTLY

### Secrets Management (CRITICAL)
```bash
# ✅ CORRECT: Use mktemp for temporary files
AUTH_FILE="$(mktemp)"
trap 'rm -f "$AUTH_FILE"' EXIT
cat > "$AUTH_FILE" << 'EOF'
clientId=VALUE
clientSecret=VALUE
EOF
kubectl create secret generic NAME --from-env-file="$AUTH_FILE"

# ❌ WRONG: Never use /tmp (world-readable)
cat > /tmp/secrets.env  # REJECT THIS IN CODE REVIEW

# ❌ WRONG: Never use --from-literal (shell history exposure)
kubectl create secret --from-literal=key=value  # REJECT THIS
```

### Kubernetes RBAC (REQUIRED)
```yaml
# ✅ CORRECT: Least privilege ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-role
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]  # ONLY what's needed
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-binding
subjects:
- kind: ServiceAccount
  name: app-sa
roleRef:
  kind: Role
  name: app-role
  apiGroup: rbac.authorization.k8s.io
```

### Pod Security Standards (MANDATORY)
```yaml
# ✅ CORRECT: Restricted profile
securityContext:
  runAsNonRoot: true
  runAsUser: 1000  # Or appropriate UID (33 for www-data, 999 for mysql)
  runAsGroup: 1000
  fsGroup: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true  # Prefer this, use false only if required
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault

# ❌ WRONG: Running as root
securityContext:
  runAsUser: 0  # REJECT THIS
  privileged: true  # REJECT THIS
```

### NetworkPolicy (REQUIRED FOR ALL DEPLOYMENTS)
```yaml
# ✅ CORRECT: Deny-all ingress + explicit allow
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-netpol
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53  # DNS only
```

### TLS Configuration (MANDATORY)
```yaml
# ✅ CORRECT: Strong TLS 1.3 with cipher suites
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-ciphers: "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305"
```

---

## Helm Chart Best Practices - ENFORCE

### Templating Standards
```yaml
# ✅ CORRECT: Use .Values.global.namespace pattern for consistency
namespace: {{ .Values.global.namespace | default .Release.Namespace }}

# ✅ CORRECT: Always provide defaults and required checks
replicas: {{ .Values.replicaCount | default 1 }}
image: {{ .Values.image.repository | required "image.repository is required" }}

# ✅ CORRECT: Conditional rendering with proper hasKey checks
{{- if .Values.mariadbOfficial }}
{{- if hasKey .Values.mariadbOfficial "enabled" }}
{{- if .Values.mariadbOfficial.enabled }}
# ... resource definition
{{- end }}
{{- end }}
{{- end }}

# ❌ WRONG: No nil pointer checks
{{ .Values.optional.field }}  # REJECT if .Values.optional might not exist
```

### Chart Structure
```
helm/
├── Chart.yaml          # Version 2.x.x, appVersion, dependencies
├── values.yaml         # All configurable values with comments
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── networkpolicy.yaml     # REQUIRED
│   ├── serviceaccount.yaml    # REQUIRED
│   ├── role.yaml              # REQUIRED if not cluster-admin
│   ├── rolebinding.yaml       # REQUIRED
│   ├── secrets.yaml           # NEVER hardcode values
│   ├── configmap.yaml
│   ├── _helpers.tpl           # Reusable templates
│   └── tests/
│       └── test-connection.yaml
```

### Testing & Validation
```bash
# ✅ ALWAYS run before committing Helm changes
helm lint ./helm
helm template test ./helm --debug
helm template test ./helm | kubectl apply --dry-run=client -f -

# ✅ Test with different values files
helm template test ./helm -f values-staging.yaml
helm template test ./helm -f values-prod.yaml
```

---

## Docker Best Practices - ENFORCE

### Multi-Stage Builds
```dockerfile
# ✅ CORRECT: Multi-stage with minimal final image
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine
RUN addgroup -g 1000 appuser && adduser -D -u 1000 -G appuser appuser
WORKDIR /app
COPY --from=builder --chown=appuser:appuser /app/node_modules ./node_modules
COPY --chown=appuser:appuser . .
USER appuser
EXPOSE 3000
CMD ["node", "server.js"]
```

### Security Hardening
```dockerfile
# ✅ CORRECT: Non-root user, minimal packages, security scanning
RUN apk add --no-cache <package> && rm -rf /var/cache/apk/*
USER 1000:1000
HEALTHCHECK --interval=30s --timeout=3s CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# ❌ WRONG: Running as root, unnecessary packages
USER root  # REJECT THIS
RUN apt-get install -y *  # REJECT excessive packages
```

---

## Testing & Validation Requirements

### Pre-Commit Checks (MUST PASS)
```bash
# Helm validation
helm lint ./helm

# YAML syntax
yamllint -c .yamllint.yml .

# Security scanning
trivy image <image>:<tag>
trivy config ./helm

# Kubernetes manifest validation
kubectl apply --dry-run=server -f <file>
```

### Integration Testing
```bash
# Deploy to staging namespace
helm upgrade --install test ./helm -n staging --create-namespace

# Verify readiness
kubectl wait --for=condition=ready pod -l app=myapp -n staging --timeout=300s

# Run smoke tests
kubectl run smoke-test --image=curlimages/curl --rm -it -- curl http://service.staging.svc.cluster.local

# Cleanup
helm uninstall test -n staging
```

### Performance Testing
- Load testing with k6/Locust before production
- Resource usage monitoring (CPU, memory, disk I/O)
- Database query optimization (no N+1 queries)
- Caching strategies validated

---

## Documentation Requirements

### README.md (REQUIRED)
- Installation instructions with prerequisites
- Configuration examples with explanations
- Upgrade procedures (preserving existing config)
- Troubleshooting common issues
- Security considerations
- License and compliance information

### CHANGELOG.md (REQUIRED - Keep a Changelog format)
```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Modifications to existing features

### Deprecated
- Features to be removed in future

### Removed
- Deleted features

### Fixed
- Bug fixes

### Security
- Security patches and improvements
```

### Inline Documentation
- Helm templates: Comments explaining complex logic
- Scripts: Usage examples, parameter descriptions
- Configuration: Purpose of each value, valid ranges, examples

---

## Version Management - #WeOwnVer Ecosystem Versioning

**Official Specification**: See `/docs/VERSIONING_WEOWNVER.md` for complete details

### #WeOwnVer Format: SEASON.WEEK.DAY.VERSION

**Current Context** (date handling for reviews):
- **Today**: February 1, 2026 (Sunday, Season 2, Week 5, Day 7)
- **Season Calendar**: Season 2 (Oct 2025-Feb 2026), Season 3 (Feb-May 2026), Season 4 (Jun-Aug 2026)
- **NOTE**: WEEK values should be validated against dates provided in PR context (commit messages, file contents). Focus on enforcing SEASON.WEEK.DAY.VERSION format and internal consistency with existing versioned files.

### Chart Version (Chart.yaml)

**Weekly Summary Releases** (3-digit format):
```yaml
# SEASON.WEEK.0 - Week rollup, no specific day
version: 2.5.0  # Season 2 (current)
```

**Daily Releases** (4-digit format):
```yaml
# SEASON.WEEK.DAY.VERSION - Multiple releases same day
version: 2.5.7.1  # Season 2, Week 5, Sunday, 1st release
version: 2.5.7.2  # Season 2, Sunday, 2nd release
```

**Version Increment Rules**:
- **New week starts** → Increment WEEK (2.5.0 → 2.6.0)
- **Same week, new day** → Increment DAY (2.5.0 → 2.5.1.1)
- **Same day, hotfix** → Increment VERSION (2.5.7.1 → 2.5.7.2)
- **New season starts** → Increment SEASON (2.x.x → 3.1.0)

### Day Values (DAY position)
```yaml
0: Summary (week rollup, no daily)
1: Monday
2: Tuesday
3: Wednesday
4: Thursday
5: Friday
6: Saturday
7: Sunday
```

### Application Version (Chart.yaml)
```yaml
appVersion: "1.9.1"  # Upstream application version (not #WeOwnVer)
```

**Sync with upstream**: Track official releases, test before upgrading, document breaking changes

### Date/Time Awareness for Copilot AI

**CRITICAL**: Always determine current date/time before version recommendations:

1. **Use web search** to find current ISO week and date
2. **Map ISO week to Season/Week** using Season Calendar in `/docs/VERSIONING_WEOWNVER.md`
3. **Determine day number** (0-7) based on current day of week
4. **Recommend version** in SEASON.WEEK.DAY.VERSION format

**Example Logic**:
```
Current Date: Feb 1, 2026 (Sunday)
ISO Week: W05
Season: Season 2 (Oct 2025-Feb 2026)
Day: Sunday = 7
Recommended Version: 2.5.7.1 (Season 2, Week 5, Day 7, Version 1)
NOTE: WEEK methodology will be clarified in future update
```

### Documentation Standards

**CHANGELOG.md Entry Template**:
```markdown
## [2.5.7.1] - 2026-01-26

### Added
- Feature description

### Changed  
- Modification description
```

**Version References**:
- Always link to `/docs/VERSIONING_WEOWNVER.md` when documenting versioning
- Use format: "Chart Version: 2.5.0 (#WeOwnVer format)"
- NOTE: WEEK methodology will be clarified in future update

---

## Breaking Changes & Migration Plans

### When Breaking Changes Are Unavoidable
1. **Document** in CHANGELOG with "BREAKING CHANGE:" prefix
2. **Provide migration guide** with step-by-step instructions
3. **Include rollback procedure** if migration fails
4. **Test migration** in staging before production
5. **Communicate** to all stakeholders before deployment

### Example Migration Plan
```markdown
## Migration from v2.x to v3.0

### Breaking Changes
- Environment slug changed from "production" to "prod"
- InfisicalSecret namespace pattern changed

### Migration Steps
1. Export current values: `helm get values app -o yaml > values.yaml`
2. Update values.yaml:
   - Change `envSlug: "production"` to `envSlug: "prod"`
3. Backup PVCs: `kubectl get pvc -n namespace -o yaml > pvc-backup.yaml`
4. Upgrade: `helm upgrade app ./helm -f values.yaml`
5. Verify: `kubectl get pods -n namespace`

### Rollback Procedure
`helm rollback app [REVISION]`
```

---

## Vulnerability Screening - ENFORCE

### Container Image Scanning
```bash
# ✅ Run before every deployment
trivy image --severity HIGH,CRITICAL <image>:<tag>

# ✅ Fail CI/CD if HIGH/CRITICAL vulnerabilities found
trivy image --exit-code 1 --severity HIGH,CRITICAL <image>:<tag>
```

### Dependency Scanning
```bash
# Node.js
npm audit --audit-level=high

# Python
safety check --json

# Go
govulncheck ./...
```

### Kubernetes Configuration Scanning
```bash
# ✅ Scan Helm charts
trivy config ./helm

# ✅ Check for misconfigurations
kube-bench run --targets master,node
```

---

## DevOps & CI/CD Best Practices

### GitOps Workflow
1. **Feature Branch**: All changes in branches (feature/*, fix/*, docs/*)
2. **Pull Request**: Required for main branch, CI/CD runs automatically
3. **Code Review**: Copilot AI + human approval required
4. **Merge to Main**: Triggers production deployment pipeline
5. **Tag Release**: Create Git tag for version tracking

### CI/CD Pipeline Stages
1. **Lint**: YAML, Helm, shell scripts, Dockerfiles
2. **Security Scan**: Trivy, container scanning, secret detection
3. **Build**: Docker images with SHA tags
4. **Test**: Unit, integration, E2E tests
5. **Staging Deploy**: Automated deployment to staging
6. **Production Deploy**: Manual approval required

### Deployment Strategy
```yaml
# ✅ CORRECT: Rolling update with surge
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0  # Zero-downtime deployments
```

---

## Kubernetes-Specific Best Practices

### Resource Management
```yaml
# ✅ CORRECT: Always define requests and limits
resources:
  requests:
    cpu: 100m      # Guaranteed CPU
    memory: 256Mi  # Guaranteed memory
  limits:
    cpu: 500m      # Maximum CPU
    memory: 1Gi    # Maximum memory
```

### Probes Configuration
```yaml
# ✅ CORRECT: Proper health checks
livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 2
  failureThreshold: 2
```

### Labels & Annotations (STANDARDIZE)
```yaml
# ✅ CORRECT: Consistent labeling
metadata:
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: prod
    app.kubernetes.io/version: "2.1.0"
    app.kubernetes.io/component: web
    app.kubernetes.io/part-of: weown-ai
    app.kubernetes.io/managed-by: Helm
```

---

## Code Review Checklist - Copilot AI MUST VALIDATE ALL

### Security Review
- [ ] No hardcoded credentials, API keys, or tokens
- [ ] Secrets use Kubernetes secrets or external vault (Infisical)
- [ ] TLS 1.3 enforced, strong cipher suites configured
- [ ] Pod Security Standards "restricted" profile applied
- [ ] NetworkPolicy defined with deny-all + explicit allow
- [ ] RBAC configured with least privilege
- [ ] Container runs as non-root user (UID 1000+)
- [ ] readOnlyRootFilesystem enabled where possible
- [ ] All capabilities dropped except required ones
- [ ] No privileged containers or hostPath volumes

### Compliance Review (SOC2/ISO/IEC 42001)
- [ ] Audit logging enabled and retention configured
- [ ] Backup procedures documented and tested
- [ ] Data encryption at rest and in transit
- [ ] Access control policies defined
- [ ] Incident response procedures documented
- [ ] Change management process followed
- [ ] AI risk assessment completed (if applicable)
- [ ] Privacy impact assessment (if PII processed)
- [ ] Third-party vendor risk assessment
- [ ] Compliance evidence collected and stored

### Code Quality Review
- [ ] Code follows project style guide
- [ ] No linter warnings or errors
- [ ] Functions have clear purpose and single responsibility
- [ ] Error handling comprehensive and logged
- [ ] No commented-out code blocks
- [ ] Dependencies up-to-date and vulnerability-free
- [ ] Performance implications assessed
- [ ] Resource usage optimized

### Testing Review
- [ ] Unit tests written for new code (>80% coverage)
- [ ] Integration tests pass
- [ ] E2E tests pass in staging
- [ ] Load testing performed for high-traffic endpoints
- [ ] Security testing (OWASP Top 10) completed
- [ ] Regression testing confirms no breaks

### Documentation Review
- [ ] README updated with new features/changes
- [ ] CHANGELOG entry added (Keep a Changelog format)
- [ ] API documentation updated
- [ ] Inline code comments explain complex logic
- [ ] Architecture decision records (ADRs) created
- [ ] Migration guide provided (if breaking changes)

### Infrastructure Review (Helm/K8s/Docker)
- [ ] Helm chart lints successfully
- [ ] helm template renders correctly
- [ ] kubectl apply --dry-run validates
- [ ] Resource requests/limits defined
- [ ] Health checks (liveness/readiness) configured
- [ ] Labels and annotations consistent
- [ ] Dockerfile uses multi-stage builds
- [ ] Base images minimal and security-scanned
- [ ] Image tags specific (not "latest")

### Versioning Review
- [ ] Chart version incremented (#WeOwnVer format)
- [ ] appVersion updated if upstream changed
- [ ] Git tags created for releases
- [ ] Breaking changes documented
- [ ] Migration plan provided (if needed)
- [ ] Rollback procedure tested

---

## Common Pitfalls - REJECT IN CODE REVIEW

### ❌ Security Anti-Patterns
```yaml
# REJECT: Hardcoded secrets
env:
- name: API_KEY
  value: "sk-1234567890"  # NEVER do this

# REJECT: Running as root
securityContext:
  runAsUser: 0
  privileged: true

# REJECT: No NetworkPolicy
# Missing networkpolicy.yaml file

# REJECT: Weak TLS
annotations:
  nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.0 TLSv1.1"
```

### ❌ Configuration Anti-Patterns
```yaml
# REJECT: Missing resource limits
resources: {}  # Always define requests/limits

# REJECT: No health checks
# Missing livenessProbe and readinessProbe

# REJECT: Using "latest" tag
image: myapp:latest  # Always use specific versions
```

### ❌ Helm Anti-Patterns
```yaml
# REJECT: No defaults
value: {{ .Values.required }}  # Use "default" or "required"

# REJECT: Hardcoded namespaces
namespace: production  # Use templating

# REJECT: No nil checks
{{ .Values.optional.nested.field }}  # Check hasKey first
```

---

## Emergency Procedures

### Security Incident Response
1. **Immediate**: Isolate affected pods (`kubectl scale deployment <name> --replicas=0`)
2. **Investigate**: Collect logs (`kubectl logs`, `kubectl describe`)
3. **Rotate**: All potentially compromised secrets
4. **Patch**: Apply security fixes
5. **Document**: Post-mortem report, lessons learned
6. **Communicate**: Stakeholders, affected users, compliance team

### Production Rollback
```bash
# Check revision history
helm history <release> -n <namespace>

# Rollback to previous version
helm rollback <release> <revision> -n <namespace>

# Verify rollback
kubectl get pods -n <namespace>
kubectl logs -n <namespace> deployment/<name>
```

---

## Additional Resources

### WeOwn-Specific Guidelines
- **Namespace Naming**: `<app>-<instance>` (e.g., `wordpress-romandid`)
- **Storage**: DigitalOcean block storage, ReadWriteOnce access mode
- **Networking**: NGINX Ingress controller in `ingress-nginx` namespace
- **Certificates**: cert-manager with Let's Encrypt prod issuer
- **Secrets**: Infisical integration for production, Kubernetes secrets for staging

### External Standards
- **SOC2**: AICPA Trust Services Criteria
- **ISO/IEC 42001**: AI Management System
- **ISO/IEC 27001**: Information Security
- **CIS Kubernetes Benchmark**: Security hardening
- **NIST Cybersecurity Framework**: Risk management

---

## Copilot AI Review Enforcement

### Copilot Capabilities & Limitations

**What GitHub Copilot CAN Do** (Static Analysis):
- ✅ Scan code for security anti-patterns (hardcoded secrets, weak TLS, root users)
- ✅ Validate YAML/JSON/code syntax
- ✅ Detect missing files (NetworkPolicy, RBAC, secrets)
- ✅ Check documentation completeness
- ✅ Verify naming conventions and style
- ✅ Identify configuration violations
- ✅ Recommend specific fixes with file locations

**What GitHub Copilot CANNOT Do** (Dynamic Execution):
- ❌ Execute shell commands (`helm lint`, `kubectl apply --dry-run`)
- ❌ Run vulnerability scanners (`trivy image`, `trivy config`)
- ❌ Execute test suites (unit, integration, E2E)
- ❌ Deploy to Kubernetes clusters
- ❌ Build Docker images
- ❌ Perform performance testing

### CI/CD Integration Required

**For command execution and automated enforcement**, see `.github/CI_CD_WORKFLOWS.md`:
- Automated validation workflows (lint, security, K8s validation)
- Quality gates and blocking checks
- Compliance automation (SOC2, ISO/IEC 42001)
- Performance and dependency scanning

### Review Process

**Copilot's Role**:
1. **Scan** all code changes against this instruction file
2. **Identify** violations with severity (CRITICAL, HIGH, MEDIUM, LOW)
3. **Recommend** specific fixes with file paths and line numbers
4. **Reference** relevant sections from this file
5. **Suggest** CI/CD workflow additions if needed

**User's Role**:
1. **Review** Copilot comments and recommendations
2. **Execute** validation commands locally (helm lint, kubectl dry-run)
3. **Run** security scans (trivy) before pushing
4. **Complete** human-in-the-loop checklist in PR
5. **Verify** CI/CD workflows pass before merge

**Rejection Criteria**: Any violation of MANDATORY requirements (marked with REQUIRED, CRITICAL, ENFORCE) must result in code review failure with specific remediation steps.

**Approval Criteria**: 
- ✅ All Copilot static analysis checks passed
- ✅ All CI/CD workflows succeeded
- ✅ Documentation complete
- ✅ Security validated
- ✅ Compliance confirmed
- ✅ Human-in-the-loop checklist completed

**Final Human Validation**: Human-in-the-loop review checklist in auto-generated PR body must be completed before merge.

---

**Last Updated**: 2026-01-26 (v2.5.0) 
**Maintained By**: Roman Di Domizio (roman@weown.email)  
**Compliance Standards**: SOC2 Type II, ISO/IEC 42001:2023
