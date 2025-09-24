#!/bin/bash
# ==========================================
# Samba Active Directory Manager
# Direct management from Samba AD server
# Compatible with all Samba AD versions
# ==========================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Global variables
SELECTED_OBJECT=""
SELECTED_OBJECT_TYPE=""
DOMAIN_DN=""
DOMAIN_NAME=""

# Function to clear screen and show header
show_header() {
    clear
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}       SAMBA AD MANAGER - LINUX          ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo ""
    if [ ! -z "$DOMAIN_NAME" ]; then
        echo -e "${GREEN}Welcome to Samba AD Manager!${NC}"
    echo -e "${YELLOW}Initializing...${NC}"
    echo ""
    
    # Initialize domain information
    if init_domain; then
        echo ""
        echo -e "${GREEN}✓ Ready to manage Active Directory${NC}"
        sleep 2
        show_main_menu
    else
        echo ""
        echo -e "${RED}✗ Failed to initialize domain${NC}"
        echo -e "${YELLOW}Please check if this is a Samba AD server${NC}"
        exit 1
    fi
}

# Run main function
main "$@"Connected to domain: $DOMAIN_NAME${NC}"
        echo -e "${GREEN}Domain DN: $DOMAIN_DN${NC}"
        echo ""
    fi
}

# Function to pause execution
pause() {
    echo ""
    read -p "Press Enter to continue..." dummy
}

# Function to initialize domain info
init_domain() {
    echo -e "${YELLOW}Initializing domain information...${NC}"
    
    # Get domain info from Samba
    DOMAIN_NAME=$(samba-tool domain info 127.0.0.1 2>/dev/null | grep "Domain" | head -1 | awk '{print $3}' | tr -d '\r')
    if [ -z "$DOMAIN_NAME" ]; then
        # Fallback: try to get from smb.conf
        DOMAIN_NAME=$(testparm -s 2>/dev/null | grep "workgroup" | awk '{print $3}' | tr -d '\r')
    fi
    
    # Convert domain name to DN format
    if [ ! -z "$DOMAIN_NAME" ]; then
        DOMAIN_DN="DC=${DOMAIN_NAME//./,DC=}"
        echo -e "${GREEN}✓ Domain detected: $DOMAIN_NAME${NC}"
        echo -e "${GREEN}✓ Domain DN: $DOMAIN_DN${NC}"
        return 0
    else
        echo -e "${RED}✗ Could not detect domain information${NC}"
        echo -e "${YELLOW}Make sure you're running this on a Samba AD server${NC}"
        return 1
    fi
}

# Function to browse OUs
browse_ous() {
    local title="$1"
    local current_ou="$2"
    
    if [ -z "$current_ou" ]; then
        current_ou="$DOMAIN_DN"
    fi
    
    while true; do
        show_header
        echo -e "${GREEN}$title${NC}"
        echo ""
        echo -e "${YELLOW}Current Location: $current_ou${NC}"
        echo ""
        
        # Get child OUs and containers
        echo -e "${CYAN}NAVIGATION:${NC}"
        echo -e "${CYAN}==========${NC}"
        
        if [ "$current_ou" != "$DOMAIN_DN" ]; then
            echo -e "${WHITE}0. Go Up (Parent OU)${NC}"
        fi
        echo -e "${GREEN}S. Select Current OU${NC}"
        echo -e "${RED}X. Cancel${NC}"
        echo ""
        
        # List child OUs
        local ous_found=false
        local counter=1
        
        echo -e "${CYAN}CHILD ORGANIZATIONAL UNITS:${NC}"
        echo -e "${CYAN}=============================${NC}"
        
        # Create temporary file to store OU list
        local ou_list="/tmp/samba_ou_list_$$"
        samba-tool ou list 2>/dev/null | grep "$current_ou" | grep -v "^$current_ou$" > "$ou_list"
        
        # Also get containers
        ldbsearch -H /var/lib/samba/private/sam.ldb "(&(objectClass=container)(!(objectClass=organizationalUnit)))" dn 2>/dev/null | grep "dn:" | awk '{print $2}' | grep "$current_ou" >> "$ou_list"
        
        if [ -s "$ou_list" ]; then
            while IFS= read -r ou_dn; do
                if [[ "$ou_dn" =~ ^(OU=|CN=)([^,]+),(.*)$ ]]; then
                    local ou_type="${BASH_REMATCH[1]%=}"
                    local ou_name="${BASH_REMATCH[2]}"
                    local parent_dn="${BASH_REMATCH[3]}"
                    
                    if [ "$parent_dn" = "$current_ou" ]; then
                        local icon="[OU]"
                        if [ "$ou_type" = "CN" ]; then
                            icon="[CN]"
                        fi
                        echo -e "${YELLOW}$counter. $icon $ou_name${NC}"
                        eval "ou_option_$counter=\"$ou_dn\""
                        ((counter++))
                        ous_found=true
                    fi
                fi
            done < "$ou_list"
        fi
        
        rm -f "$ou_list"
        
        if [ "$ous_found" = false ]; then
            echo -e "${GRAY}No child OUs found.${NC}"
        fi
        
        echo ""
        read -p "Choose an option: " choice
        
        case "${choice^^}" in
            "0")
                if [ "$current_ou" != "$DOMAIN_DN" ]; then
                    # Extract parent DN
                    current_ou=$(echo "$current_ou" | sed 's/^[^,]*,//')
                fi
                ;;
            "S")
                echo "$current_ou"
                return 0
                ;;
            "X")
                return 1
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -gt 0 ]; then
                    local selected_var="ou_option_$choice"
                    local selected_ou="${!selected_var}"
                    if [ ! -z "$selected_ou" ]; then
                        current_ou="$selected_ou"
                    else
                        echo -e "${RED}Invalid option!${NC}"
                        sleep 1
                    fi
                else
                    echo -e "${RED}Invalid option!${NC}"
                    sleep 1
                fi
                ;;
        esac
    done
}

