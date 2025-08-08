# Additional functions for AnythingLLM deployment script
# This file contains the remaining functions to be integrated

get_install_instructions() {
    local tool="$1"
    local os="$2"
    
    case "$tool" in
        "kubectl")
            case "$os" in
                "macOS")
                    echo "  # Using Homebrew (recommended):"
                    echo "  brew install kubectl"
                    echo "  "
                    echo "  # Or download directly:"
                    echo "  curl -LO 'https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl'"
                    echo "  chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
                    ;;
                "Linux")
                    echo "  # Download and install:"
                    echo "  curl -LO 'https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl'"
                    echo "  chmod +x kubectl && sudo mv kubectl /usr/local/bin/"
                    ;;
                "Windows")
                    echo "  # Download kubectl.exe from:"
                    echo "  https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/"
                    ;;
            esac
            ;;
        "helm")
            case "$os" in
                "macOS")
                    echo "  # Using Homebrew (recommended):"
                    echo "  brew install helm"
                    echo "  "
                    echo "  # Or install script:"
                    echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
                    ;;
                "Linux")
                    echo "  # Install script:"
                    echo "  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
                    ;;
                "Windows")
                    echo "  # Using Chocolatey:"
                    echo "  choco install kubernetes-helm"
                    echo "  "
                    echo "  # Or download from: https://github.com/helm/helm/releases"
                    ;;
            esac
            ;;
        "curl")
            case "$os" in
                "macOS")
                    echo "  # Usually pre-installed. If not:"
                    echo "  brew install curl"
                    ;;
                "Linux")
                    echo "  # Ubuntu/Debian:"
                    echo "  sudo apt-get update && sudo apt-get install curl"
                    echo "  "
                    echo "  # CentOS/RHEL:"
                    echo "  sudo yum install curl"
                    ;;
                "Windows")
                    echo "  # Usually available in Git Bash/WSL"
                    echo "  # Or download from: https://curl.se/windows/"
                    ;;
            esac
            ;;
        "git")
            case "$os" in
                "macOS")
                    echo "  # Using Homebrew:"
                    echo "  brew install git"
                    echo "  "
                    echo "  # Or download from: https://git-scm.com/download/mac"
                    ;;
                "Linux")
                    echo "  # Ubuntu/Debian:"
                    echo "  sudo apt-get update && sudo apt-get install git"
                    echo "  "
                    echo "  # CentOS/RHEL:"
                    echo "  sudo yum install git"
                    ;;
                "Windows")
                    echo "  # Download Git for Windows:"
                    echo "  https://git-scm.com/download/win"
                    ;;
            esac
            ;;
        "openssl")
            case "$os" in
                "macOS")
                    echo "  # Usually pre-installed. If not:"
                    echo "  brew install openssl"
                    ;;
                "Linux")
                    echo "  # Ubuntu/Debian:"
                    echo "  sudo apt-get update && sudo apt-get install openssl"
                    echo "  "
                    echo "  # CentOS/RHEL:"
                    echo "  sudo yum install openssl"
                    ;;
                "Windows")
                    echo "  # Available in Git Bash/WSL"
                    echo "  # Or install via Chocolatey: choco install openssl"
                    ;;
            esac
            ;;
    esac
}

check_tool() {
    local tool="$1"
    local description="$2"
    
    if command -v "$tool" &> /dev/null; then
        log_success "$tool is installed ✓"
        return 0
    else
        log_warning "$tool is not installed"
        echo -e "${YELLOW}What is $tool?${NC} $description"
        echo
        
        if ask_yes_no "Would you like to see installation instructions for $tool? This is required for deployment"; then
            echo -e "${BLUE}Installation instructions for $tool:${NC}"
            get_install_instructions "$tool" "$(detect_os)"
            echo
            log_warning "Please install $tool and run this script again."
            exit 1
        else
            log_error "Cannot continue without $tool. Exiting."
            exit 1
        fi
    fi
}

check_prerequisites() {
    log_step "Checking prerequisites and system requirements"
    echo
    
    local os=$(detect_os)
    log_info "Detected operating system: $os"
    echo
    
    log_info "This script will check for required tools and guide you through installation if needed."
    echo
    
    # Check kubectl
    check_tool "kubectl" "Kubernetes command-line tool for managing clusters"
    
    # Check helm
    check_tool "helm" "Kubernetes package manager for deploying applications"
    
    # Check curl
    check_tool "curl" "Command-line tool for downloading files and making HTTP requests"
    
    # Check git
    check_tool "git" "Version control system for downloading source code"
    
    # Check openssl
    check_tool "openssl" "Cryptographic toolkit for generating secure passwords and certificates"
    
    echo
    log_success "All prerequisites are installed!"
}

