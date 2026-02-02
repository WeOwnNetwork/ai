# CI/CD Workflows - Automated Testing & Validation

**Purpose**: GitHub Copilot can scan code and provide recommendations but **cannot execute shell commands**. This document defines CI/CD workflows to automate the validation steps from `copilot-instructions.md`.

---

## GitHub Copilot Capabilities vs CI/CD Requirements

### What Copilot CAN Do
- ✅ Static code analysis and pattern detection
- ✅ YAML/JSON/code syntax validation
- ✅ Security pattern detection (hardcoded secrets, weak TLS, etc.)
- ✅ Best practice recommendations
- ✅ Documentation completeness checks
- ✅ Code style and convention validation

### What Copilot CANNOT Do
- ❌ Execute shell commands (`helm lint`, `kubectl apply --dry-run`)
- ❌ Run container vulnerability scans (`trivy image`)
- ❌ Execute test suites (unit, integration, E2E)
- ❌ Deploy to Kubernetes clusters
- ❌ Perform dynamic security testing
- ❌ Generate performance benchmarks

### Solution: Hybrid Approach
**Copilot** → Scan and recommend in PR reviews
**CI/CD** → Execute commands and enforce quality gates

---

## Recommended CI/CD Pipeline Architecture

### GitHub Actions Workflow Template

**File**: `.github/workflows/validation.yml`