# Function to select user
select_user() {
    local title="$1"
    
    while true; do
        show_header
        echo -e "${GREEN}$title${NC}"
        echo ""
        
        echo -e "${WHITE}1. Search by name/login${NC}"
        echo -e "${WHITE}2. Browse by OU${NC}"
        echo -e "${RED}0. Cancel${NC}"
        echo ""
        
        read -p "Choose search method: " choice
        
        case "$choice" in
            "1")
                echo ""
                read -p "Enter search term: " search_term
                if [ ! -z "$search_term" ]; then
                    search_and_select_users "$search_term" "$title"
                    return $?
                fi
                ;;
            "2")
                local selected_ou
                selected_ou=$(browse_ous "Select OU to browse users")
                if [ $? -eq 0 ] && [ ! -z "$selected_ou" ]; then
                    list_and_select_users_from_ou "$selected_ou" "$title"
                    return $?
                fi
                ;;
            "0")
                return 1
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Function to search and select users
search_and_select_users() {
    local search_term="$1"
    local title="$2"
    
    show_header
    echo -e "${YELLOW}Searching for users with term: $search_term${NC}"
    echo ""
    
    # Create temporary file for search results
    local user_list="/tmp/samba_users_$$"
    samba-tool user list 2>/dev/null | grep -i "$search_term" > "$user_list"
    
    if [ ! -s "$user_list" ]; then
        echo -e "${YELLOW}No users found!${NC}"
        rm -f "$user_list"
        pause
        return 1
    fi
    
    echo -e "${CYAN}SEARCH RESULTS:${NC}"
    echo -e "${CYAN}===============${NC}"
    echo ""
    
    local counter=1
    while IFS= read -r username; do
        echo -e "${YELLOW}$counter. $username${NC}"
        
        # Get user details
        local user_info=$(samba-tool user show "$username" 2>/dev/null)
        if [ ! -z "$user_info" ]; then
            local email=$(echo "$user_info" | grep "mail:" | awk '{print $2}')
            local dn=$(echo "$user_info" | grep "dn:" | awk '{print $2}')
            
            if [ ! -z "$email" ]; then
                echo -e "    ${GRAY}Email: $email${NC}"
            fi
            echo -e "    ${GRAY}DN: $dn${NC}"
        fi
        
        eval "user_option_$counter=\"$username\""
        echo ""
        ((counter++))
    done < "$user_list"
    
    echo -e "${RED}0. Cancel${NC}"
    echo ""
    
    read -p "Select user by number: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ]; then
        local selected_var="user_option_$selection"
        local selected_user="${!selected_var}"
        if [ ! -z "$selected_user" ]; then
            SELECTED_OBJECT="$selected_user"
            SELECTED_OBJECT_TYPE="User"
            rm -f "$user_list"
            return 0
        fi
    fi
    
    rm -f "$user_list"
    return 1
}

