# Nextcloud Development Testing Guide

Testing guide for Nextcloud deployment in development environments.

## Quick Start Testing

### Option 1: Local Testing with Minikube

```bash
# 1. Install Minikube
# Windows: choco install minikube
# macOS: brew install minikube
# Linux: curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# 2. Start Minikube with sufficient resources
minikube start --memory=4096 --cpus=2 --disk-size=20g

# 3. Enable required addons
minikube addons enable ingress
minikube addons enable storage-provisioner

# 4. Run automated tests
cd nextcloud
chmod +x test-deployment.sh
./test-deployment.sh

# 5. Access the application
minikube service nextcloud-test -n nextcloud-test --url
```

### **Option 2: Cloud Development Environment**

#### **DigitalOcean Droplet Setup**
```bash
# 1. Create development droplet
doctl compute droplet create nextcloud-dev \
  --image ubuntu-22-04-x64 \
  --size s-2vcpu-4gb \
  --region nyc1 \
  --ssh-keys <your-ssh-key-id>

# 2. SSH into droplet
ssh root@<droplet-ip>

# 3. Install k3s (lightweight Kubernetes)
curl -sfL https://get.k3s.io | sh -

# 4. Configure kubectl
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 5. Install NGINX Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# 6. Test deployment
cd /opt/nextcloud
./test-deployment.sh
```

## 🧪 **Testing Strategies**

### **1. Automated Testing**

The `test-deployment.sh` script provides comprehensive automated testing:

```bash
# Run all tests
./test-deployment.sh

# Clean up test environment
./test-deployment.sh cleanup

# Show help
./test-deployment.sh help
```

**Tests Included:**
- ✅ Prerequisites validation
- ✅ Helm chart syntax and rendering
- ✅ Kubernetes deployment
- ✅ Pod health and readiness
- ✅ Service connectivity
- ✅ Persistent volume binding
- ✅ Secret management
- ✅ Network policy enforcement
- ✅ Ingress configuration
- ✅ Internal connectivity (PostgreSQL, Redis)
- ✅ Application health checks

### **2. Manual Testing**

#### **Step-by-Step Manual Testing**

```bash
# 1. Create test namespace
kubectl create namespace nextcloud-test

# 2. Deploy with test values
helm install nextcloud-test ./helm \
  --namespace=nextcloud-test \
  --set global.domain=nextcloud-test.local \
  --set global.email=test@example.com \
  --set nextcloud.secrets.NEXTCLOUD_ADMIN_PASSWORD=testpass123 \
  --set nextcloud.secrets.POSTGRES_PASSWORD=testpass123 \
  --set nextcloud.secrets.REDIS_PASSWORD=testpass123 \
  --set nextcloud.secrets.NEXTCLOUD_SECRET=testsecret123

# 3. Check deployment status
kubectl get all -n nextcloud-test

# 4. Check pod logs
kubectl logs -n nextcloud-test -l app.kubernetes.io/name=nextcloud

# 5. Test database connectivity
kubectl exec -it nextcloud-test-postgresql-0 -n nextcloud-test -- psql -U nextcloud -d nextcloud

# 6. Test Redis connectivity
kubectl exec -it nextcloud-test-redis-<pod-id> -n nextcloud-test -- redis-cli ping

# 7. Port forward for web testing
kubectl port-forward -n nextcloud-test svc/nextcloud-test 8080:80

# 8. Test in browser: http://localhost:8080
```

### **3. Integration Testing**

#### **Test with Real Domain (Optional)**

```bash
# 1. Set up local DNS (add to /etc/hosts)
echo "127.0.0.1 nextcloud-test.local" | sudo tee -a /etc/hosts

# 2. Deploy with real domain
helm install nextcloud-test ./helm \
  --namespace=nextcloud-test \
  --set global.domain=nextcloud-test.local \
  --set global.email=your-email@example.com

# 3. Install cert-manager for TLS testing
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.yaml

# 4. Wait for TLS certificate
kubectl get certificate -n nextcloud-test -w

# 5. Test HTTPS access
curl -k https://nextcloud-test.local
```

