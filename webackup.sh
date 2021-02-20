#!/bin/bash

# Default webackup_cfg, backup folder and log file location.
webackup_cfg_folder="$HOME/.webackup_cfg"
backup_folder="$HOME/.backup"
log_file="$backup_folder/backup.log"

if [[ ! -d $webackup_cfg_folder ]]; then
    mkdir $webackup_cfg_folder
fi

while getopts "df:gth" OPTIONS; do
    case $OPTIONS in
        d)
            db_only=true
            ;;
            
        f)
            path="$OPTARG"
            ;;
        
        g)
            gui_disabled=true
            ;;
            
        t)
            printf '# Global values\nname="project-name"\nproject_path="/var/www/html/project-folder"\n\n# Mysql/MariaDB logins\ndb_user="backup-user"\ndb_password="supersecretpassword"\ndb_name="database-name"\n\n# SSH values\nport="22"\ndistant_user="distant-user"\ndestination_server="destination.server.com"\ndistant_backup_folder="/path/to/backup/folder"\n\n# Log file (Defaulted to $HOME/.backup/backup.log), only change it if you explicitely want it elsewhere\n# log_file=""\n' > "$webackup_cfg_folder/template.cfg"
            echo "Template file created at [$webackup_cfg_folder/template.cfg]. You can now start editing it and relaunch this script."
            exit
            ;;
        
        h)
            echo "No option for GUI guided full backup."
            echo "-d for database-only."
            echo "-f /path/to/file to specifie file for automatic backup."
            echo "-g to disable the gui."
            echo "-t to create a template file to facilitate the process."
            echo "-h to display this help (duh!)."
            exit
            ;;
    esac
done

# Info
blue_echo() {
    echo -e "\e[1;34m$MESSAGE\e[0m"
}

# Success
green_echo() {
    echo -e "\e[1;32m$MESSAGE\e[0m"
}

# Error
red_echo() {
    echo -e "\e[1;31m$MESSAGE\e[0m"
}

# Warning
orange_echo() {
    echo -e "\e[1;33m$MESSAGE\e[0m"
}

# Questions
purple_echo() {
    echo -e "\e[1;35m$MESSAGE\e[0m"
}

if ! command -v pv &> /dev/null; then
    MESSAGE="pv isn't installed. Please install pv and relaunch this script." ; red_echo
    exit
fi