# Function to list and select users from OU
list_and_select_users_from_ou() {
    local ou_dn="$1"
    local title="$2"
    
    show_header
    echo -e "${YELLOW}Users in OU: $ou_dn${NC}"
    echo ""
    
    # Get users from specific OU using ldbsearch
    local user_list="/tmp/samba_ou_users_$$"
    ldbsearch -H /var/lib/samba/private/sam.ldb -b "$ou_dn" -s one "(&(objectClass=user)(!(objectClass=computer)))" sAMAccountName mail 2>/dev/null | grep -E "(sAMAccountName|mail):" > "$user_list"
    
    if [ ! -s "$user_list" ]; then
        echo -e "${YELLOW}No users found in this OU!${NC}"
        rm -f "$user_list"
        pause
        return 1
    fi
    
    echo -e "${CYAN}USERS FOUND:${NC}"
    echo -e "${CYAN}============${NC}"
    echo ""
    
    local counter=1
    local current_user=""
    local current_email=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ sAMAccountName:\ (.+) ]]; then
            current_user="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ mail:\ (.+) ]]; then
            current_email="${BASH_REMATCH[1]}"
        fi
        
        # If we have a username and potentially an email, display it
        if [ ! -z "$current_user" ]; then
            echo -e "${YELLOW}$counter. $current_user${NC}"
            if [ ! -z "$current_email" ]; then
                echo -e "    ${GRAY}Email: $current_email${NC}"
            fi
            
            eval "user_option_$counter=\"$current_user\""
            echo ""
            ((counter++))
            
            # Reset for next user
            current_user=""
            current_email=""
        fi
    done < "$user_list"
    
    echo -e "${RED}0. Cancel${NC}"
    echo ""
    
    read -p "Select user by number: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ]; then
        local selected_var="user_option_$selection"
        local selected_user="${!selected_var}"
        if [ ! -z "$selected_user" ]; then
            SELECTED_OBJECT="$selected_user"
            SELECTED_OBJECT_TYPE="User"
            rm -f "$user_list"
            return 0
        fi
    fi
    
    rm -f "$user_list"
    return 1
}

# Function to create user
create_user() {
    show_header
    echo -e "${GREEN}CREATE NEW USER${NC}"
    echo -e "${GREEN}===============${NC}"
    echo ""
    
    read -p "Username (login): " username
    if [ -z "$username" ]; then
        echo -e "${RED}Username is required!${NC}"
        pause
        return
    fi
    
    read -s -p "Password: " password
    echo ""
    if [ -z "$password" ]; then
        echo -e "${RED}Password is required!${NC}"
        pause
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Select target OU for the new user...${NC}"
    local target_ou
    target_ou=$(browse_ous "Select Target OU for New User")
    
    if [ $? -ne 0 ] || [ -z "$target_ou" ]; then
        echo -e "${YELLOW}User creation cancelled - no OU selected.${NC}"
        pause
        return
    fi
    
    read -p "First name (optional): " firstname
    read -p "Last name (optional): " lastname
    read -p "Email (optional): " email
    read -p "Description (optional): " description
    
    echo ""
    echo -e "${YELLOW}Creating user...${NC}"
    
    # Build samba-tool command
    local cmd="samba-tool user create \"$username\" \"$password\""
    
    if [ ! -z "$firstname" ]; then
        cmd="$cmd --given-name=\"$firstname\""
    fi
    
    if [ ! -z "$lastname" ]; then
        cmd="$cmd --surname=\"$lastname\""
    fi
    
    if [ ! -z "$email" ]; then
        cmd="$cmd --mail-address=\"$email\""
    fi
    
    if [ ! -z "$description" ]; then
        cmd="$cmd --description=\"$description\""
    fi
    
    # Execute user creation
    if eval "$cmd" 2>/dev/null; then
        echo -e "${GREEN}✓ User $username created successfully!${NC}"
        
        # Move user to selected OU if not default
        if [ "$target_ou" != "$DOMAIN_DN" ] && [ "$target_ou" != "CN=Users,$DOMAIN_DN" ]; then
            echo -e "${YELLOW}Moving user to selected OU...${NC}"
            local user_dn="CN=$username,CN=Users,$DOMAIN_DN"
            if samba-tool user move "$user_dn" "$target_ou" 2>/dev/null; then
                echo -e "${GREEN}✓ User moved to $target_ou${NC}"
            else
                echo -e "${YELLOW}! User created but could not be moved to target OU${NC}"
            fi
        fi
    else
        echo -e "${RED}✗ Failed to create user!${NC}"
    fi
    
    pause
}

