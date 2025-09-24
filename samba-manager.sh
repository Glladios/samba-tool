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
        echo -e "${GREEN}Connected to domain: $DOMAIN_NAME${NC}"
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

# Function to browse OUs - simplified version
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
        
        echo -e "${CYAN}NAVIGATION:${NC}"
        echo -e "${CYAN}==========${NC}"
        
        if [ "$current_ou" != "$DOMAIN_DN" ]; then
            echo -e "${WHITE}0. Go Up (Parent OU)${NC}"
        fi
        echo -e "${GREEN}S. Select Current OU${NC}"
        echo -e "${RED}X. Cancel${NC}"
        echo ""
        
        # List child OUs using simple method
        echo -e "${CYAN}AVAILABLE OUs:${NC}"
        echo -e "${CYAN}==============${NC}"
        
        local counter=1
        local found_ous=false
        
        # Get OUs using samba-tool
        while IFS= read -r ou_line; do
            if [ ! -z "$ou_line" ] && [[ "$ou_line" == *"$current_ou"* ]]; then
                # Extract OU name from DN
                if [[ "$ou_line" =~ ^(OU=|CN=)([^,]+), ]]; then
                    local ou_name="${BASH_REMATCH[2]}"
                    local ou_type="${BASH_REMATCH[1]%=}"
                    local icon="[$ou_type]"
                    
                    echo -e "${YELLOW}$counter. $icon $ou_name${NC}"
                    echo -e "    ${GRAY}$ou_line${NC}"
                    
                    # Store the full DN for selection
                    eval "ou_choice_$counter=\"$ou_line\""
                    counter=$((counter + 1))
                    found_ous=true
                fi
            fi
        done < <(samba-tool ou list 2>/dev/null; echo "CN=Users,$DOMAIN_DN"; echo "CN=Computers,$DOMAIN_DN")
        
        if [ "$found_ous" = false ]; then
            echo -e "${GRAY}No child OUs found.${NC}"
        fi
        
        echo ""
        read -p "Choose an option: " choice
        
        case "${choice^^}" in
            "0")
                if [ "$current_ou" != "$DOMAIN_DN" ]; then
                    # Extract parent DN (remove first component)
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
                    local selected_var="ou_choice_$choice"
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

# Function to select user - simplified
select_user() {
    local title="$1"
    
    while true; do
        show_header
        echo -e "${GREEN}$title${NC}"
        echo ""
        
        echo -e "${WHITE}1. Search by name/login${NC}"
        echo -e "${WHITE}2. List all users${NC}"
        echo -e "${RED}0. Cancel${NC}"
        echo ""
        
        read -p "Choose search method: " choice
        
        case "$choice" in
            "1")
                echo ""
                read -p "Enter search term: " search_term
                if [ ! -z "$search_term" ]; then
                    if search_and_select_users "$search_term"; then
                        return 0
                    fi
                fi
                ;;
            "2")
                if list_and_select_users; then
                    return 0
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
    
    show_header
    echo -e "${YELLOW}Searching for users with term: $search_term${NC}"
    echo ""
    
    local counter=1
    local found_users=false
    
    echo -e "${CYAN}SEARCH RESULTS:${NC}"
    echo -e "${CYAN}===============${NC}"
    echo ""
    
    # Search in user list
    while IFS= read -r username; do
        if [[ "$username" == *"$search_term"* ]] || [[ "$username" =~ .*$(echo "$search_term" | tr '[:upper:]' '[:lower:]').* ]]; then
            echo -e "${YELLOW}$counter. $username${NC}"
            
            # Try to get additional info
            local user_info=$(samba-tool user show "$username" 2>/dev/null)
            if [ $? -eq 0 ]; then
                local email=$(echo "$user_info" | grep -i "mail:" | awk '{print $2}')
                if [ ! -z "$email" ]; then
                    echo -e "    ${GRAY}Email: $email${NC}"
                fi
            fi
            
            eval "user_choice_$counter=\"$username\""
            counter=$((counter + 1))
            found_users=true
            echo ""
        fi
    done < <(samba-tool user list 2>/dev/null)
    
    if [ "$found_users" = false ]; then
        echo -e "${YELLOW}No users found!${NC}"
        pause
        return 1
    fi
    
    echo -e "${RED}0. Cancel${NC}"
    echo ""
    
    read -p "Select user by number: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ]; then
        local selected_var="user_choice_$selection"
        local selected_user="${!selected_var}"
        if [ ! -z "$selected_user" ]; then
            SELECTED_OBJECT="$selected_user"
            SELECTED_OBJECT_TYPE="User"
            return 0
        fi
    fi
    
    return 1
}

