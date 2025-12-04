#!/usr/bin/env bash

# version 1.3 | 28/11/25

DESKTOP="$HOME/Desktop"
cd "$DESKTOP" || exit

# --- Save old oui.txt if exists ---
if [[ -f oui.txt ]]; then
    old_oui_count=$(tail -n +5 oui.txt | grep -v '^[[:space:]]*$' | wc -l)
    cp oui.txt old_oui.txt
fi

echo -e "\nDownloading updated OUI from IEEE + Extra OUIs + Sorting the file by MAC prefix.\n\n"

process_oui() {
    echo -e "\nDownloading IEEE OUI database..."
    wget -O oui_raw.txt https://standards-oui.ieee.org/oui/oui.txt || exit

    echo "Processing ieee oui_raw.txt to create oui.txt..."
    awk '
    /\(hex\)/ {
        mac_raw = substr($1,1,8)
        gsub(/-/,"",mac_raw)
        mac = toupper(substr(mac_raw,1,2) ":" substr(mac_raw,3,2) ":" substr(mac_raw,5,2))

        company = $0
        sub(/.*\(hex\)[ \t]*/,"",company)
        gsub(/[\r\n]+/, "", company)

        country = ""
        for (i = 0; i < 5; i++) {
            if (getline > 0) {
                line = $0
                gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", line)
                if (length(line) == 2 && line ~ /^[A-Z]{2}$/) {
                    country = line
                    break
                }
            }
        }

        printf "%s %s (%s)\n", mac, company, country
    }
    ' oui_raw.txt > oui.txt

    echo -e "\nDownloading Extra_OUIs.txt..."
    wget -O Extra_OUIs.txt https://raw.githubusercontent.com/idoCo10/OUI-list-2025/main/Extra_OUIs.txt

    echo -e "\n\nAppending Extra_OUIs.txt to oui.txt..."
    cat Extra_OUIs.txt >> oui.txt

    # automatically sort with header
    sort_oui
}

sort_oui() {
    if [[ ! -f oui.txt ]]; then
        echo "oui.txt not found! Please run process_oui first."
        return
    fi

    echo -e "Sorting oui.txt by MAC prefix..."
    DATE_NOW=$(date "+%d/%m/%Y %H:%M")
    oui_count=$(grep -v '^===' oui.txt | grep -v '^[[:space:]]*$' | sort -u | wc -l)

    {
        echo "=============================="
        echo "Update Date: $DATE_NOW"
        echo "Total Records: $oui_count."
        echo "=============================="
        grep -v '^===' oui.txt | grep -v '^[[:space:]]*$' | sort -u -k1,1 -k2 -f
    } > oui-sorted.txt

    mv oui-sorted.txt oui.txt
    echo "Removing raw files..."
    rm -f oui_raw.txt Extra_OUIs.txt

    echo -e "\nNumber of OUIs in the updated file ($DATE_NOW): $oui_count"

    if [[ $old_oui_count -gt 0 ]]; then
        # Extract old update date without the "Update Date: " prefix
        old_date=$(sed -n '2p' old_oui.txt | sed 's/^Update Date: //')

        echo -e "Number of OUIs before the update (${old_date}): $old_oui_count"
    
        new_ouis=$(comm -23 <(tail -n +5 oui.txt | grep -v '^[[:space:]]*$' | sort) \
                <(tail -n +5 old_oui.txt | grep -v '^[[:space:]]*$' | sort))

        if [[ -n "$new_ouis" ]]; then
            echo -e "\nNew OUIs added in this update:"
            echo "$new_ouis"
        else 
            echo -e "\nNo OUI was added to IEEE since your last update.\n"
        fi

        rm -f old_oui.txt
    fi

    echo -e "\nDone!"
}

process_oui

# --- Ask user if they want to upload to GitHub ---
echo -e "\nDo you want to upload the updated oui.txt to GitHub? (Y/n): "
read -r upload_choice

if [[ -z "$upload_choice" || "$upload_choice" == "y" || "$upload_choice" == "Y" ]]; then
    USERHOME="$HOME"
    USERNAME="$(whoami)"

    echo -e "\nUploading to GitHub as user: $USERNAME\n"

    cd "$USERHOME/OUI-list" || exit
    
    # Clean up any existing rebase/merge state
    if [[ -d ".git/rebase-merge" ]] || [[ -d ".git/rebase-apply" ]]; then
        echo "Cleaning up previous rebase/merge state..."
        git rebase --abort 2>/dev/null || true
        rm -rf ".git/rebase-merge" ".git/rebase-apply" 2>/dev/null || true
    fi
    
    # Check if the git repository is clean
    if ! git diff --quiet; then
        echo "There are uncommitted changes in the repository. Stashing them..."
        git stash push -m "Auto-stash by OUI update script $(date '+%Y-%m-%d %H:%M:%S')"
    fi
    
    # Pull the latest changes from GitHub
    echo "Pulling latest changes from GitHub..."
    if ! git pull --rebase origin main; then
        echo "Rebase failed. Trying regular pull..."
        git merge --abort 2>/dev/null || true
        git pull origin main
    fi
    
    # If we stashed changes, apply them back
    if git stash list | grep -q "Auto-stash by OUI update script"; then
        echo "Applying stashed changes..."
        git stash pop
    fi
    
    # Copy and commit the new oui.txt
    cp "$USERHOME/Desktop/oui.txt" "$USERHOME/OUI-list/oui.txt"

    git add oui.txt
    git commit -m "Updated oui.txt $(date '+%d/%m/%Y %H:%M')"
    
    # Push to GitHub
    echo "Pushing to GitHub..."
    if git push origin main; then
        echo -e "\nUpload completed successfully!"
    else
        echo -e "\nPush failed. The remote has changes you don't have locally."
        echo "Do you want to:"
        echo "1) Pull and merge (recommended)"
        echo "2) Force push (overwrites remote - use with caution)"
        echo "3) Cancel and resolve manually"
        read -r -p "Enter choice (1/2/3): " conflict_choice
        
        case $conflict_choice in
            1)
                echo "Pulling and merging..."
                git pull origin main
                git add oui.txt
                git commit -m "Merge remote changes and update oui.txt"
                git push origin main
                ;;
            2)
                echo "Force pushing..."
                git push --force-with-lease origin main
                echo -e "\nForce push completed!"
                ;;
            3)
                echo -e "\nPush cancelled. Please resolve conflicts manually."
                echo "You can run: git pull origin main"
                echo "Then resolve any conflicts and push again."
                ;;
            *)
                echo -e "\nInvalid choice. Push cancelled."
                ;;
        esac
    fi
else
    echo -e "\nSkipped uploading to GitHub."
fi