```yaml
name: Code Validation & Security

on:
  pull_request:
    branches: [main, maintenance]
  push:
    branches: [main, maintenance]

permissions:
  contents: read
  pull-requests: write
  security-events: write

jobs:
  lint:
    name: Lint & Syntax Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: YAML Lint
        uses: ibiqlik/action-yamllint@2576378a8e339169678f9939646ee3ee325e845c # v3.1.1
        with:
          file_or_dir: .
          config_file: .yamllint.yml

      - name: Helm Lint
        run: |
          helm lint ./*/helm 2>&1 | tee helm-lint.log
          if grep -q "ERROR" helm-lint.log; then
            echo "::error::Helm lint failed"
            exit 1
          fi

      - name: Shell Script Lint
        uses: ludeeus/action-shellcheck@00b27aa7cb85167568cb48a3838b75f4265f2bca # v2.0.0
        with:
          scandir: './scripts'

  security:
    name: Security Scanning
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: Secret Detection
        uses: trufflesecurity/trufflehog@4b0d468b4a67df0f6b86db2db182c992fb2cbb4e # v3.82.13
        with:
          path: ./
          base: ${{ github.event.repository.default_branch }}
          head: HEAD

      - name: Trivy Config Scan
        uses: aquasecurity/trivy-action@6e7b7d1fd3e4fef0c5fa8cce1229c54b2c9bd0d8 # v0.24.0
        with:
          scan-type: 'config'
          scan-ref: '.'
          format: 'sarif'
          output: 'trivy-config.sarif'
          severity: 'HIGH,CRITICAL'
          exit-code: '1'

      - name: Upload Trivy Results
        uses: github/codeql-action/upload-sarif@b8d3b6e8af63cde30bdc382c0bc28114f4346c88 # v2
        if: always()
        with:
          sarif_file: 'trivy-config.sarif'

  kubernetes:
    name: Kubernetes Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: Helm Template Validation
        run: |
          for chart in */helm; do
            echo "Validating $chart"
            helm template test ./$chart --debug
          done

      - name: Kubernetes Dry-Run
        run: |
          for chart in */helm; do
            echo "Dry-run validation: $chart"
            helm template test ./$chart | kubectl apply --dry-run=server -f -
          done

      - name: Kubeval Validation
        uses: instrumenta/kubeval-action@831e8d7618bee0555ef06c4a7c1635c6e9130339 # v0.4.0
        with:
          files: ./*/helm/templates/*.yaml

  compliance:
    name: Compliance Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: SOC2 Checklist Validation
        run: |
          # Check for required security controls
          
          # 1. NetworkPolicy exists
          find . -name "networkpolicy.yaml" -o -name "network-policy.yaml" | grep -q . || {
            echo "::error::Missing NetworkPolicy - SOC2 requirement"
            exit 1
          }
          
          # 2. No hardcoded secrets (exclude comments, examples, and proper secret injection)
          if grep -RInE '^[[:space:]]*[^#]*password[^:]*[:=][[:space:]]*[^[:space:]#]+' --include="*.yaml" --include="*.yml" . | grep -Ev "valueFrom|secretKeyRef|envFrom:|example|sample"; then
            echo "::error::Hardcoded secrets detected - SOC2 violation"
            exit 1
          fi
          
          # 3. TLS 1.3 enforcement (check Ingress resources specifically)
          ingress_files=$(find . -type f \( -name "*.yaml" -o -name "*.yml" \) -exec grep -l "kind: *Ingress" {} \;)
          if [ -z "$ingress_files" ]; then
            echo "::warning::No Ingress resources found to validate TLS 1.3 enforcement"
          elif ! grep -l "TLSv1.3" $ingress_files >/dev/null 2>&1; then
            echo "::error::TLS 1.3 not enforced in Ingress resources - SOC2 requirement"
            exit 1
          fi
          
          # 4. RBAC configured
          find . -name "role.yaml" -o -name "rolebinding.yaml" | grep -q . || {
            echo "::error::Missing RBAC - SOC2 requirement"
            exit 1
          }

      - name: ISO/IEC 42001 AI Management Validation
        if: contains(github.event.head_commit.message, 'ai') || contains(github.event.head_commit.message, 'AI')
        run: |
          # AI-specific compliance checks
          
          # 1. Check for AI risk assessment documentation
          if [ ! -f "docs/AI_RISK_ASSESSMENT.md" ]; then
            echo "::warning::Missing AI risk assessment documentation"
          fi
          
          # 2. Check for model versioning (ensure models have version tracking)
          model_matches=$(grep -r "model" --include="*.yaml" . || true)
          if [ -n "$model_matches" ] && ! echo "$model_matches" | grep -q "version"; then
            echo "::warning::AI models should have version tracking"
          fi

  documentation:
    name: Documentation Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: Check Required Files
        run: |
          required_files=(
            "README.md"
            "CHANGELOG.md"
          )
          
          for file in "${required_files[@]}"; do
            if [ ! -f "$file" ]; then
              echo "::error::Missing required file: $file"
              exit 1
            fi
          done

      - name: Markdown Lint
        uses: nosborn/github-action-markdown-cli@9b5e871c11cc0649c5ac2526af22e23525fa344d # v3.3.0
        with:
          files: .
          config_file: .markdownlint.json

      - name: Version Consistency Check
        run: |
          # Check Chart.yaml version matches CHANGELOG.md
          chart_version=$(grep "^version:" */helm/Chart.yaml | head -1 | awk '{print $2}')
          if ! grep -q "\[$chart_version\]" */CHANGELOG.md; then
            echo "::error::Chart version $chart_version not documented in CHANGELOG"
            exit 1
          fi

  versioning:
    name: WeOwnVer Validation
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: Validate WeOwnVer Format
        run: |
          # Extract version from Chart.yaml
          version=$(grep "^version:" */helm/Chart.yaml | head -1 | awk '{print $2}')
          
          # Validate format: SEASON.WEEK[.DAY[.VERSION]]
          if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?(\.[0-9]+)?$'; then
            echo "::error::Invalid WeOwnVer format: $version"
            echo "Expected: SEASON.WEEK[.DAY[.VERSION]] where all components are non-negative integers"
            exit 1
          fi
          
          # Validate season/week/day ranges
          season=$(echo "$version" | cut -d. -f1)
          week=$(echo "$version" | cut -d. -f2)
          day=$(echo "$version" | cut -d. -f3)
          
          # Season must be a positive, reasonable number (1+)
          if [ "$season" -lt 1 ] || [ "$season" -gt 9999 ]; then
            echo "::error::Season $season is out of allowed range (1-9999)"
            exit 1
          fi
          
          # Week must be between 1 and 17 inclusive
          if [ "$week" -lt 1 ] || [ "$week" -gt 17 ]; then
            echo "::error::Week $week is out of allowed range (1-17)"
            exit 1
          fi
          
          # If a day component is present, it must be between 0 and 7 inclusive
          if [ -n "$day" ]; then
            if [ "$day" -lt 0 ] || [ "$day" -gt 7 ]; then
              echo "::error::Day $day is out of allowed range (0-7)"
              exit 1
            fi
          fi

          # If a version component is present (4th digit), it must be 1 or greater
          version_num=$(echo "$version" | cut -d. -f4)
          if [ -n "$version_num" ]; then
            if [ "$version_num" -lt 1 ]; then
              echo "::error::Version $version_num is out of allowed range (1+)"
              exit 1
            fi
          fi

      - name: Check Version References
        run: |
          # Ensure all documentation references WeOwnVer
          if ! grep -r "WeOwnVer\|#WeOwnVer" README.md CHANGELOG.md; then
            echo "::warning::Documentation should reference WeOwnVer system"
          fi

  summary:
    name: Validation Summary
    runs-on: ubuntu-latest
    needs: [lint, security, kubernetes, compliance, documentation, versioning]
    if: always()
    steps:
      - name: Generate Summary
        run: |
          echo "## 🎯 Validation Results" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "| Check | Status |" >> $GITHUB_STEP_SUMMARY
          echo "|-------|--------|" >> $GITHUB_STEP_SUMMARY
          echo "| Lint | ${{ needs.lint.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Security | ${{ needs.security.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Kubernetes | ${{ needs.kubernetes.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Compliance | ${{ needs.compliance.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Documentation | ${{ needs.documentation.result }} |" >> $GITHUB_STEP_SUMMARY
          echo "| Versioning | ${{ needs.versioning.result }} |" >> $GITHUB_STEP_SUMMARY
```

---

## Configuration Files

