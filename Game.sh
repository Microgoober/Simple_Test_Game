#!/bin/bash

# Game configuration
PLAYER_CHAR="P"
EMPTY_CHAR="."
CHEST_CHAR="C"

# Color definitions - using tput for better compatibility
if command -v tput &> /dev/null; then
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
    GREEN_BG=$(tput setab 2)
    RED_BG=$(tput setab 1)
    WHITE=$(tput setaf 7)
else
    # Fallback if tput is not available
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    RESET='\033[0m'
    GREEN_BG='\033[42m'
    RED_BG='\033[41m'
    WHITE='\033[37m'
fi

# Map file names
EASY_MAP="easy_map.txt"
NORMAL_MAP="normal_map.txt"
HARD_MAP="hard_map.txt"

# Player position
PLAYER_ROW=0
PLAYER_COL=0

# Chest position
CHEST_ROW=0
CHEST_COL=0

# Map dimensions
ROWS=0
COLS=0

# Store map in array
declare -A MAP
declare -A VISITED
declare -A HINTS
declare -A HINT_TRUTH

# Hint types
HINT_TYPES=(
    "distance"
    "above"
    "below"
    "left"
    "right"
    "no_cardinal"
    "cardinal"
    "not_left"
    "not_right"
    "not_above"
    "not_below"
)

# Function to check if map file exists
check_map_file() {
    local map_file="$1"
    if [[ ! -f "$map_file" ]]; then
        echo "Error: Map file '$map_file' not found!"
        echo "Creating default map file..."
        create_default_map "$map_file"
        return 1
    fi
    return 0
}

# Function to create default map file if missing
create_default_map() {
    local map_file="$1"
    local size=0
    
    case "$map_file" in
        "$EASY_MAP") size=5 ;;
        "$NORMAL_MAP") size=10 ;;
        "$HARD_MAP") size=15 ;;
        *) size=5 ;;
    esac
    
    cat > "$map_file" << EOF
$(generate_empty_grid $size)
EOF
    echo "Default $size x $size map created at '$map_file'"
}

# Function to generate empty grid
generate_empty_grid() {
    local size=$1
    local line=""
    for ((i=0; i<size; i++)); do
        line="$line. "
    done
    line="${line% }"  # Remove trailing space
    
    for ((i=0; i<size; i++)); do
        echo "$line"
    done
}

# Function to load map from file
load_map() {
    local map_file="$1"
    
    # Check if file exists
    check_map_file "$map_file"
    
    # Clear existing map
    MAP=()
    VISITED=()
    HINTS=()
    HINT_TRUTH=()
    
    local row=0
    local max_cols=0
    
    # Read the map file
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing spaces
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        local col=0
        local chars=()
        
        # Split line by spaces
        IFS=' ' read -ra chars <<< "$line"
        
        for char in "${chars[@]}"; do
            if [[ -n "$char" ]]; then
                MAP[$row,$col]="$char"
                if [[ "$char" == "$PLAYER_CHAR" ]]; then
                    PLAYER_ROW=$row
                    PLAYER_COL=$col
                    VISITED[$row,$col]=1
                else
                    VISITED[$row,$col]=0
                fi
                ((col++))
            fi
        done
        
        # Track maximum columns
        if [[ $col -gt $max_cols ]]; then
            max_cols=$col
        fi
        
        ((row++))
    done < "$map_file"
    
    ROWS=$row
    COLS=$max_cols
    
    # Validate map
    if [[ $ROWS -eq 0 || $COLS -eq 0 ]]; then
        echo "Error: Map file is empty or invalid!"
        echo "Creating new map..."
        create_default_map "$map_file"
        load_map "$map_file"
        return
    fi
    
    # Set player position if not found
    if [[ -z "${MAP[$PLAYER_ROW,$PLAYER_COL]}" ]] || [[ "${MAP[$PLAYER_ROW,$PLAYER_COL]}" != "$PLAYER_CHAR" ]]; then
        MAP[0,0]="$PLAYER_CHAR"
        PLAYER_ROW=0
        PLAYER_COL=0
        VISITED[0,0]=1
    fi
    
    echo "Map loaded successfully! Size: ${ROWS}x${COLS}"
}