# Function to change user password
change_user_password() {
    show_header
    echo -e "${GREEN}CHANGE USER PASSWORD${NC}"
    echo -e "${GREEN}====================${NC}"
    echo ""
    
    if select_user "Select user to change password"; then
        echo ""
        echo -e "${YELLOW}Selected user: $SELECTED_OBJECT${NC}"
        read -s -p "Enter new password: " new_password
        echo ""
        
        if [ ! -z "$new_password" ]; then
            if samba-tool user setpassword "$SELECTED_OBJECT" --newpassword="$new_password" 2>/dev/null; then
                echo -e "${GREEN}✓ Password changed successfully!${NC}"
            else
                echo -e "${RED}✗ Failed to change password!${NC}"
            fi
        else
            echo -e "${RED}Password cannot be empty!${NC}"
        fi
    else
        echo -e "${YELLOW}Operation cancelled.${NC}"
    fi
    
    pause
}

# Function to enable/disable user
toggle_user_account() {
    local operation="$1"
    local title="$2"
    
    show_header
    echo -e "${GREEN}$title${NC}"
    echo -e "${GREEN}$(echo "$title" | sed 's/./=/g')${NC}"
    echo ""
    
    if select_user "Select user to $operation"; then
        echo ""
        echo -e "${YELLOW}Selected user: $SELECTED_OBJECT${NC}"
        
        if [ "$operation" = "enable" ]; then
            if samba-tool user enable "$SELECTED_OBJECT" 2>/dev/null; then
                echo -e "${GREEN}✓ User account enabled successfully!${NC}"
            else
                echo -e "${RED}✗ Failed to enable user account!${NC}"
            fi
        else
            if samba-tool user disable "$SELECTED_OBJECT" 2>/dev/null; then
                echo -e "${GREEN}✓ User account disabled successfully!${NC}"
            else
                echo -e "${RED}✗ Failed to disable user account!${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Operation cancelled.${NC}"
    fi
    
    pause
}

# Function to add user to group
add_user_to_group() {
    show_header
    echo -e "${GREEN}ADD USER TO GROUP${NC}"
    echo -e "${GREEN}=================${NC}"
    echo ""
    
    if select_user "Select user to add to group"; then
        echo ""
        echo -e "${YELLOW}Selected user: $SELECTED_OBJECT${NC}"
        read -p "Group name: " group_name
        
        if [ ! -z "$group_name" ]; then
            if samba-tool group addmembers "$group_name" "$SELECTED_OBJECT" 2>/dev/null; then
                echo -e "${GREEN}✓ User added to group successfully!${NC}"
            else
                echo -e "${RED}✗ Failed to add user to group!${NC}"
                echo -e "${YELLOW}Make sure the group exists.${NC}"
            fi
        else
            echo -e "${RED}Group name cannot be empty!${NC}"
        fi
    else
        echo -e "${YELLOW}Operation cancelled.${NC}"
    fi
    
    pause
}

# Function to remove user
remove_user() {
    show_header
    echo -e "${RED}REMOVE USER${NC}"
    echo -e "${RED}===========${NC}"
    echo ""
    
    if select_user "Select user to remove"; then
        echo ""
        echo -e "${YELLOW}Selected user: $SELECTED_OBJECT${NC}"
        echo -e "${RED}WARNING: This action cannot be undone!${NC}"
        echo ""
        
        read -p "Are you sure you want to delete user $SELECTED_OBJECT? (yes/no): " confirm
        
        if [ "${confirm,,}" = "yes" ]; then
            if samba-tool user delete "$SELECTED_OBJECT" 2>/dev/null; then
                echo -e "${GREEN}✓ User removed successfully!${NC}"
                SELECTED_OBJECT=""
                SELECTED_OBJECT_TYPE=""
            else
                echo -e "${RED}✗ Failed to remove user!${NC}"
            fi
        else
            echo -e "${YELLOW}User removal cancelled.${NC}"
        fi
    else
        echo -e "${YELLOW}Operation cancelled.${NC}"
    fi
    
    pause
}