# Run as normal user, no root or sudo
if [ "$EUID" -ne 0 ]; then

    # If a failed transfert is detected from previously running this script, ask the user if they want to try transfering the existing files again or just start over and erase the existing data.
    if [[ -f $HOME/.backup/in_transfert ]]; then
        MESSAGE="It seems like a transfert failed last time you ran this script. The data about the transfert is the following :" ; orange_echo
        echo "$(cat $HOME/.backup/in_transfert)"
        # Ask the user if they want to try again or just start over.
        choice=-1
        while [[ ${choice^^} != "S" && ${choice^^} != "T" && ${choice^^} != "L" ]]; do
            MESSAGE="Do you want to try uploading again using these variables or do you want to start over? (S)tart over | (T)ry again | (L)eave" ; purple_echo
            read choice
            echo $choice
        done
        
        # If the user chooses to start over, then delete anything in the backup folder and redo everything before uploading. Try again will load the variables from the in_transfert file and try to transfer the files again using these.
        if [[ ${choice^^} == "S" ]]; then
            start_over=True
            find $HOME/.backup/ -type f -not -name '*.log' -print0 | xargs -0 rm --
            MESSAGE="Starting over. Deleted all files except the log in the backup folder." ; blue_echo
        elif [[ ${choice^^} == "L" ]]; then
            MESSAGE="Leaving the script." ; blue_echo
            exit
        elif [[ ${choice^^} == "T" ]]; then
            echo "-------------------------------------------------" >> $log_file
            echo "$(date)" >> $log_file
            echo "Attempting to upload the file again using the variables in [$HOME/.backup/in_transfert] :" >> $log_file
            echo "$(cat $HOME/.backup/in_transfert)" >> $log_file
            source "$HOME/.backup/in_transfert"
        fi
    fi
        
    if [[ ! -f $HOME/.backup/in_transfert || $start_over == "True" ]]; then
        # If no argument when invoking script, then ask for a file, else use the name provided in $1
        if [[ "$path" == "" ]]; then
            # Diabling GUI if dialog not installed
            if ! command -v dialog &> /dev/null; then
                MESSAGE="Dialog isn't installed. Not using GUI." ; orange_echo
                gui_disabled=true
            fi
                
            # Search for ".cfg" files, add their path to $fileTable and display the names. If no such file exist, throw a warning and leave the script.
            if  [[ $(find $HOME/.webackup_cfg -name "*.cfg" -type f) ]]; then
                fileCounter=1
                while IFS= read -r -d '' file; do
                    fileTable[$fileCounter]="${file}"
                    if [[ $gui_disabled == true ]]; then
                        echo "($fileCounter) - ${file##*/}"
                    fi
                    ((fileCounter++))
                done < <(find $HOME/.webackup_cfg -type f -name '*.cfg' -print0)
            else
                MESSAGE="Folder .webackup_cfg is empty or does not contain any .cfg file. You can create a template file using the -t argument when invoking this script. Aborting." ; orange_echo
                exit
            fi
            
            # If the dialog package is not installed or if the user doesn't want to use the semi-graphical interface.
            if [[ $gui_disabled == true ]]; then        
                #Ask the user which file they want to load (from $fileTable) and also gives the option to leave
                choice=-1
                while [[ "$choice" -eq -1 ]]; do
                    echo "Which variables file do you want to load? (1 - ${#fileTable[@]}) (L)eave"
                    read choice
                    if [[ "${fileTable[$choice]}" == "" && "${choice^^}" != "L" ]]; then
                        choice=-1
                    elif [[ "${choice^^}" == "L" ]]; then
                        MESSAGE="Leaving script." ; blue_echo
                        exit
                    fi
                done
                
                # Display the content of the cfg file and ask if the file about to be loaded seems correct. Leave if not.
                echo "$(cat "${fileTable[$choice]}")"
                choice=-1
                while [[ "${choice^^}" != "Y" && "${choice^^}" != "N" ]]; do
                    MESSAGE="Here's the file that is going to be loaded. Is it okay? (Y)es | (N)o" ; purple_echo
                    read choice
                done
                
                if [[ "${choice^^}" == "N" ]]; then
                    MESSAGE="Please change the values of your file and launch this script again." ; red_echo
                    exit
                fi
                    
            else
                # Prepare the semi-graphical interface with the variables.
                ask=""
                for ((i=1;i<=${#fileTable[@]};i++)); do
                    file="${fileTable[$i]// /_}"
                    ask="$ask $i ${file##*/}"
                done
                
                # Creates a dialog with all the present .cfg files in the right folder.
                choice=$(dialog --stdout --title "File list" --menu "Please pick the configuration you want to load :" 0 0 ${#fileTable[@]} $ask)
                
                # If the user decides to leave, exit the script.
                if [[ $? == "1" ]]; then
                    clear
                    MESSAGE="No configuration loaded, aborting."; red_echo
                    exit
                fi
                
                dialog --yesno "Do you wish to see the content of the file before launching this script?" 0 0
                
                # Show the content of the previously selected file and ask if is correct. Leave the script otherwise.
                if [[ $? == "0" ]]; then
                    dialog --textbox ${fileTable[$choice]} 0 0
                    dialog --yesno "Is the content correct?" 0 0
                        if [[ $? == "1" ]]; then
                            clear
                            MESSAGE="Please change the values of your file and launch this script again."; red_echo
                            exit
                        fi
                fi
            fi
            
            clear
            
            # Load the variables from the selected file above
            source "${fileTable[$choice]}"
        else
            source "$path"
        fi
        
        if [ ! -d "$project_path" ]; then
            MESSAGE="The path to the project folder leads nowhere. Please change it and relaunch this script again."; red_echo
            exit
        #elif [[ "$(ssh -p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$distant_user"@"$destination_server" "echo "OK"")" != "OK" ]]; then
            #MESSAGE="SSH couldn't connect to the server. Please check if everything is ok in your .variables file."; red_echo
            #exit
        fi

        # Create the .backup folder if it doesn't exist already and move there
        if [ ! -d $HOME/.backup ]; then
            mkdir $HOME/.backup
        fi
        
        cd $HOME/.backup
        
        # Prepare variables to help read the script easier
        date=$(date +"%d-%m-%Y")
        database_file=""$name"_db-$date.sql"
        
        if [[ $db_only == "true" ]]; then
            backup_file=""$name"_backup-database-$date.tar.gz"
        else
            backup_file=""$name"_backup-$date.tar.gz"
        fi
        
        md5_file="md5-"$name"-$date.txt"
        
        echo "-------------------------------------------------" >> $log_file
        echo "$(date)" >> $log_file

        # MySQL/MariaDB database dumping using specific account
        MESSAGE="Dumping database..." ; blue_echo
        mysqldump -u "$db_user" -p"$db_password" -x --databases "$db_name" > ./$database_file
        echo "Dumped database [$db_name] in [$database_file]." >> $log_file

        # Archive the database and the website folder with full path in a tar.gz file and use pv to get a clean looking progress bar
        if [[ $db_only == "true" ]]; then
            MESSAGE="Archiving the database..." ; blue_echo
            tar -czf - $database_file | pv > "$backup_file"
            echo "[$database_file] archived as [$backup_file]." >> $log_file
        else
            MESSAGE="Archiving the folder and database..." ; blue_echo
            tar -czf - $database_file "$project_path" | pv > "$backup_file"
            echo "[$database_file] and [${project_path##*/}] folder archived as [$backup_file]." >> $log_file
        fi
        
        # Generate an MD5 hash of the archive and send the result in a file for integrity checking later-on
        MESSAGE="Generating md5 hash for the archive..." ; blue_echo
        md5sum "$backup_file" > "$md5_file"
        echo "Generated md5 hash for [$backup_file] as [$md5_file]." >> $log_file

        # Generate a file named "in-transfert" containing the necessary variables to resume the upload if it failed last time this script was run
        echo "backup_file=\"$backup_file\"" > in_transfert
        echo "md5_file=\"$md5_file\"" >> in_transfert
        echo "distant_user=\"$distant_user\"" >> in_transfert
        echo "destination_server=\"$destination_server\"" >> in_transfert
        echo "port=$port" >> in_transfert
        echo "distant_backup_folder=\"$distant_backup_folder\"" >> in_transfert
        echo "date=\"$date\"" >> in_transfert
        echo "log_file=\"$log_file\"" >> in_transfert
    fi

    # Send the archive and the file containing its MD5 to the remote server, and then ask the remote server to check if the hash from the file is the same as the transfered archive
    # If more than 3 errors (connectivity and/or MD5 mismatch), abort the process
    counter=0
    while [[ ${check:(-2)} != "OK" && $counter -le 3 ]]; do
        if [[ "$(pwd)" != "$HOME/.backup" ]]; then
            cd "$HOME/.backup"
        fi
        echo "Attempting to transfer the file [$backup_file] to distant server [$destination_server]." >> $log_file
        MESSAGE="Transfering backup file..." ; blue_echo
        rsync -avz -e "ssh -p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" --progress "$backup_file" "$md5_file" "$distant_user"@"$destination_server":"$distant_backup_folder"
        echo "Checking md5sum of the sent file and comparing both." >> $log_file
        MESSAGE="Checking MD5 sum..." ; blue_echo
        ssh -p $port -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$distant_user"@"$destination_server" "cd "$distant_backup_folder"; md5sum -c $md5_file" > md5_check-$date.txt
        check=$(cat md5_check-$date.txt)
        ((counter++))
    done

    # If 3 fails, display red message, else if the MD5 from the file is the same as the one generated from the server, display green success message and delete all local files
    if [[ $counter -ge 3 ]]; then
        echo "Couldn't synchronize [$backup_file] with the remote server [$destination_server]. Please try again." >> $log_file
        MESSAGE="Can't synchronize $backup_file with the remote server. Aborting." ; red_echo
    elif [[ ${check:(-2)} == "OK" ]]; then
        echo "Synchronization of the file [$backup_file] to [$destination_server] successful!" >> $log_file
        MESSAGE="$backup_file synchronized with the remote server. Closing." ; green_echo
        find $HOME/.backup/ -type f -not -name '*.log' -print0 | xargs -0 rm --
    fi
    
else
    echo "Please do not use the root user to launch this script."
fi