# Function to place chest randomly
place_chest() {
    local max_attempts=100
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        CHEST_ROW=$((RANDOM % ROWS))
        CHEST_COL=$((RANDOM % COLS))
        
        # Make sure chest is not on player's starting position
        if [[ $CHEST_ROW -ne $PLAYER_ROW || $CHEST_COL -ne $PLAYER_COL ]]; then
            # Place chest on map (visible for testing)
            MAP[$CHEST_ROW,$CHEST_COL]="$CHEST_CHAR"
            return 0
        fi
        ((attempts++))
    done
    
    # If we can't place chest randomly, use a fallback position
    CHEST_ROW=1
    CHEST_COL=1
    MAP[$CHEST_ROW,$CHEST_COL]="$CHEST_CHAR"
}

# Function to calculate Manhattan distance
calculate_distance() {
    local row1=$1
    local col1=$2
    local row2=$3
    local col2=$4
    echo $(( (row1 > row2 ? row1 - row2 : row2 - row1) + (col1 > col2 ? col1 - col2 : col2 - col1) ))
}

# Function to check cardinal direction
is_above() {
    local player_row=$1
    local player_col=$2
    local chest_row=$3
    local chest_col=$4
    [[ $chest_col -eq $player_col && $chest_row -lt $player_row ]]
}

is_below() {
    local player_row=$1
    local player_col=$2
    local chest_row=$3
    local chest_col=$4
    [[ $chest_col -eq $player_col && $chest_row -gt $player_row ]]
}

is_left() {
    local player_row=$1
    local player_col=$2
    local chest_row=$3
    local chest_col=$4
    [[ $chest_row -eq $player_row && $chest_col -lt $player_col ]]
}

is_right() {
    local player_row=$1
    local player_col=$2
    local chest_row=$3
    local chest_col=$4
    [[ $chest_row -eq $player_row && $chest_col -gt $player_col ]]
}

is_cardinal_direction() {
    local player_row=$1
    local player_col=$2
    local chest_row=$3
    local chest_col=$4
    is_above $player_row $player_col $chest_row $chest_col ||
    is_below $player_row $player_col $chest_row $chest_col ||
    is_left $player_row $player_col $chest_row $chest_col ||
    is_right $player_row $player_col $chest_row $chest_col
}