# Function to move user between OUs
move_user() {
    show_header
    echo -e "${GREEN}MOVE USER BETWEEN OUs${NC}"
    echo -e "${GREEN}=====================${NC}"
    echo ""
    
    if select_user "Select user to move"; then
        echo ""
        echo -e "${YELLOW}Selected user: $SELECTED_OBJECT${NC}"
        
        # Get current user DN
        local user_info=$(samba-tool user show "$SELECTED_OBJECT" 2>/dev/null)
        local current_dn=$(echo "$user_info" | grep "dn:" | awk '{print $2}')
        
        if [ ! -z "$current_dn" ]; then
            echo -e "${GRAY}Current OU: $current_dn${NC}"
            echo ""
            echo -e "${YELLOW}Select target OU...${NC}"
            
            local target_ou
            target_ou=$(browse_ous "Select Target OU")
            
            if [ $? -eq 0 ] && [ ! -z "$target_ou" ]; then
                if samba-tool user move "$current_dn" "$target_ou" 2>/dev/null; then
                    echo -e "${GREEN}✓ User moved successfully!${NC}"
                else
                    echo -e "${RED}✗ Failed to move user!${NC}"
                fi
            else
                echo -e "${YELLOW}Move operation cancelled.${NC}"
            fi
        else
            echo -e "${RED}Could not get user information!${NC}"
        fi
    else
        echo -e "${YELLOW}Operation cancelled.${NC}"
    fi
    
    pause
}

# Function to list users
list_users() {
    show_header
    echo -e "${CYAN}DOMAIN USERS${NC}"
    echo -e "${CYAN}============${NC}"
    echo ""
    
    echo -e "${YELLOW}Loading users...${NC}"
    
    # Get all users
    local user_count=0
    while IFS= read -r username; do
        if [ ! -z "$username" ]; then
            echo -e "${YELLOW}User: $username${NC}"
            
            # Get user details
            local user_info=$(samba-tool user show "$username" 2>/dev/null)
            if [ ! -z "$user_info" ]; then
                local email=$(echo "$user_info" | grep "mail:" | awk '{print $2}')
                local dn=$(echo "$user_info" | grep "dn:" | awk '{print $2}')
                
                if [ ! -z "$email" ]; then
                    echo -e "  ${GRAY}Email: $email${NC}"
                fi
                echo -e "  ${GRAY}DN: $dn${NC}"
            fi
            
            echo ""
            ((user_count++))
        fi
    done < <(samba-tool user list 2>/dev/null)
    
    echo -e "${GREEN}Total users found: $user_count${NC}"
    pause
}

# Function to list computers
list_computers() {
    show_header
    echo -e "${CYAN}DOMAIN COMPUTERS${NC}"
    echo -e "${CYAN}================${NC}"
    echo ""
    
    echo -e "${YELLOW}Loading computers...${NC}"
    
    # Get all computers using ldbsearch
    local computer_count=0
    local computer_list="/tmp/samba_computers_$$"
    
    ldbsearch -H /var/lib/samba/private/sam.ldb "(&(objectClass=computer))" sAMAccountName operatingSystem 2>/dev/null | grep -E "(sAMAccountName|operatingSystem):" > "$computer_list"
    
    local current_computer=""
    local current_os=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ sAMAccountName:\ (.+) ]]; then
            current_computer="${BASH_REMATCH[1]}"
            current_computer="${current_computer%$}"  # Remove trailing $
        elif [[ "$line" =~ operatingSystem:\ (.+) ]]; then
            current_os="${BASH_REMATCH[1]}"
        fi
        
        # If we have a computer name, display it
        if [ ! -z "$current_computer" ]; then
            echo -e "${YELLOW}Computer: $current_computer${NC}"
            if [ ! -z "$current_os" ]; then
                echo -e "  ${GRAY}OS: $current_os${NC}"
            fi
            echo ""
            
            ((computer_count++))
            
            # Reset for next computer
            current_computer=""
            current_os=""
        fi
    done < "$computer_list"
    
    rm -f "$computer_list"
    
    echo -e "${GREEN}Total computers found: $computer_count${NC}"
    pause
}

# Function to show OU structure
show_ou_structure() {
    show_header
    echo -e "${CYAN}OU STRUCTURE${NC}"
    echo -e "${CYAN}============${NC}"
    echo ""
    
    echo -e "${YELLOW}Domain OUs:${NC}"
    
    # List all OUs
    samba-tool ou list 2>/dev/null | while IFS= read -r ou_dn; do
        # Calculate indentation level
        local level=$(echo "$ou_dn" | grep -o ",OU=" | wc -l)
        local indent=""
        for ((i=0; i<level; i++)); do
            indent="  $indent"
        done
        
        # Extract OU name
        if [[ "$ou_dn" =~ ^OU=([^,]+) ]]; then
            local ou_name="${BASH_REMATCH[1]}"
            echo -e "${indent}${YELLOW}+ $ou_name${NC}"
            echo -e "${indent}  ${GRAY}$ou_dn${NC}"
        fi
    done
    
    pause
}