### .yamllint.yml
```yaml
extends: default

rules:
  line-length:
    max: 120
    level: warning
  indentation:
    spaces: 2
    indent-sequences: true
  comments:
    min-spaces-from-content: 1
  truthy:
    allowed-values: ['true', 'false', 'on', 'off']
```

### .markdownlint.json
```json
{
  "default": true,
  "MD013": false,
  "MD033": false,
  "MD041": false
}
```

---

## Advanced Workflows

### Container Image Scanning

**File**: `.github/workflows/container-scan.yml`

```yaml
name: Container Security Scan

on:
  pull_request:
    paths:
      - '**/Dockerfile*'
      - '**/values.yaml'

jobs:
  scan:
    name: Trivy Image Scan
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: Build Test Images
        run: |
          # Build all Dockerfiles for scanning
          find . -name "Dockerfile*" -exec dirname {} \; | sort -u | while read dir; do
            docker build -t test:latest "$dir"
            trivy image --exit-code 1 --severity HIGH,CRITICAL test:latest
          done
```

### Performance Testing

**File**: `.github/workflows/performance.yml`

```yaml
name: Performance Testing

on:
  pull_request:
    branches: [main]

jobs:
  lighthouse:
    name: Lighthouse CI
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: Run Lighthouse
        uses: treosh/lighthouse-ci-action@2f8dda6cf4de7d73b29853c3f29e73a01e297bd8 # v10.1.0
        with:
          urls: |
            https://staging.example.com
          uploadArtifacts: true
          temporaryPublicStorage: true
```

### Dependency Scanning

**File**: `.github/workflows/dependencies.yml`

```yaml
name: Dependency Security

on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly
  pull_request:
    paths:
      - '**/package*.json'
      - '**/requirements.txt'
      - '**/go.mod'

jobs:
  scan:
    name: Dependency Audit
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@11bd71901bca8484df8a183e9c3623645834c2b0 # v4.1.5

      - name: Node.js Audit
        if: hashFiles('**/package-lock.json') != ''
        run: |
          npm audit --audit-level=high

      - name: Python Safety Check
        if: hashFiles('**/requirements.txt') != ''
        run: |
          pip install safety
          safety check --json

      - name: Go Vulnerability Check
        if: hashFiles('**/go.mod') != ''
        run: |
          go install golang.org/x/vuln/cmd/govulncheck@latest
          govulncheck ./...
```

---

## Integration with Copilot

### Copilot's Role (PR Review)
1. **Scan code** for patterns and anti-patterns
2. **Recommend fixes** with specific file locations
3. **Reference** copilot-instructions.md requirements
4. **Flag violations** with severity levels

### CI/CD's Role (Automated Enforcement)
1. **Execute** all validation commands
2. **Enforce** quality gates (fail on HIGH/CRITICAL)
3. **Generate** reports and artifacts
4. **Block** merges if checks fail

### Workflow Integration
```
1. Developer pushes to maintenance branch
2. GitHub Actions runs validation workflows
3. GitHub Copilot reviews code patterns
4. Both provide feedback in PR comments
5. Developer fixes issues
6. Push updates trigger re-validation
7. All checks pass → Human approves → Merge
```

---

## Quality Gates

### Blocking (Must Pass)
- ❌ Helm lint errors
- ❌ Kubernetes dry-run failures
- ❌ HIGH/CRITICAL security vulnerabilities
- ❌ Hardcoded secrets detected
- ❌ Missing NetworkPolicy
- ❌ Missing RBAC configuration
- ❌ WeOwnVer format violations

### Warning (Review Required)
- ⚠️ Missing TLS 1.3 enforcement
- ⚠️ Documentation gaps
- ⚠️ Performance regressions
- ⚠️ Code style violations
- ⚠️ Missing AI risk assessments

---

## Monitoring & Reporting

### GitHub Actions Dashboard
- **Status badges** in README.md
- **Workflow run history** for trend analysis
- **Artifact storage** for scan reports
- **Notification integration** (Slack, email)

### Metrics to Track
- ✅ CI/CD success rate
- ✅ Average validation time
- ✅ Security vulnerability trends
- ✅ Code quality score over time
- ✅ Deployment frequency

---

## Maintenance

### Weekly Tasks
- Review and update workflow configurations
- Update action versions to latest
- Review security scan findings
- Optimize workflow performance

### Monthly Tasks
- Audit quality gate effectiveness
- Review blocked PRs for patterns
- Update compliance checklists
- Performance benchmark analysis

---

## Implementation Checklist

- [ ] Create `.github/workflows/validation.yml`
- [ ] Create `.yamllint.yml` configuration
- [ ] Create `.markdownlint.json` configuration
- [ ] Enable GitHub Actions in repository settings
- [ ] Configure required status checks in branch protection
- [ ] Set up notification integrations
- [ ] Train team on workflow usage
- [ ] Document workflow customizations

---

**Last Updated**: 2026-01-26 (v2.5.0)  
**Maintained By**: Roman Di Domizio (roman@weown.email)  
**Compliance**: SOC2, ISO/IEC 42001 automated validation
