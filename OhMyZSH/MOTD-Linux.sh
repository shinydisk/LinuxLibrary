# Function to display the custom banner
custom_banner() {
  # Colors
  local bold=$(tput bold)
  local reset=$(tput sgr0)
  local blue=$(tput setaf 4)
  local green=$(tput setaf 2)
  local yellow=$(tput setaf 3)
  local cyan=$(tput setaf 6)

  # Information
  local user="  ${bold}${blue}User:${reset} $(whoami)"
  local hostname="  ${bold}${green}Hostname:${reset} $(hostname)"
  local local_ip="  ${bold}${yellow}Local IPv4:${reset} $(ipconfig getifaddr en0 2>/dev/null || echo "N/A")"
  local public_ip="  ${bold}${cyan}Public IPv4:${reset} $(curl -s https://api.ipify.org || echo "N/A")"
  local uptime="  ${bold}${blue}Uptime:${reset} $(uptime | awk -F'( |,|:)+' '{if ($6 ~ /day/) {print $6 " " $7 " hours " $8 " minutes"} else {print $6 " hours " $7 " minutes"}}')"
  local space="  ${bold}${green}Space:${reset} $(df -h / | awk 'NR==2 {print $4}')"
  
  # Optional: Additional information
  local shell="  ${bold}${cyan}Shell:${reset} $SHELL"
  local date_time="  ${bold}${yellow}Date/Time:${reset} $(date)"

  # Print Figlet title with lolcat
  echo ""
  echo "Be Strong" | figlet | lolcat
  echo "$user"
  echo "$hostname"
  echo "$local_ip"
  echo "$public_ip"
  echo "$uptime"
  echo "$space"
  echo "$shell"
  echo "$date_time"
  echo " -------------------------------------------" | lolcat
  echo ""
}

# Call the banner function
custom_banner