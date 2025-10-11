# Custom MOTD Banner for Rocky Linux Docker Host
custom_banner() {
  # Colors & Styles
  local bold=$(tput bold)
  local reset=$(tput sgr0)
  local blue=$(tput setaf 4)
  local green=$(tput setaf 2)
  local yellow=$(tput setaf 3)
  local cyan=$(tput setaf 6)
  local magenta=$(tput setaf 5)

  # Decorative separator
  local separator="$(printf '%*s' "${COLUMNS:-$(tput cols)}" '' | tr ' ' '=')"

  # Gather info
  local user_info="${bold}${blue} User:${reset} $(whoami)"
  local host_info="${bold}${green}󰒋 Hostname:${reset} $(hostname)"
  local local_ip="${bold}${yellow}󰩠 Local IPv4:${reset} $(hostname -I | awk '{print $1}')"
  local public_ip="${bold}${cyan} Public IPv4:${reset} $(curl -s ifconfig.me || echo "N/A")"
  local uptime_info="${bold}${magenta} Uptime:${reset} $(uptime -p)"
  local disk_root_space="${bold}${green} Space (/root):${reset} $(df -h / | awk 'NR==2 {print $4}')"
  local disk_home_space="${bold}${green} Space (/home):${reset} $(df -h /home | awk 'NR==2 {print $4}')"
  local docker_info="${bold}${cyan} Docker Containers:${reset} $(docker ps -q | wc -l) running"
  local shell_info="${bold}${cyan} Shell:${reset} $(basename $SHELL)"
  local datetime_info="${bold}${yellow} Date/Time:${reset} $(date '+%Y-%m-%d %H:%M:%S')"

  # Display
  printf "\n"
  figlet -f slant "Rocky Host" | lolcat
  printf "%s\n" "$separator" | lolcat
  printf "%s\n" "$user_info"
  printf "%s\n" "$host_info"
  printf "%s\n" "$local_ip"
  printf "%s\n" "$public_ip"
  printf "%s\n" "$uptime_info"
  printf "%s\n" "$disk_root_space"
  printf "%s\n" "$disk_home_space"
  printf "%s\n" "$docker_info"
  printf "%s\n" "$shell_info"
  printf "%s\n" "$datetime_info"
  printf "%s\n\n" "$separator" | lolcat
}

# Appel de la fonction
custom_banner