# Function to generate hint for a specific location
generate_hint() {
    local row=$1
    local col=$2
    
    # Skip if this is the chest location
    if [[ $row -eq $CHEST_ROW && $col -eq $CHEST_COL ]]; then
        HINTS["$row,$col"]="You found the treasure chest! Dig to claim it!"
        HINT_TRUTH["$row,$col"]="true"
        return
    fi
    
    # Calculate distance
    local distance=$(calculate_distance $row $col $CHEST_ROW $CHEST_COL)
    
    # Determine truth status (50% chance of lying)
    local is_truth=$((RANDOM % 2))
    local hint_type=""
    local hint_text=""
    local is_true=""
    
    # Pick a random hint type
    local hint_index=$((RANDOM % ${#HINT_TYPES[@]}))
    hint_type="${HINT_TYPES[$hint_index]}"
    
    case $hint_type in
        "distance")
            if [[ $is_truth -eq 1 ]]; then
                # Truth: say the actual distance
                hint_text="The chest is $distance spaces away from here."
                is_true="true"
            else
                # Lie: say a different distance (not the actual one)
                local fake_distance=$distance
                while [[ $fake_distance -eq $distance ]]; do
                    fake_distance=$((RANDOM % (ROWS + COLS) + 1))
                done
                hint_text="The chest is $fake_distance spaces away from here."
                is_true="false"
            fi
            ;;
            
        "above")
            if is_above $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is in a location above me."
                    is_true="true"
                else
                    hint_text="The chest is in a location above me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not above me."
                    is_true="true"
                else
                    hint_text="The chest is above me."
                    is_true="false"
                fi
            fi
            ;;
            
        "below")
            if is_below $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is in a location below me."
                    is_true="true"
                else
                    hint_text="The chest is in a location below me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not below me."
                    is_true="true"
                else
                    hint_text="The chest is below me."
                    is_true="false"
                fi
            fi
            ;;
            
        "left")
            if is_left $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is in a location to the left of me."
                    is_true="true"
                else
                    hint_text="The chest is in a location to the left of me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not to the left of me."
                    is_true="true"
                else
                    hint_text="The chest is to the left of me."
                    is_true="false"
                fi
            fi
            ;;
            
        "right")
            if is_right $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is in a location to the right of me."
                    is_true="true"
                else
                    hint_text="The chest is in a location to the right of me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not to the right of me."
                    is_true="true"
                else
                    hint_text="The chest is to the right of me."
                    is_true="false"
                fi
            fi
            ;;
            
        "no_cardinal")
            if ! is_cardinal_direction $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not in any cardinal direction of me."
                    is_true="true"
                else
                    hint_text="The chest is not in any cardinal direction of me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is in a cardinal direction."
                    is_true="true"
                else
                    hint_text="The chest is not in any cardinal direction of me."
                    is_true="false"
                fi
            fi
            ;;
            
        "cardinal")
            if is_cardinal_direction $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is in a cardinal direction."
                    is_true="true"
                else
                    hint_text="The chest is in a cardinal direction."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not in any cardinal direction of me."
                    is_true="true"
                else
                    hint_text="The chest is in a cardinal direction."
                    is_true="false"
                fi
            fi
            ;;
            
        "not_left")
            if ! is_left $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not to the left of me."
                    is_true="true"
                else
                    hint_text="The chest is not to the left of me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is to the left of me."
                    is_true="true"
                else
                    hint_text="The chest is not to the left of me."
                    is_true="false"
                fi
            fi
            ;;
            
        "not_right")
            if ! is_right $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not to the right of me."
                    is_true="true"
                else
                    hint_text="The chest is not to the right of me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is to the right of me."
                    is_true="true"
                else
                    hint_text="The chest is not to the right of me."
                    is_true="false"
                fi
            fi
            ;;
            
        "not_above")
            if ! is_above $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not above me."
                    is_true="true"
                else
                    hint_text="The chest is not above me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is above me."
                    is_true="true"
                else
                    hint_text="The chest is not above me."
                    is_true="false"
                fi
            fi
            ;;
            
        "not_below")
            if ! is_below $row $col $CHEST_ROW $CHEST_COL; then
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is not below me."
                    is_true="true"
                else
                    hint_text="The chest is not below me."
                    is_true="false"
                fi
            else
                if [[ $is_truth -eq 1 ]]; then
                    hint_text="The chest is below me."
                    is_true="true"
                else
                    hint_text="The chest is not below me."
                    is_true="false"
                fi
            fi
            ;;
    esac
    
    HINTS["$row,$col"]="$hint_text"
    HINT_TRUTH["$row,$col"]="$is_true"
}

# Function to generate hints for all locations
generate_all_hints() {
    for ((row=0; row<ROWS; row++)); do
        for ((col=0; col<COLS; col++)); do
            generate_hint $row $col
        done
    done
}

