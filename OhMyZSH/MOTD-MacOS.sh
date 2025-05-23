# Improved Custom MOTD Banner for iTerm2 (MacOS)
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

  # Gather information (without additional spaces)
  local user_info="${bold}${blue} User:${reset} $(whoami)"
  local host_info="${bold}${green}󰒋 Hostname:${reset} $(hostname)"
  local local_ip="${bold}${yellow}󰩠 Local IPv4:${reset} $(ipconfig getifaddr en0 2>/dev/null || echo "N/A")"
  local public_ip="${bold}${cyan} Public IPv4:${reset} $(curl -s ifconfig.io || echo "N/A")"
  local uptime_info="${bold}${magenta} Uptime:${reset} $(uptime | awk -F'( |,|:)+' '{if ($6 ~ /day/) {print $6" "$7"h "$8"m"} else {print $6"h "$7"m"}}')"
  local disk_space="${bold}${green} Space:${reset} $(df -h / | awk 'NR==2 {print $4}')"
  local shell_info="${bold}${cyan} Shell:${reset} $(basename $SHELL)"
  local datetime_info="${bold}${yellow} Date/Time:${reset} $(date '+%Y-%m-%d %H:%M:%S')"

  # Display banner (printf instead of echo -e)
  printf "\n"
  figlet -f slant "Welcome!" | lolcat
  printf "%s\n" "$separator" | lolcat
  printf "%s\n" "$user_info"
  printf "%s\n" "$host_info"
  printf "%s\n" "$local_ip"
  printf "%s\n" "$public_ip"
  printf "%s\n" "$uptime_info"
  printf "%s\n" "$disk_space"
  printf "%s\n" "$shell_info"
  printf "%s\n" "$datetime_info"
  printf "%s\n\n" "$separator" | lolcat
}

# Call the function
custom_banner