# Main menu function
show_main_menu() {
    while true; do
        show_header
        
        if [ ! -z "$SELECTED_OBJECT" ]; then
            echo -e "${YELLOW}SELECTED OBJECT: [$SELECTED_OBJECT_TYPE] $SELECTED_OBJECT${NC}"
            echo ""
        fi
        
        echo -e "${CYAN}MAIN MENU:${NC}"
        echo -e "${CYAN}==========${NC}"
        echo ""
        echo -e "${YELLOW}  STRUCTURE AND NAVIGATION:${NC}"
        echo -e "${WHITE}  1.  Show OU Structure${NC}"
        echo -e "${WHITE}  2.  List Users${NC}"
        echo -e "${WHITE}  3.  List Computers${NC}"
        echo ""
        echo -e "${YELLOW}  USER MANAGEMENT:${NC}"
        echo -e "${WHITE}  4.  Create User${NC}"
        echo -e "${WHITE}  5.  Change User Password${NC}"
        echo -e "${WHITE}  6.  Enable User Account${NC}"
        echo -e "${WHITE}  7.  Disable User Account${NC}"
        echo -e "${WHITE}  8.  Add User to Group${NC}"
        echo -e "${WHITE}  9.  Remove User${NC}"
        echo -e "${WHITE}  10. Move User between OUs${NC}"
        echo ""
        echo -e "${YELLOW}  SYSTEM:${NC}"
        echo -e "${WHITE}  98. Refresh Domain Info${NC}"
        echo -e "${WHITE}  99. About${NC}"
        echo -e "${RED}  0.  Exit${NC}"
        echo ""
        
        read -p "Choose an option: " choice
        
        case "$choice" in
            "1") show_ou_structure ;;
            "2") list_users ;;
            "3") list_computers ;;
            "4") create_user ;;
            "5") change_user_password ;;
            "6") toggle_user_account "enable" "ENABLE USER ACCOUNT" ;;
            "7") toggle_user_account "disable" "DISABLE USER ACCOUNT" ;;
            "8") add_user_to_group ;;
            "9") remove_user ;;
            "10") move_user ;;
            "98") 
                echo -e "${YELLOW}Refreshing domain information...${NC}"
                init_domain
                pause
                ;;
            "99")
                show_header
                echo -e "${CYAN}ABOUT SAMBA AD MANAGER${NC}"
                echo -e "${CYAN}======================${NC}"
                echo ""
                echo -e "${GREEN}Samba Active Directory Manager${NC}"
                echo -e "${WHITE}Version: 1.0${NC}"
                echo ""
                echo -e "${YELLOW}Compatibility:${NC}"
                echo -e "${WHITE}• Samba 4.x Active Directory${NC}"
                echo -e "${WHITE}• Direct server management${NC}"
                echo -e "${WHITE}• Linux/Unix environments${NC}"
                echo ""
                echo -e "${YELLOW}Features:${NC}"
                echo -e "${WHITE}• Complete user management${NC}"
                echo -e "${WHITE}• OU navigation and management${NC}"
                echo -e "${WHITE}• Visual interface${NC}"
                echo -e "${WHITE}• No external dependencies${NC}"
                echo ""
                echo -e "${YELLOW}Current status:${NC}"
                echo -e "${WHITE}• Domain: $DOMAIN_NAME${NC}"
                echo -e "${WHITE}• Domain DN: $DOMAIN_DN${NC}"
                if [ ! -z "$SELECTED_OBJECT" ]; then
                    echo -e "${WHITE}• Selected Object: [$SELECTED_OBJECT_TYPE] $SELECTED_OBJECT${NC}"
                fi
                pause
                ;;
            "0")
                echo -e "${GREEN}Exiting Samba AD Manager...${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Main execution
main() {
    # Check if running as root or with proper permissions
    if [ "$EUID" -ne 0 ] && [ ! -r "/var/lib/samba/private/sam.ldb" ]; then
        echo -e "${RED}Error: This script requires root privileges or access to Samba databases.${NC}"
        echo -e "${YELLOW}Please run as root: sudo $0${NC}"
        exit 1
    fi
    
    # Check if samba-tool is available
    if ! command -v samba-tool &> /dev/null; then
        echo -e "${RED}Error: samba-tool not found!${NC}"
        echo -e "${YELLOW}Please install Samba AD DC or run this on a Samba server.${NC}"
        exit 1
    fi
    
    show_header
    echo -e "${GREEN}
