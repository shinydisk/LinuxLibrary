#!/bin/bash

#=================================================================
# Installateur automatique d'applications pour Linux
# Support multi-distributions avec détection automatique
#=================================================================

# Configuration
BOT_TOKEN="BOT_TOKEN"
CHAT_ID="CHAT_ID"
HOSTNAME=$(hostname)

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Détection de la distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    else
        DISTRO="unknown"
    fi
    
    echo "$DISTRO"
}

# Notification Telegram
send_notification() {
    local status="$1"
    local title="$2"
    local message="$3"
    
    local emoji=""
    case $status in
        "SUCCESS") emoji="✅" ;;
        "ERROR") emoji="❌" ;;
        "WARNING") emoji="⚠️" ;;
        "INFO") emoji="📦" ;;
    esac
    
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        --data-urlencode text="$emoji <b>INSTALLATION $status</b> - $HOSTNAME
<b>$title</b>
$message
🕒 $(date '+%Y-%m-%d %H:%M:%S')" \
        -d parse_mode="HTML"
}

# Gestionnaire de paquets selon la distribution
get_package_manager() {
    local distro="$1"
    
    case $distro in
        ubuntu|debian|linuxmint|pop|elementary)
            echo "apt"
            ;;
        fedora|centos|rhel|rocky|almalinux)
            echo "dnf"
            ;;
        opensuse*|sles)
            echo "zypper"
            ;;
        arch|manjaro|endeavouros)
            echo "pacman"
            ;;
        alpine)
            echo "apk"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Mise à jour du système
update_system() {
    local distro=$(detect_distro)
    local package_manager=$(get_package_manager "$distro")
    
    echo -e "${BLUE}🔄 Mise à jour du système ($distro)...${NC}"
    
    case $package_manager in
        apt)
            sudo apt update && sudo apt upgrade -y
            ;;
        dnf)
            sudo dnf update -y
            ;;
        zypper)
            sudo zypper refresh && sudo zypper update -y
            ;;
        pacman)
            sudo pacman -Syu --noconfirm
            ;;
        apk)
            sudo apk update && sudo apk upgrade
            ;;
        *)
            echo -e "${RED}❌ Gestionnaire de paquets non supporté${NC}"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Système mis à jour${NC}"
        send_notification "SUCCESS" "Mise à jour système" "Distribution: $distro
Gestionnaire: $package_manager"
        return 0
    else
        echo -e "${RED}❌ Échec de la mise à jour${NC}"
        send_notification "ERROR" "Échec mise à jour système" "Distribution: $distro
Erreur lors de la mise à jour"
        return 1
    fi
}

# Installation d'un paquet
install_package() {
    local package="$1"
    local distro=$(detect_distro)
    local package_manager=$(get_package_manager "$distro")
    
    echo -e "${BLUE}📦 Installation de $package...${NC}"
    
    case $package_manager in
        apt)
            sudo apt install -y "$package"
            ;;
        dnf)
            sudo dnf install -y "$package"
            ;;
        zypper)
            sudo zypper install -y "$package"
            ;;
        pacman)
            sudo pacman -S --noconfirm "$package"
            ;;
        apk)
            sudo apk add "$package"
            ;;
        *)
            echo -e "${RED}❌ Gestionnaire de paquets non supporté${NC}"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $package installé avec succès${NC}"
        send_notification "SUCCESS" "Paquet installé" "Package: $package
Distribution: $distro"
        return 0
    else
        echo -e "${RED}❌ Échec de l'installation de $package${NC}"
        send_notification "ERROR" "Échec installation" "Package: $package
Distribution: $distro"
        return 1
    fi
}

# Installation Docker
install_docker() {
    echo -e "${PURPLE}🐳 Installation de Docker...${NC}"
    
    local distro=$(detect_distro)
    
    case $distro in
        ubuntu|debian)
            # Supprimer les anciennes versions
            sudo apt-get remove docker docker-engine docker.io containerd runc 2>/dev/null
            
            # Installer les prérequis
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
            
            # Ajouter la clé GPG officielle de Docker
            curl -fsSL https://download.docker.com/linux/$distro/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            
            # Ajouter le dépôt Docker
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$distro $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Installer Docker
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        fedora|centos|rhel)
            sudo dnf remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine 2>/dev/null
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        arch)
            sudo pacman -S --noconfirm docker docker-compose
            ;;
        *)
            echo -e "${RED}❌ Distribution non supportée pour l'installation automatique de Docker${NC}"
            return 1
            ;;
    esac
    
    # Démarrer et activer Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Ajouter l'utilisateur au groupe docker
    sudo usermod -aG docker $USER
    
    if systemctl is-active --quiet docker; then
        echo -e "${GREEN}✅ Docker installé et démarré${NC}"
        send_notification "SUCCESS" "Docker installé" "Distribution: $distro
Version: $(docker --version)"
        return 0
    else
        echo -e "${RED}❌ Problème avec l'installation de Docker${NC}"
        return 1
    fi
}