# Function to display the map
display_map() {
    clear
    echo "========================================================"
    echo "              TREASURE HUNT GAME"
    echo "========================================================"
    echo "  Map: ${ROWS}x${COLS} | Controls: ↑/w=Up ↓/s=Down ←/a=Left →/d=Right"
    echo "  Commands: 'e' to dig for treasure | 'q' to quit"
    echo "  Legend: P=Player  C=Chest (visible for testing)"
    echo ""
    
    # Display column numbers
    echo -n "   "
    for ((col=0; col<COLS; col++)); do
        printf "%3d" $((col+1))
    done
    echo ""
    
    # Display map with colors
    for ((row=0; row<ROWS; row++)); do
        printf "%2d " $((row+1))
        for ((col=0; col<COLS; col++)); do
            if [[ $row -eq $PLAYER_ROW && $col -eq $PLAYER_COL ]]; then
                # Player position (green)
                echo -ne "[P]"
            elif [[ $row -eq $CHEST_ROW && $col -eq $CHEST_COL ]]; then
                # Chest position (red)
                echo -ne "[C]"
            elif [[ "${VISITED[$row,$col]}" -eq 1 ]]; then
                # Visited spot
                echo -ne " · "
            else
                # Unvisited spot
                echo -ne " . "
            fi
        done
        echo ""
    done
    
    echo ""
    echo "  Position: ($((PLAYER_ROW+1)), $((PLAYER_COL+1)))"
    echo "  Visited: $(count_visited)/$((ROWS*COLS)) locations"
    
    # Show hint for current location
    if [[ -n "${HINTS["$PLAYER_ROW,$PLAYER_COL"]}" ]]; then
        echo ""
        echo "  Hint: ${HINTS["$PLAYER_ROW,$PLAYER_COL"]}"
        if [[ "${HINT_TRUTH["$PLAYER_ROW,$PLAYER_COL"]}" == "true" ]]; then
            echo "  [TRUTH]"
        else
            echo "  [LIE]"
        fi
    fi
    echo ""
}

# Function to count visited spots
count_visited() {
    local count=0
    for ((row=0; row<ROWS; row++)); do
        for ((col=0; col<COLS; col++)); do
            if [[ "${VISITED[$row,$col]}" -eq 1 ]]; then
                ((count++))
            fi
        done
    done
    echo "$count"
}

# Function to move the player
move_player() {
    local new_row=$PLAYER_ROW
    local new_col=$PLAYER_COL
    
    case $1 in
        "up"|"w"|"W") ((new_row--)) ;;
        "down"|"s"|"S") ((new_row++)) ;;
        "left"|"a"|"A") ((new_col--)) ;;
        "right"|"d"|"D") ((new_col++)) ;;
        *) return 1 ;;
    esac
    
    # Check if new position is within bounds
    if [[ $new_row -lt 0 || $new_row -ge $ROWS || $new_col -lt 0 || $new_col -ge $COLS ]]; then
        echo ""
        echo "You can't move off the map!"
        echo "Press Enter to continue..."
        read
        return 1
    fi
    
    # Clear old player position (if not chest)
    if [[ "${MAP[$PLAYER_ROW,$PLAYER_COL]}" != "$CHEST_CHAR" ]]; then
        MAP[$PLAYER_ROW,$PLAYER_COL]="$EMPTY_CHAR"
    fi
    
    # Move player
    PLAYER_ROW=$new_row
    PLAYER_COL=$new_col
    
    # Update map with new player position
    MAP[$PLAYER_ROW,$PLAYER_COL]="$PLAYER_CHAR"
    VISITED[$PLAYER_ROW,$PLAYER_COL]=1
    
    echo ""
    echo "You moved to ($((PLAYER_ROW+1)), $((PLAYER_COL+1)))"
    echo "Press Enter to continue..."
    read
    
    return 0
}

# Function to dig for treasure
dig_for_treasure() {
    echo ""
    echo "Digging at location ($((PLAYER_ROW+1)), $((PLAYER_COL+1)))..."
    echo ""
    
    if [[ $PLAYER_ROW -eq $CHEST_ROW && $PLAYER_COL -eq $CHEST_COL ]]; then
        echo "========================================"
        echo "  CONGRATULATIONS! You found the treasure!"
        echo "========================================"
        echo "The treasure was hidden at ($((CHEST_ROW+1)), $((CHEST_COL+1)))!"
        echo ""
        echo -n "  Play again? (y/n): "
        read play_again
        if [[ "$play_again" == "y" || "$play_again" == "Y" ]]; then
            main
            return
        else
            echo "Thanks for playing! Goodbye!"
            exit 0
        fi
    else
        echo "Sorry, no treasure here. Keep searching!"
        echo ""
        echo "Press Enter to continue..."
        read
    fi
}

