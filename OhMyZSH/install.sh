#############################################
#     SH1NYDISK SHELL USER INSTALLATION     #
#############################################

#!/bin/bash

# Detect the package manager
install_dependencies() {
    echo "Detecting the package manager..."

    if command -v apt >/dev/null 2>&1; then
        echo "APT detected. Installing dependencies..."
        sudo apt update
        sudo apt install -y zsh git curl ruby-full

    elif command -v dnf >/dev/null 2>&1; then
        echo "DNF detected. Installing dependencies..."
        sudo dnf install -y zsh git curl ruby

    elif command -v yum >/dev/null 2>&1; then
        echo "YUM detected. Installing dependencies..."
        sudo yum install -y zsh git curl ruby

    elif command -v brew >/dev/null 2>&1; then
        echo "Homebrew detected. Installing dependencies..."
        brew install zsh git curl ruby

    else
        echo "No compatible package manager found. Please install zsh, git, curl, and ruby manually."
        exit 1
    fi
}

# Install Oh My Zsh
install_ohmyzsh() {
    if [ ! -d "${HOME}/.oh-my-zsh" ]; then
        echo "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
        echo "Oh My Zsh is already installed."
    fi
}

# Install PowerLevel10k
install_powerlevel10k() {
    POWERLEVEL10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [ ! -d "$POWERLEVEL10K_DIR" ]; then
        echo "Installing PowerLevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$POWERLEVEL10K_DIR"
    else
        echo "PowerLevel10k is already installed."
    fi
}

# Install Zsh plugins
install_plugins() {
    PLUGINS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"

    echo "Installing Zsh plugins..."

    # Plugin zsh-autosuggestions
    if [ ! -d "${PLUGINS_DIR}/zsh-autosuggestions" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "${PLUGINS_DIR}/zsh-autosuggestions"
    fi

    # Plugin zsh-syntax-highlighting
    if [ ! -d "${PLUGINS_DIR}/zsh-syntax-highlighting" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${PLUGINS_DIR}/zsh-syntax-highlighting"
    fi

    # Plugin zsh-completions
    if [ ! -d "${PLUGINS_DIR}/zsh-completions" ]; then
        git clone https://github.com/zsh-users/zsh-completions "${PLUGINS_DIR}/zsh-completions"
    fi
}

# Install Colorls
install_colorls() {
    echo "Installing Colorls..."
    if ! command -v colorls >/dev/null 2>&1; then
        sudo gem install colorls
    else
        echo "Colorls is already installed."
    fi
}

# Configure .zshrc
configure_zshrc() {
    echo "Configuring .zshrc..."

    # Set PowerLevel10k theme
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"

    # Add plugins
    if grep -q '^plugins=' "$HOME/.zshrc"; then
        sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' "$HOME/.zshrc"
    else
        echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)' >> "$HOME/.zshrc"
    fi

    # Add Colorls aliases
    cat <<'EOF' >> "$HOME/.zshrc"

# COLORLS
alias ll="colorls -l" # Simple list
alias ld="colorls -ld" # Directory list
alias lf="colorls -lf" # File list
alias la="colorls -lA" # All list

# Heat gradient (blue to red) with green
HOT_BLUE="\033[38;5;33m"      # Hot blue
LIGHT_BLUE="\033[38;5;39m"    # Light blue
TEAL="\033[38;5;45m"          # Teal
GREEN="\033[38;5;82m"         # Green
ORANGE="\033[38;5;208m"       # Orange
LIGHT_ORANGE="\033[38;5;214m" # Light orange
RED="\033[38;5;196m"          # Red
PURPLE="\033[38;5;129m"       # Purple
BOLD="\033[1m"
RESET="\033[0m"

echo ""
echo -e "${BOLD}${TEAL}  👤 User:${RESET} $(whoami)"
echo -e "${BOLD}${LIGHT_BLUE}  💻 Hostname:${RESET} $(hostname)"
echo -e "${BOLD}${HOT_BLUE}  🛜 Local IPv4:${RESET} $(ipconfig getifaddr en0 2>/dev/null || echo 'N/A')"
echo -e "${BOLD}${PURPLE}  🌍 Public IPv4:${RESET} $(curl -s ifconfig.me)"
echo -e "${BOLD}${GREEN}  ⏳ Uptime:${RESET} $(uptime -p)"
echo -e "${BOLD}${RED}  💾 Space:${RESET} $(df -h | grep '/$' | awk '{print $4 " free of " $2}')"
echo ""
EOF

    echo "Reloading Zsh configuration..."
    source "$HOME/.zshrc"
}

# Call functions
install_dependencies
install_ohmyzsh
install_powerlevel10k
install_plugins
install_colorls
configure_zshrc

echo -e "\nInstallation and configuration complete."
echo "Restart your terminal or run 'zsh' to see the changes."