# Installation Node.js via NodeSource
install_nodejs() {
    echo -e "${YELLOW}📦 Installation de Node.js...${NC}"
    
    local distro=$(detect_distro)
    local node_version="${1:-18}"  # Version par défaut
    
    case $distro in
        ubuntu|debian)
            curl -fsSL https://deb.nodesource.com/setup_${node_version}.x | sudo -E bash -
            sudo apt-get install -y nodejs
            ;;
        fedora|centos|rhel)
            curl -fsSL https://rpm.nodesource.com/setup_${node_version}.x | sudo bash -
            sudo dnf install -y nodejs npm
            ;;
        *)
            echo -e "${YELLOW}⚠️  Installation via gestionnaire de paquets par défaut${NC}"
            install_package "nodejs"
            install_package "npm"
            ;;
    esac
    
    if command -v node &> /dev/null && command -v npm &> /dev/null; then
        local node_ver=$(node --version)
        local npm_ver=$(npm --version)
        echo -e "${GREEN}✅ Node.js $node_ver et npm $npm_ver installés${NC}"
        send_notification "SUCCESS" "Node.js installé" "Node.js: $node_ver
npm: $npm_ver"
        return 0
    else
        echo -e "${RED}❌ Échec de l'installation de Node.js${NC}"
        return 1
    fi
}

# Installation Python et pip
install_python() {
    echo -e "${CYAN}🐍 Installation de Python et pip...${NC}"
    
    local distro=$(detect_distro)
    local python_version="${1:-3}"
    
    case $distro in
        ubuntu|debian)
            sudo apt update
            sudo apt install -y python${python_version} python${python_version}-pip python${python_version}-venv
            ;;
        fedora|centos|rhel)
            sudo dnf install -y python${python_version} python${python_version}-pip
            ;;
        arch)
            sudo pacman -S --noconfirm python python-pip
            ;;
        *)
            install_package "python${python_version}"
            install_package "python${python_version}-pip"
            ;;
    esac
    
    # Vérifier l'installation
    if command -v python3 &> /dev/null && command -v pip3 &> /dev/null; then
        local python_ver=$(python3 --version)
        local pip_ver=$(pip3 --version | awk '{print $2}')
        echo -e "${GREEN}✅ $python_ver et pip $pip_ver installés${NC}"
        
        # Mettre à jour pip
        python3 -m pip install --upgrade pip
        
        send_notification "SUCCESS" "Python installé" "Version: $python_ver
pip: $pip_ver"
        return 0
    else
        echo -e "${RED}❌ Échec de l'installation de Python${NC}"
        return 1
    fi
}

# Installation des outils de développement
install_dev_tools() {
    echo -e "${BLUE}🛠️  Installation des outils de développement...${NC}"
    
    local distro=$(detect_distro)
    local tools=("git" "curl" "wget" "vim" "nano" "htop" "tree" "zip" "unzip")
    local failed=0
    
    # Ajouter des outils spécifiques selon la distribution
    case $distro in
        ubuntu|debian)
            tools+=("build-essential" "software-properties-common")
            ;;
        fedora|centos|rhel)
            tools+=("gcc" "gcc-c++" "make" "kernel-devel")
            ;;
        arch)
            tools+=("base-devel")
            ;;
    esac
    
    echo -e "${CYAN}📋 Installation de ${#tools[@]} outils...${NC}"
    
    for tool in "${tools[@]}"; do
        echo -n "  • $tool... "
        if install_package "$tool" > /dev/null 2>&1; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌${NC}"
            failed=$((failed + 1))
        fi
    done
    
    echo ""
    echo -e "${BLUE}📊 Résumé:${NC}"
    echo -e "  ${GREEN}✅ Réussis: $((${#tools[@]} - failed))/${#tools[@]}${NC}"
    echo -e "  ${RED}❌ Échecs: $failed/${#tools[@]}${NC}"
    
    if [ $failed -eq 0 ]; then
        send_notification "SUCCESS" "Outils de développement installés" "Tous les outils ont été installés avec succès
Distribution: $distro"
    else
        send_notification "WARNING" "Installation partielle des outils" "Échecs: $failed/${#tools[@]}
Distribution: $distro"
    fi
}

# Installation des applications multimédia
install_multimedia() {
    echo -e "${PURPLE}🎬 Installation des applications multimédia...${NC}"
    
    local distro=$(detect_distro)
    local multimedia_apps=("vlc" "gimp" "audacity" "ffmpeg")
    
    # Activer les dépôts nécessaires
    case $distro in
        ubuntu|debian)
            # Activer les dépôts universe et multiverse
            sudo apt update
            ;;
        fedora)
            # Activer RPM Fusion
            sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
            sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
            ;;
    esac
    
    for app in "${multimedia_apps[@]}"; do
        install_package "$app"
    done
    
    send_notification "INFO" "Applications multimédia installées" "Applications: ${multimedia_apps[*]}