## 🔧 **Development Environment Setup**

### **Local Development with Docker**

```bash
# 1. Create docker-compose.yml for local development
cat <<EOF > docker-compose.dev.yml
version: '3.8'
services:
  nextcloud:
    image: nextcloud:latest
    ports:
      - "8080:80"
    environment:
      - NEXTCLOUD_ADMIN_USER=admin
      - NEXTCLOUD_ADMIN_PASSWORD=admin123
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD=nextcloud123
      - REDIS_HOST=redis
    depends_on:
      - postgres
      - redis
    volumes:
      - nextcloud_data:/var/www/html/data
      - nextcloud_config:/var/www/html/config

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=nextcloud
      - POSTGRES_PASSWORD=nextcloud123
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass redis123

volumes:
  nextcloud_data:
  nextcloud_config:
  postgres_data:
EOF

# 2. Start development environment
docker-compose -f docker-compose.dev.yml up -d

# 3. Access at http://localhost:8080
```

### **Kubernetes Development Environment**

#### **Kind (Kubernetes in Docker)**

```bash
# 1. Install Kind
# Windows: choco install kind
# macOS: brew install kind
# Linux: go install sigs.k8s.io/kind@v0.20.0

# 2. Create cluster with ingress
cat <<EOF | kind create cluster --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF

# 3. Install NGINX Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# 4. Wait for ingress to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# 5. Test deployment
cd nextcloud
./test-deployment.sh
```

## 🐛 **Debugging and Troubleshooting**

### **Common Issues and Solutions**

#### **1. Pods Not Starting**

```bash
# Check pod status
kubectl get pods -n nextcloud-test

# Check pod events
kubectl describe pod <pod-name> -n nextcloud-test

# Check pod logs
kubectl logs <pod-name> -n nextcloud-test

# Common causes:
# - Insufficient resources
# - Image pull errors
# - Persistent volume issues
# - Network policy restrictions
```

#### **2. Database Connection Issues**

```bash
# Check PostgreSQL status
kubectl get pods -n nextcloud-test -l app.kubernetes.io/name=postgresql

# Test database connection
kubectl exec -it nextcloud-test-postgresql-0 -n nextcloud-test -- psql -U nextcloud -d nextcloud

# Check secrets
kubectl get secrets -n nextcloud-test
kubectl describe secret nextcloud-test-postgresql -n nextcloud-test
```

#### **3. Storage Issues**

```bash
# Check PVC status
kubectl get pvc -n nextcloud-test

# Check storage class
kubectl get storageclass

# For Minikube, ensure storage provisioner is enabled
minikube addons enable storage-provisioner
```

#### **4. Network Policy Issues**

```bash
# Check network policies
kubectl get networkpolicies -n nextcloud-test

# Test connectivity between pods
kubectl exec -it <pod-name> -n nextcloud-test -- nslookup <service-name>

# Disable network policies for testing
kubectl patch networkpolicy nextcloud-test -n nextcloud-test -p '{"spec":{"podSelector":{}}}'
```

### **Debug Commands**

```bash
# Get all resources
kubectl get all -n nextcloud-test

# Check events
kubectl get events -n nextcloud-test --sort-by='.lastTimestamp'

# Port forward for testing
kubectl port-forward -n nextcloud-test svc/nextcloud-test 8080:80

# Check resource usage
kubectl top pods -n nextcloud-test
kubectl top nodes

# Check ingress
kubectl get ingress -n nextcloud-test
kubectl describe ingress nextcloud-test -n nextcloud-test
```

## 📊 **Performance Testing**

### **Load Testing**

