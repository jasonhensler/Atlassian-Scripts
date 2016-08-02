#!/bin/bash
# This script requires bash, on some systems like Ubuntu, /bin/sh redirects to a different shell
# such as dash, which will not properly run this script in it's current iteration.
########################################## Settings ##########################################
# username - Admin user on the Jira Server
username="jason.hensler"
# password - Password for user, can be left as '' and passed in at run time by call script with password argument ex: ./reindex.sh <password>
password=""
# server needs to be the server name and context of Jira install, ex: http(s)://<jira_dns>:<port>/<jira_context>
server="https://confjira01aq:8080/jira"
# background - [true|false] Set to true for background index or false to preform an instance locking re-index
background=true
# monitor - [true|false] Set to true for the script to monitor the re-index. This will cause the script to check status until it reaches 100%
monitor=true
# Debug - [true|false] Set to true to print the output of the curl request
debug=false
# print_date - [true|false] Set to 1 to print the date on each output line.
print_date=true
# date_format - Standard date command format to be displayed if print_date=true
date_format="+%Y-%m-%d_%T"
# cookie_dir - Directory to store the .cookies.txt (cookie jar) for curl.
cookie_dir=$HOME

#################################################################################################

########################################### Functions ###########################################
#pdate - Function will print date string before echo statements in format $date_format if print_date is enabled.
pdate() {
        if [[ "$print_date" == "true" ]]; then
                echo -n "$(date $date_format) - "
        fi
}

# url_call() - Function calls the url via curl. Checks that curl did not return an error and that login was successful. Set the output
callUrl() {
        #
        output=`curl -D- -s -S -k  --cookie $cookie_dir/.cookies.txt --cookie-jar $cookie_dir/.cookies.txt -u $username:$password -X $1 -H "X-Atlassian-Token: no-check" -H "Content-Type: application/json" "$2"`
        if [[ $? == 0 ]]; then
                login=`echo $output | grep -c "X-Seraph-LoginReason: OK"`
                if [[ $login != 1 ]]; then
                        echo "$(pdate)Error: login unsuccessful!"
                        return 1
                fi
                ret=0
        else
                echo "$(pdate)Curl command return an error!"
                ret=1
        fi
        if [[ "$debug" == "true" ]]; then
                echo "$(pdate)------------------- Http raw response ---------------------------"
                echo "$(pdate)$output"
                echo "$(pdate)------------------- ---------------------------"

        fi
        return $ret
}

#################################################################################################

############################################# Main ##############################################
#verify password is set or passed at runtime.
if [[ -z "$1" && -z $password ]]; then
        echo "$(pdate) Must set \$password or pass to script at runtime!"
        exit 2
fi
if [[ ! -z "$1" ]]; then
        password=$1
fi
#Version check, Used to decided which url to use during status checking. Useful for future updates as well.
callUrl "GET" "${server}/rest/api/2/serverInfo"
if [[ $? != 0 ]]; then
        echo "$(pdate)Version Check FAILED!"
        echo $(pdate)------------------- Http raw response ---------------------------
        echo $(pdate)$output
        echo $(pdate)------------------- ---------------------------
        exit 1
else
        #Get the "VersionNumbers" json response and phrase to an array
        version=$(echo $output | sed -e 's/[{}]/''/g' | awk -v RS=',"' -F: '/^versionNumber/ {print $2}' | tr -d '[]')
        version=(${version//,/ })
        echo "$(pdate) Jira Version Detected: ${version[0]}.${version[1]}.${version[2]}."
fi

#Call re-index
if [[ "$background" == "true" ]]; then
                echo "$(pdate) Starting Background re-index...."
        callUrl "POST" "${server}/rest/api/2/reindex"
else
                echo "$(pdate) Starting Foreground re-index...."
        callUrl "POST" "${server}/rest/api/2/reindex?type=FOREGROUND"
fi

if [[ $? != 0 ]]; then
        echo "$(pdate) re-index FAILED!"
        echo "$(pdate)------------------- Http raw response ---------------------------"
        echo "$(pdate)$output"
        echo "$(pdate)------------------- ---------------------------"
        exit 1
fi

#Check version to see if we should use progressUrl or the re-index url, this changed in 6.4.x
if [[ ${version[0]} -ge 6 && ${version[1]} -ge 4 ]]; then
        progress_url=$(echo $output | grep -Po '"progressUrl":.*?[^\\],')
        progress_url=$(echo $progress_url | cut -d ":" -f 2 | tr -d '",')
        TaskID=$(echo $progress_url | cut -d '=' -f 2)
        progress_url="/rest/api/2/reindex/progress?taskId=${TaskID}"
else
        progress_url="/rest/api/2/reindex"
fi

progress=0
until [[ "$progress" == "100" || "$monitor" != "true" ]]
do
        sleep 5
        callUrl "GET" "${server}${progress_url}"
        if [[ $? != 0 ]];then
                echo "$(pdate) Error retrieving progress!"
                echo "$(pdate)------------------- Http raw response ---------------------------"
                echo "$(pdate)$output"
                echo "$(pdate)------------------- ---------------------------"
                exit 1
        fi

        #Parse response for the currentProgress json object, hopefully this will be more change tolerant
        progress=$(echo $output | grep -Po '"currentProgress":.*?[^\\],' | cut -d ":" -f 2 | tr -d ,)
        sucess=$(echo $output | grep -Po '"success":.*?[^\\][,|}]' | cut -d ":" -f 2 | tr -d ,})
        if [ "$oldprog" != "$progress" ]; then
                echo "$(pdate) Re-Indexing is at ${progress}%"
        fi
        oldprog=$progress
done

echo -n "$(pdate) Re-indexing is completed "
if [[ "$sucess" == "true" ]]; then
        echo "successfully."
else
        echo " with errors."
        exit 1
fi
#cleanup curl cookie store after running.
rm $cookie_dir/.cookies.txt