# Function to list and select all users
list_and_select_users() {
    show_header
    echo -e "${YELLOW}Loading all users...${NC}"
    echo ""
    
    local counter=1
    local found_users=false
    
    echo -e "${CYAN}ALL USERS:${NC}"
    echo -e "${CYAN}==========${NC}"
    echo ""
    
    while IFS= read -r username; do
        if [ ! -z "$username" ]; then
            echo -e "${YELLOW}$counter. $username${NC}"
            eval "user_choice_$counter=\"$username\""
            counter=$((counter + 1))
            found_users=true
        fi
    done < <(samba-tool user list 2>/dev/null)
    
    if [ "$found_users" = false ]; then
        echo -e "${YELLOW}No users found!${NC}"
        pause
        return 1
    fi
    
    echo ""
    echo -e "${RED}0. Cancel${NC}"
    echo ""
    
    read -p "Select user by number: " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -gt 0 ]; then
        local selected_var="user_choice_$selection"
        local selected_user="${!selected_var}"
        if [ ! -z "$selected_user" ]; then
            SELECTED_OBJECT="$selected_user"
            SELECTED_OBJECT_TYPE="User"
            return 0
        fi
    fi
    
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
    
    echo -n "Password: "
    read -s password
    echo ""
    if [ -z "$password" ]; then
        echo -e "${RED}Password is required!${NC}"
        pause
        return
    fi
    
    echo ""
    echo -e "${YELLOW}Select target OU for the new user...${NC}"
    pause
    
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
    local cmd="samba-tool user create '$username' '$password'"
    
    if [ ! -z "$firstname" ]; then
        cmd="$cmd --given-name='$firstname'"
    fi
    
    if [ ! -z "$lastname" ]; then
        cmd="$cmd --surname='$lastname'"
    fi
    
    if [ ! -z "$email" ]; then
        cmd="$cmd --mail-address='$email'"
    fi
    
    if [ ! -z "$description" ]; then
        cmd="$cmd --description='$description'"
    fi
    
    # Execute user creation
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ User $username created successfully!${NC}"
        
        # Move user to selected OU if not default
        if [ "$target_ou" != "$DOMAIN_DN" ] && [ "$target_ou" != "CN=Users,$DOMAIN_DN" ]; then
            echo -e "${YELLOW}Moving user to selected OU...${NC}"
            local user_dn="CN=$username,CN=Users,$DOMAIN_DN"
            if samba-tool user move "$user_dn" "$target_ou" >/dev/null 2>&1; then
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
        echo -n "Enter new password: "
        read -s new_password
        echo ""
        
        if [ ! -z "$new_password" ]; then
            if samba-tool user setpassword "$SELECTED_OBJECT" --newpassword="$new_password" >/dev/null 2>&1; then
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
            if samba-tool user enable "$SELECTED_OBJECT" >/dev/null 2>&1; then
                echo -e "${GREEN}✓ User account enabled successfully!${NC}"
            else
                echo -e "${RED}✗ Failed to enable user account!${NC}"
            fi
        else
            if samba-tool user disable "$SELECTED_OBJECT" >/dev/null 2>&1; then
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
            if samba-tool group addmembers "$group_name" "$SELECTED_OBJECT" >/dev/null 2>&1; then
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
            if samba-tool user delete "$SELECTED_OBJECT" >/dev/null 2>&1; then
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
            echo -e "${GRAY}Current DN: $current_dn${NC}"
            echo ""
            echo -e "${YELLOW}Select target OU...${NC}"
            pause
            
            local target_ou
            target_ou=$(browse_ous "Select Target OU")
            
            if [ $? -eq 0 ] && [ ! -z "$target_ou" ]; then
                if samba-tool user move "$current_dn" "$target_ou" >/dev/null 2>&1; then
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
    
    local user_count=0
    while IFS= read -r username; do
        if [ ! -z "$username" ]; then
            echo -e "${YELLOW}User: $username${NC}"
            
            # Get user details
            local user_info=$(samba-tool user show "$username" 2>/dev/null)
            if [ $? -eq 0 ]; then
                local email=$(echo "$user_info" | grep -i "mail:" | awk '{print $2}')
                local dn=$(echo "$user_info" | grep "dn:" | awk '{print $2}')
                
                if [ ! -z "$email" ]; then
                    echo -e "  ${GRAY}Email: $email${NC}"
                fi
                echo -e "  ${GRAY}DN: $dn${NC}"
            fi
            
            echo ""
            user_count=$((user_count + 1))
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
    
    local computer_count=0
    
    # Try to get computers using ldbsearch
    if command -v ldbsearch >/dev/null 2>&1; then
        while IFS= read -r computer_line; do
            if [[ "$computer_line" =~ sAMAccountName:\ (.+) ]]; then
                local computer_name="${BASH_REMATCH[1]}"
                computer_name="${computer_name%$}"  # Remove trailing $
                echo -e "${YELLOW}Computer: $computer_name${NC}"
                computer_count=$((computer_count + 1))
                echo ""
            fi
        done < <(ldbsearch -H /var/lib/samba/private/sam.ldb "(&(objectClass=computer))" sAMAccountName 2>/dev/null)
    else
        echo -e "${YELLOW}ldbsearch not available. Computer listing limited.${NC}"
    fi
    
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
    echo ""
    
    # List all OUs
    local ou_count=0
    while IFS= read -r ou_dn; do
        if [ ! -z "$ou_dn" ]; then
            # Calculate indentation level based on comma count
            local level=$(echo "$ou_dn" | grep -o "," | wc -l)
            level=$((level - 2))  # Adjust for domain components
            
            if [ $level -lt 0 ]; then
                level=0
            fi
            
            local indent=""
            for ((i=0; i<level; i++)); do
                indent="  $indent"
            done
            
            # Extract OU name
            if [[ "$ou_dn" =~ ^(OU=|CN=)([^,]+) ]]; then
                local ou_name="${BASH_REMATCH[2]}"
                local ou_type="${BASH_REMATCH[1]%=}"
                echo -e "${indent}${YELLOW}+ [$ou_type] $ou_name${NC}"
                echo -e "${indent}  ${GRAY}$ou_dn${NC}"
                ou_count=$((ou_count + 1))
            fi
        fi
    done < <(samba-tool ou list 2>/dev/null; echo "CN=Users,$DOMAIN_DN"; echo "CN=Computers,$DOMAIN_DN")
    
    echo ""
    echo -e "${GREEN}Total OUs found: $ou_count${NC}"
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
main "$@"