```bash
# Install Apache Bench
# Ubuntu/Debian: sudo apt-get install apache2-utils
# macOS: brew install httpd
# Windows: Download from Apache website

# Test basic connectivity
ab -n 100 -c 10 http://localhost:8080/

# Test with authentication (if configured)
ab -n 100 -c 10 -A admin:password http://localhost:8080/

# Monitor resource usage during test
kubectl top pods -n nextcloud-test --watch
```

### **Resource Monitoring**

```bash
# Monitor pod resource usage
kubectl top pods -n nextcloud-test

# Monitor node resource usage
kubectl top nodes

# Check resource limits
kubectl describe pod <pod-name> -n nextcloud-test | grep -A 10 "Limits\|Requests"
```

## 🔒 **Security Testing**

### **Network Policy Testing**

```bash
# Test network isolation
kubectl run test-pod --image=busybox --rm -it --restart=Never -- nslookup nextcloud-test-postgresql

# Test ingress access
curl -I http://localhost/nextcloud-test

# Test egress restrictions
kubectl exec -it nextcloud-test-<pod-id> -n nextcloud-test -- wget -O- http://google.com
```

### **Security Context Testing**

```bash
# Check security contexts
kubectl get pod <pod-name> -n nextcloud-test -o yaml | grep -A 20 securityContext

# Test non-root execution
kubectl exec -it <pod-name> -n nextcloud-test -- whoami

# Check capabilities
kubectl exec -it <pod-name> -n nextcloud-test -- capsh --print
```

## 🚀 **Production Readiness Testing**

### **High Availability Testing**

```bash
# Test pod disruption
kubectl delete pod <pod-name> -n nextcloud-test

# Test node failure simulation
kubectl drain <node-name> --ignore-daemonsets

# Test backup and restore
kubectl create job --from=cronjob/nextcloud-test-backup manual-backup -n nextcloud-test
```

### **Scaling Testing**

```bash
# Test horizontal scaling
kubectl scale deployment nextcloud-test -n nextcloud-test --replicas=3

# Monitor scaling behavior
kubectl get pods -n nextcloud-test -w

# Test resource limits
kubectl apply -f - <<EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: nextcloud-quota
  namespace: nextcloud-test
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
EOF
```

## 📝 **Testing Checklist**

### **Pre-Deployment Testing**
- [ ] Helm chart syntax validation
- [ ] Template rendering test
- [ ] Resource requirements validation
- [ ] Security context verification
- [ ] Network policy testing

### **Deployment Testing**
- [ ] Pod startup and readiness
- [ ] Service connectivity
- [ ] Persistent volume binding
- [ ] Secret management
- [ ] Ingress configuration

### **Application Testing**
- [ ] Web interface accessibility
- [ ] Database connectivity
- [ ] Redis cache functionality
- [ ] File upload/download
- [ ] User authentication
- [ ] Admin panel access

### **Security Testing**
- [ ] Network policy enforcement
- [ ] TLS certificate generation
- [ ] Non-root container execution
- [ ] Secret encryption
- [ ] RBAC permissions

### **Performance Testing**
- [ ] Resource usage monitoring
- [ ] Load testing
- [ ] Scaling behavior
- [ ] Backup and restore
- [ ] High availability

## 🎯 **Next Steps**

After successful testing:

1. **Deploy to Staging**: Use a staging environment with real domain
2. **Performance Tuning**: Optimize resource limits and scaling
3. **Security Hardening**: Implement additional security measures
4. **Monitoring Setup**: Configure comprehensive monitoring
5. **Backup Testing**: Validate backup and restore procedures
6. **Production Deployment**: Deploy to production environment

## 📚 **Additional Resources**

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Helm Documentation](https://helm.sh/docs/)
- [Nextcloud Documentation](https://docs.nextcloud.com/)
- [Minikube Documentation](https://minikube.sigs.k8s.io/docs/)
- [Kind Documentation](https://kind.sigs.k8s.io/docs/)

---

**Happy Testing!** 🚀