check_cluster_connection() {
    log_step "Checking Kubernetes cluster connection"
    echo
    
    log_info "Testing connection to your Kubernetes cluster..."
    
    if kubectl cluster-info &> /dev/null; then
        local cluster_info=$(kubectl cluster-info | head -1)
        log_success "Connected to Kubernetes cluster ✓"
        echo -e "${GREEN}$cluster_info${NC}"
        echo
        
        # Show cluster nodes
        log_info "Cluster nodes:"
        kubectl get nodes --no-headers | while read line; do
            echo "  • $line"
        done
        echo
        return 0
    else
        log_error "Cannot connect to Kubernetes cluster"
        echo
        log_info "This usually means you haven't configured kubectl to connect to your cluster."
        echo
        
        if ask_yes_no "Do you have a DigitalOcean Kubernetes cluster set up?"; then
            echo
            log_info "To connect to your DigitalOcean cluster:"
            echo "  1. Install doctl: https://docs.digitalocean.com/reference/doctl/how-to/install/"
            echo "  2. Authenticate: doctl auth init"
            echo "  3. Get your cluster ID: doctl kubernetes cluster list"
            echo "  4. Configure kubectl: doctl kubernetes cluster kubeconfig save <cluster-id>"
            echo
            log_warning "Please complete these steps and run this script again."
            exit 1
        else
            echo
            log_info "You'll need a Kubernetes cluster to deploy AnythingLLM."
            log_info "DigitalOcean Kubernetes is recommended for this deployment."
            log_info "Visit: https://cloud.digitalocean.com/kubernetes/clusters"
            exit 1
        fi
    fi
}

get_user_configuration() {
    log_step "Gathering your deployment configuration"
    echo
    
    log_info "I'll ask you a few questions to customize your AnythingLLM deployment."
    log_info "AnythingLLM is a private AI assistant that runs entirely on your infrastructure."
    echo
    
    # Get subdomain
    SUBDOMAIN=$(ask_user "Enter your desired subdomain (e.g., 'ai')" "ai")
    
    # Get domain
    DOMAIN=$(ask_user "Enter your domain name (e.g., 'example.com')")
    
    # Construct full domain
    FULL_DOMAIN="$SUBDOMAIN.$DOMAIN"
    
    # Get email for Let's Encrypt
    EMAIL=$(ask_user "Enter your email address for SSL certificates")
    
    # Generate secure admin password
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    log_success "Secure admin password generated: ${ADMIN_PASSWORD}"
    
    # Generate JWT secret
    JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    log_success "JWT secret generated ✓"
    
    # LLM Provider configuration
    echo
    log_info "🤖 LLM Provider Configuration"
    echo "AnythingLLM needs an AI language model to function. Choose your preferred option:"
    echo
    echo "1. OpenRouter (Recommended) - Access to multiple models, often cheaper than OpenAI"
    echo "2. OpenAI - Direct OpenAI API access"
    echo "3. Skip for now - Configure later in the web interface"
    echo
    
    local llm_choice
    while true; do
        llm_choice=$(ask_user "Choose your LLM provider [1-3]" "1")
        case "$llm_choice" in
            1|"openrouter")
                log_info "OpenRouter selected - Great choice for cost-effective AI!"
                echo
                echo "📝 To get your OpenRouter API key:"
                echo "  1. Visit: https://openrouter.ai/keys"
                echo "  2. Sign up/login (free account)"
                echo "  3. Create a new API key"
                echo "  4. Fund your account (as little as \$1 works)"
                echo
                echo "💡 OpenRouter offers free models too! Look for models marked 'Free'."
                echo
                OPENAI_API_KEY=$(ask_user "Enter your OpenRouter API key (or press Enter to skip)")
                OPENAI_API_BASE="https://openrouter.ai/api/v1"
                break
                ;;
            2|"openai")
                log_info "OpenAI selected - Premium option with excellent performance!"
                echo
                echo "📝 To get your OpenAI API key:"
                echo "  1. Visit: https://platform.openai.com/api-keys"
                echo "  2. Sign up/login"
                echo "  3. Create a new API key"
                echo "  4. Add billing information (required for API access)"
                echo
                OPENAI_API_KEY=$(ask_user "Enter your OpenAI API key (or press Enter to skip)")
                OPENAI_API_BASE="https://api.openai.com/v1"
                break
                ;;
            3|"skip")
                log_info "Skipping LLM configuration - you can set this up later in the web interface."
                OPENAI_API_KEY="placeholder-configure-in-ui"
                OPENAI_API_BASE="https://api.openai.com/v1"
                break
                ;;
            *)
                echo "Please choose 1, 2, or 3."
                ;;
        esac
    done
    
    # Configuration summary
    echo
    log_info "📋 Configuration Summary:"
    echo "  Full URL: https://$FULL_DOMAIN"
    echo "  Email: $EMAIL"
    echo "  Admin Password: $ADMIN_PASSWORD"
    echo "  LLM Provider: $([ "$OPENAI_API_BASE" == "https://openrouter.ai/api/v1" ] && echo "OpenRouter" || echo "OpenAI")"
    echo "  API Key: $([ -n "$OPENAI_API_KEY" ] && [ "$OPENAI_API_KEY" != "placeholder-configure-in-ui" ] && echo "✓ Provided" || echo "⚠ Will configure later")"
    echo
    
    if ! ask_yes_no "Continue with this configuration?" "y"; then
        log_info "Deployment cancelled."
        exit 0
    fi
}

# Main execution function
main() {
    print_banner
    
    # Check prerequisites
    check_prerequisites
    
    # Check cluster connection
    check_cluster_connection
    
    # Get user configuration
    get_user_configuration
    
    # Setup DNS instructions
    setup_dns_instructions
    
    # Check and install cluster prerequisites
    check_and_install_cluster_prerequisites
    
    # Deploy AnythingLLM
    deploy_anythingllm
    
    log_success "🎉 AnythingLLM deployment completed successfully!"
}
