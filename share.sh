#!/bin/bash

# Loop through each file in each directory
for file in ./* "lib/Cron"/* "lib/Cron/Toolkit/"/* "lib/Cron/Toolkit/Pattern"/* "t"/*; do
    # Check if it is a file
    if [[ -f "$file" ]]; then
        # Echo the filename
        echo "#Filename: $(basename "$file")"
        
        # Display the content of the file
        cat "$file"
        echo
    fi
done

