#!/bin/sh

# Settings
username="user"
password="password"
# server needs to be the server name and context of Jira install, ex: https://jira/jira
server="https://jira/jira"

# background - [true|false] Set to true for background index or false to preform an instance locking reindex
background=true

# monitor - [true|false] Set to true for the script to monitor the re-index. This will cause the script to check status until it reaches 100%
monitor=true

# Debug - [true|false] Set to true to print the output of the curl request
debug=0

#### Main

#Version check. For possible future use otherwise, only informational.
output=$(curl -D- -s -S -k -u $username:$password -X GET -H "Content-Type: application/json" "${server}/rest/api/2/serverInfo")
if [[ $debug == 1 ]]; then
        echo ------------------- Http raw response ---------------------------
        echo $output
        echo ------------------- ---------------------------
fi
if [[ $? != 0 ]]; then
        echo "Version Check FAILED!"
        echo "Curl Failed with exit code $?: $!"
        echo ------------------- Http raw response ---------------------------
        echo $output
        echo ------------------- ---------------------------
        exit 1
else
        #Get the "VersionNumbers" json response and phrase to an array
        version=$(echo $output | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^versionNumber/ {print $2}' | tr -d '[]')
        version=(${version//,/ })
        echo "$(date +%Y-%m-%d_%T) - Jira Version Detected: ${version[0]}.${version[1]}.${version[2]}."
fi

#Call reindex
if [[ "$background" == "true" ]]; then
                echo -n "$(date +%Y-%m-%d_%T) - Starting Background re-index...."
        output=$(curl -D- -s -S -k -u $username:$password -X POST -H "Content-Type: application/json" "${server}/rest/api/2/reindex")
else
                echo -n "$(date +%Y-%m-%d_%T) - Starting Background re-index...."
        output=$(curl -D- -s -S -k -u $username:$password -X POST -H "Content-Type: application/json" "${server}/rest/api/2/reindex?type=FOREGROUND")
fi

if [[ $? != 0 ]]; then
        echo "\t FAILED!"
        echo "Curl Failed with exit code $?: $!"
        echo ------------------- Http raw response ---------------------------
        echo $output
        echo ------------------- ---------------------------
        exit 1
else
                echo -e "\t OKAY."
fi

if [[ $debug == 1 ]]; then
        echo ------------------- Http raw response ---------------------------
        echo $output
        echo ------------------- ---------------------------
fi

#Check version to see if we should use progressUrl or the reindex url, this changed in 6.4.x
if [[ ${version[0]} -ge 6 && ${version[1]} -ge 4 ]]; then
        progress_url=$(echo $output | grep -Po '"progressUrl":.*?[^\\],')
        progress_url=$(echo $progress_url | cut -d ":" -f 2 | tr -d '",')
        TaskID=$(echo $progress_url | cut -d '=' -f 2)
        progress_url="/rest/api/2/reindex/progress?taskId=${TaskID}"
else
        progress_url="/rest/api/2/reindex"
fi
echo ProgressURL: $progress_url
progress=0
until [[ "$progress" == "100" || "$monitor" != "true" ]]
do
        sleep 5
        output=$(curl -s -S -k -u $username:$password -X GET -H "Content-Type: application/json" "${server}${progress_url}")
        if [[ $debug == 1 ]]; then
                echo ------------------- Http raw response ---------------------------
                echo $output
                echo ------------------- ---------------------------
        fi
        progress=$(echo $output | grep -Po '"currentProgress":.*?[^\\],' | cut -d ":" -f 2 | tr -d ,)
        status=$(echo $output | grep -Po '"success":.*?[^\\][,|}]' | cut -d ":" -f 2 | tr -d ,})
        if [ "$oldprog" != "$progress" ]; then
                echo "$(date +%Y-%m-%d_%T) - Index is at ${progress}%, success: $status"
        fi
        oldprog=$progress
done

echo -n "$(date +%Y-%m-%d_%T) - Re-indexing is completed "
if [[ "$status" == "true" ]]; then
        echo "successfully."
else
        echo " with errors."
        exit 1
fi