# Function to read single key input (for arrow keys)
read_key() {
    local key
    IFS= read -r -s -n 1 key
    
    if [[ $key == $'\x1b' ]]; then
        # Arrow key detected
        read -r -s -n 2 key
        case $key in
            "[A") echo "up" ;;
            "[B") echo "down" ;;
            "[D") echo "left" ;;
            "[C") echo "right" ;;
            *) echo "unknown" ;;
        esac
    else
        # Regular key
        echo "$key"
    fi
}

# Function to read input (handles single key presses)
read_input() {
    local key=$(read_key)
    echo "$key"
}

# Function to select difficulty
select_difficulty() {
    clear
    echo "========================================================"
    echo "          TREASURE HUNT - SELECT MAP"
    echo "========================================================"
    echo ""
    echo "  Choose your adventure map:"
    echo ""
    echo "  1) Easy   - 5x5 grid   - Using easy_map.txt"
    echo "  2) Normal - 10x10 grid - Using normal_map.txt"
    echo "  3) Hard   - 15x15 grid - Using hard_map.txt"
    echo ""
    echo "  Customization Tip: Edit the .txt map files to create your own maps!"
    echo ""
    echo -n "  Enter your choice (1-3): "
    read choice
    
    case $choice in
        1|"easy"|"Easy"|"e"|"E") 
            echo ""
            echo "Loading Easy map..."
            load_map "$EASY_MAP"
            ;;
        2|"normal"|"Normal"|"n"|"N")
            echo ""
            echo "Loading Normal map..."
            load_map "$NORMAL_MAP"
            ;;
        3|"hard"|"Hard"|"h"|"H")
            echo ""
            echo "Loading Hard map..."
            load_map "$HARD_MAP"
            ;;
        *) 
            echo ""
            echo "  Invalid choice. Using Easy map."
            echo "Press Enter to continue..."
            read
            load_map "$EASY_MAP"
            ;;
    esac
    
    # Place chest randomly
    place_chest
    
    # Generate hints for all locations
    generate_all_hints
    
    echo ""
    echo "Chest hidden at ($((CHEST_ROW+1)), $((CHEST_COL+1))) (visible for testing)"
    echo "Each location gives you a hint (50% chance of being true or false!)"
    echo "Controls: w/a/s/d or Arrow Keys = Move | e = Dig | q = Quit"
    echo ""
    echo "Press Enter to begin your treasure hunt..."
    read
}

# Main game loop
main() {
    # Select difficulty first
    select_difficulty
    
    while true; do
        display_map
        
        echo "  Controls: w/a/s/d or Arrow Keys = Move | e = Dig | q = Quit"
        echo ""
        
        # Get single key input
        local action=$(read_input)
        
        # Handle dig command
        if [[ "$action" == "e" || "$action" == "E" ]]; then
            dig_for_treasure
            # If dig_for_treasure didn't exit (didn't find treasure), continue
            continue
        fi
        
        # Handle quit
        if [[ "$action" == "q" || "$action" == "Q" ]]; then
            echo ""
            echo "Thanks for playing! Goodbye!"
            break
        fi
        
        # Handle movement
        case $action in
            "w"|"W"|"up")
                move_player "up"
                ;;
            "s"|"S"|"down")
                move_player "down"
                ;;
            "a"|"A"|"left")
                move_player "left"
                ;;
            "d"|"D"|"right")
                move_player "right"
                ;;
            "unknown")
                echo ""
                echo "Unknown key pressed. Use w/a/s/d, Arrow Keys, 'e' to dig, or 'q' to quit."
                echo "Press Enter to continue..."
                read
                ;;
            *)
                echo ""
                echo "Invalid input: '$action'. Use w/a/s/d, Arrow Keys, 'e' to dig, or 'q' to quit."
                echo "Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Run the game
main