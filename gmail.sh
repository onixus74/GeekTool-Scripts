#!/bin/bash

# This script gets your Gmail as text from the inbox.
# for another label, change the "inbox_feed" variable and 
# replace "inbox" with the label name.

# Written by Bernhard Seeger
# This script uses OAuth 2.0, which is why you do not have to enter a password
# directly in the script!

# Run "gmail.sh init" and the script will walk you through.
# Afterwards, you can run "gmail.sh getmail". That's it.

# For the init step
client_id="375155156636"
client_secret="qidSVebEy-gag8l5Ck-dR8yv"
redirect_uri="urn:ietf:wg:oauth:2.0:oob"
scope="https://mail.google.com/mail/feed/atom"

inbox_feed="https://mail.google.com/mail/feed/atom/inbox"

if [ -n "$2" ] || [ -z "$1" ]; then
  echo 'usage: gmail.sh {init|getmail}'; exit 1
fi

scope_uri_encoded="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$scope")"

if [ "$1" == "init" ]; then
  auth_url="https://accounts.google.com/o/oauth2/auth?redirect_uri=$redirect_uri&response_type=code&client_id=$client_id.apps.googleusercontent.com&approval_prompt=force&scope=$scope_uri_encoded&access_type=offline"
  echo "OK. This is your first run with this script?"
  echo -e "You need to authorize this script (application)""\n""to have access to your mails."
  echo "To do this, you have to complete some steps:"
  echo "1. Go to an auto-generated web address and allow access"
  echo "2. You will get a code. Copy it and enter it in this dialog"
  echo "3. From this code, a new one will be retrieved."
  echo "   This one will be stored in your keychain - you have to allow it"
  echo "   by hitting "allow" on a popup prompt 2 times".
  echo ""
  read -p "If you are good to go, please press 1 (if not, press 2)" choice

  if [ "$choice" != "1" ]; then exit 1; fi
  echo " "
  echo "(A Browser window should have opened. If it did not, the address is stated below)"
  echo " "
  echo "$auth_url"
  echo " "
  echo -e "After Allowing Access, you should get a code.""\n""Copy it and enter it here. Then press Enter."
  open ""$auth_url""
  read authorization_code
  
  auth_code_uri_encoded="$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$authorization_code")"  
  oauth_response=$(curl -s --request POST -H "content-type: application/x-www-form-urlencoded" \
      https://accounts.google.com/o/oauth2/token \
      -d code="$auth_code_uri_encoded" \
      -d redirect_uri="$redirect_uri"  \
      -d client_id="$client_id.apps.googleusercontent.com" \
      -d scope="$scope_uri_encoded" \
      -d client_secret="$client_secret" \
      -d grant_type=authorization_code)
  
  lines=$(echo "$oauth_response"|wc -l)
  if [ "$lines" -le 4 ]; then
    echo "Sorry, but something went wrong. Please try again."
    echo "For Debugging Purposes: here is what the response was:"
    echo "$oauth_response"
  else
    refresh_token=$(echo "$oauth_response"|grep "refresh_token"|cut -c22-400|sed -e 's/"//g')
    refresh_token_base64=$(echo "$refresh_token"|base64)

    security add-generic-password -a "RefreshToken" -s "GeekToolMail" -w "$refresh_token_base64" -T "" -U

    check_base64=$(security 2>&1 >/dev/null find-generic-password -gs "GeekToolMail" -a "RefreshToken"| cut -d '"' -f 2 )
    check=$(echo "$check_base64"|base64 -D)
    
    if [ "$check" == "$refresh_token" ]; then
      echo -e "Everything is set up now""\n""You are good to go!"
    else
      echo -e "The refresh token from the internet did not get stored correctly in your keychain.""\n""Maybe try again?..."
    fi
  fi
fi

if [ "$1" == "getmail" ];then
  #Refresh the Access Token using the Refresh Token
  refresh_token_base64=$(security 2>&1 >/dev/null find-generic-password -gs "GeekToolMail" -a "RefreshToken"| cut -d '"' -f 2 )
  refresh_token=$(echo "$refresh_token_base64"|base64 -D)

  oauth_response=$(curl -s --request POST -H "content-type: application/x-www-form-urlencoded" \
        https://accounts.google.com/o/oauth2/token \
        -d client_secret="$client_secret" \
        -d grant_type=refresh_token \
        -d refresh_token="$refresh_token" \
        -d client_id="$client_id.apps.googleusercontent.com")

  access_token=$(echo "$oauth_response"|grep "access_token"|cut -c21-400|sed -e 's/",//g')
  mail=$(curl -s -H "Authorization: OAuth $access_token" "$inbox_feed")

  account=$(echo "$mail"|xpath /feed/title 2>/dev/null|rev|sed -e 's,>eltit/<,,'|awk '{print $1}'|rev) 
  mail_count=$(echo "$mail"|xpath "count(/feed/entry/title)" 2>/dev/null)  
  authors=$(echo "$mail"| tr -d '\n' | awk -F '<entry>' '{for (i=2; i<=NF; i++) {print $i}}' | perl -pe 's/^<title>(.*)<\/title>.*<name>(.*)<\/name>.*$/$2/')
  authors=$(php -r "echo html_entity_decode( \"$authors\" );")
  titles=$(echo "$mail"| tr -d '\n' | awk -F '<entry>' '{for (i=2; i<=NF; i++) {print $i}}' | perl -pe 's/^<title>(.*)<\/title>.*<name>(.*)<\/name>.*$/$1/')
  titles=$(php -r "echo html_entity_decode( \"$titles\" );")
  number_of_lines=$(echo "$authors"|wc -l)

  longest_author=$(echo "$authors"|awk '{ if (length($0) > max) {max = length($0); maxline = $0} } END { print maxline }')
  max_length=$(echo "$longest_author"|wc -m 2>/dev/null)
  let max_length=max_length+2
  
  echo "$account you have $mail_count new mails"
  echo " "
  COUNTER=1
  while [  $COUNTER -le "$number_of_lines" ]; do
    current_author=$(echo "$authors"|sed -n "$COUNTER"p)
    current_length=$(echo "$current_author"|wc -m 2> /dev/null)
    while [ $current_length -lt "$max_length" ]; do
      current_author=$(echo -n "$current_author";echo -n " ")
      current_length=$(echo "$current_author"|wc -m 2> /dev/null)
    done
    current_title=$(echo "$titles"|sed -n "$COUNTER"p)
    echo "$current_author""$current_title"
    let COUNTER=COUNTER+1 
  done
fi
