#!/bin/bash

#----------------------------------------------------------#
#                  Variables&Functions                     #
#----------------------------------------------------------#
# Function: prompt_yn
# -------------------
# Prompts for a y/n input. Returns 0 if the input is y, 1 if n.
# $1 is prompt
# $2 is default (Y|N)
function prompt_yn()
{
    local response=''
    local prompt="$1"
    local default="$( echo "$2" | tr '[A-Z]' '[a-z]' )"
    
    if [ "$default" = 'y' ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    
    echo -n "$prompt"
    
    while true; do
        read -s -n 1 response
        if [ -z "$response" ]; then
            response="$default"
        fi
        
        response="$( echo $response | tr '[A-Z]' '[a-z]' )"
        if [ "$response" = 'y' ]; then
            echo "y"
            return 0
        elif [ "$response" = 'n' ]; then
            echo "n"
            return 1
        fi
    done
}

#----------------------------------------------------------#
#                      Entry Point                         #
#----------------------------------------------------------#

# First of all, we check if the user is root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

#----------------------------------------------------------#
#                   Change root password                   #
#----------------------------------------------------------#
if prompt_yn "Do you want to change the root password?" "Y"; then
    passwd root
fi

#----------------------------------------------------------#
#                   Create user account                    #
#----------------------------------------------------------#
if prompt_yn "Do you want to create a non-privileged user account?" "Y"; then
    while true; do
        read -e -p "Enter new username: " username
        adduser $username
        if [ $? -eq 0 ]; then
            break;
        fi
    done
fi