Distribution: $distro"
}

# Menu d'installation
show_installation_menu() {
    echo -e "${CYAN}📦 INSTALLATEUR AUTOMATIQUE D'APPLICATIONS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. 🔄 Mettre à jour le système"
    echo "2. 🛠️  Installer les outils de développement"
    echo "3. 🐳 Installer Docker"
    echo "4. 📦 Installer Node.js"
    echo "5. 🐍 Installer Python"
    echo "6. 🎬 Installer les applications multimédia"
    echo "7. 📦 Installer un paquet personnalisé"
    echo "8. 🔧 Installation complète (recommandée)"
    echo "9. 📋 Afficher les informations système"
    echo "0. ❌ Quitter"
    echo ""
    echo -n "Choisissez une option: "
}

# Installation complète
full_installation() {
    echo -e "${GREEN}🚀 INSTALLATION COMPLÈTE${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo -e "${BLUE}Cette installation comprend:${NC}"
    echo "• Mise à jour du système"
    echo "• Outils de développement"
    echo "• Docker"
    echo "• Node.js"
    echo "• Python"
    echo "• Applications multimédia"
    echo ""
    
    read -p "Continuer ? (o/N): " confirm
    if [[ $confirm =~ ^[Oo]$ ]]; then
        update_system
        echo ""
        install_dev_tools
        echo ""
        install_docker
        echo ""
        install_nodejs
        echo ""
        install_python
        echo ""
        install_multimedia
        
        echo -e "${GREEN}🎉 Installation complète terminée !${NC}"
        send_notification "SUCCESS" "Installation complète terminée" "Toutes les applications ont été installées
Distribution: $(detect_distro)"
    else
        echo "Installation annulée"
    fi
}

# Afficher les informations système
show_system_info() {
    local distro=$(detect_distro)
    local package_manager=$(get_package_manager "$distro")
    
    echo -e "${CYAN}💻 INFORMATIONS SYSTÈME${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}🖥️  Hostname:${NC} $HOSTNAME"
    echo -e "${BLUE}🐧 Distribution:${NC} $distro"
    echo -e "${BLUE}📦 Gestionnaire de paquets:${NC} $package_manager"
    echo -e "${BLUE}👤 Utilisateur:${NC} $USER"
    echo -e "${BLUE}🏠 Répertoire home:${NC} $HOME"
    echo -e "${BLUE}🗂️  Répertoire actuel:${NC} $(pwd)"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "${BLUE}📋 Version:${NC} $PRETTY_NAME"
    fi
    
    echo -e "${BLUE}🧮 Architecture:${NC} $(uname -m)"
    echo -e "${BLUE}🔧 Kernel:${NC} $(uname -r)"
    
    # Vérifier les applications installées
    echo ""
    echo -e "${BLUE}📦 Applications installées:${NC}"
    local apps=("docker" "node" "python3" "git" "curl" "vim")
    for app in "${apps[@]}"; do
        if command -v "$app" &> /dev/null; then
            local version=$(command -v "$app" && $app --version 2>/dev/null | head -1)
            echo -e "  ${GREEN}✅ $app${NC}: $(echo $version | awk '{print $NF}')"
        else
            echo -e "  ${RED}❌ $app${NC}: non installé"
        fi
    done
}

# Fonction principale
main() {
    # Vérifier les privilèges
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}⚠️  Ce script ne doit pas être exécuté en tant que root${NC}"
        echo "Veuillez l'exécuter en tant qu'utilisateur normal avec sudo"
        exit 1
    fi
    
    # Vérifier sudo
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}🔐 Privilèges sudo requis${NC}"
        sudo true || {
            echo -e "${RED}❌ Impossible d'obtenir les privilèges sudo${NC}"
            exit 1
        }
    fi
    
    if [ "$1" = "--full" ]; then
        full_installation
        exit 0
    fi
    
    # Menu interactif
    while true; do
        clear
        show_installation_menu
        read -r choice
        
        case $choice in
            1)
                clear
                update_system
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            2)
                clear
                install_dev_tools
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            3)
                clear
                install_docker
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            4)
                clear
                read -p "Version de Node.js (défaut: 18): " node_version
                node_version=${node_version:-18}
                install_nodejs "$node_version"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            5)
                clear
                read -p "Version de Python (défaut: 3): " python_version
                python_version=${python_version:-3}
                install_python "$python_version"
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            6)
                clear
                install_multimedia
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            7)
                clear
                read -p "Nom du paquet à installer: " package_name
                if [ ! -z "$package_name" ]; then
                    install_package "$package_name"
                fi
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            8)
                clear
                full_installation
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            9)
                clear
                show_system_info
                read -p "Appuyez sur Entrée pour continuer..."
                ;;
            0)
                echo -e "${GREEN}👋 Au revoir !${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Option invalide${NC}"
                sleep 2
                ;;
        esac
    done
}

# Exécution
main "$@"